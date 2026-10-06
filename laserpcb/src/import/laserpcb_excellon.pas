unit laserpcb_excellon;

{ Leitor de arquivos de furacao Excellon (NC drill) do LaserPCB.

  Suporta: cabecalho M48 ate % ou M95; METRIC/INCH (e M71/M72) com LZ/TZ;
  FMAT,1/2; formato ;FILE_FORMAT=i:d (KiCad/Altium); ferramentas TnC<d>
  (com F/S/B/H ignorados); coordenadas decimais ou inteiras; G90/G91 (ICI);
  furos; rasgos G85 (X Y G85 X Y) e modo rota (G00 + M15 + G01 + M16/M17);
  T0 (descarregar). Arquivos Excellon em polegadas sao convertidos para mm. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, laserpcb_geom;

type
  TLPDrillTool = record
    Number: Integer;
    Diameter: Double;   { mm }
    Plated: Boolean;
  end;

  TLPHole = record
    X, Y: Double;
    Tool: Integer;      { indice em Tools }
    Slot: Boolean;
    X2, Y2: Double;     { fim do rasgo }
  end;

  TLPDrillFile = class
  public
    FileName: string;
    Tools: array of TLPDrillTool;
    Holes: array of TLPHole;
    Warnings: TStringList;
    Plated: Boolean;    { PTH (padrao) ou NPTH pelo nome/atributo }
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function ToolIndex(Number: Integer): Integer;
    function AddTool(Number: Integer; Diameter: Double): Integer;
    procedure AddHole(X, Y: Double; Tool: Integer);
    procedure AddSlot(X1, Y1, X2, Y2: Double; Tool: Integer);
    function HoleCount: Integer;
    function Bounds: TLPRect;
    procedure Transform(const M: TLPMatrix);
    { junta outro arquivo (ex.: PTH + NPTH); ferramentas iguais sao reaproveitadas }
    procedure Merge(Other: TLPDrillFile);
  end;

  TLPExcellonReader = class
  public
    class function LoadFromFile(const FileName: string; D: TLPDrillFile): Boolean;
    class function LoadFromString(const Text: string; D: TLPDrillFile): Boolean;
  end;

implementation

const
  IN2MM = 25.4;

var
  InvFS: TFormatSettings;

{ ---------------- TLPDrillFile ---------------- }

constructor TLPDrillFile.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
  Plated := True;
end;

destructor TLPDrillFile.Destroy;
begin
  Warnings.Free;
  inherited Destroy;
end;

procedure TLPDrillFile.Clear;
begin
  SetLength(Tools, 0);
  SetLength(Holes, 0);
  Warnings.Clear;
  Plated := True;
end;

function TLPDrillFile.ToolIndex(Number: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Tools) do
    if Tools[I].Number = Number then Exit(I);
  Result := -1;
end;

function TLPDrillFile.AddTool(Number: Integer; Diameter: Double): Integer;
begin
  Result := ToolIndex(Number);
  if Result < 0 then
  begin
    Result := Length(Tools);
    SetLength(Tools, Result + 1);
    Tools[Result].Number := Number;
  end;
  Tools[Result].Diameter := Diameter;
  Tools[Result].Plated := Plated;
end;

procedure TLPDrillFile.AddHole(X, Y: Double; Tool: Integer);
var
  N: Integer;
begin
  N := Length(Holes);
  SetLength(Holes, N + 1);
  Holes[N].X := X;
  Holes[N].Y := Y;
  Holes[N].Tool := Tool;
  Holes[N].Slot := False;
  Holes[N].X2 := X;
  Holes[N].Y2 := Y;
end;

procedure TLPDrillFile.AddSlot(X1, Y1, X2, Y2: Double; Tool: Integer);
var
  N: Integer;
begin
  N := Length(Holes);
  SetLength(Holes, N + 1);
  Holes[N].X := X1;
  Holes[N].Y := Y1;
  Holes[N].Tool := Tool;
  Holes[N].Slot := True;
  Holes[N].X2 := X2;
  Holes[N].Y2 := Y2;
end;

function TLPDrillFile.HoleCount: Integer;
begin
  Result := Length(Holes);
end;

function TLPDrillFile.Bounds: TLPRect;
var
  I: Integer;
  R: Double;
begin
  Result := LPEmptyRect;
  for I := 0 to High(Holes) do
  begin
    if (Holes[I].Tool >= 0) and (Holes[I].Tool <= High(Tools)) then
      R := Tools[Holes[I].Tool].Diameter / 2
    else
      R := 0;
    LPRectInclude(Result, Holes[I].X - R, Holes[I].Y - R);
    LPRectInclude(Result, Holes[I].X + R, Holes[I].Y + R);
    LPRectInclude(Result, Holes[I].X2 - R, Holes[I].Y2 - R);
    LPRectInclude(Result, Holes[I].X2 + R, Holes[I].Y2 + R);
  end;
end;

procedure TLPDrillFile.Transform(const M: TLPMatrix);
var
  I: Integer;
  P: TLPPoint;
begin
  for I := 0 to High(Holes) do
  begin
    P := LPApply(M, LPPoint(Holes[I].X, Holes[I].Y));
    Holes[I].X := P.X;
    Holes[I].Y := P.Y;
    P := LPApply(M, LPPoint(Holes[I].X2, Holes[I].Y2));
    Holes[I].X2 := P.X;
    Holes[I].Y2 := P.Y;
  end;
end;

procedure TLPDrillFile.Merge(Other: TLPDrillFile);
var
  I, J, T: Integer;
  Map: array of Integer;
begin
  SetLength(Map, Length(Other.Tools));
  for I := 0 to High(Other.Tools) do
  begin
    T := -1;
    for J := 0 to High(Tools) do
      if (Abs(Tools[J].Diameter - Other.Tools[I].Diameter) < 1e-4) and
         (Tools[J].Plated = Other.Tools[I].Plated) then
      begin
        T := J;
        Break;
      end;
    if T < 0 then
    begin
      T := Length(Tools);
      SetLength(Tools, T + 1);
      Tools[T] := Other.Tools[I];
      Tools[T].Number := 1;
      for J := 0 to T - 1 do
        if Tools[J].Number >= Tools[T].Number then Tools[T].Number := Tools[J].Number + 1;
    end;
    Map[I] := T;
  end;
  for I := 0 to High(Other.Holes) do
  begin
    J := Length(Holes);
    SetLength(Holes, J + 1);
    Holes[J] := Other.Holes[I];
    if (Other.Holes[I].Tool >= 0) and (Other.Holes[I].Tool <= High(Map)) then
      Holes[J].Tool := Map[Other.Holes[I].Tool];
  end;
  for I := 0 to Other.Warnings.Count - 1 do
    Warnings.Add(Other.Warnings[I]);
end;

{ ---------------- leitor ---------------- }

type
  TExcState = record
    Units: Double;
    IntDigits, DecDigits: Integer;
    LeadingZeros: Boolean;   { LZ: zeros a esquerda presentes => trailing omitidos }
    Incremental: Boolean;
    X, Y: Double;
    CurTool: Integer;
    RouteMode: Boolean;
    PlungeDown: Boolean;
    RouteX, RouteY: Double;
  end;

function ParseNum(const S: string; const St: TExcState): Double;
var
  T: string;
  Neg: Boolean;
begin
  T := Trim(S);
  if T = '' then Exit(0);
  if Pos('.', T) > 0 then
    Exit(StrToFloatDef(T, 0, InvFS) * St.Units);
  Neg := False;
  if T[1] in ['+', '-'] then
  begin
    Neg := T[1] = '-';
    Delete(T, 1, 1);
  end;
  if St.LeadingZeros then
  begin
    { zeros a direita omitidos: completa a direita ate int+dec }
    while Length(T) < St.IntDigits + St.DecDigits do T := T + '0';
    Result := StrToInt64Def(T, 0) / IntPower(10, Length(T) - St.IntDigits);
  end
  else
    Result := StrToInt64Def(T, 0) / IntPower(10, St.DecDigits);
  Result := Result * St.Units;
  if Neg then Result := -Result;
end;

procedure SetUnits(var St: TExcState; Inch: Boolean);
begin
  if Inch then
  begin
    St.Units := IN2MM;
    St.IntDigits := 2;
    St.DecDigits := 4;
  end
  else
  begin
    St.Units := 1;
    St.IntDigits := 3;
    St.DecDigits := 3;
  end;
end;

{ extrai o numero apos a letra L a partir de P; avanca P }
function TakeNumber(const S: string; var P: Integer): string;
var
  St: Integer;
begin
  St := P;
  while (P <= Length(S)) and (S[P] in ['0'..'9', '.', '-', '+']) do Inc(P);
  Result := Copy(S, St, P - St);
end;

class function TLPExcellonReader.LoadFromString(const Text: string; D: TLPDrillFile): Boolean;
var
  Lines: TStringList;
  I, P, Code, T, Colon: Integer;
  L, U, Num, Fmt: string;
  St: TExcState;
  InHeader, HasX, HasY, IsSlot: Boolean;
  NX, NY, SX, SY, Dia: Double;
  C: Char;
begin
  D.Clear;
  FillChar(St, SizeOf(St), 0);
  SetUnits(St, False);
  St.LeadingZeros := True;
  St.CurTool := -1;
  InHeader := False;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      L := Trim(Lines[I]);
      if L = '' then Continue;
      U := UpperCase(L);
      { comentarios e formato KiCad/Altium }
      if L[1] = ';' then
      begin
        if Pos('FILE_FORMAT=', U) > 0 then
        begin
          Fmt := Copy(U, Pos('FILE_FORMAT=', U) + 12, MaxInt);
          Colon := Pos(':', Fmt);
          if Colon > 0 then
          begin
            St.IntDigits := StrToIntDef(Copy(Fmt, 1, Colon - 1), St.IntDigits);
            St.DecDigits := StrToIntDef(Copy(Fmt, Colon + 1, 1), St.DecDigits);
          end;
        end;
        if (Pos('NON_PLATED', U) > 0) or (Pos('NPTH', U) > 0) then D.Plated := False;
        Continue;
      end;
      if U = 'M48' then
      begin
        InHeader := True;
        Continue;
      end;
      if (U = '%') or (U = 'M95') then
      begin
        InHeader := False;
        Continue;
      end;
      if (Copy(U, 1, 6) = 'METRIC') or (Copy(U, 1, 4) = 'INCH') then
      begin
        SetUnits(St, Copy(U, 1, 4) = 'INCH');
        if Pos(',TZ', U) > 0 then St.LeadingZeros := False
        else if Pos(',LZ', U) > 0 then St.LeadingZeros := True;
        { formato explicito: METRIC,LZ,000.000 }
        P := Pos('.', U);
        if (P > 0) and (RPos(',', U) < P) then
        begin
          Fmt := Copy(U, RPos(',', U) + 1, MaxInt);
          St.IntDigits := Pos('.', Fmt) - 1;
          St.DecDigits := Length(Fmt) - Pos('.', Fmt);
        end;
        Continue;
      end;
      if U = 'M71' then begin SetUnits(St, False); Continue; end;
      if U = 'M72' then begin SetUnits(St, True); Continue; end;
      if (U = 'ICI') or (U = 'ICI,ON') then begin St.Incremental := True; Continue; end;
      if U = 'ICI,OFF' then begin St.Incremental := False; Continue; end;
      if (Copy(U, 1, 4) = 'FMAT') or (Copy(U, 1, 3) = 'VER') or (Copy(U, 1, 3) = 'DET') or
         (Copy(U, 1, 3) = 'ATC') or (Copy(U, 1, 3) = 'TCST') then Continue;
      if (U = 'M30') or (U = 'M00') then Break;
      { definicao de ferramenta: T1C0.8 (cabecalho; alguns arquivos fora dele) }
      if (U[1] = 'T') and (Pos('C', U) > 0) then
      begin
        P := 2;
        T := StrToIntDef(TakeNumber(U, P), -1);
        Dia := 0;
        while P <= Length(U) do
        begin
          C := U[P];
          Inc(P);
          Num := TakeNumber(U, P);
          if C = 'C' then Dia := StrToFloatDef(Num, 0, InvFS) * St.Units;
        end;
        if T >= 0 then
        begin
          D.AddTool(T, Dia);
          if not InHeader then St.CurTool := D.ToolIndex(T);
        end;
        Continue;
      end;
      if InHeader then Continue;
      { corpo }
      HasX := False; HasY := False; IsSlot := False;
      NX := St.X; NY := St.Y; SX := St.X; SY := St.Y;
      P := 1;
      while P <= Length(U) do
      begin
        C := U[P];
        Inc(P);
        Num := TakeNumber(U, P);
        case C of
          'T':
            begin
              T := StrToIntDef(Num, -1);
              if T <= 0 then St.CurTool := -1
              else
              begin
                St.CurTool := D.ToolIndex(T);
                if St.CurTool < 0 then
                begin
                  D.Warnings.Add('Ferramenta T' + Num + ' sem diametro');
                  St.CurTool := D.AddTool(T, 0);
                end;
              end;
            end;
          'X':
            begin
              if St.Incremental then NX := NX + ParseNum(Num, St) else NX := ParseNum(Num, St);
              HasX := True;
            end;
          'Y':
            begin
              if St.Incremental then NY := NY + ParseNum(Num, St) else NY := ParseNum(Num, St);
              HasY := True;
            end;
          'G':
            begin
              Code := StrToIntDef(Num, -1);
              case Code of
                85:
                  begin
                    { X1Y1G85X2Y2: o que veio antes e o inicio }
                    IsSlot := True;
                    SX := NX;
                    SY := NY;
                  end;
                0: St.RouteMode := True;
                5: St.RouteMode := False;
                90: St.Incremental := False;
                91: St.Incremental := True;
              end;
            end;
          'M':
            begin
              Code := StrToIntDef(Num, -1);
              case Code of
                15: St.PlungeDown := True;
                16, 17: St.PlungeDown := False;
                71: SetUnits(St, False);
                72: SetUnits(St, True);
              end;
            end;
        end;
      end;
      if not (HasX or HasY) then
      begin
        if St.RouteMode and St.PlungeDown then
        begin
          St.RouteX := St.X;
          St.RouteY := St.Y;
        end;
        Continue;
      end;
      if St.CurTool < 0 then
      begin
        D.Warnings.Add('Coordenada sem ferramenta: ' + L);
        St.X := NX; St.Y := NY;
        Continue;
      end;
      if IsSlot then
        D.AddSlot(SX, SY, NX, NY, St.CurTool)
      else if St.RouteMode then
      begin
        if St.PlungeDown then
          D.AddSlot(St.X, St.Y, NX, NY, St.CurTool);
      end
      else
        D.AddHole(NX, NY, St.CurTool);
      St.X := NX;
      St.Y := NY;
    end;
  finally
    Lines.Free;
  end;
  Result := Length(D.Holes) > 0;
end;

class function TLPExcellonReader.LoadFromFile(const FileName: string; D: TLPDrillFile): Boolean;
var
  F: TStringList;
  U: string;
  I: Integer;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  F := TStringList.Create;
  try
    F.LoadFromFile(FileName);
    Result := LoadFromString(F.Text, D);
    D.FileName := FileName;
  finally
    F.Free;
  end;
  U := UpperCase(ExtractFileName(FileName));
  if (Pos('NPTH', U) > 0) or (Pos('NON-PLATED', U) > 0) or (Pos('NONPLATED', U) > 0) then
    D.Plated := False;
  for I := 0 to High(D.Tools) do
    D.Tools[I].Plated := D.Plated;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
  InvFS.ThousandSeparator := #0;
end.
