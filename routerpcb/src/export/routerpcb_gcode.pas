unit routerpcb_gcode;

{ G-code do RouterPCB para o MultiCNC (CNC Router, GRBL).

  So usa G0, G1, G4, M0, M2, M3, M5 (e G38.2/G10 L20 na sondagem), ponto
  decimal e linhas curtas (< 127 caracteres, limite do MultiCNC/GRBL).
  Cabecalho:
    ; RouterPCB -> MultiCNC (CNC Router)
    ; LaserPCB -> MultiCNC (CNC Router)   (o MultiCNC instalado reconhece esta)

  RPBuildPrograms monta TODOS os programas em memoria; RPSavePrograms so grava
  depois que tudo foi gerado sem erro (nunca deixa arquivo pela metade).
  Ordem de execucao, que tambem e a ordem dos nomes:
    <nome>_0_sondagem   (nivelamento ligado)
    <nome>_1_isolacao
    <nome>_2_furos[_T<n>_<d>mm]
    <nome>_3_recorte    (furos fresados, recortes internos, contorno externo)
  Com nivelamento ligado e sem mapa medido, so a sondagem e gerada
  (NeedsProbe): rode-a, importe o log e gere de novo. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_drill, routerpcb_types,
  routerpcb_drillmap, routerpcb_cutout, routerpcb_heightmap, routerpcb_project;

const
  RP_HEADER = '; RouterPCB -> MultiCNC (CNC Router)';
  RP_COMPAT_HEADER = '; LaserPCB -> MultiCNC (CNC Router)';

type
  TRPProgram = class
  public
    Suffix: string;     { 1_isolacao ... }
    Title: string;      { descricao da etapa }
    Tool: string;       { ferramenta a montar }
    Lines: TStringList;
    Seconds: Double;    { estimativa }
    CutLength: Double;  { mm em G1 }
    constructor Create;
    destructor Destroy; override;
  end;

  TRPPrograms = class
  private
    FItems: TList;
  public
    NeedsProbe: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Add(const ASuffix, ATitle, ATool: string): TRPProgram;
    function Count: Integer;
    function Item(I: Integer): TRPProgram;
    function TotalSeconds: Double;
  end;

  { escreve um programa: controla F modal, posicao atual e alturas }
  TRPWriter = class
  private
    FL: TStrings;
    FX, FY, FZ, FFeed: Double;
    FKnown: Boolean;
    FMachine: TRPMachineOptions;
    procedure Emit(const S: string);
  public
    constructor Create(ALines: TStrings; const M: TRPMachineOptions);
    procedure Header(const Name, Stage, Tool: string; BoardW, BoardH: Double; Mirrored: Boolean);
    procedure Start(RPM: Double);
    procedure Finish;
    procedure Rapid(X, Y: Double);
    procedure RapidZ(Z: Double);
    procedure Cut(X, Y, Z, Feed: Double);
    procedure CutZ(Z, Feed: Double);
    procedure Pause(const Msg: string);
    { caminhos 3D: continua sem subir se o proximo comeca onde o anterior acabou }
    procedure CutPaths(const P: TRPPaths3; Feed, Plunge: Double);
    { furo com bicadas; ZOffset = correcao do nivelamento no ponto }
    procedure DrillHole(X, Y, Depth, Peck, Plunge, ZOffset: Double);
    procedure DrillSlot(X1, Y1, X2, Y2, Depth, Peck, Plunge, SlotFeed, ZOffset: Double);
  end;

function RPFormat(V: Double): string;

{ estimativa de tempo e comprimento de corte lendo o proprio G-code }
procedure RPEstimate(Lines: TStrings; RapidFeed: Double; out Seconds, CutLength: Double);

{ HM pode ser nil (sem nivelamento). Levanta excecao com a mensagem do erro. }
function RPBuildPrograms(P: TRouterPCBProject; HM: TRPHeightMap): TRPPrograms;

{ grava <Folder>/<Base>_<sufixo>.gcode; devolve os nomes na ordem }
function RPSavePrograms(Progs: TRPPrograms; const Folder, Base: string): TStringList;

{ confere as regras do G-code gerado; acrescenta problemas em Errors }
function RPCheckGCode(Lines: TStrings; Errors: TStrings): Boolean;

implementation

var
  InvFS: TFormatSettings;

function RPFormat(V: Double): string;
begin
  if Abs(V) < 0.0005 then V := 0;
  Result := FormatFloat('0.###', V, InvFS);
end;

{ ---------------- TRPProgram / TRPPrograms ---------------- }

constructor TRPProgram.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TRPProgram.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

constructor TRPPrograms.Create;
begin
  inherited Create;
  FItems := TList.Create;
end;

destructor TRPPrograms.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TRPPrograms.Clear;
var I: Integer;
begin
  for I := 0 to FItems.Count - 1 do TRPProgram(FItems[I]).Free;
  FItems.Clear;
  NeedsProbe := False;
end;

function TRPPrograms.Add(const ASuffix, ATitle, ATool: string): TRPProgram;
begin
  Result := TRPProgram.Create;
  Result.Suffix := ASuffix;
  Result.Title := ATitle;
  Result.Tool := ATool;
  FItems.Add(Result);
end;

function TRPPrograms.Count: Integer;
begin
  Result := FItems.Count;
end;

function TRPPrograms.Item(I: Integer): TRPProgram;
begin
  Result := TRPProgram(FItems[I]);
end;

function TRPPrograms.TotalSeconds: Double;
var I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do Result := Result + Item(I).Seconds;
end;

{ ---------------- TRPWriter ---------------- }

constructor TRPWriter.Create(ALines: TStrings; const M: TRPMachineOptions);
begin
  inherited Create;
  FL := ALines;
  FMachine := M;
  FKnown := False;
  FFeed := -1;
end;

procedure TRPWriter.Emit(const S: string);
begin
  FL.Add(S);
end;

procedure TRPWriter.Header(const Name, Stage, Tool: string; BoardW, BoardH: Double; Mirrored: Boolean);
begin
  Emit(RP_HEADER);
  Emit(RP_COMPAT_HEADER);
  Emit('; ' + Name + ' - ' + Stage);
  Emit('; Ferramenta: ' + Tool);
  if Mirrored then
    Emit('; Lado Bottom (espelhado). Placa ' + RPFormat(BoardW) + ' x ' + RPFormat(BoardH) + ' mm')
  else
    Emit('; Lado Top. Placa ' + RPFormat(BoardW) + ' x ' + RPFormat(BoardH) + ' mm');
  Emit('; Zero: X/Y no canto inferior esquerdo da placa, Z na superficie do cobre');
  Emit('G21');
  Emit('G90');
  Emit('G94');
end;

procedure TRPWriter.Start(RPM: Double);
begin
  RapidZ(FMachine.SafeZ);
  if RPM > 0 then Emit('M3 S' + RPFormat(RPM)) else Emit('M3');
  if FMachine.SpinUpSeconds > 0 then Emit('G4 P' + RPFormat(FMachine.SpinUpSeconds));
end;

procedure TRPWriter.Finish;
begin
  RapidZ(FMachine.SafeZ);
  Emit('M5');
  Rapid(0, 0);
  Emit('M2');
end;

procedure TRPWriter.Rapid(X, Y: Double);
begin
  if FKnown and (Abs(X - FX) < 1e-4) and (Abs(Y - FY) < 1e-4) then Exit;
  Emit('G0 X' + RPFormat(X) + ' Y' + RPFormat(Y));
  FX := X; FY := Y;
end;

procedure TRPWriter.RapidZ(Z: Double);
begin
  if FKnown and (Abs(Z - FZ) < 1e-4) then Exit;
  Emit('G0 Z' + RPFormat(Z));
  FZ := Z;
  FKnown := True;
end;

procedure TRPWriter.Cut(X, Y, Z, Feed: Double);
var S: string;
begin
  S := 'G1';
  if Abs(X - FX) >= 0.0005 then S := S + ' X' + RPFormat(X);
  if Abs(Y - FY) >= 0.0005 then S := S + ' Y' + RPFormat(Y);
  if Abs(Z - FZ) >= 0.0005 then S := S + ' Z' + RPFormat(Z);
  if S = 'G1' then Exit;
  if Abs(Feed - FFeed) > 1e-6 then
  begin
    S := S + ' F' + RPFormat(Feed);
    FFeed := Feed;
  end;
  Emit(S);
  FX := X; FY := Y; FZ := Z;
end;

procedure TRPWriter.CutZ(Z, Feed: Double);
begin
  Cut(FX, FY, Z, Feed);
end;

procedure TRPWriter.Pause(const Msg: string);
begin
  RapidZ(FMachine.SafeZ);
  Emit('M5');
  Emit('; ' + Msg);
  Emit('M0');
end;

procedure TRPWriter.CutPaths(const P: TRPPaths3; Feed, Plunge: Double);
var K, I: Integer; A, B: TRPPoint3;
begin
  for K := 0 to High(P) do
  begin
    if Length(P[K]) = 0 then Continue;
    A := P[K][0];
    if not (FKnown and (Abs(A.X - FX) < 1e-4) and (Abs(A.Y - FY) < 1e-4) and (FZ < 0)) then
    begin
      RapidZ(FMachine.TravelZ);
      Rapid(A.X, A.Y);
    end;
    CutZ(A.Z, Plunge);
    for I := 1 to High(P[K]) do
    begin
      B := P[K][I];
      { descida vertical (ponte do recorte): avanco de mergulho }
      if (Abs(B.X - FX) < 1e-6) and (Abs(B.Y - FY) < 1e-6) and (B.Z < FZ) then Cut(B.X, B.Y, B.Z, Plunge)
      else Cut(B.X, B.Y, B.Z, Feed);
    end;
  end;
  RapidZ(FMachine.TravelZ);
end;

procedure TRPWriter.DrillHole(X, Y, Depth, Peck, Plunge, ZOffset: Double);
var Z: Double;
begin
  RapidZ(FMachine.TravelZ);
  Rapid(X, Y);
  if Peck <= 0 then
    Cut(X, Y, Depth + ZOffset, Plunge)
  else
  begin
    Z := 0;
    repeat
      Z := Max(Depth, Z - Peck);
      Cut(X, Y, Z + ZOffset, Plunge);
      if Z > Depth + 1e-9 then
      begin
        RapidZ(FMachine.TravelZ);
        RapidZ(Z + ZOffset + 0.2);   { volta rapido ate perto do fundo }
      end;
    until Z <= Depth + 1e-9;
  end;
  RapidZ(FMachine.TravelZ);
end;

procedure TRPWriter.DrillSlot(X1, Y1, X2, Y2, Depth, Peck, Plunge, SlotFeed, ZOffset: Double);
var Z, StepZ: Double; Fwd: Boolean;
begin
  RapidZ(FMachine.TravelZ);
  Rapid(X1, Y1);
  if Peck <= 0 then StepZ := Abs(Depth) else StepZ := Peck;
  Z := 0; Fwd := True;
  repeat
    Z := Max(Depth, Z - StepZ);
    CutZ(Z + ZOffset, Plunge);
    if Fwd then Cut(X2, Y2, Z + ZOffset, SlotFeed) else Cut(X1, Y1, Z + ZOffset, SlotFeed);
    Fwd := not Fwd;
  until Z <= Depth + 1e-9;
  RapidZ(FMachine.TravelZ);
end;

{ ---------------- estimativa e conferencia ---------------- }

function Field(const S: string; C: Char; out V: Double): Boolean;
var P, Q: Integer;
begin
  Result := False;
  P := Pos(' ' + C, S);
  if P = 0 then Exit;
  Q := P + 2;
  while (Q <= Length(S)) and (S[Q] <> ' ') do Inc(Q);
  Result := TryStrToFloat(Copy(S, P + 2, Q - P - 2), V, InvFS);
end;

procedure RPEstimate(Lines: TStrings; RapidFeed: Double; out Seconds, CutLength: Double);
var I: Integer; S: string; X, Y, Z, NX, NY, NZ, F, V, D: Double; Rapid: Boolean;
begin
  Seconds := 0; CutLength := 0;
  X := 0; Y := 0; Z := 0; F := 100;
  for I := 0 to Lines.Count - 1 do
  begin
    S := Trim(Lines[I]);
    if (S = '') or (S[1] = ';') then Continue;
    if Copy(S, 1, 3) = 'G4 ' then
    begin
      if Field(S, 'P', V) then Seconds := Seconds + V;
      Continue;
    end;
    if Copy(S, 1, 3) = 'G0 ' then Rapid := True
    else if Copy(S, 1, 3) = 'G1 ' then Rapid := False
    else if Copy(S, 1, 6) = 'G38.2 ' then
    begin
      if Field(S, 'F', V) and (V > 0) then Seconds := Seconds + 3 / V * 60;  { ~3 mm de descida }
      Continue;
    end
    else Continue;
    NX := X; NY := Y; NZ := Z;
    if Field(S, 'X', V) then NX := V;
    if Field(S, 'Y', V) then NY := V;
    if Field(S, 'Z', V) then NZ := V;
    if Field(S, 'F', V) and (V > 0) then F := V;
    D := Sqrt(Sqr(NX - X) + Sqr(NY - Y) + Sqr(NZ - Z));
    if Rapid then Seconds := Seconds + D / Max(1, RapidFeed) * 60
    else
    begin
      Seconds := Seconds + D / F * 60;
      CutLength := CutLength + D;
    end;
    X := NX; Y := NY; Z := NZ;
  end;
end;

function RPCheckGCode(Lines: TStrings; Errors: TStrings): Boolean;
const
  Allowed: array[0..11] of string = ('G0 ', 'G1 ', 'G4 ', 'G21', 'G90', 'G94', 'M0', 'M2', 'M3', 'M5',
    'G38.2 ', 'G10 L20 ');
var I, K, N0: Integer; S: string; Ok: Boolean;
begin
  N0 := Errors.Count;
  if (Lines.Count = 0) or (Pos(RP_HEADER, Lines[0]) <> 1) then Errors.Add('G-code sem o cabecalho do RouterPCB');
  for I := 0 to Lines.Count - 1 do
  begin
    S := Lines[I];
    if Length(S) > 120 then Errors.Add(Format('Linha %d com %d caracteres', [I + 1, Length(S)]));
    if (S = '') or (S[1] = ';') then Continue;
    if Pos(',', S) > 0 then Errors.Add(Format('Linha %d com virgula: %s', [I + 1, S]));
    Ok := False;
    for K := 0 to High(Allowed) do
      if (Copy(S + ' ', 1, Length(Allowed[K])) = Allowed[K]) or (S = Trim(Allowed[K])) then Ok := True;
    if (Copy(S, 1, 3) = 'M3 ') then Ok := True;
    if not Ok then Errors.Add(Format('Linha %d com comando nao permitido: %s', [I + 1, S]));
    if Errors.Count - N0 > 20 then Break;
  end;
  Result := Errors.Count = N0;
end;

{ ---------------- programas ---------------- }

function ToolVBit(const O: TRPIsolationOptions): string;
begin
  if O.Kind = tkVBit then
    Result := 'fresa V ' + RPFormat(O.Angle) + ' graus, ponta ' + RPFormat(O.TipWidth) + ' mm (corte ' +
      RPFormat(RPIsolationWidth(O)) + ' mm)'
  else
    Result := 'fresa de topo ' + RPFormat(O.Diameter) + ' mm';
end;

function PathsTo3(const P: TLPPaths; Z: Double): TRPPaths3;
var I: Integer;
begin
  Result := nil;
  for I := 0 to High(P) do RPAddPath3(Result, RPLift(P[I], Z));
end;

function HoleOffset(HM: TRPHeightMap; Use: Boolean; X, Y: Double): Double;
begin
  Result := 0;
  if not Use or (HM = nil) then Exit;
  if not HM.Height(X, Y, Result) then
    raise Exception.Create(Format('Furo em X %.2f Y %.2f fora da grade de sondagem', [X, Y], InvFS));
end;

procedure Finalize(Prg: TRPProgram; const M: TRPMachineOptions);
var Errors: TStringList;
begin
  RPEstimate(Prg.Lines, M.RapidFeed, Prg.Seconds, Prg.CutLength);
  Errors := TStringList.Create;
  try
    if not RPCheckGCode(Prg.Lines, Errors) then
      raise Exception.Create('G-code invalido (' + Prg.Suffix + '): ' + Errors[0]);
  finally
    Errors.Free;
  end;
end;

procedure DrillGroup(W: TRPWriter; const G: TLPDrillGroup; const O: TRPDrillOptions;
  HM: TRPHeightMap; UseHM: Boolean);
var I: Integer; H: TLPDrillHole;
begin
  for I := 0 to High(G.Holes) do
  begin
    H := G.Holes[I];
    if H.Slot then
      W.DrillSlot(H.X, H.Y, H.X2, H.Y2, O.Depth, O.Peck, O.PlungeFeed, O.SlotFeed,
        HoleOffset(HM, UseHM, H.X, H.Y))
    else
      W.DrillHole(H.X, H.Y, O.Depth, O.Peck, O.PlungeFeed, HoleOffset(HM, UseHM, H.X, H.Y));
  end;
end;

function RPBuildPrograms(P: TRouterPCBProject; HM: TRPHeightMap): TRPPrograms;
var Prg: TRPProgram; W: TRPWriter; Paths: TRPPaths3; I, K: Integer;
  UseHM: Boolean; G: TLPDrillGroup; Tool, Suffix: string; Errors: TStringList;
  CCW: Boolean;
begin
  Errors := TStringList.Create;
  try
    if not P.Validate(Errors, True) then raise Exception.Create(Trim(Errors.Text));
  finally
    Errors.Free;
  end;
  Result := TRPPrograms.Create;
  W := nil;
  try
    UseHM := P.Level.Enabled and (HM <> nil) and HM.Complete;
    { sondagem }
    if P.Level.Enabled then
    begin
      if (HM = nil) or not HM.Ready then raise Exception.Create('Defina a grade de sondagem');
      Prg := Result.Add('0_sondagem', 'Sondagem da superficie (G38.2)', 'a mesma fresa da isolacao');
      Prg.Lines.Free;
      Prg.Lines := HM.ProbeProgram(P.Level, P.Machine, P.Name + ' - sondagem ' +
        IntToStr(HM.Cols) + ' x ' + IntToStr(HM.Rows));
      Finalize(Prg, P.Machine);
      if not UseHM then
      begin
        Result.NeedsProbe := True;
        Exit;
      end;
    end;
    { isolacao }
    if P.Isolation.Enabled and (Length(P.IsolationPaths) > 0) then
    begin
      Tool := ToolVBit(P.Isolation);
      Prg := Result.Add('1_isolacao', 'Isolacao do cobre', Tool);
      W := TRPWriter.Create(Prg.Lines, P.Machine);
      W.Header(P.Name, Format('isolacao, %d passada(s)', [P.Isolation.Passes]), Tool,
        P.BoardWidth, P.BoardHeight, P.Mirrored);
      Paths := PathsTo3(P.IsolationPaths, P.Isolation.Depth);
      if UseHM then Paths := HM.Compensate(Paths, P.Level.MaxSegment, P.Level.MaxCorrection);
      W.Start(P.Isolation.RPM);
      W.CutPaths(Paths, P.Isolation.Feed, P.Isolation.PlungeFeed);
      W.Finish;
      FreeAndNil(W);
      Finalize(Prg, P.Machine);
    end;
    { furacao }
    if P.Drilling.Enabled and (P.DrillPlan.GroupCount > 0) then
    begin
      if P.Machine.OneFilePerTool and (P.DrillPlan.GroupCount > 1) then
      begin
        for K := 0 to P.DrillPlan.GroupCount - 1 do
        begin
          G := P.DrillPlan.Group(K);
          Tool := 'broca ' + RPFormat(G.Diameter) + ' mm';
          Suffix := Format('2_furos_T%d_%smm', [K + 1, FormatFloat('0.00', G.Diameter, InvFS)]);
          Prg := Result.Add(Suffix, Format('Furacao T%d (%d furos)', [K + 1, Length(G.Holes)]), Tool);
          W := TRPWriter.Create(Prg.Lines, P.Machine);
          W.Header(P.Name, Format('furacao T%d de %d', [K + 1, P.DrillPlan.GroupCount]), Tool,
            P.BoardWidth, P.BoardHeight, P.Mirrored);
          W.Start(P.Drilling.RPM);
          DrillGroup(W, G, P.Drilling, HM, UseHM and P.Level.ApplyDrill);
          W.Finish;
          FreeAndNil(W);
          Finalize(Prg, P.Machine);
        end;
      end
      else
      begin
        Tool := '';
        for K := 0 to P.DrillPlan.GroupCount - 1 do
        begin
          if K > 0 then Tool := Tool + ', ';
          Tool := Tool + RPFormat(P.DrillPlan.Group(K).Diameter);
        end;
        Tool := 'brocas ' + Tool + ' mm';
        Prg := Result.Add('2_furos', Format('Furacao (%d furos)', [P.DrillPlan.HoleCount]), Tool);
        W := TRPWriter.Create(Prg.Lines, P.Machine);
        W.Header(P.Name, 'furacao', Tool, P.BoardWidth, P.BoardHeight, P.Mirrored);
        for K := 0 to P.DrillPlan.GroupCount - 1 do
        begin
          G := P.DrillPlan.Group(K);
          if K > 0 then
          begin
            if P.Machine.ToolChange = rtcPause then
              W.Pause('Troque para a broca ' + RPFormat(G.Diameter) + ' mm, sem mexer no zero X/Y; zere Z e continue')
            else
              W.RapidZ(P.Machine.SafeZ);
          end;
          W.Start(P.Drilling.RPM);
          DrillGroup(W, G, P.Drilling, HM, UseHM and P.Level.ApplyDrill);
        end;
        W.Finish;
        FreeAndNil(W);
        Finalize(Prg, P.Machine);
      end;
    end;
    { recorte }
    if P.Cutout.Enabled and (Length(P.Cutouts) > 0) then
    begin
      Tool := 'fresa de topo ' + RPFormat(P.Cutout.ToolDiameter) + ' mm';
      Prg := Result.Add('3_recorte', 'Recorte da placa', Tool);
      W := TRPWriter.Create(Prg.Lines, P.Machine);
      W.Header(P.Name, Format('recorte, %d ponte(s)', [Length(P.Cutouts[High(P.Cutouts)].Tabs)]), Tool,
        P.BoardWidth, P.BoardHeight, P.Mirrored);
      W.Start(P.Cutout.RPM);
      CCW := P.Cutout.Direction = cdClimb;
      for I := 0 to High(P.MilledHoles) do
      begin
        Paths := RPMilledHolePasses(P.MilledHoles[I], P.Cutout, CCW, 0.01);
        if UseHM and P.Level.ApplyCutout then Paths := HM.Compensate(Paths, P.Level.MaxSegment, P.Level.MaxCorrection);
        W.CutPaths(Paths, P.Cutout.Feed, P.Cutout.PlungeFeed);
      end;
      for I := 0 to High(P.Cutouts) do
      begin
        Paths := RPContourPasses(P.Cutouts[I], P.Cutout);
        if UseHM and P.Level.ApplyCutout then Paths := HM.Compensate(Paths, P.Level.MaxSegment, P.Level.MaxCorrection);
        W.CutPaths(Paths, P.Cutout.Feed, P.Cutout.PlungeFeed);
      end;
      W.Finish;
      FreeAndNil(W);
      Finalize(Prg, P.Machine);
    end;
    if Result.Count = 0 then raise Exception.Create('Nada para gerar: confira as operacoes ligadas');
  except
    W.Free;
    Result.Free;
    raise;
  end;
end;

function RPSavePrograms(Progs: TRPPrograms; const Folder, Base: string): TStringList;
var I: Integer; FN: string;
begin
  if not DirectoryExists(Folder) and not ForceDirectories(Folder) then
    raise Exception.Create('Nao foi possivel criar a pasta ' + Folder);
  Result := TStringList.Create;
  try
    for I := 0 to Progs.Count - 1 do
    begin
      FN := IncludeTrailingPathDelimiter(Folder) + Base + '_' + Progs.Item(I).Suffix + '.gcode';
      Progs.Item(I).Lines.SaveToFile(FN);
      Result.Add(FN);
    end;
  except
    Result.Free;
    raise;
  end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
