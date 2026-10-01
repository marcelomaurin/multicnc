unit multicnc_gcode_analyzer;

{$mode objfpc}{$H+}

{ Analise previa ("preflight"/dry run) de um programa G-code antes de enviar
  para a maquina.

  - Interpretador modal: G0/G1/G2/G3 (IJK e R, planos G17/G18/G19, helicoidal),
    G20/G21, G90/G91, G90.1/G91.1, G4, G53, M3/M4/M5, M6, F, S, T.
  - Envelope de trabalho: avisa quando o programa sai dos limites da maquina
    (equivalente a um soft-limit verificado antes da execucao).
  - Estimativa de tempo com o mesmo modelo do planejador do Grbl: perfil
    trapezoidal por segmento, velocidade de junta por "junction deviation"
    ($11), passes reverso e direto, arcos discretizados com tolerancia ($12).
  - Avisos de seguranca: corte sem spindle/laser ligado, avanco ausente,
    avanco acima do maximo, arcos com raio inconsistente, comandos nao
    suportados.

  Nao envia nada a maquina; e usado pela UI/CLI e pelo MultiSuite. }

interface

uses
  Classes, SysUtils, Math;

type
  TMachineEnvelope = record
    MinX, MaxX, MinY, MaxY, MinZ, MaxZ: Double; // mm, coordenadas de trabalho
    MaxFeed: Double;            // mm/min
    RapidFeed: Double;          // mm/min
    Acceleration: Double;       // mm/s^2 (XY)
    AccelerationZ: Double;      // mm/s^2 (Z)
    JunctionDeviation: Double;  // mm ($11)
    ArcTolerance: Double;       // mm ($12)
    RequireSpindleForCut: Boolean;
  end;

  TGCodeReport = record
    Lines, Motions, Arcs, ToolChanges, Errors: Integer;
    HasBounds: Boolean;
    MinX, MaxX, MinY, MaxY, MinZ, MaxZ: Double;
    CutLength, RapidLength: Double;   // mm
    EstimatedSeconds: Double;
    MaxFeed, MaxSpindle: Double;
    UsesInches: Boolean;
  end;

  TGCodeAnalyzer = class
  public
    class function Analyze(Source: TStrings; const Env: TMachineEnvelope;
      Warnings: TStrings): TGCodeReport;
    class function AnalyzeFile(const FileName: string; const Env: TMachineEnvelope;
      Warnings: TStrings): TGCodeReport;
  end;

function DefaultEnvelope(SizeX, SizeY, SizeZ: Double): TMachineEnvelope;
function FormatDuration(Seconds: Double): string;

implementation

type
  TPlanSegment = record
    Length, NominalSpeed, Accel: Double; // mm, mm/s, mm/s^2
    UX, UY, UZ: Double;
  end;

  TAnalyzerState = class
    Env: TMachineEnvelope;
    Warnings: TStrings;
    R: TGCodeReport;
    X, Y, Z: Double;
    Motion: Integer;          // 0,1,2,3, -1 = nenhum
    Plane: Integer;           // 17,18,19
    Absolute, ArcAbsolute, Inches: Boolean;
    Feed, Spindle: Double;
    SpindleOn: Boolean;
    LineNo: Integer;
    Plan: array of TPlanSegment;
    PlanCount: Integer;
    WarnedFeed, WarnedNoSpindle: Boolean;
    WarnedLimit: array[0..5] of Boolean;
    WarnCount: Integer;
    procedure Warn(const Msg: string);
    procedure AddPoint(PX, PY, PZ: Double);
    procedure AddSegment(DX, DY, DZ, SpeedMMs: Double);
    procedure FlushPlan;
    procedure Linear(TX, TY, TZ: Double; Rapid: Boolean);
    procedure Arc(TX, TY, TZ, I, J, K, Radius: Double; HasR, Clockwise: Boolean);
  end;

const
  MAX_WARNINGS = 200;

