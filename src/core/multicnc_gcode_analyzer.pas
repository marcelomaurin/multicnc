unit multicnc_gcode_analyzer;

{ objfpc}{+}

interface

uses
  Classes, SysUtils, Math, multisuite_numfmt;

type
  TGCodeBounds = record
    HasMotion: Boolean;
    MinX, MaxX: Double;
    MinY, MaxY: Double;
    MinZ, MaxZ: Double;
  end;

  TGCodeAnalyzer = class
  public
    class function EmptyBounds: TGCodeBounds; static;
    class function Analyze(ALines: TStrings; out Bounds: TGCodeBounds): Boolean; static;
    class function BuildFramingGCode(const Bounds: TGCodeBounds;
      AFramingFeed: Double; AUseLaser: Boolean; ALaserPowerS: Integer): TStringList; static;
  end;

function BoundsWidth(const Bounds: TGCodeBounds): Double;
function BoundsHeight(const Bounds: TGCodeBounds): Double;
function BoundsDepth(const Bounds: TGCodeBounds): Double;
function BoundsSummary(const Bounds: TGCodeBounds): string;

implementation

function BoundsWidth(const Bounds: TGCodeBounds): Double;
begin
  if Bounds.HasMotion then Result := Max(0.0, Bounds.MaxX - Bounds.MinX) else Result := 0;
end;

function BoundsHeight(const Bounds: TGCodeBounds): Double;
begin
  if Bounds.HasMotion then Result := Max(0.0, Bounds.MaxY - Bounds.MinY) else Result := 0;
end;

function BoundsDepth(const Bounds: TGCodeBounds): Double;
begin
  if Bounds.HasMotion then Result := Max(0.0, Bounds.MaxZ - Bounds.MinZ) else Result := 0;
end;

function BoundsSummary(const Bounds: TGCodeBounds): string;
begin
  if not Bounds.HasMotion then Exit('Nenhum movimento identificado');
  Result := Format('Área: %.2f x %.2f mm | X: %.2f → %.2f mm | Y: %.2f → %.2f mm',
    [BoundsWidth(Bounds), BoundsHeight(Bounds), Bounds.MinX, Bounds.MaxX, Bounds.MinY, Bounds.MaxY], InvariantFS);
end;

class function TGCodeAnalyzer.EmptyBounds: TGCodeBounds;
begin
  Result.HasMotion := False;
  Result.MinX := 0; Result.MaxX := 0;
  Result.MinY := 0; Result.MaxY := 0;
  Result.MinZ := 0; Result.MaxZ := 0;
end;

class function TGCodeAnalyzer.Analyze(ALines: TStrings; out Bounds: TGCodeBounds): Boolean;
var
  I, J, LineIdx, MotionG: Integer;
  Line, WordStr: string;
  CurX, CurY, CurZ: Double;
  TargetX, TargetY, TargetZ: Double;
  OffsetX, OffsetY, OffsetZ: Double;
  RelativeMode: Boolean;
  Scale: Double;
  HasX, HasY, HasZ, HasI, HasJ, HasR: Boolean;
  ValX, ValY, ValZ, ValI, ValJ, ValR: Double;
  CenterX, CenterY, Radius, Ang0, Ang1, Ang, StepFrac: Double;
  StepIdx, StepCount: Integer;

  procedure IncludePoint(const PX, PY, PZ: Double);
  begin
    if not Bounds.HasMotion then
    begin
      Bounds.HasMotion := True;
      Bounds.MinX := PX; Bounds.MaxX := PX;
      Bounds.MinY := PY; Bounds.MaxY := PY;
      Bounds.MinZ := PZ; Bounds.MaxZ := PZ;
    end
    else
    begin
      if PX < Bounds.MinX then Bounds.MinX := PX;
      if PX > Bounds.MaxX then Bounds.MaxX := PX;
      if PY < Bounds.MinY then Bounds.MinY := PY;
      if PY > Bounds.MaxY then Bounds.MaxY := PY;
      if PZ < Bounds.MinZ then Bounds.MinZ := PZ;
      if PZ > Bounds.MaxZ then Bounds.MaxZ := PZ;
    end;
  end;

