unit laserpcb_project;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, laserpcb_types, laserpcb_job, laserpcb_layout,
  laserpcb_geom, laserpcb_gerber, laserpcb_excellon, laserpcb_raster, laserpcb_drill;

type
  { cmDrillMarks: marca a laser o lugar de cada furo (laserpcb_drill)
    cmOutline:    percorre o contorno da placa (linha, sem compensacao) }
  TLPCamMode = (cmVectors, cmIsolation, cmRemoveCopper, cmLayerHatch, cmDrillMarks, cmOutline);
  TLPLayerRole = (lrUnknown, lrTopCopper, lrBottomCopper, lrOutline,
    lrTopMask, lrBottomMask, lrTopSilk, lrBottomSilk);
  TLPSource = class
    FileName: string;
    Role: TLPLayerRole;
    Layer: TLPGerberLayer;
    constructor Create;
    destructor Destroy; override;
  end;
  { Camada de corte (estilo "Cuts / Layers" do LightBurn): um processo com
    seus parametros. O trabalho junta as camadas com Saida ligada, na ordem
    da lista. Feixe, S-max e resolucao sao da maquina (Profile do projeto). }
  TLPOperation = class
  public
    Name: string;
    ColorIndex: Integer;       { paleta 00..29 }
    Mode: TLPCamMode;
    SourceLayer: Integer;      { cmLayerHatch: indice da camada importada }
    Power, Feed, Overlap: Double;
    Passes: Integer;
    MarkKind: TLPMarkKind;
    MarkDiameter: Double;
    Output, Show: Boolean;
    ItemPaths: array of TLPPaths;   { trajetorias por copia (Generate) }
    constructor Create;
    function Caption: string;
    function Generated: Boolean;
    function PathsFor(Index: Integer): TLPPaths;
    function CutLength: Double;
  end;

  TLaserPCBProject = class
  private
    FOperations: TList;
    FSources: TList;
    FSVG: TLaserPCBJob;
    FBoard, FCopper, FArtwork: TLPMask;
    FPaths: TLPPaths;
    FItemPaths: array of TLPPaths;
    FBounds: TLPRect;
    FSVGFile: string;
    function ProcessMasks(Copper, Board, Artwork: TLPMask): TLPPaths;
    function ScaledPaths(SX, SY: Double): TLPPaths;
    procedure UpdateBoard;
    procedure FreeMasks;
    function FindRole(Role: TLPLayerRole): TLPGerberLayer;
    function SVGPaths: TLPPaths;
    function DrillMarkPaths: TLPPaths;
  public
    Layout: TLaserBedLayout;
    Drills: TLPDrillFile;
    DrillFiles, Warnings: TStringList;
    Profile: TLaserProfile;
    Side: TPCBLayerSide;
    MirrorBottom: Boolean;
    Mode: TLPCamMode;
    Resolution, Overlap: Double;
    SelectedLayer: Integer;
    { furacao: filtro comum a marcacao e ao CNC Router }
    DrillFilter: TLPDrillFilter;
    MarkKind: TLPMarkKind;
    MarkDiameter: Double;
    Router: TLPRouterOptions;
    { pinos de registro para dupla face (somente no programa do Router) }
    RegistrationPins: Boolean;
    RegistrationOffset, RegistrationDiameter: Double;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure InvalidateCAM;
    procedure ImportFile(const FileName: string);
    { importa todos os Gerber/Excellon de uma pasta (ex.: exportacao do MakePCB);
      devolve quantos arquivos entraram }
    function ImportFolder(const Dir: string): Integer;
    function SourceCount: Integer;
    function Source(I: Integer): TLPSource;
    procedure SetLayerRole(I: Integer; Role: TLPLayerRole);
    function HasSVG: Boolean;
    function Width: Double;
    function Height: Double;
    function OriginX: Double;
    function OriginY: Double;
    function OutlinePaths: TLPPaths;
    function ReferencePaths: TLPPaths;
    procedure RebuildMasks(GridResolution: Double = 0);
    procedure Generate;
    function AddCopy: TLaserLayoutItem;
    function WorldPoint(Item: TLaserLayoutItem; const P: TLPPoint): TLPPoint;
    function Validate(Errors: TStrings; ForExport: Boolean): Boolean;
    function BuildJob: TLaserPCBJob;
    function PathsForItem(Item: TLaserLayoutItem): TLPPaths;
    { furos de todas as copias, ja na mesa (mm), filtrados e ordenados }
    procedure BuildDrillPlan(Plan: TLPDrillPlan);
    function ValidateDrilling(Errors: TStrings): Boolean;
    { programa de furacao para CNC Router; valida antes de gerar.
      GroupIndex -1 = todas as brocas; >= 0 = so a broca indicada do plano }
    function DrillProgram(const Title: string; GroupIndex: Integer = -1): TStringList;
    property BoardMask: TLPMask read FBoard;
    property CopperMask: TLPMask read FCopper;
    property ArtworkMask: TLPMask read FArtwork;
    property Paths: TLPPaths read FPaths;
    property SVGFile: string read FSVGFile;
  public
    { ---- camadas de corte ---- }
    function OperationCount: Integer;
    function Operation(I: Integer): TLPOperation;
    function AddOperation(AMode: TLPCamMode; const AName: string; AColor: Integer): TLPOperation;
    procedure DeleteOperation(I: Integer);
    procedure MoveOperation(I, Delta: Integer);
    procedure ClearOperations;
    { cria as camadas tipicas para o que foi importado (so se nao houver camadas) }
    procedure CreateDefaultOperations;
    { copia os parametros da camada para os campos do processo unico }
    procedure ApplyOperation(Op: TLPOperation);
    { gera as camadas com Saida ou Mostrar ligado; erro cita a camada }
    procedure GenerateOperations;
    procedure InvalidateOperations;
    function ValidateOperations(Errors: TStrings; ForExport: Boolean): Boolean;
    { trabalho unico com potencia/velocidade por camada; passadas expandidas }
    function BuildOperationsJob: TLaserPCBJob;
    { comprimento de corte e tempo estimado das camadas com Saida }
    procedure EstimateOperations(RapidFeed: Double; out CutMM, TravelMM, Seconds: Double);
  end;