function DefaultEnvelope(SizeX, SizeY, SizeZ: Double): TMachineEnvelope;
begin
  Result.MinX := 0; Result.MaxX := SizeX;
  Result.MinY := 0; Result.MaxY := SizeY;
  Result.MinZ := -SizeZ; Result.MaxZ := SizeZ;
  Result.MaxFeed := 5000;
  Result.RapidFeed := 3000;
  Result.Acceleration := 300;
  Result.AccelerationZ := 100;
  Result.JunctionDeviation := 0.01;
  Result.ArcTolerance := 0.002;
  Result.RequireSpindleForCut := True;
end;

function FormatDuration(Seconds: Double): string;
var S: Int64;
begin
  S := Round(Seconds);
  Result := Format('%d:%.2d:%.2d', [S div 3600, (S div 60) mod 60, S mod 60]);
end;

procedure TAnalyzerState.Warn(const Msg: string);
begin
  Inc(WarnCount);
  if WarnCount <= MAX_WARNINGS then
    Warnings.Add(Format('Linha %d: %s', [LineNo, Msg]))
  else if WarnCount = MAX_WARNINGS + 1 then
    Warnings.Add('... avisos adicionais omitidos');
end;

procedure TAnalyzerState.AddPoint(PX, PY, PZ: Double);
const Names: array[0..5] of string = ('X min', 'X max', 'Y min', 'Y max', 'Z min', 'Z max');
var Out: array[0..5] of Boolean; I: Integer;
begin
  if not R.HasBounds then begin
    R.MinX := PX; R.MaxX := PX; R.MinY := PY; R.MaxY := PY; R.MinZ := PZ; R.MaxZ := PZ;
    R.HasBounds := True;
  end else begin
    R.MinX := Min(R.MinX, PX); R.MaxX := Max(R.MaxX, PX);
    R.MinY := Min(R.MinY, PY); R.MaxY := Max(R.MaxY, PY);
    R.MinZ := Min(R.MinZ, PZ); R.MaxZ := Max(R.MaxZ, PZ);
  end;
  Out[0] := PX < Env.MinX - 1e-6; Out[1] := PX > Env.MaxX + 1e-6;
  Out[2] := PY < Env.MinY - 1e-6; Out[3] := PY > Env.MaxY + 1e-6;
  Out[4] := PZ < Env.MinZ - 1e-6; Out[5] := PZ > Env.MaxZ + 1e-6;
  for I := 0 to 5 do
    if Out[I] and not WarnedLimit[I] then begin
      WarnedLimit[I] := True;
      Inc(R.Errors);
      Warn(Format('fora do envelope da maquina (%s) em X%.3f Y%.3f Z%.3f',
        [Names[I], PX, PY, PZ]));
    end;
end;

procedure TAnalyzerState.AddSegment(DX, DY, DZ, SpeedMMs: Double);
var L, A: Double;
begin
  L := Sqrt(DX * DX + DY * DY + DZ * DZ);
  if L < 1e-9 then Exit;
  if PlanCount >= Length(Plan) then SetLength(Plan, Max(64, PlanCount * 2));
  Plan[PlanCount].Length := L;
  Plan[PlanCount].NominalSpeed := Max(SpeedMMs, 0.01);
  Plan[PlanCount].UX := DX / L;
  Plan[PlanCount].UY := DY / L;
  Plan[PlanCount].UZ := DZ / L;
  // Aceleracao limitada pelo eixo mais restritivo na direcao do movimento.
  A := Env.Acceleration;
  if Abs(DZ / L) > 1e-9 then A := Min(A, Env.AccelerationZ / Abs(DZ / L));
  if (Abs(DX / L) > 1e-9) or (Abs(DY / L) > 1e-9) then
    A := Min(A, Env.Acceleration / Max(Abs(DX / L), Abs(DY / L)));
  Plan[PlanCount].Accel := Max(A, 1e-3);
  Inc(PlanCount);
end;