begin
  Bounds := EmptyBounds;
  Result := False;
  if (ALines = nil) or (ALines.Count = 0) then Exit;

  CurX := 0.0; CurY := 0.0; CurZ := 0.0;
  OffsetX := 0.0; OffsetY := 0.0; OffsetZ := 0.0;
  RelativeMode := False; // G90 default
  Scale := 1.0;          // G21 mm default
  MotionG := -1;

  for LineIdx := 0 to ALines.Count - 1 do
  begin
    Line := Trim(ALines[LineIdx]);
    if (Line = '') or (Line[1] = ';') or (Line = '%') then Continue;

    // Remove comentarios entre parenteses
    while True do
    begin
      I := Pos('(', Line);
      if I = 0 then Break;
      J := Pos(')', Line);
      if J > I then Delete(Line, I, J - I + 1) else Break;
    end;
    I := Pos(';', Line);
    if I > 0 then Line := Copy(Line, 1, I - 1);
    Line := UpperCase(Trim(Line));
    if Line = '' then Continue;

    HasX := False; HasY := False; HasZ := False;
    HasI := False; HasJ := False; HasR := False;
    ValX := 0; ValY := 0; ValZ := 0;
    ValI := 0; ValJ := 0; ValR := 0;

    // Tokenize
    I := 1;
    while I <= Length(Line) do
    begin
      if Line[I] in [' ', #9] then begin Inc(I); Continue; end;
      if Line[I] in ['A'..'Z'] then
      begin
        WordStr := Line[I];
        Inc(I);
        J := I;
        while (J <= Length(Line)) and (Line[J] in ['0'..'9', '-', '+', '.']) do Inc(J);
        if J > I then
        begin
          WordStr := WordStr + Copy(Line, I, J - I);
          I := J;
        end;

        // Parse WordStr
        if Length(WordStr) >= 2 then
        begin
          case WordStr[1] of
            'G':
              begin
                if WordStr = 'G90' then RelativeMode := False
                else if WordStr = 'G91' then RelativeMode := True
                else if WordStr = 'G20' then Scale := 25.4
                else if WordStr = 'G21' then Scale := 1.0
                else if (WordStr = 'G0') or (WordStr = 'G00') then MotionG := 0
                else if (WordStr = 'G1') or (WordStr = 'G01') then MotionG := 1
                else if (WordStr = 'G2') or (WordStr = 'G02') then MotionG := 2
                else if (WordStr = 'G3') or (WordStr = 'G03') then MotionG := 3
                else if WordStr = 'G92' then MotionG := 92;
              end;
            'X':
              if TryStrToFloat(Copy(WordStr, 2, MaxInt), ValX, InvariantFS) then HasX := True;
            'Y':
              if TryStrToFloat(Copy(WordStr, 2, MaxInt), ValY, InvariantFS) then HasY := True;
            'Z':
              if TryStrToFloat(Copy(WordStr, 2, MaxInt), ValZ, InvariantFS) then HasZ := True;
            'I':
              if TryStrToFloat(Copy(WordStr, 2, MaxInt), ValI, InvariantFS) then HasI := True;
            'J':
              if TryStrToFloat(Copy(WordStr, 2, MaxInt), ValJ, InvariantFS) then HasJ := True;
            'R':
              if TryStrToFloat(Copy(WordStr, 2, MaxInt), ValR, InvariantFS) then HasR := True;
          end;
        end;
      end
      else Inc(I);
    end;

    // Handle G92 (Work offset reset/change)
    if MotionG = 92 then
    begin
      if HasX then OffsetX := ValX * Scale - CurX;
      if HasY then OffsetY := ValY * Scale - CurY;
      if HasZ then OffsetZ := ValZ * Scale - CurZ;
      MotionG := -1;
      Continue;
    end;

    // Motion execution
    if MotionG in [0, 1, 2, 3] then
    begin
      if not (HasX or HasY or HasZ) then Continue;

      if RelativeMode then
      begin
        if HasX then TargetX := CurX + ValX * Scale else TargetX := CurX;
        if HasY then TargetY := CurY + ValY * Scale else TargetY := CurY;
        if HasZ then TargetZ := CurZ + ValZ * Scale else TargetZ := CurZ;
      end
      else
      begin
        if HasX then TargetX := ValX * Scale - OffsetX else TargetX := CurX;
        if HasY then TargetY := ValY * Scale - OffsetY else TargetY := CurY;
        if HasZ then TargetZ := ValZ * Scale - OffsetZ else TargetZ := CurZ;
      end;

      if MotionG in [0, 1] then
      begin
        IncludePoint(TargetX, TargetY, TargetZ);
      end
      else if MotionG in [2, 3] then
      begin
        // Arcs G2 (CW) or G3 (CCW)
        IncludePoint(CurX, CurY, CurZ);
        IncludePoint(TargetX, TargetY, TargetZ);

        if HasI or HasJ then
        begin
          CenterX := CurX + ValI * Scale;
          CenterY := CurY + ValJ * Scale;
          Radius := Hypot(ValI * Scale, ValJ * Scale);
        end
        else if HasR and (ValR > 0) then
        begin
          Radius := ValR * Scale;
          CenterX := (CurX + TargetX) / 2.0;
          CenterY := (CurY + TargetY) / 2.0;
        end
        else
          Radius := 0;

        if Radius > 1e-5 then
        begin
          Ang0 := ArcTan2(CurY - CenterY, CurX - CenterX);
          Ang1 := ArcTan2(TargetY - CenterY, TargetX - CenterX);
          if MotionG = 2 then // CW
          begin
            if Ang1 >= Ang0 then Ang1 := Ang1 - 2.0 * Pi;
          end
          else // CCW
          begin
            if Ang1 <= Ang0 then Ang1 := Ang1 + 2.0 * Pi;
          end;

          StepCount := 16;
          for StepIdx := 1 to StepCount - 1 do
          begin
            StepFrac := StepIdx / StepCount;
            Ang := Ang0 + (Ang1 - Ang0) * StepFrac;
            IncludePoint(CenterX + Radius * Cos(Ang), CenterY + Radius * Sin(Ang), TargetZ);
          end;
        end;
      end;

      CurX := TargetX;
      CurY := TargetY;
      CurZ := TargetZ;
    end;
  end;

  Result := Bounds.HasMotion;
end;

class function TGCodeAnalyzer.BuildFramingGCode(const Bounds: TGCodeBounds;
  AFramingFeed: Double; AUseLaser: Boolean; ALaserPowerS: Integer): TStringList;
begin
  Result := TStringList.Create;
  if not Bounds.HasMotion then Exit;
  if AFramingFeed <= 0 then AFramingFeed := 3000;

  Result.Add('; --- Inicio do Contorno (Framing) ---');
  Result.Add('G90');
  Result.Add('M5');
  Result.Add(Format('G0 X%.3f Y%.3f F%.0f', [Bounds.MinX, Bounds.MinY, AFramingFeed], InvariantFS));
  if AUseLaser and (ALaserPowerS > 0) then
    Result.Add(Format('M3 S%d', [ALaserPowerS]))
  else
    Result.Add('M5');
  Result.Add(Format('G1 X%.3f Y%.3f F%.0f', [Bounds.MaxX, Bounds.MinY, AFramingFeed], InvariantFS));
  Result.Add(Format('G1 X%.3f Y%.3f F%.0f', [Bounds.MaxX, Bounds.MaxY, AFramingFeed], InvariantFS));
  Result.Add(Format('G1 X%.3f Y%.3f F%.0f', [Bounds.MinX, Bounds.MaxY, AFramingFeed], InvariantFS));
  Result.Add(Format('G1 X%.3f Y%.3f F%.0f', [Bounds.MinX, Bounds.MinY, AFramingFeed], InvariantFS));
  Result.Add('M5');
  Result.Add('; --- Fim do Contorno ---');
end;

end.