function LayerRoleName(Role: TLPLayerRole): string;
function CamModeName(Mode: TLPCamMode): string;
function DetectLayerRole(const FileName, FileFunction: string): TLPLayerRole;
implementation
uses laserpcb_svg, laserpcb_profile, laserpcb_cam, laserpcb_gcode;

function CamModeName(Mode: TLPCamMode): string;
begin
  case Mode of
    cmVectors: Result := 'Vetores';
    cmIsolation: Result := 'Isolacao';
    cmRemoveCopper: Result := 'Remocao';
    cmLayerHatch: Result := 'Preencher';
    cmDrillMarks: Result := 'Furos';
    cmOutline: Result := 'Contorno';
  else Result := '?'; end;
end;

{ ---------------- TLPOperation ---------------- }

constructor TLPOperation.Create;
begin
  inherited Create;
  SourceLayer := -1; Overlap := 0.2; Passes := 1;
  MarkKind := mkCenter; MarkDiameter := 0.4;
  Output := True; Show := True;
  { Potencia e velocidade comecam zeradas: dependem de calibracao. }
end;
function TLPOperation.Caption: string;
begin Result := 'C' + Format('%.2d', [ColorIndex]); end;
function TLPOperation.Generated: Boolean;
begin Result := Length(ItemPaths) > 0; end;
function TLPOperation.PathsFor(Index: Integer): TLPPaths;
begin
  if (Index >= 0) and (Index < Length(ItemPaths)) then Result := ItemPaths[Index] else Result := nil;
end;
function TLPOperation.CutLength: Double;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(ItemPaths) do Result := Result + LPPathsLength(ItemPaths[I]);
end;

function LayerRoleName(Role: TLPLayerRole): string;
begin
  case Role of
    lrTopCopper: Result := 'Cobre Top';
    lrBottomCopper: Result := 'Cobre Bottom';
    lrOutline: Result := 'Contorno da placa';
    lrTopMask: Result := 'Mascara Top';
    lrBottomMask: Result := 'Mascara Bottom';
    lrTopSilk: Result := 'Serigrafia Top';
    lrBottomSilk: Result := 'Serigrafia Bottom';
  else Result := 'Definir funcao'; end;
end;

function DetectLayerRole(const FileName, FileFunction: string): TLPLayerRole;
var S, E: string; Bottom: Boolean;
begin
  S := LowerCase(FileFunction + ' ' + ExtractFileName(FileName));
  E := LowerCase(ExtractFileExt(FileName));
  Bottom := (Pos('bot', S) > 0) or (Pos('b_cu', S) > 0) or
    (Pos('b_mask', S) > 0) or (Pos('b_silk', S) > 0) or (E = '.gbl') or
    (E = '.gbs') or (E = '.gbo');
  if (Pos('profile', S) > 0) or (Pos('edge_cuts', S) > 0) or
     (E = '.gm1') or (E = '.gko') then Exit(lrOutline);
  if (Pos('copper', S) > 0) or (Pos('_cu', S) > 0) or (E = '.gtl') or (E = '.gbl') then
  begin if Bottom then Exit(lrBottomCopper) else Exit(lrTopCopper); end;
  if (Pos('soldermask', S) > 0) or (Pos('_mask', S) > 0) or (E = '.gts') or (E = '.gbs') then
  begin if Bottom then Exit(lrBottomMask) else Exit(lrTopMask); end;
  if (Pos('legend', S) > 0) or (Pos('silk', S) > 0) or (E = '.gto') or (E = '.gbo') then
  begin if Bottom then Exit(lrBottomSilk) else Exit(lrTopSilk); end;
  Result := lrUnknown;
end;

constructor TLPSource.Create;
begin inherited Create; Layer := TLPGerberLayer.Create; end;
destructor TLPSource.Destroy;
begin Layer.Free; inherited Destroy; end;
constructor TLaserPCBProject.Create;
begin
  inherited Create;
  FSources := TList.Create; FSVG := TLaserPCBJob.Create; FOperations := TList.Create;
  Layout := TLaserBedLayout.Create; Drills := TLPDrillFile.Create;
  DrillFiles := TStringList.Create; Warnings := TStringList.Create;
  Profile := DefaultLaserProfile;
  Side := lsTop; MirrorBottom := True; Mode := cmIsolation;
  Resolution := 0.05; Overlap := 0.2; SelectedLayer := -1;
  FBounds := LPEmptyRect;
  DrillFilter := LPDefaultDrillFilter; MarkKind := mkCenter; MarkDiameter := 0.4;
  Router := LPDefaultRouterOptions;
  RegistrationPins := False; RegistrationOffset := 5; RegistrationDiameter := 3;
end;
destructor TLaserPCBProject.Destroy;
begin
  Clear; FOperations.Free; FSources.Free; FSVG.Free; Layout.Free; Drills.Free;
  DrillFiles.Free; Warnings.Free; inherited Destroy;
end;
procedure TLaserPCBProject.FreeMasks;
begin FreeAndNil(FBoard); FreeAndNil(FCopper); FreeAndNil(FArtwork); end;
procedure TLaserPCBProject.InvalidateCAM;
begin FPaths := nil; FItemPaths := nil; FreeMasks; InvalidateOperations; end;
procedure TLaserPCBProject.Clear;
var I: Integer;
begin
  InvalidateCAM; ClearOperations;
  for I := 0 to FSources.Count - 1 do TObject(FSources[I]).Free;
  FSources.Clear; FSVG.Clear; FSVGFile := ''; FBounds := LPEmptyRect; Mode := cmIsolation;
  Layout.Clear; Drills.Clear; DrillFiles.Clear; Warnings.Clear; SelectedLayer := -1;