procedure TAnalyzerState.FlushPlan;
var V: array of Double; I: Integer; CosT, SinT2, VJ, L, A, VN, VI, VO, DA, DD, VP: Double;
begin
  if PlanCount = 0 then Exit;
  SetLength(V, PlanCount + 1);
  // Velocidade maxima de entrada em cada junta (Grbl junction deviation).
  V[0] := 0;
  V[PlanCount] := 0;
  for I := 1 to PlanCount - 1 do begin
    CosT := -(Plan[I - 1].UX * Plan[I].UX + Plan[I - 1].UY * Plan[I].UY +
      Plan[I - 1].UZ * Plan[I].UZ);
    if CosT > 0.999999 then
      VJ := 0                                 // reversao total
    else if CosT < -0.999999 then
      VJ := 1e9                               // colinear
    else begin
      SinT2 := Sqrt(0.5 * (1 - CosT));
      VJ := Sqrt(Min(Plan[I - 1].Accel, Plan[I].Accel) * Env.JunctionDeviation *
        SinT2 / (1 - SinT2));
    end;
    V[I] := Min(VJ, Min(Plan[I - 1].NominalSpeed, Plan[I].NominalSpeed));
  end;
  // Passe reverso: precisa conseguir frear ate a proxima junta.
  for I := PlanCount - 1 downto 0 do
    V[I] := Min(V[I], Sqrt(Sqr(V[I + 1]) + 2 * Plan[I].Accel * Plan[I].Length));
  // Passe direto: limitado pela aceleracao a partir da junta anterior.
  for I := 0 to PlanCount - 1 do
    V[I + 1] := Min(V[I + 1], Sqrt(Sqr(V[I]) + 2 * Plan[I].Accel * Plan[I].Length));
  // Tempo de cada trapezio.
  for I := 0 to PlanCount - 1 do begin
    L := Plan[I].Length; A := Plan[I].Accel; VN := Plan[I].NominalSpeed;
    VI := Min(V[I], VN); VO := Min(V[I + 1], VN);
    DA := (VN * VN - VI * VI) / (2 * A);
    DD := (VN * VN - VO * VO) / (2 * A);
    if DA + DD <= L then
      R.EstimatedSeconds := R.EstimatedSeconds + (VN - VI) / A + (VN - VO) / A + (L - DA - DD) / VN
    else begin
      VP := Sqrt(Max(0, (2 * A * L + VI * VI + VO * VO) / 2));
      R.EstimatedSeconds := R.EstimatedSeconds + Max(0, VP - VI) / A + Max(0, VP - VO) / A;
    end;
  end;
  PlanCount := 0;
end;

procedure TAnalyzerState.Linear(TX, TY, TZ: Double; Rapid: Boolean);
var D, Speed: Double;
begin
  D := Sqrt(Sqr(TX - X) + Sqr(TY - Y) + Sqr(TZ - Z));
  Inc(R.Motions);
  if Rapid then begin
    R.RapidLength := R.RapidLength + D;
    Speed := Env.RapidFeed / 60;
  end else begin
    R.CutLength := R.CutLength + D;
    if Feed <= 0 then begin
      if not WarnedFeed then begin
        WarnedFeed := True;
        Inc(R.Errors);
        Warn('movimento de corte sem avanco F definido (Grbl error:22)');
      end;
      Speed := 1;
    end else
      Speed := Min(Feed, Env.MaxFeed) / 60;
    if Env.RequireSpindleForCut and not SpindleOn and not WarnedNoSpindle and (D > 0) then begin
      WarnedNoSpindle := True;
      Warn('movimento de corte com spindle/laser desligado (M3/M4 ausente)');
    end;
  end;
  AddSegment(TX - X, TY - Y, TZ - Z, Speed);
  X := TX; Y := TY; Z := TZ;
  AddPoint(X, Y, Z);
end;

procedure TAnalyzerState.Arc(TX, TY, TZ, I, J, K, Radius: Double; HasR, Clockwise: Boolean);
var
  // coordenadas no plano do arco (A,B) e eixo linear (C)
  A0, B0, C0, A1, B1, C1, OA, OB, CA, CB, R0, R1, Sweep, Ang0, Ang1, H, D, Tol,
  Seg, T, PA, PB, PC, PX, PY, PZ, LastX, LastY, LastZ, Speed, ChordLen: Double;
  N, S: Integer;

  procedure ToPlane(PX, PY, PZ: Double; out PA, PB, PC: Double);
  begin
    case Plane of
      18: begin PA := PZ; PB := PX; PC := PY; end;
      19: begin PA := PY; PB := PZ; PC := PX; end;
    else
      PA := PX; PB := PY; PC := PZ;
    end;
  end;

  procedure FromPlane(PA, PB, PC: Double; out PX, PY, PZ: Double);
  begin
    case Plane of
      18: begin PZ := PA; PX := PB; PY := PC; end;
      19: begin PY := PA; PZ := PB; PX := PC; end;
    else
      PX := PA; PY := PB; PZ := PC;
    end;
  end;

