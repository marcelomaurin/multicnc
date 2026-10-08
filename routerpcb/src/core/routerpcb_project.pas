unit routerpcb_project;

{ Projeto do RouterPCB: importa a pasta Gerber + Excellon (MakePCB ou outro
  EDA) e gera as operacoes de fresagem na CNC Router.

  Coordenadas: o projeto guarda a geometria importada intacta (mm, Y para
  cima). A saida usa OutputMatrix: zero no canto inferior esquerdo da placa;
  no lado Bottom espelha em X dentro da caixa da placa (X' = MaxX - X). A
  mesma matriz vale para isolacao, furos, recorte e grade de sondagem.

  Generate monta, para as operacoes ligadas:
  - IsolationPaths: isolacao do cobre do lado escolhido (ordenada, sentido
    de corte ja aplicado), mais ClearanceIssues (cobres mais proximos que a
    largura da fresa);
  - DrillPlan + MilledHoles: furos casados com as brocas;
  - Cutouts: recortes internos e contorno externo com pontes.
  Validate lista todos os problemas; com ForExport exige o que foi gerado. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_gerber, laserpcb_excellon,
  laserpcb_raster, laserpcb_drill, laserpcb_roles, routerpcb_types,
  routerpcb_isolation, routerpcb_drillmap, routerpcb_cutout;

type
  TRPLayer = class
  public
    FileName: string;
    Role: TLPLayerRole;
    Layer: TLPGerberLayer;
    constructor Create;
    destructor Destroy; override;
  end;

  TRouterPCBProject = class
  private
    FLayers: TList;
    FBounds: TLPRect;
    FBoard, FCopper, FCutBoard: TLPMask;
    FRes: Double;
    FIsolation: TLPPaths;
    FIssues: TLPPath;
    FCutouts: TRPCutContours;
    FMilled: TRPMilledHoles;
    FPlan: TLPDrillPlan;
    FGenerated: Boolean;
    FLostCutouts: Integer;
    procedure FreeMasks;
    procedure UpdateBounds;
  public
    Name: string;                { base dos nomes dos arquivos }
    Drills: TLPDrillFile;
    DrillFiles: TStringList;
    Warnings: TStringList;       { importacao }
    Notes: TStringList;          { geracao (avisos que nao bloqueiam) }
    Side: TRPSide;
    Resolution: Double;          { mm/pixel; 0 = automatica }
    Machine: TRPMachineOptions;
    Isolation: TRPIsolationOptions;
    Drilling: TRPDrillOptions;
    Cutout: TRPCutoutOptions;
    Level: TRPLevelOptions;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure InvalidateCAM;
    procedure ImportFile(const FileName: string);
    { importa todos os Gerber/Excellon da pasta; devolve quantos entraram }
    function ImportFolder(const Dir: string): Integer;
    function LayerCount: Integer;
    function Layer(I: Integer): TRPLayer;
    procedure SetLayerRole(I: Integer; Role: TLPLayerRole);
    function FindRole(Role: TLPLayerRole): TLPGerberLayer;
    function CopperLayer: TLPGerberLayer;
    function HasOutline: Boolean;
    function Bounds: TLPRect;
    function BoardWidth: Double;
    function BoardHeight: Double;
    function Mirrored: Boolean;
    function OutputMatrix: TLPMatrix;
    function ToOutput(X, Y: Double): TLPPoint;
    function OutlinePaths: TLPPaths;          { projeto }
    function OutputOutline: TLPPaths;         { saida }
    function EffectiveResolution: Double;
    function IsolationWidth: Double;
    procedure RebuildMasks;
    procedure Generate;
    function Validate(Errors: TStrings; ForExport: Boolean): Boolean;
    property Generated: Boolean read FGenerated;
    property IsolationPaths: TLPPaths read FIsolation;
    property ClearanceIssues: TLPPath read FIssues;
    property Cutouts: TRPCutContours read FCutouts;
    property MilledHoles: TRPMilledHoles read FMilled;
    property DrillPlan: TLPDrillPlan read FPlan;
    property BoardMask: TLPMask read FBoard;
    property CopperMask: TLPMask read FCopper;
  end;

function RPSideName(S: TRPSide): string;

implementation

var
  InvFS: TFormatSettings;

function RPSideName(S: TRPSide): string;
begin
  if S = rsTop then Result := 'Top' else Result := 'Bottom';
end;

{ ---------------- TRPLayer ---------------- }

constructor TRPLayer.Create;
begin
  inherited Create;
  Layer := TLPGerberLayer.Create;
end;

destructor TRPLayer.Destroy;
begin
  Layer.Free;
  inherited Destroy;
end;

{ ---------------- TRouterPCBProject ---------------- }

constructor TRouterPCBProject.Create;
begin
  inherited Create;
  FLayers := TList.Create;
  Drills := TLPDrillFile.Create;
  DrillFiles := TStringList.Create;
  Warnings := TStringList.Create;
  Notes := TStringList.Create;
  FPlan := TLPDrillPlan.Create;
  Machine := RPDefaultMachine;
  Isolation := RPDefaultIsolation;
  Drilling := RPDefaultDrilling;
  Cutout := RPDefaultCutout;
  Level := RPDefaultLevel;
  Side := rsTop;
  Resolution := 0;
  FBounds := LPEmptyRect;
end;

destructor TRouterPCBProject.Destroy;
begin
  Clear;
  FLayers.Free;
  Drills.Free;
  DrillFiles.Free;
  Warnings.Free;
  Notes.Free;
  FPlan.Free;
  inherited Destroy;
end;

procedure TRouterPCBProject.FreeMasks;
begin
  FreeAndNil(FBoard);
  FreeAndNil(FCopper);
  FreeAndNil(FCutBoard);
end;

procedure TRouterPCBProject.InvalidateCAM;
begin
  FreeMasks;
  FIsolation := nil;
  FIssues := nil;
  FCutouts := nil;
  FMilled := nil;
  FPlan.Clear;
  FGenerated := False;
  FLostCutouts := 0;
  Notes.Clear;
end;

procedure TRouterPCBProject.Clear;
var I: Integer;
begin
  InvalidateCAM;
  for I := 0 to FLayers.Count - 1 do TRPLayer(FLayers[I]).Free;
  FLayers.Clear;
  Drills.Clear;
  DrillFiles.Clear;
  Warnings.Clear;
  Name := '';
  Side := rsTop;
  FBounds := LPEmptyRect;
end;

function TRouterPCBProject.LayerCount: Integer;
begin
  Result := FLayers.Count;
end;

function TRouterPCBProject.Layer(I: Integer): TRPLayer;
begin
  Result := TRPLayer(FLayers[I]);
end;

procedure TRouterPCBProject.SetLayerRole(I: Integer; Role: TLPLayerRole);
begin
  Layer(I).Role := Role;
  InvalidateCAM;
  UpdateBounds;
end;

function TRouterPCBProject.FindRole(Role: TLPLayerRole): TLPGerberLayer;
var I: Integer;
begin
  for I := 0 to LayerCount - 1 do
    if Layer(I).Role = Role then Exit(Layer(I).Layer);
  Result := nil;
end;

function TRouterPCBProject.CopperLayer: TLPGerberLayer;
begin
  if Side = rsTop then Result := FindRole(lrTopCopper)
  else Result := FindRole(lrBottomCopper);
end;

function TRouterPCBProject.OutlinePaths: TLPPaths;
var L: TLPGerberLayer;
begin
  Result := nil;
  L := FindRole(lrOutline);
  if L <> nil then Result := L.TracePaths;
end;

function TRouterPCBProject.HasOutline: Boolean;
begin
  Result := Length(OutlinePaths) > 0;
end;

procedure TRouterPCBProject.UpdateBounds;
var I: Integer; P: TLPPaths;
begin
  FBounds := LPEmptyRect;
  P := OutlinePaths;
  if Length(P) > 0 then FBounds := LPPathsBounds(P)
  else
    for I := 0 to LayerCount - 1 do LPRectIncludeRect(FBounds, Layer(I).Layer.Bounds);
end;

function TRouterPCBProject.Bounds: TLPRect;
begin
  Result := FBounds;
end;

function TRouterPCBProject.BoardWidth: Double;
begin
  if FBounds.Valid then Result := LPRectWidth(FBounds) else Result := 0;
end;

function TRouterPCBProject.BoardHeight: Double;
begin
  if FBounds.Valid then Result := LPRectHeight(FBounds) else Result := 0;
end;

function TRouterPCBProject.Mirrored: Boolean;
begin
  Result := Side = rsBottom;
end;

function TRouterPCBProject.OutputMatrix: TLPMatrix;
begin
  Result := LPIdentity;
  if not FBounds.Valid then Exit;
  if Mirrored then
  begin
    Result.A := -1; Result.C := FBounds.MaxX;
  end
  else
    Result.C := -FBounds.MinX;
  Result.F := -FBounds.MinY;
end;

function TRouterPCBProject.ToOutput(X, Y: Double): TLPPoint;
begin
  Result := LPApply(OutputMatrix, LPPoint(X, Y));
end;

function TRouterPCBProject.OutputOutline: TLPPaths;
begin
  Result := LPApplyPaths(OutputMatrix, OutlinePaths);
end;

procedure TRouterPCBProject.ImportFile(const FileName: string);
var E, FN: string; S: TRPLayer; D: TLPDrillFile; I: Integer;
begin
  if not FileExists(FileName) then raise Exception.Create('Arquivo nao encontrado: ' + FileName);
  FN := ExpandFileName(FileName);
  E := LowerCase(ExtractFileExt(FN));
  if (E = '.drl') or (E = '.xln') or (E = '.exc') then
  begin
    if DrillFiles.IndexOf(FN) >= 0 then Exit;
    D := TLPDrillFile.Create;
    try
      if not TLPExcellonReader.LoadFromFile(FN, D) then
        raise Exception.Create('Excellon sem furos reconhecidos: ' + ExtractFileName(FN));
      Drills.Merge(D);
      Warnings.AddStrings(D.Warnings);
      DrillFiles.Add(FN);
    finally
      D.Free;
    end;
  end
  else
  begin
    S := TRPLayer.Create;
    try
      if not TLPGerberReader.LoadFromFile(FN, S.Layer) then
        raise Exception.Create('Gerber sem geometria reconhecida: ' + ExtractFileName(FN));
      S.FileName := FN;
      S.Role := DetectLayerRole(FN, S.Layer.FileFunction);
      for I := LayerCount - 1 downto 0 do
        if SameFileName(Layer(I).FileName, FN) then
        begin
          Layer(I).Free;
          FLayers.Delete(I);
        end;
      Warnings.AddStrings(S.Layer.Warnings);
      FLayers.Add(S);
      S := nil;
    finally
      S.Free;
    end;
  end;
  if Name = '' then
  begin
    Name := ChangeFileExt(ExtractFileName(FN), '');
    if Pos('-', Name) > 1 then Name := Copy(Name, 1, LastDelimiter('-', Name) - 1);
  end;
  InvalidateCAM;
  UpdateBounds;
end;

function TRouterPCBProject.ImportFolder(const Dir: string): Integer;
const
  GERBER_EXT: array[0..12] of string = ('.gbr', '.ger', '.gtl', '.gbl', '.gts', '.gbs', '.gto', '.gbo',
    '.gm1', '.gko', '.gml', '.gtp', '.gbp');
  DRILL_EXT: array[0..2] of string = ('.drl', '.xln', '.exc');
var SR: TSearchRec; G, DL: TStringList; E, Base, N: string; I: Integer;

  function InList(const X: string; const L: array of string): Boolean;
  var K: Integer;
  begin
    Result := False;
    for K := 0 to High(L) do if X = L[K] then Exit(True);
  end;

begin
  Result := 0;
  if not DirectoryExists(Dir) then raise Exception.Create('Pasta nao encontrada: ' + Dir);
  Base := IncludeTrailingPathDelimiter(ExpandFileName(Dir));
  G := TStringList.Create; DL := TStringList.Create;
  try
    G.Sorted := True; DL.Sorted := True;
    if FindFirst(Base + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) <> 0 then Continue;
        E := LowerCase(ExtractFileExt(SR.Name));
        if InList(E, GERBER_EXT) then G.Add(Base + SR.Name)
        else if InList(E, DRILL_EXT) then DL.Add(Base + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    if G.Count = 0 then raise Exception.Create('Nenhum Gerber na pasta: ' + Dir);
    Clear;
    for I := 0 to G.Count - 1 do begin ImportFile(G[I]); Inc(Result); end;
    for I := 0 to DL.Count - 1 do begin ImportFile(DL[I]); Inc(Result); end;
    { nome do projeto: pasta "<nome>_gerber" do MakePCB }
    N := ExtractFileName(ExcludeTrailingPathDelimiter(Base));
    if SameText(Copy(N, Length(N) - 6, 7), '_gerber') then N := Copy(N, 1, Length(N) - 7);
    if N <> '' then Name := N;
    { face simples com cobre so embaixo: abre pelo lado Bottom }
    if (FindRole(lrTopCopper) = nil) and (FindRole(lrBottomCopper) <> nil) then Side := rsBottom
    else Side := rsTop;
  finally
    G.Free; DL.Free;
  end;
end;

function TRouterPCBProject.EffectiveResolution: Double;
var A: Double;
begin
  if Resolution > 0 then Exit(Resolution);
  Result := 0.02;
  if FBounds.Valid then
  begin
    { cabe com folga no limite de 16 milhoes de pixels do TLPMask }
    A := (BoardWidth + 2 * (Cutout.ToolDiameter + 2)) * (BoardHeight + 2 * (Cutout.ToolDiameter + 2));
    Result := Max(Result, Sqrt(A / 10e6));
  end;
  Result := Ceil(Result * 1000) / 1000;
end;

function TRouterPCBProject.IsolationWidth: Double;
begin
  Result := RPIsolationWidth(Isolation);
end;

procedure TRouterPCBProject.RebuildMasks;
var Area: TLPRect; P: TLPPaths; L: TLPGerberLayer; I: Integer; W: Double;
begin
  FreeMasks;
  P := OutlinePaths;
  if Length(P) = 0 then raise Exception.Create('Importe o contorno da placa (Edge_Cuts)');
  for I := 0 to High(P) do
    if not LPIsClosed(P[I], 0.01) then raise Exception.Create('Contorno da placa aberto');
  FRes := EffectiveResolution;
  W := IsolationWidth;
  if not RPFinite(W) or (W <= 0) then W := 0.2;
  try
    Area := FBounds;
    LPRectInflate(Area, Max(W * (Isolation.Passes + 1), FRes * 4) + 0.5);
    FBoard := TLPMask.Create(Area, FRes);
    FBoard.FillPathsEvenOdd(P);
    FBoard.DrawHoles(Drills, 0);
    FCopper := TLPMask.CreateLike(FBoard);
    L := CopperLayer;
    if L <> nil then
    begin
      FCopper.DrawGerber(L);
      FCopper.AndMask(FBoard);
    end;
    Area := FBounds;
    LPRectInflate(Area, Max(Cutout.ToolDiameter, 0.5) + 1);
    FCutBoard := TLPMask.Create(Area, FRes);
    FCutBoard.FillPathsEvenOdd(P);
  except
    FreeMasks;
    raise;
  end;
end;

function ApplyPath(const M: TLPMatrix; const P: TLPPath): TLPPath;
var I: Integer;
begin
  SetLength(Result, Length(P));
  for I := 0 to High(P) do Result[I] := LPApply(M, P[I]);
end;

procedure TRouterPCBProject.Generate;
var M: TLPMatrix; P: TLPPaths; Outer, I, Loops: Integer; MillD: Double;
  C: TRPCutContour; Inner: TRPCutContours;
begin
  InvalidateCAM;
  RebuildMasks;
  M := OutputMatrix;
  { isolacao }
  if Isolation.Enabled and (CopperLayer <> nil) then
  begin
    P := RPIsolationPaths(FCopper, FBoard, Isolation, Mirrored);
    FIsolation := RPOrderPaths(LPApplyPaths(M, P), 0, 0);
    FIssues := RPClearanceIssues(FCopper, IsolationWidth);
    for I := 0 to High(FIssues) do FIssues[I] := LPApply(M, FIssues[I]);
  end;
  { furacao }
  if Cutout.Enabled then MillD := Cutout.ToolDiameter else MillD := 0;
  RPBuildDrilling(Drills, M, Drilling, MillD, FPlan, FMilled, Notes);
  if (Length(FMilled) > 0) and not Cutout.Enabled then FMilled := nil;
  { recorte: internos primeiro, externo por ultimo (a placa sai no fim) }
  if Cutout.Enabled then
  begin
    P := RPCutoutContours(FCutBoard, Cutout.ToolDiameter, FRes / 4,
      (Cutout.Direction = cdClimb) xor Mirrored);
    Outer := RPOuterIndex(P);
    Loops := Length(OutlinePaths);
    if Length(P) < Loops then
    begin
      FLostCutouts := Loops - Length(P);
      Notes.Add(Format('%d recorte(s) interno(s) menor(es) que a fresa de %.2f mm ficaram de fora',
        [FLostCutouts, Cutout.ToolDiameter], InvFS));
    end;
    Inner := nil;
    for I := 0 to High(P) do
    begin
      if I = Outer then Continue;
      C.Path := ApplyPath(M, P[I]);
      C.Outer := False;
      C.Tabs := nil;
      SetLength(Inner, Length(Inner) + 1);
      Inner[High(Inner)] := C;
    end;
    FCutouts := Inner;
    if Outer >= 0 then
    begin
      SetLength(FCutouts, Length(FCutouts) + 1);
      C.Path := ApplyPath(M, P[Outer]);
      C.Outer := True;
      C.Tabs := RPTabIntervals(C.Path, Cutout.Tabs, Cutout.TabWidth, Cutout.ToolDiameter);
      FCutouts[High(FCutouts)] := C;
      if (Cutout.Tabs > 0) and (Length(C.Tabs) < Cutout.Tabs) then
        Notes.Add(Format('Placa pequena: %d ponte(s) em vez de %d', [Length(C.Tabs), Cutout.Tabs]));
    end;
  end;
  FGenerated := True;
end;

function TRouterPCBProject.Validate(Errors: TStrings; ForExport: Boolean): Boolean;
var N0, I: Integer; P: TLPPaths;

  procedure Err(const S: string);
  begin
    Errors.Add(S);
  end;

begin
  N0 := Errors.Count;
  RPValidateMachine(Machine, Errors);
  RPValidateIsolation(Isolation, Errors);
  RPValidateDrilling(Drilling, Errors);
  RPValidateCutout(Cutout, Errors);
  RPValidateLevel(Level, Errors);
  if not (Isolation.Enabled or Drilling.Enabled or Cutout.Enabled) then
    Err('Ligue pelo menos uma operacao (isolacao, furacao ou recorte)');
  if LayerCount = 0 then Err('Importe a pasta Gerber + Excellon da placa (MakePCB: <nome>_gerber)')
  else
  begin
    P := OutlinePaths;
    if Length(P) = 0 then Err('Contorno da placa (Edge_Cuts) nao encontrado: defina a funcao da camada')
    else
      for I := 0 to High(P) do
        if not LPIsClosed(P[I], 0.01) then
        begin
          Err('Contorno da placa aberto');
          Break;
        end;
    if Isolation.Enabled and (CopperLayer = nil) then
      Err('Sem camada de cobre ' + RPSideName(Side) + ': troque o lado ou desligue a isolacao');
  end;
  if ForExport and (Errors.Count = N0) then
  begin
    if not FGenerated then Err('Gere as trajetorias antes de exportar')
    else
    begin
      if Isolation.Enabled and (Length(FIsolation) = 0) then
        Err('Isolacao vazia: confira o cobre do lado ' + RPSideName(Side));
      if Isolation.Enabled and (Length(FIssues) > 0) then
        Err(Format('Folga entre cobres menor que a fresa (%.3f mm) em %d ponto(s), o primeiro em X %.2f Y %.2f: ' +
          'reduza a profundidade, use ponta menor ou aumente a folga no MakePCB',
          [IsolationWidth, Length(FIssues), FIssues[0].X, FIssues[0].Y], InvFS));
      if Cutout.Enabled and (Length(FCutouts) = 0) then
        Err('Recorte vazio: confira o contorno da placa');
      if Drilling.Enabled and (FPlan.HoleCount = 0) and (Length(FMilled) = 0) and (DrillFiles.Count > 0) then
        Err('Nenhum furo passou no filtro PTH/NPTH');
    end;
  end;
  Result := Errors.Count = N0;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