end;
function TLaserPCBProject.SourceCount: Integer;
begin Result := FSources.Count; end;
function TLaserPCBProject.Source(I: Integer): TLPSource;
begin Result := TLPSource(FSources[I]); end;
function TLaserPCBProject.HasSVG: Boolean;
begin Result := FSVG.Count > 0; end;
function TLaserPCBProject.Width: Double;
begin Result := LPRectWidth(FBounds); end;
function TLaserPCBProject.Height: Double;
begin Result := LPRectHeight(FBounds); end;
function TLaserPCBProject.OriginX: Double;
begin Result := FBounds.MinX; end;
function TLaserPCBProject.OriginY: Double;
begin Result := FBounds.MinY; end;
function TLaserPCBProject.FindRole(Role: TLPLayerRole): TLPGerberLayer;
var I: Integer;
begin
  Result := nil;
  for I := 0 to SourceCount - 1 do
    if Source(I).Role = Role then
    begin
      if Result <> nil then raise Exception.Create('Mais de uma camada: ' + LayerRoleName(Role));
      Result := Source(I).Layer;
    end;
end;
procedure TLaserPCBProject.SetLayerRole(I: Integer; Role: TLPLayerRole);
begin Source(I).Role := Role; InvalidateCAM; UpdateBoard; end;
function TLaserPCBProject.SVGPaths: TLPPaths;
var I: Integer; P: TPathPoint; Q: TLPPath;
begin
  Result := nil; Q := nil;
  for I := 0 to FSVG.Count - 1 do
  begin
    P := FSVG.RawPoint(I);
    if not P.LaserOn then
    begin if Length(Q) > 1 then LPAddPath(Result, Q); Q := nil; end;
    LPAddPoint(Q, P.X, P.Y);
  end;
  if Length(Q) > 1 then LPAddPath(Result, Q);
end;
function TLaserPCBProject.OutlinePaths: TLPPaths;
var L: TLPGerberLayer;
begin
  Result := nil;
  L := FindRole(lrOutline);
  if L <> nil then Result := L.TracePaths;
end;
procedure TLaserPCBProject.UpdateBoard;
var I: Integer; P: TLPPaths; L: TLPGerberLayer;
begin
  FBounds := LPEmptyRect;
  Warnings.Clear;
  if HasSVG then
  begin
    LPRectInclude(FBounds, 0, 0); LPRectInclude(FBounds, FSVG.Width, FSVG.Height);
    Warnings.AddStrings(FSVG.Warnings);
  end
  else
  begin
    L := FindRole(lrOutline);
    if L <> nil then
    begin
      P := L.TracePaths;
      FBounds := LPPathsBounds(P);
      for I := 0 to High(P) do
        if not LPIsClosed(P[I], 0.01) then Warnings.Add('Contorno da placa esta aberto');
      if Length(P) = 0 then Warnings.Add('Contorno sem linhas de centro reconhecidas');
    end;
    if not FBounds.Valid then
    begin
      for I := 0 to SourceCount - 1 do LPRectIncludeRect(FBounds, Source(I).Layer.Bounds);
      if SourceCount > 0 then Warnings.Add('Importe um contorno Gerber fechado para gerar CAM');
    end;
    for I := 0 to SourceCount - 1 do
    begin
      Warnings.AddStrings(Source(I).Layer.Warnings);
      if Source(I).Layer.Negative then Warnings.Add('Gerber negativo precisa de conversao para positivo');
    end;
    Warnings.AddStrings(Drills.Warnings);
  end;
  for I := 0 to Layout.Count - 1 do
  begin Layout.Item(I).Width := Width; Layout.Item(I).Height := Height; end;
  if (Layout.Count = 0) and (Width > 0) and (Height > 0) then AddCopy;
end;
procedure TLaserPCBProject.ImportFile(const FileName: string);
var E: string; S: TLPSource; D: TLPDrillFile; J: TLaserPCBJob; I: Integer;
begin
  if not FileExists(FileName) then raise Exception.Create('Arquivo nao encontrado: ' + FileName);
  E := LowerCase(ExtractFileExt(FileName));
  if E = '.svg' then
  begin
    J := TLaserPCBJob.Create;
    try
      if not TSVGImporter.ImportFile(FileName, J) then raise Exception.Create('SVG sem vetores reconhecidos');
      Clear; FSVG.Free; FSVG := J; J := nil; FSVGFile := ExpandFileName(FileName); Mode := cmVectors;
    finally J.Free; end;
  end
  else if (E = '.drl') or (E = '.xln') or (E = '.exc') then
  begin
    if HasSVG then raise Exception.Create('Inicie um projeto Gerber antes de adicionar Excellon');
    if DrillFiles.IndexOf(ExpandFileName(FileName)) >= 0 then Exit;
    D := TLPDrillFile.Create;
    try
      if not TLPExcellonReader.LoadFromFile(FileName, D) then raise Exception.Create('Excellon sem furos reconhecidos');
      Drills.Merge(D); Drills.Warnings.AddStrings(D.Warnings);
      DrillFiles.Add(ExpandFileName(FileName));
    finally D.Free; end;
  end
  else
  begin
    S := TLPSource.Create;
    try
      if not TLPGerberReader.LoadFromFile(FileName, S.Layer) then raise Exception.Create('Gerber sem geometria reconhecida');
      if HasSVG then begin Clear; Mode := cmIsolation; end;
      S.FileName := ExpandFileName(FileName);
      S.Role := DetectLayerRole(FileName, S.Layer.FileFunction);
      for I := SourceCount - 1 downto 0 do
        if SameFileName(Source(I).FileName, S.FileName) then
        begin Source(I).Free; FSources.Delete(I); end;
      FSources.Add(S); SelectedLayer := FSources.Count - 1; S := nil;
    finally S.Free; end;
  end;
  InvalidateCAM; UpdateBoard;
end;
function TLaserPCBProject.ImportFolder(const Dir: string): Integer;
const
  GERBER_EXT: array[0..12] of string = ('.gbr', '.ger', '.gtl', '.gbl', '.gts', '.gbs', '.gto', '.gbo',
    '.gm1', '.gko', '.gml', '.gtp', '.gbp');
  DRILL_EXT: array[0..2] of string = ('.drl', '.xln', '.exc');
var
  SR: TSearchRec;
  Gerbers, Drills_: TStringList;
  E, Base: string;
  I: Integer;
  function InList(const X: string; const L: array of string): Boolean;
  var K: Integer;
  begin
    Result := False;
    for K := 0 to High(L) do if X = L[K] then Exit(True);
  end;