begin
  Inc(R.Motions);
  Inc(R.Arcs);
  ToPlane(X, Y, Z, A0, B0, C0);
  ToPlane(TX, TY, TZ, A1, B1, C1);
  if HasR then begin
    // Centro a partir do raio (R negativo = arco maior que 180 graus).
    D := Hypot(A1 - A0, B1 - B0);
    if (D < 1e-9) or (Abs(Radius) * 2 < D - 1e-6) then begin
      Inc(R.Errors);
      Warn('arco com raio R impossivel para os pontos dados (Grbl error:34)');
      Linear(TX, TY, TZ, False);
      Exit;
    end;
    H := Sqrt(Max(0, Sqr(Radius) - Sqr(D / 2)));
    if Clockwise xor (Radius < 0) then H := -H;
    CA := (A0 + A1) / 2 - H * (B1 - B0) / D;
    CB := (B0 + B1) / 2 + H * (A1 - A0) / D;
  end else begin
    case Plane of
      18: begin OA := K; OB := I; end;
      19: begin OA := J; OB := K; end;
    else
      begin OA := I; OB := J; end;
    end;
    if ArcAbsolute then begin
      // em G90.1, IJK sao absolutos; reordena conforme plano
      case Plane of
        18: begin CA := K; CB := I; end;
        19: begin CA := J; CB := K; end;
      else
        begin CA := I; CB := J; end;
      end;
    end else begin
      CA := A0 + OA;
      CB := B0 + OB;
    end;
  end;
  R0 := Hypot(A0 - CA, B0 - CB);
  R1 := Hypot(A1 - CA, B1 - CB);
  if Abs(R0 - R1) > Max(0.005, 0.001 * R0) then begin
    Inc(R.Errors);
    Warn(Format('arco com raio inconsistente (inicio %.4f, fim %.4f; Grbl error:33)', [R0, R1]));
  end;
  Ang0 := ArcTan2(B0 - CB, A0 - CA);
  Ang1 := ArcTan2(B1 - CB, A1 - CA);
  Sweep := Ang1 - Ang0;
  if Clockwise then begin
    if Sweep >= -1e-9 then Sweep := Sweep - 2 * Pi;
  end else begin
    if Sweep <= 1e-9 then Sweep := Sweep + 2 * Pi;
  end;
  // Discretiza com a tolerancia de corda do controlador.
  Tol := Max(Env.ArcTolerance, 1e-4);
  if R0 > Tol then
    Seg := 2 * ArcCos(Max(-1, 1 - Tol / R0))
  else
    Seg := Pi / 4;
  N := Max(1, Ceil(Abs(Sweep) / Max(Seg, 1e-4)));
  N := Min(N, 10000);
  if Feed <= 0 then begin
    if not WarnedFeed then begin
      WarnedFeed := True;
      Inc(R.Errors);
      Warn('arco sem avanco F definido (Grbl error:22)');
    end;
    Speed := 1;
  end else
    Speed := Min(Feed, Env.MaxFeed) / 60;
  if Env.RequireSpindleForCut and not SpindleOn and not WarnedNoSpindle then begin
    WarnedNoSpindle := True;
    Warn('arco de corte com spindle/laser desligado (M3/M4 ausente)');
  end;
  LastX := X; LastY := Y; LastZ := Z;
  for S := 1 to N do begin
    T := S / N;
    PA := CA + R0 * Cos(Ang0 + Sweep * T);
    PB := CB + R0 * Sin(Ang0 + Sweep * T);
    PC := C0 + (C1 - C0) * T;
    if S = N then begin PA := A1; PB := B1; PC := C1; end;
    FromPlane(PA, PB, PC, PX, PY, PZ);
    ChordLen := Sqrt(Sqr(PX - LastX) + Sqr(PY - LastY) + Sqr(PZ - LastZ));
    R.CutLength := R.CutLength + ChordLen;
    AddSegment(PX - LastX, PY - LastY, PZ - LastZ, Speed);
    AddPoint(PX, PY, PZ);
    LastX := PX; LastY := PY; LastZ := PZ;
  end;
  X := TX; Y := TY; Z := TZ;
end;

function InvFloat(const S: string; out V: Double): Boolean;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := TryStrToFloat(S, V, FS);
end;

class function TGCodeAnalyzer.Analyze(Source: TStrings; const Env: TMachineEnvelope;
  Warnings: TStrings): TGCodeReport;
var
  St: TAnalyzerState;
  Idx, P, Q, GCount: Integer;
  Line, Num: string;
  Letter: Char;
  Value, Scale, TX, TY, TZ, AI, AJ, AK, AR, Dwell: Double;
  HasX, HasY, HasZ, HasI, HasJ, HasK, HasR, HasMotionWord, MachineCoords, HasDwell: Boolean;
  NewMotion, Code10: Integer;
begin
  St := TAnalyzerState.Create;
  try
    St.Env := Env;
    St.Warnings := Warnings;
    FillChar(St.R, SizeOf(St.R), 0);
    St.Motion := -1;
    St.Plane := 17;
    St.Absolute := True;
    St.ArcAbsolute := False;
    for Idx := 0 to Source.Count - 1 do begin
      St.LineNo := Idx + 1;
      Line := UpperCase(Source[Idx]);
      // remove comentarios
      P := Pos(';', Line);
      if P > 0 then Line := Copy(Line, 1, P - 1);
      while Pos('(', Line) > 0 do begin
        P := Pos('(', Line);
        Q := Pos(')', Line);
        if Q < P then Q := Length(Line);
        Delete(Line, P, Q - P + 1);
      end;
      Line := Trim(Line);
      if (Line = '') or (Line = '%') then Continue;
      if Line[1] = '$' then Continue; // comandos de sistema Grbl
      Inc(St.R.Lines);
      HasX := False; HasY := False; HasZ := False; HasI := False; HasJ := False;
      HasK := False; HasR := False; HasMotionWord := False; MachineCoords := False;
      HasDwell := False; Dwell := 0;
      AI := 0; AJ := 0; AK := 0; AR := 0; TX := 0; TY := 0; TZ := 0;
      NewMotion := St.Motion;
      GCount := 0;
      P := 1;
      while P <= Length(Line) do begin
        Letter := Line[P];
        if not (Letter in ['A'..'Z']) then begin Inc(P); Continue; end;
        Q := P + 1;
        while (Q <= Length(Line)) and (Line[Q] in [' ', #9]) do Inc(Q);
        Num := '';
        while (Q <= Length(Line)) and (Line[Q] in ['0'..'9', '.', '-', '+']) do begin
          Num := Num + Line[Q];
          Inc(Q);
        end;
        P := Q;
        if not InvFloat(Num, Value) then begin
          Inc(St.R.Errors);
          St.Warn(Format('palavra %s sem valor numerico valido', [Letter]));
          Continue;
        end;
        case Letter of
          'G': begin
                 Code10 := Round(Value * 10);
                 case Code10 of
                   0, 10, 20, 30: begin NewMotion := Code10 div 10; HasMotionWord := True; end;
                   800: NewMotion := -1;
                   40: HasDwell := True;
                   170: St.Plane := 17;
                   180: St.Plane := 18;
                   190: St.Plane := 19;
                   200: begin St.Inches := True; St.R.UsesInches := True; end;
                   210: St.Inches := False;
                   900: St.Absolute := True;
                   910: St.Absolute := False;
                   901: St.ArcAbsolute := True;
                   911: St.ArcAbsolute := False;
                   530: MachineCoords := True;
                   540, 550, 560, 570, 580, 590, 940, 930, 430, 491, 61, 640, 400, 490, 920, 921:
                     ; // aceitos sem efeito na analise de trajetoria
                   280, 300: begin
                     St.Warn('G28/G30 move para posicao de maquina; trajetoria seguinte nao rastreada');
                     St.FlushPlan;
                   end;
                   382, 383, 384, 385: begin
                     NewMotion := -2; // probe
                     HasMotionWord := True;
                   end;
                 else
                   Inc(St.R.Errors);
                   St.Warn(Format('G%s nao suportado pelo controlador alvo', [Num]));
                 end;
                 Inc(GCount);
               end;
          'M': begin
                 case Round(Value) of
                   3, 4: begin St.SpindleOn := True; St.FlushPlan; end;
                   5: begin St.SpindleOn := False; St.FlushPlan; end;
                   6: begin Inc(St.R.ToolChanges); St.FlushPlan;
                        St.Warn('troca de ferramenta (M6): exige intervencao/ATC'); end;
                   0, 1: St.FlushPlan;
                   2, 30: St.FlushPlan;
                   7, 8, 9: ;
                 end;
               end;
          'F': begin
                 if St.Inches then St.Feed := Value * 25.4 else St.Feed := Value;
                 St.R.MaxFeed := Max(St.R.MaxFeed, St.Feed);
                 if (St.Feed > Env.MaxFeed) and (Env.MaxFeed > 0) then
                   St.Warn(Format('avanco F%.0f acima do maximo da maquina (%.0f mm/min)',
                     [St.Feed, Env.MaxFeed]));
               end;
          'S': begin St.Spindle := Value; St.R.MaxSpindle := Max(St.R.MaxSpindle, Value); end;
          'X': begin TX := Value; HasX := True; end;
          'Y': begin TY := Value; HasY := True; end;
          'Z': begin TZ := Value; HasZ := True; end;
          'I': begin AI := Value; HasI := True; end;
          'J': begin AJ := Value; HasJ := True; end;
          'K': begin AK := Value; HasK := True; end;
          'R': begin AR := Value; HasR := True; end;
          'P': begin Dwell := Value; end;
          'N', 'T', 'L', 'H', 'D', 'Q', 'E', 'A', 'B', 'C': ;
        end;
      end;
      St.Motion := NewMotion;
      if HasDwell then begin
        St.FlushPlan;
        St.R.EstimatedSeconds := St.R.EstimatedSeconds + Max(0, Dwell);
        Continue;
      end;
      if not (HasX or HasY or HasZ) then Continue;
      if MachineCoords then begin
        St.FlushPlan;
        Continue; // coordenadas de maquina: fora do sistema de trabalho
      end;
      if St.Inches then Scale := 25.4 else Scale := 1;
      if St.Absolute then begin
        if not HasX then TX := St.X else TX := TX * Scale;
        if not HasY then TY := St.Y else TY := TY * Scale;
        if not HasZ then TZ := St.Z else TZ := TZ * Scale;
      end else begin
        TX := St.X + TX * Scale; TY := St.Y + TY * Scale; TZ := St.Z + TZ * Scale;
      end;
      AI := AI * Scale; AJ := AJ * Scale; AK := AK * Scale; AR := AR * Scale;
      case St.Motion of
        0: St.Linear(TX, TY, TZ, True);
        1: St.Linear(TX, TY, TZ, False);
        2, 3: begin
                if not (HasR or HasI or HasJ or HasK) then begin
                  Inc(St.R.Errors);
                  St.Warn('arco sem IJK nem R (Grbl error:35)');
                  St.Linear(TX, TY, TZ, False);
                end else
                  St.Arc(TX, TY, TZ, AI, AJ, AK, AR, HasR, St.Motion = 2);
              end;
        -2: begin St.FlushPlan; St.Warn('ciclo de probe: posicao final depende do contato'); end;
      else
        begin
          Inc(St.R.Errors);
          St.Warn('coordenadas sem modo de movimento ativo');
        end;
      end;
    end;
    St.FlushPlan;
    Result := St.R;
  finally
    St.Free;
  end;
end;

class function TGCodeAnalyzer.AnalyzeFile(const FileName: string;
  const Env: TMachineEnvelope; Warnings: TStrings): TGCodeReport;
var L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Result := Analyze(L, Env, Warnings);
  finally
    L.Free;
  end;
end;

end.