begin
  Result := 0;
  if not DirectoryExists(Dir) then raise Exception.Create('Pasta nao encontrada: ' + Dir);
  Base := IncludeTrailingPathDelimiter(Dir);
  Gerbers := TStringList.Create; Drills_ := TStringList.Create;
  try
    Gerbers.Sorted := True; Drills_.Sorted := True;
    if FindFirst(Base + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) <> 0 then Continue;
        E := LowerCase(ExtractFileExt(SR.Name));
        if InList(E, GERBER_EXT) then Gerbers.Add(Base + SR.Name)
        else if InList(E, DRILL_EXT) then Drills_.Add(Base + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    if Gerbers.Count = 0 then raise Exception.Create('Nenhum Gerber na pasta: ' + Dir);
    { Gerber antes do Excellon (o furo precisa da placa) }
    for I := 0 to Gerbers.Count - 1 do begin ImportFile(Gerbers[I]); Inc(Result); end;
    for I := 0 to Drills_.Count - 1 do begin ImportFile(Drills_[I]); Inc(Result); end;
    { placa de face simples (cobre so embaixo): ja abre pelo lado Bottom }
    if (FindRole(lrTopCopper) = nil) and (FindRole(lrBottomCopper) <> nil) then Side := lsBottom;
  finally
    Gerbers.Free; Drills_.Free;
  end;
end;
function TLaserPCBProject.AddCopy: TLaserLayoutItem;
begin
  if (Width <= 0) or (Height <= 0) then raise Exception.Create('Importe uma placa primeiro');
  Result := Layout.AddItem('Placa ' + IntToStr(Layout.Count + 1), Width, Height);
  Result.X := Layout.Margin; Result.Y := Layout.Margin;
  if Layout.Count > 1 then
    Result.X := Layout.Item(Layout.Count-2).X + Layout.Item(Layout.Count-2).PlacedWidth + Layout.Spacing;
end;
function TLaserPCBProject.ReferencePaths: TLPPaths;
var L: TLPGerberLayer; I, J: Integer; S: TLPGShape;
begin
  if HasSVG then Exit(SVGPaths);
  Result := nil;
  if Side = lsTop then L := FindRole(lrTopCopper) else L := FindRole(lrBottomCopper);
  if L = nil then Exit;
  for I := 0 to L.ShapeCount - 1 do
  begin
    S := L.Shape(I);
    for J := 0 to High(S.Items) do LPAddPaths(Result, S.Items[J].Paths);
  end;
end;
procedure TLaserPCBProject.RebuildMasks(GridResolution: Double);
var Area: TLPRect; P: TLPPaths; L: TLPGerberLayer; I: Integer;
begin
  FreeMasks;
  if HasSVG then Exit;
  if GridResolution = 0 then GridResolution := Resolution;
  if not FiniteNumber(Resolution) or (Resolution < 0.001) then
    raise Exception.Create('Resolucao deve ser pelo menos 0,001 mm');
  L := FindRole(lrOutline);
  if L = nil then raise Exception.Create('Importe um contorno Gerber fechado');
  P := L.TracePaths;
  if Length(P) = 0 then raise Exception.Create('Contorno sem trajetorias');
  for I := 0 to High(P) do
    if not LPIsClosed(P[I], 0.01) then raise Exception.Create('Contorno da placa aberto');
  Area := FBounds;
  LPRectInflate(Area, Max(Profile.SpotMM * (Profile.Passes+1), Resolution*4));
  try
    FBoard := TLPMask.Create(Area, GridResolution); FBoard.FillPathsEvenOdd(P);
    FBoard.DrawHoles(Drills, 0);
    FCopper := TLPMask.CreateLike(FBoard);
    if Side = lsTop then L := FindRole(lrTopCopper) else L := FindRole(lrBottomCopper);
    if L <> nil then begin FCopper.DrawGerber(L); FCopper.AndMask(FBoard); end;
    FArtwork := TLPMask.CreateLike(FBoard);
    if (SelectedLayer >= 0) and (SelectedLayer < SourceCount) then
    begin FArtwork.DrawGerber(Source(SelectedLayer).Layer); FArtwork.AndMask(FBoard); end;
  except FreeMasks; raise; end;
end;
function TLaserPCBProject.ProcessMasks(Copper, Board, Artwork: TLPMask): TLPPaths;
var M, SafeBoard: TLPMask; Generated: TLPPaths; L: TLPGerberLayer;
begin
  SafeBoard := LPOffsetMask(Board, Profile.SpotMM/2);
  try
    case Mode of
      cmIsolation, cmRemoveCopper:
      begin
        if Side = lsTop then L := FindRole(lrTopCopper) else L := FindRole(lrBottomCopper);
        if L = nil then raise Exception.Create('Camada de cobre do lado selecionado ausente');
        if Mode = cmIsolation then
          Generated := LPIsolation(Copper, SafeBoard, Profile.SpotMM, Profile.Passes, Overlap, Board.Res/4)
        else
        begin
          M := LPRemoveCopperMask(Copper, Board, Profile.SpotMM/2);
          try Generated := LPHatch(M, Profile.SpotMM*(1-Overlap), Profile.SpotMM/2, hdHorizontal, True);
          finally M.Free; end;
          Generated := LPClipPathsToMask(Generated, SafeBoard);
        end;
      end;
      cmLayerHatch:
      begin
        if (SelectedLayer < 0) or (SelectedLayer >= SourceCount) then raise Exception.Create('Selecione uma camada para preencher');
        if Source(SelectedLayer).Role in [lrUnknown,lrOutline] then raise Exception.Create('Defina a funcao da camada a preencher');
        Generated := LPHatch(Artwork, Profile.SpotMM*(1-Overlap), Profile.SpotMM/2, hdHorizontal, True);
        Generated := LPClipPathsToMask(Generated, SafeBoard);
      end;
    else raise Exception.Create('Selecione um processo CAM para o Gerber');
    end;
    Result := Generated;
    if Length(Result) = 0 then raise Exception.Create('CAM vazio; confira camada, feixe e resolucao');
  finally SafeBoard.Free; end;
end;

function TLaserPCBProject.ScaledPaths(SX, SY: Double): TLPPaths;
var Area: TLPRect; B,C,A: TLPMask; X,Y,I,J,IX,IY: Integer; RX,RY: Double;
begin
  SX := Abs(SX); SY := Abs(SY);
  Area := FBoard.Area;
  Area.MinX := (Area.MinX-OriginX)*SX; Area.MaxX := (Area.MaxX-OriginX)*SX;
  Area.MinY := (Area.MinY-OriginY)*SY; Area.MaxY := (Area.MaxY-OriginY)*SY;
  B := nil; C := nil; A := nil;
  try
    B := TLPMask.Create(Area,Resolution); C := TLPMask.CreateLike(B); A := TLPMask.CreateLike(B);
    for Y := 0 to B.Height-1 do
    begin
      RY := B.PixelY(Y)/SY+OriginY; IY := FBoard.RowOf(RY);
      for X := 0 to B.Width-1 do
      begin
        RX := B.PixelX(X)/SX+OriginX; IX := FBoard.ColOf(RX);
        B.SetPx(X,Y,FBoard.Get(IX,IY)); C.SetPx(X,Y,FCopper.Get(IX,IY)); A.SetPx(X,Y,FArtwork.Get(IX,IY));
      end;
    end;
    { Os offsets usam a geometria escalada e o diametro fisico do laser. }
    Result := ProcessMasks(C,B,A);
    for I := 0 to High(Result) do for J := 0 to High(Result[I]) do
    begin Result[I][J].X := Result[I][J].X/SX+OriginX; Result[I][J].Y := Result[I][J].Y/SY+OriginY; end;
    Result := LPOrderPaths(Result,OriginX,OriginY);
  finally A.Free; C.Free; B.Free; end;
end;

procedure TLaserPCBProject.Generate;
var I: Integer; MaxScale, SX, SY: Double;
begin
  FPaths := nil; FItemPaths := nil;
  if not FiniteNumber(Profile.SpotMM) or (Profile.SpotMM <= 0) or
    (Profile.Passes < 1) or (Profile.Passes > 1000) or not FiniteNumber(Overlap) or
    (Overlap < 0) or (Overlap > 0.9) then raise Exception.Create('Feixe, passadas ou sobreposicao invalidos');
  if HasSVG then
  begin
    if Mode <> cmVectors then raise Exception.Create('SVG usa modo Vetores; areas de cobre requerem Gerber');
    FPaths := SVGPaths; Exit;
  end;
  if Mode = cmVectors then raise Exception.Create('Selecione um processo CAM para o Gerber');
  if Mode = cmOutline then
  begin
    RebuildMasks(Resolution);
    FPaths := LPOrderPaths(OutlinePaths,OriginX,OriginY);
    SetLength(FItemPaths,Layout.Count);
    for I := 0 to Layout.Count-1 do FItemPaths[I] := FPaths;
    Exit;
  end;
  if Mode = cmDrillMarks then
  begin
    { A mascara so serve para a previa; marcas nao dependem do contorno. }
    if FindRole(lrOutline) <> nil then RebuildMasks(Resolution);
    FPaths := LPOrderPaths(DrillMarkPaths,OriginX,OriginY);
    if Length(FPaths) = 0 then raise Exception.Create('Nenhum furo selecionado para marcar');
    SetLength(FItemPaths,Layout.Count);
    for I := 0 to Layout.Count-1 do FItemPaths[I] := FPaths;
    Exit;
  end;
  MaxScale := 1;
  for I := 0 to Layout.Count-1 do
  begin
    SX := Abs(Layout.Item(I).ScaleX); SY := Abs(Layout.Item(I).ScaleY);
    if not FiniteNumber(SX) or not FiniteNumber(SY) or (SX < 1e-9) or (SY < 1e-9) then
      raise Exception.Create('Escala da placa invalida');
    MaxScale := Max(MaxScale,Max(SX,SY));
  end;
  RebuildMasks(Resolution/MaxScale);
  try
    FPaths := LPOrderPaths(ProcessMasks(FCopper,FBoard,FArtwork),OriginX,OriginY);
    SetLength(FItemPaths,Layout.Count);
    for I := 0 to Layout.Count-1 do
    begin
      SX := Layout.Item(I).ScaleX; SY := Layout.Item(I).ScaleY;
      if (Abs(Abs(SX)-1) < 1e-9) and (Abs(Abs(SY)-1) < 1e-9) then FItemPaths[I] := FPaths
      else FItemPaths[I] := ScaledPaths(SX,SY);
    end;
  except FPaths := nil; FItemPaths := nil; raise; end;
end;

function TLaserPCBProject.DrillMarkPaths: TLPPaths;
var Plan: TLPDrillPlan;
begin
  if Drills.HoleCount = 0 then raise Exception.Create('Importe um Excellon para marcar os furos');
  Plan := TLPDrillPlan.Create;
  try
    Plan.AddFile(Drills,LPIdentity,DrillFilter);
    Result := Plan.LaserMarks(MarkKind,MarkDiameter,Profile.SpotMM,Max(0.002,Resolution/4));
  finally Plan.Free; end;
end;

procedure TLaserPCBProject.BuildDrillPlan(Plan: TLPDrillPlan);
var I, J: Integer; H: TLPHole; T: TLPDrillTool; A, B, P1, P2: TLPPoint;
  Item: TLaserLayoutItem; Box: TLPRect;
begin
  Plan.Clear;
  for I := 0 to Layout.Count-1 do
  begin
    Item := Layout.Item(I);
    for J := 0 to Drills.HoleCount-1 do
    begin
      H := Drills.Holes[J];
      if (H.Tool < 0) or (H.Tool > High(Drills.Tools)) then Continue;
      T := Drills.Tools[H.Tool];
      if not LPDrillFilterAccepts(DrillFilter,T.Diameter,T.Plated) then Continue;
      { mesmo mapeamento das trajetorias do laser: copia, rotacao, escala e espelho Bottom }
      A := WorldPoint(Item,LPPoint(H.X,H.Y));
      if H.Slot then
      begin
        B := WorldPoint(Item,LPPoint(H.X2,H.Y2));
        Plan.AddSlot(A.X,A.Y,B.X,B.Y,T.Diameter,T.Plated);
      end
      else Plan.AddHole(A.X,A.Y,T.Diameter,T.Plated);
    end;
    if RegistrationPins then
    begin
      Box := LPEmptyRect;
      LPRectInclude(Box,Item.X,Item.Y);
      LPRectInclude(Box,Item.X+Item.PlacedWidth,Item.Y+Item.PlacedHeight);
      { eixo vertical no centro da placa: virar a placa nesse eixo mantem os pinos }
      LPRegistrationHoles(Box,Item.X+Item.PlacedWidth/2,RegistrationOffset,P1,P2);
      Plan.AddHole(P1.X,P1.Y,RegistrationDiameter,False);
      Plan.AddHole(P2.X,P2.Y,RegistrationDiameter,False);
    end;
  end;
  Plan.Optimize(0,0);
end;

function TLaserPCBProject.ValidateDrilling(Errors: TStrings): Boolean;
var N, I: Integer; Plan: TLPDrillPlan; B: TLPRect;
begin
  N := Errors.Count;
  if HasSVG then Errors.Add('Furacao requer um projeto Gerber + Excellon');
  if Drills.HoleCount = 0 then Errors.Add('Importe um arquivo Excellon');
  Layout.Validate(Errors);
  if Layout.Count = 0 then Errors.Add('Importe uma placa');
  LPValidateRouterOptions(Router,Errors);
  if RegistrationPins then
  begin
    if not (FiniteNumber(RegistrationOffset) and FiniteNumber(RegistrationDiameter)) or
      (RegistrationDiameter <= 0) or (RegistrationOffset < RegistrationDiameter/2) then
      Errors.Add('Pinos de registro: afastamento deve ser maior que o raio do pino');
    for I := 0 to Layout.Count-1 do
      if Abs(Frac(Layout.Item(I).Rotation/180)) > 1e-6 then
        Errors.Add(Layout.Item(I).Name+': pinos de registro exigem rotacao 0 ou 180 graus');
  end;
  if Errors.Count = N then
  begin
    Plan := TLPDrillPlan.Create;
    try
      BuildDrillPlan(Plan);
      if Plan.HoleCount = 0 then Errors.Add('Nenhum furo passa pelo filtro de diametro/tipo')
      else
      begin
        B := Plan.Bounds;
        if (B.MinX < -1e-6) or (B.MinY < -1e-6) or (B.MaxX > Layout.BedWidth+1e-6) or
          (B.MaxY > Layout.BedHeight+1e-6) then
          Errors.Add('Furos ou pinos de registro fora da mesa');
      end;
    finally Plan.Free; end;
  end;
  Result := Errors.Count = N;
end;

function TLaserPCBProject.DrillProgram(const Title: string; GroupIndex: Integer): TStringList;
var Errors: TStringList; Plan: TLPDrillPlan;
begin
  Errors := TStringList.Create;
  try
    if not ValidateDrilling(Errors) then raise Exception.Create(Trim(Errors.Text));
  finally Errors.Free; end;
  Plan := TLPDrillPlan.Create;
  try
    BuildDrillPlan(Plan);
    Result := Plan.RouterGCode(Router,Title,GroupIndex);
  finally Plan.Free; end;
end;

function TLaserPCBProject.PathsForItem(Item: TLaserLayoutItem): TLPPaths;
var I: Integer;
begin
  for I := 0 to Min(Layout.Count,Length(FItemPaths))-1 do
    if Layout.Item(I) = Item then Exit(FItemPaths[I]);
  Result := FPaths;
end;
function TLaserPCBProject.WorldPoint(Item: TLaserLayoutItem; const P: TLPPoint): TLPPoint;
var X, Y: Double;
begin
  X := P.X - OriginX; Y := P.Y - OriginY;
  if (Side = lsBottom) and MirrorBottom then X := Width - X;
  Item.LocalToWorld(X, Y, Result.X, Result.Y);
end;
function TLaserPCBProject.Validate(Errors: TStrings; ForExport: Boolean): Boolean;
var I, J, K: Integer; Q: TLPPoint; B: TLPRect; Job: TLaserPCBJob; ItemPaths: TLPPaths;
begin
  Layout.Validate(Errors);
  if Layout.Count = 0 then Errors.Add('Importe uma placa');
  Errors.AddStrings(Warnings);
  if Length(FPaths) = 0 then Errors.Add('Atualize as trajetorias CAM');
  for I := 0 to Layout.Count - 1 do
  begin
    B := LPEmptyRect; ItemPaths := PathsForItem(Layout.Item(I));
    for J := 0 to High(ItemPaths) do
      for K := 0 to High(ItemPaths[J]) do
      begin Q := WorldPoint(Layout.Item(I), ItemPaths[J][K]); LPRectInclude(B, Q.X, Q.Y); end;
    if B.Valid and ((B.MinX < Layout.Item(I).X-1e-6) or
      (B.MinY < Layout.Item(I).Y-1e-6) or
      (B.MaxX > Layout.Item(I).X+Layout.Item(I).PlacedWidth+1e-6) or
      (B.MaxY > Layout.Item(I).Y+Layout.Item(I).PlacedHeight+1e-6)) then
      Errors.Add(Layout.Item(I).Name + ': trajetorias fora da placa');
  end;
  if ForExport and (Errors.Count = 0) then
  begin
    Job := BuildJob;
    try
      try TLaserGCodeExporter.ValidateJob(Job);
      except on E: Exception do Errors.Add(E.Message); end;
    finally Job.Free; end;
  end;
  Result := Errors.Count = 0;
end;
function TLaserPCBProject.BuildJob: TLaserPCBJob;
var I, J, K: Integer; Q: TLPPoint; ItemPaths: TLPPaths;
begin
  Result := TLaserPCBJob.Create;
  try
    Result.Profile := Profile;
    { Passes na isolacao sao aneis de offset; nao repetir todos os aneis N vezes. }
    if Mode = cmIsolation then Result.Profile.Passes := 1;
    Result.Width := Layout.BedWidth; Result.Height := Layout.BedHeight; Result.Side := Side;
    for I := 0 to Layout.Count - 1 do
    begin
      ItemPaths := PathsForItem(Layout.Item(I));
      for J := 0 to High(ItemPaths) do
        for K := 0 to High(ItemPaths[J]) do
        begin
          Q := WorldPoint(Layout.Item(I), ItemPaths[J][K]);
          Result.AddPoint(Q.X, Q.Y, K > 0);
        end;
    end;
  except Result.Free; raise; end;
end;

{ ---------------- camadas de corte ---------------- }

function TLaserPCBProject.OperationCount: Integer;
begin Result := FOperations.Count; end;
function TLaserPCBProject.Operation(I: Integer): TLPOperation;
begin Result := TLPOperation(FOperations[I]); end;
function TLaserPCBProject.AddOperation(AMode: TLPCamMode; const AName: string; AColor: Integer): TLPOperation;
begin
  Result := TLPOperation.Create;
  Result.Mode := AMode; Result.Name := AName; Result.ColorIndex := EnsureRange(AColor,0,29);
  if AMode = cmLayerHatch then Result.SourceLayer := SelectedLayer;
  FOperations.Add(Result);
end;
procedure TLaserPCBProject.DeleteOperation(I: Integer);
begin Operation(I).Free; FOperations.Delete(I); end;
procedure TLaserPCBProject.MoveOperation(I, Delta: Integer);
var J: Integer;
begin
  J := I + Delta;
  if (I < 0) or (I >= OperationCount) or (J < 0) or (J >= OperationCount) then Exit;
  FOperations.Exchange(I,J);
end;
procedure TLaserPCBProject.ClearOperations;
var I: Integer;
begin
  for I := 0 to FOperations.Count-1 do TObject(FOperations[I]).Free;
  FOperations.Clear;
end;
procedure TLaserPCBProject.InvalidateOperations;
var I: Integer;
begin
  if FOperations = nil then Exit;
  for I := 0 to OperationCount-1 do Operation(I).ItemPaths := nil;
end;

procedure TLaserPCBProject.CreateDefaultOperations;
var I: Integer; Op: TLPOperation;

  function HasMode(M: TLPCamMode): Boolean;
  var K: Integer;
  begin
    Result := False;
    for K := 0 to OperationCount-1 do if Operation(K).Mode = M then Exit(True);
  end;

  function HasSource(Index: Integer): Boolean;
  var K: Integer;
  begin
    Result := False;
    for K := 0 to OperationCount-1 do
      if (Operation(K).Mode = cmLayerHatch) and (Operation(K).SourceLayer = Index) then Exit(True);
  end;

begin
  { Acrescenta as camadas tipicas do que ja foi importado e ainda nao tem
    camada. Ordem de trabalho: isolar o cobre, marcar furos, mascara,
    serigrafia e por ultimo o contorno. Camadas extras comecam sem Saida. }
  if HasSVG then
  begin
    if not HasMode(cmVectors) then AddOperation(cmVectors,'Vetores',0);
    Exit;
  end;
  if ((FindRole(lrTopCopper) <> nil) or (FindRole(lrBottomCopper) <> nil)) and
    not HasMode(cmIsolation) then AddOperation(cmIsolation,'Isolacao do cobre',1);
  if (Drills.HoleCount > 0) and not HasMode(cmDrillMarks) then
  begin Op := AddOperation(cmDrillMarks,'Marcar furos',6); Op.Output := False; end;
  for I := 0 to SourceCount-1 do
    if (Source(I).Role in [lrTopMask,lrBottomMask,lrTopSilk,lrBottomSilk]) and not HasSource(I) then
    begin
      if Source(I).Role in [lrTopMask,lrBottomMask] then
        Op := AddOperation(cmLayerHatch,LayerRoleName(Source(I).Role),3)
      else Op := AddOperation(cmLayerHatch,LayerRoleName(Source(I).Role),5);
      Op.SourceLayer := I; Op.Output := False;
    end;
  if (FindRole(lrOutline) <> nil) and not HasMode(cmOutline) then
  begin Op := AddOperation(cmOutline,'Contorno da placa',0); Op.Output := False; end;
  { o contorno solta a placa: deve ser a ultima camada a cortar }
  for I := OperationCount-2 downto 0 do
    if (Operation(I).Mode = cmOutline) and (Operation(I+1).Mode <> cmOutline) then
      FOperations.Move(I,OperationCount-1);
end;

procedure TLaserPCBProject.ApplyOperation(Op: TLPOperation);
begin
  Mode := Op.Mode;
  Profile.Power := Op.Power; Profile.Feed := Op.Feed; Profile.Passes := Op.Passes;
  Overlap := Op.Overlap; MarkKind := Op.MarkKind; MarkDiameter := Op.MarkDiameter;
  if Op.Mode = cmLayerHatch then SelectedLayer := Op.SourceLayer;
end;

procedure TLaserPCBProject.GenerateOperations;
var I, J, Count: Integer; Op: TLPOperation; SavedMode: TLPCamMode; SavedProfile: TLaserProfile;
  SavedOverlap, SavedMarkDia: Double; SavedSelected: Integer; SavedMark: TLPMarkKind;
begin
  SavedMode := Mode; SavedProfile := Profile; SavedOverlap := Overlap;
  SavedSelected := SelectedLayer; SavedMark := MarkKind; SavedMarkDia := MarkDiameter;
  InvalidateOperations; Count := 0;
  try
    for I := 0 to OperationCount-1 do
    begin
      Op := Operation(I);
      if not (Op.Output or Op.Show) then Continue;
      if (Op.Mode = cmLayerHatch) and ((Op.SourceLayer < 0) or (Op.SourceLayer >= SourceCount)) then
        raise Exception.Create(Op.Caption+' '+Op.Name+': escolha a camada a preencher');
      ApplyOperation(Op);
      { Potencia/velocidade nao alteram a geometria; passadas = aneis na isolacao. }
      if Op.Passes < 1 then Profile.Passes := 1;
      try Generate;
      except on E: Exception do raise Exception.Create(Op.Caption+' '+Op.Name+': '+E.Message); end;
      SetLength(Op.ItemPaths,Layout.Count);
      for J := 0 to Layout.Count-1 do Op.ItemPaths[J] := PathsForItem(Layout.Item(J));
      Inc(Count);
    end;
    if Count = 0 then raise Exception.Create('Ligue a Saida ou Mostrar de pelo menos uma camada');
  finally
    { o processo unico volta ao estado anterior; a previa usa as camadas }
    Mode := SavedMode; Profile := SavedProfile; Overlap := SavedOverlap;
    SelectedLayer := SavedSelected; MarkKind := SavedMark; MarkDiameter := SavedMarkDia;
  end;
end;

function TLaserPCBProject.ValidateOperations(Errors: TStrings; ForExport: Boolean): Boolean;
var I, J, K, L, N, Outputs: Integer; Op: TLPOperation; B: TLPRect; Q: TLPPoint;
  Item: TLaserLayoutItem; P: TLPPaths; Job: TLaserPCBJob; Name: string;
begin
  N := Errors.Count;
  Layout.Validate(Errors);
  if Layout.Count = 0 then Errors.Add('Importe uma placa');
  Errors.AddStrings(Warnings);
  if not FiniteNumber(Profile.SMax) or (Profile.SMax < 1) then Errors.Add('S-max da maquina invalido');
  Outputs := 0;
  for I := 0 to OperationCount-1 do
  begin
    Op := Operation(I);
    if not Op.Output then Continue;
    Inc(Outputs); Name := Op.Caption+' '+Op.Name+': ';
    if not FiniteNumber(Op.Power) or (Op.Power <= 0) then Errors.Add(Name+'potencia nao calibrada')
    else if Op.Power > Profile.SMax then Errors.Add(Name+'potencia maior que o S-max')
    else if Round(Op.Power) < 1 then Errors.Add(Name+'potencia seria arredondada para S0');
    if not FiniteNumber(Op.Feed) or (Op.Feed < 0.001) then Errors.Add(Name+'velocidade nao calibrada');
    if (Op.Passes < 1) or (Op.Passes > 1000) then Errors.Add(Name+'use 1 a 1000 passadas');
    if not Op.Generated then begin Errors.Add(Name+'atualize as trajetorias'); Continue; end;
    for J := 0 to Min(Layout.Count,Length(Op.ItemPaths))-1 do
    begin
      Item := Layout.Item(J); P := Op.ItemPaths[J]; B := LPEmptyRect;
      for K := 0 to High(P) do
        for L := 0 to High(P[K]) do
        begin Q := WorldPoint(Item,P[K][L]); LPRectInclude(B,Q.X,Q.Y); end;
      if B.Valid and ((B.MinX < Item.X-1e-6) or (B.MinY < Item.Y-1e-6) or
        (B.MaxX > Item.X+Item.PlacedWidth+1e-6) or (B.MaxY > Item.Y+Item.PlacedHeight+1e-6)) then
        Errors.Add(Name+Item.Name+': trajetorias fora da placa');
    end;
  end;
  if Outputs = 0 then Errors.Add('Nenhuma camada com Saida ligada');
  if ForExport and (Errors.Count = N) then
  begin
    Job := BuildOperationsJob;
    try
      try TLaserGCodeExporter.ValidateJob(Job);
      except on E: Exception do Errors.Add(E.Message); end;
    finally Job.Free; end;
  end;
  Result := Errors.Count = N;
end;

function TLaserPCBProject.BuildOperationsJob: TLaserPCBJob;
var I, J, K, L, R, Repeats: Integer; Op: TLPOperation; Q: TLPPoint; P: TLPPaths;
begin
  Result := TLaserPCBJob.Create;
  try
    Result.Profile := Profile; Result.Profile.Passes := 1; Result.Profile.Power := 0; Result.Profile.Feed := 0;
    Result.Width := Layout.BedWidth; Result.Height := Layout.BedHeight; Result.Side := Side;
    for I := 0 to OperationCount-1 do
    begin
      Op := Operation(I);
      if not (Op.Output and Op.Generated) then Continue;
      { Na isolacao as passadas ja sao aneis de offset. }
      if Op.Mode = cmIsolation then Repeats := 1 else Repeats := Max(1,Op.Passes);
      for R := 1 to Repeats do
        for J := 0 to Min(Layout.Count,Length(Op.ItemPaths))-1 do
        begin
          P := Op.ItemPaths[J];
          for K := 0 to High(P) do
            for L := 0 to High(P[K]) do
            begin
              Q := WorldPoint(Layout.Item(J),P[K][L]);
              Result.AddPointWithParams(Q.X,Q.Y,L > 0,Op.Power,Op.Feed);
            end;
        end;
    end;
  except Result.Free; raise; end;
end;

procedure TLaserPCBProject.EstimateOperations(RapidFeed: Double; out CutMM, TravelMM, Seconds: Double);
var I, J, K, R, Repeats: Integer; Op: TLPOperation; P: TLPPaths; Last, A: TLPPoint; Len: Double;
begin
  CutMM := 0; TravelMM := 0; Seconds := 0; Last := LPPoint(0,0);
  if RapidFeed <= 0 then RapidFeed := 3000;
  for I := 0 to OperationCount-1 do
  begin
    Op := Operation(I);
    if not (Op.Output and Op.Generated) then Continue;
    if Op.Mode = cmIsolation then Repeats := 1 else Repeats := Max(1,Op.Passes);
    for R := 1 to Repeats do
      for J := 0 to Min(Layout.Count,Length(Op.ItemPaths))-1 do
      begin
        P := Op.ItemPaths[J];
        for K := 0 to High(P) do
        begin
          if Length(P[K]) = 0 then Continue;
          A := WorldPoint(Layout.Item(J),P[K][0]);
          TravelMM := TravelMM + LPDist(Last,A);
          Len := LPPathLength(P[K]);
          CutMM := CutMM + Len;
          if Op.Feed > 0 then Seconds := Seconds + Len/Op.Feed*60;
          Last := WorldPoint(Layout.Item(J),P[K][High(P[K])]);
        end;
      end;
  end;
  Seconds := Seconds + TravelMM/RapidFeed*60;
end;
end.
