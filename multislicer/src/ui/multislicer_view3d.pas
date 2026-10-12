unit multislicer_view3d;

{ MultiSlicer - vista 3D da mesa (Etapa 3 do docs/PLANO_TAREFAS.md).

  Mostra a mesa da impressora (placa, grade de 10 mm, volume de impressao,
  eixos) e as pecas da cena, sombreadas, como no Cura. Usa a camera e o
  renderizador por software do MultiCAD (multicad_camera, multicad_softrender):
  funciona igual no Windows e no Linux, sem OpenGL nem driver de video.

  Eixos: a mesa usa Z para cima (X para a direita, Y para o fundo); o MultiCAD
  usa Y para cima. Conversao: CAD = (x, z, -y). Assim a vista "Frontal" do
  MultiCAD olha a impressora pela frente.

  Mouse:
    esquerdo na peca        seleciona (Ctrl soma); arrastar move na mesa
    esquerdo no vazio       arrastar gira; clique limpa a selecao
    direito ou meio         gira (orbita em torno do alvo)
    Shift ou Ctrl + arrastar desloca (pan)
    roda                    zoom no cursor
  Teclado: F enquadra a mesa; Delete pede para remover a selecao (OnDelete).

  Selecao exata pelo buffer de Id do renderizador: Tag = indice da peca + 1. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, LCLIntf, GraphType, IntfGraphics,
  LMessages, multislicer_types, multislicer_mesh, multislicer_scene,
  multicad_types, multicad_mesh, multicad_camera, multicad_softrender;

type
  TSlicerMouseMode = (smmNone, smmPending, smmOrbit, smmPan, smmMove);
  TSlicerFacePickEvent = procedure(Sender: TObject; ObjIndex, TriIndex: Integer) of object;

  TSlicerObjCache = record
    Obj: TSliceObject;
    Shape: Integer;
    BoxMin: TVec3;
    Mesh: TCadMesh;
    Cache: TCadMeshCache;
    Lod: TCadMesh;             { versao reduzida para girar malhas pesadas }
    LodCache: TCadMeshCache;
  end;

  TSlicerView3D = class(TCustomControl)
  private
    FScene: TSliceScene;
    FCam: TCadCamera;
    FRaster: TCadRaster;
    FBmp: TBitmap;
    FImg: TLazIntfImage;
    FBedMesh: TCadMesh;
    FBedCache: TCadMeshCache;
    FBedKey: string;
    FCaches: array of TSlicerObjCache;
    FDirty, FNeedFit: Boolean;
    FMode: TSlicerMouseMode;
    FDownX, FDownY, FLastX, FLastY: Integer;
    FDownObj: Integer;
    FDownShift: TShiftState;
    FDragFrom: TVec3;
    FMoved: Boolean;
    FLastRenderMS: Int64;
    FFullRenderMS: Int64;      { ultimo quadro em qualidade total }
    FInteractive: Boolean;     { girando/deslocando: quadro rapido }
    FFactor: Integer;          { 1 = resolucao total; 2 = meia }
    FOnSelect, FOnMoved, FOnDelete, FOnBeforeMove: TNotifyEvent;
    FOnFacePicked: TSlicerFacePickEvent;
    FPickFace: Boolean;
    procedure SetPickFace(AValue: Boolean);
    procedure SetScene(AValue: TSliceScene);
    procedure SyncCaches;
    procedure FreeCaches;
    procedure EnsureBed;
    procedure Render;
    procedure Blit;
    procedure PaintOverlay;
    function BedPoint(PX, PY: Integer; out P: TVec3): Boolean;
    procedure WMEraseBkgnd(var Message: TLMEraseBkgnd); message LM_ERASEBKGND;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Redraw;                      { a cena mudou }
    procedure FitBed;                      { enquadra a mesa (F) }
    procedure DefaultView;                 { frente, de cima, como o Cura }
    procedure StdView(V: TCadStdView);
    procedure ZoomBy(Factor: Double);
    procedure Orbit(DX, DY: Double);
    { para os testes: desenha agora e informa o que ha no pixel }
    procedure RenderNow;
    function PickObject(X, Y: Integer): Integer;   { -1 = nenhuma }
    function ObjectPixels(Index: Integer): Integer;
    function ScreenOf(const P: TVec3): TPoint;      { ponto da mesa -> pixel }
    { triangulo da malha na mesa atingido pelo raio do pixel (-1 = nenhum) }
    function PickTriangle(X, Y: Integer; out ObjIndex: Integer): Integer;
    { proximo clique escolhe a face a deitar na mesa (OnFacePicked) }
    property PickFaceMode: Boolean read FPickFace write SetPickFace;
    property OnFacePicked: TSlicerFacePickEvent read FOnFacePicked write FOnFacePicked;
    { avisa antes do primeiro movimento de um arraste (para desfazer) }
    property OnBeforeMove: TNotifyEvent read FOnBeforeMove write FOnBeforeMove;
    property Scene: TSliceScene read FScene write SetScene;
    property Camera: TCadCamera read FCam;
    property LastRenderMS: Int64 read FLastRenderMS;
    { quadro rapido (meia resolucao, sem arestas) enquanto gira/desloca malhas pesadas }
    property Interactive: Boolean read FInteractive write FInteractive;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnMoved: TNotifyEvent read FOnMoved write FOnMoved;
    property OnDelete: TNotifyEvent read FOnDelete write FOnDelete;
  end;

function SlicerToCad(X, Y, Z: Double): TCadVec3; inline;

implementation

const
  BED_TAG = 2000;
  COL_PART = $0096AAC8;      { cinza azulado }
  COL_SELECTED = $003B82F6;  { azul da suite }
  COL_OUTSIDE = $00EF4444;   { vermelho: fora do volume }
  COL_BED = $00ECF0F5;
  COL_GRID = $00CBD3DE;
  COL_GRID5 = $00A9B4C2;
  COL_VOLUME = $0094A3B8;

function SlicerToCad(X, Y, Z: Double): TCadVec3;
begin
  Result := V3(X, Z, -Y);
end;

function CadToSlicer(const P: TCadVec3): TVec3;
begin
  Result.X := P.X; Result.Y := -P.Z; Result.Z := P.Y;
end;

const
  LOD_MIN_TRIS = 40000;   { acima disso, gira com a malha reduzida }

function BuildCadMesh(M: TMesh; Tol: Double = 0): TCadMesh;
var I, A, B, C, Face: Integer; T: TTriangle; Info: TCadFaceInfo;
begin
  { Tol > 0: vertices a menos de Tol viram um so e triangulos degenerados somem
    (agrupamento de vertices) - versao reduzida para navegar }
  if Tol > 0 then Result := TCadMesh.Create(Tol) else Result := TCadMesh.Create;
  Info.Name := 'peca';
  Info.Surf := skOther;
  Info.Origin := V3(0, 0, 0); Info.Axis := V3(0, 0, 1);
  Info.Radius := 0; Info.Radius2 := 0;
  Face := Result.AddFace(Info);
  for I := 0 to M.Count - 1 do
  begin
    T := M.Triangle(I);
    A := Result.AddVertex(SlicerToCad(T.A.X, T.A.Y, T.A.Z));
    B := Result.AddVertex(SlicerToCad(T.B.X, T.B.Y, T.B.Z));
    C := Result.AddVertex(SlicerToCad(T.C.X, T.C.Y, T.C.Z));
    Result.AddTri(A, B, C, Face);
  end;
end;

{ ---------------- TSlicerView3D ---------------- }

constructor TSlicerView3D.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  FCam := TCadCamera.Create;
  FRaster := TCadRaster.Create;
  FRaster.Style := dsShadedEdges;
  FRaster.Background1 := $00F4F6FA;   { topo }
  FRaster.Background2 := $00D5DDE8;   { base }
  FBmp := TBitmap.Create;
  FNeedFit := True;
  FDirty := True;
  FDownObj := -1;
  FFactor := 1;
  DefaultView;
end;

destructor TSlicerView3D.Destroy;
begin
  FreeCaches;
  FBedCache.Free;
  FBedMesh.Free;
  FImg.Free;
  FBmp.Free;
  FRaster.Free;
  FCam.Free;
  inherited Destroy;
end;

procedure TSlicerView3D.WMEraseBkgnd(var Message: TLMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TSlicerView3D.SetScene(AValue: TSliceScene);
begin
  if FScene = AValue then Exit;
  FreeCaches;
  FScene := AValue;
  FNeedFit := True;
  Redraw;
end;

procedure TSlicerView3D.Redraw;
begin
  FDirty := True;
  Invalidate;
end;

procedure TSlicerView3D.FreeCaches;
var I: Integer;
begin
  for I := 0 to High(FCaches) do
  begin
    FCaches[I].Cache.Free;
    FCaches[I].Mesh.Free;
    FCaches[I].LodCache.Free;
    FCaches[I].Lod.Free;
  end;
  SetLength(FCaches, 0);
end;

procedure TSlicerView3D.SyncCaches;
var
  I, K, V: Integer; Old: array of TSlicerObjCache; O: TSliceObject; Found: Boolean;
  B: TBox3; D: TCadVec3;
begin
  if FScene = nil then
  begin
    FreeCaches;
    Exit;
  end;
  Old := FCaches;
  FCaches := nil;
  SetLength(FCaches, FScene.Count);
  for I := 0 to FScene.Count - 1 do
  begin
    O := FScene[I];
    Found := False;
    for K := 0 to High(Old) do
      if Old[K].Obj = O then
      begin
        FCaches[I] := Old[K];
        Old[K].Obj := nil;
        Found := True;
        Break;
      end;
    B := O.WorldBox;
    if Found and (FCaches[I].Shape = O.ShapeVersion) then
    begin
      { so arrastou: desloca os vertices (normais e arestas nao mudam) }
      if (B.Min.X <> FCaches[I].BoxMin.X) or (B.Min.Y <> FCaches[I].BoxMin.Y) then
      begin
        D := SlicerToCad(B.Min.X - FCaches[I].BoxMin.X, B.Min.Y - FCaches[I].BoxMin.Y, 0);
        for V := 0 to FCaches[I].Mesh.VertCount - 1 do
          FCaches[I].Mesh.SetVert(V, VAdd(FCaches[I].Mesh.Verts[V], D));
        if FCaches[I].Lod <> nil then
          for V := 0 to FCaches[I].Lod.VertCount - 1 do
            FCaches[I].Lod.SetVert(V, VAdd(FCaches[I].Lod.Verts[V], D));
        FCaches[I].BoxMin := B.Min;
      end;
      Continue;
    end;
    if Found then
    begin
      FCaches[I].Cache.Free;
      FCaches[I].Mesh.Free;
      FreeAndNil(FCaches[I].LodCache);
      FreeAndNil(FCaches[I].Lod);
    end;
    FCaches[I].Lod := nil;
    FCaches[I].LodCache := nil;
    FCaches[I].Obj := O;
    FCaches[I].Shape := O.ShapeVersion;
    FCaches[I].BoxMin := B.Min;
    FCaches[I].Mesh := BuildCadMesh(O.WorldMesh);
    FCaches[I].Cache := TCadMeshCache.Create(FCaches[I].Mesh);
  end;
  { pecas removidas }
  for K := 0 to High(Old) do
    if Old[K].Obj <> nil then
    begin
      Old[K].Cache.Free;
      Old[K].Mesh.Free;
      Old[K].LodCache.Free;
      Old[K].Lod.Free;
    end;
end;

procedure TSlicerView3D.EnsureBed;
var Key: string; BX, BY: Double; Info: TCadFaceInfo; F: Integer;
begin
  if FScene = nil then Exit;
  BX := FScene.BedX; BY := FScene.BedY;
  Key := FloatToStr(BX) + 'x' + FloatToStr(BY);
  if (FBedCache <> nil) and (Key = FBedKey) then Exit;
  FreeAndNil(FBedCache);
  FreeAndNil(FBedMesh);
  { placa: so a face de cima, um pouco abaixo de Z = 0 para a grade aparecer }
  FBedMesh := TCadMesh.Create;
  Info.Name := 'mesa'; Info.Surf := skPlane;
  Info.Origin := V3(0, 0, 0); Info.Axis := V3(0, 1, 0);
  Info.Radius := 0; Info.Radius2 := 0;
  F := FBedMesh.AddFace(Info);
  FBedMesh.AddQuadP(SlicerToCad(0, 0, -0.05), SlicerToCad(BX, 0, -0.05),
    SlicerToCad(BX, BY, -0.05), SlicerToCad(0, BY, -0.05), F);
  FBedCache := TCadMeshCache.Create(FBedMesh);
  FBedKey := Key;
end;

procedure TSlicerView3D.Render;
var
  I, G: Integer; Opt: TCadDrawOptions; Col: LongWord; BX, BY, BZ, V: Double;
  T0: QWord; SavedStyle: TCadDisplayStyle; SavedScale: Double; Sz: TVec3;
  procedure Edge(X0, Y0, Z0, X1, Y1, Z1: Double);
  begin
    FRaster.DrawLine3D(SlicerToCad(X0, Y0, Z0), SlicerToCad(X1, Y1, Z1), COL_VOLUME, 1, True, 4);
  end;
begin
  T0 := GetTickCount64;
  if FNeedFit and (ClientWidth > 50) and (ClientHeight > 50) then
  begin
    FitBed;
    FNeedFit := False;
  end;
  { durante o arraste, se o ultimo quadro completo foi lento, desenha em meia
    resolucao e sem arestas (como o MultiCAD); ao soltar volta ao completo }
  if FInteractive and (FFullRenderMS > 50) then FFactor := 2 else FFactor := 1;
  SavedScale := FCam.Scale;
  FRaster.SetSize(Max(1, ClientWidth div FFactor), Max(1, ClientHeight div FFactor));
  FCam.SetViewport(FRaster.Width, FRaster.Height);
  FCam.Scale := SavedScale / FFactor;
  if FFactor > 1 then FRaster.Style := dsShaded else FRaster.Style := dsShadedEdges;
  try
  FRaster.BeginFrame(FCam);
  if FScene <> nil then
  begin
    BX := FScene.BedX; BY := FScene.BedY; BZ := FScene.BedZ;
    EnsureBed;
    { mesa sem arestas }
    SavedStyle := FRaster.Style;
    FRaster.Style := dsShaded;
    Opt := CadDrawOptions(COL_BED, BED_TAG);
    FRaster.DrawMesh(FBedCache, Opt);
    FRaster.Style := SavedStyle;
    { grade de 10 mm, mais forte a cada 50 mm }
    G := 0; V := 0;
    while V <= BX + 1e-6 do
    begin
      if G mod 5 = 0 then Col := COL_GRID5 else Col := COL_GRID;
      FRaster.DrawLine3D(SlicerToCad(V, 0, 0), SlicerToCad(V, BY, 0), Col, 1, True);
      Inc(G); V := G * 10;
    end;
    G := 0; V := 0;
    while V <= BY + 1e-6 do
    begin
      if G mod 5 = 0 then Col := COL_GRID5 else Col := COL_GRID;
      FRaster.DrawLine3D(SlicerToCad(0, V, 0), SlicerToCad(BX, V, 0), Col, 1, True);
      Inc(G); V := G * 10;
    end;
    { pecas }
    SyncCaches;
    for I := 0 to High(FCaches) do
    begin
      if not FScene.Inside(I) then Col := COL_OUTSIDE
      else if FScene[I].Selected then Col := COL_SELECTED
      else Col := COL_PART;
      Opt := CadDrawOptions(Col, I + 1);
      Opt.EdgeColor := CadMix(Col, $00101820, 0.45);
      if (FFactor > 1) and (FCaches[I].Mesh.TriCount > LOD_MIN_TRIS) then
      begin
        if FCaches[I].Lod = nil then
        begin
          Sz := FScene[I].Size;
          FCaches[I].Lod := BuildCadMesh(FScene[I].WorldMesh, Max(Sz.X, Max(Sz.Y, Sz.Z)) / 90);
          FCaches[I].LodCache := TCadMeshCache.Create(FCaches[I].Lod);
        end;
        FRaster.DrawMesh(FCaches[I].LodCache, Opt);
      end
      else
        FRaster.DrawMesh(FCaches[I].Cache, Opt);
    end;
    { volume de impressao (tracejado) }
    Edge(0, 0, BZ, BX, 0, BZ); Edge(BX, 0, BZ, BX, BY, BZ);
    Edge(BX, BY, BZ, 0, BY, BZ); Edge(0, BY, BZ, 0, 0, BZ);
    Edge(0, 0, 0, 0, 0, BZ); Edge(BX, 0, 0, BX, 0, BZ);
    Edge(BX, BY, 0, BX, BY, BZ); Edge(0, BY, 0, 0, BY, BZ);
    { contorno da mesa e eixos na origem }
    FRaster.DrawLine3D(SlicerToCad(0, 0, 0), SlicerToCad(BX, 0, 0), COL_GRID5, 1, True);
    FRaster.DrawLine3D(SlicerToCad(BX, 0, 0), SlicerToCad(BX, BY, 0), COL_GRID5, 1, True);
    FRaster.DrawLine3D(SlicerToCad(BX, BY, 0), SlicerToCad(0, BY, 0), COL_GRID5, 1, True);
    FRaster.DrawLine3D(SlicerToCad(0, BY, 0), SlicerToCad(0, 0, 0), COL_GRID5, 1, True);
    FRaster.DrawLine3D(SlicerToCad(0, 0, 0.1), SlicerToCad(25, 0, 0.1), $00DC2626, 2, False);
    FRaster.DrawLine3D(SlicerToCad(0, 0, 0.1), SlicerToCad(0, 25, 0.1), $0016A34A, 2, False);
    FRaster.DrawLine3D(SlicerToCad(0, 0, 0.1), SlicerToCad(0, 0, 25), $002563EB, 2, False);
  end;
  finally
    FCam.Scale := SavedScale;
    FCam.SetViewport(Max(1, ClientWidth), Max(1, ClientHeight));
  end;
  Blit;
  FDirty := False;
  FLastRenderMS := GetTickCount64 - T0;
  if FFactor = 1 then FFullRenderMS := FLastRenderMS;
end;

procedure TSlicerView3D.Blit;
var W, H, Y: Integer; Desc: TRawImageDescription; Direct: Boolean;
begin
  W := FRaster.Width;
  H := FRaster.Height;
  { raster $00RRGGBB = bytes B,G,R,0 (igual ao MultiCAD): no Windows copia as
    linhas direto no bitmap de 32 bits; nos outros, pelo TLazIntfImage. }
  if (FBmp.Width <> W) or (FBmp.Height <> H) or (FBmp.PixelFormat <> pf32bit) then
  begin
    FBmp.PixelFormat := pf32bit;
    FBmp.SetSize(W, H);
  end;
  Desc := FBmp.RawImage.Description;
  Direct := {$IFDEF WINDOWS} (Desc.BitsPerPixel = 32) and (Desc.RedShift = 16) and
    (Desc.GreenShift = 8) and (Desc.BlueShift = 0) and (Desc.LineOrder = riloTopToBottom) and
    (Desc.BitOrder = riboBitsInOrder) and (Desc.ByteOrder = riboLSBFirst) {$ELSE} False {$ENDIF};
  if Direct then
  begin
    FBmp.BeginUpdate(False);
    try
      for Y := 0 to H - 1 do
        Move(FRaster.Color[Y * W], FBmp.RawImage.GetLineStart(Y)^, W * 4);
    finally
      FBmp.EndUpdate(False);
    end;
    Exit;
  end;
  if (FImg = nil) or (FImg.Width <> W) or (FImg.Height <> H) then
  begin
    FreeAndNil(FImg);
    Desc.Init_BPP32_B8G8R8_BIO_TTB(W, H);
    FImg := TLazIntfImage.Create(0, 0);
    FImg.DataDescription := Desc;
  end;
  for Y := 0 to H - 1 do
    Move(FRaster.Color[Y * W], FImg.GetDataLineStart(Y)^, W * 4);
  FBmp.LoadFromIntfImage(FImg);
end;

procedure TSlicerView3D.PaintOverlay;
const
  NAMES: array[0..2] of string = ('X', 'Y', 'Z');
  COLS: array[0..2] of TColor = ($002626DC, $004AA316, $00EB6325); { BGR do TColor }
var I, OX, OY, EX, EY: Integer; D: TCadVec3; HelpText: string;
begin
  { triedro no canto inferior esquerdo, nos eixos da impressora }
  OX := 44; OY := ClientHeight - 44;
  Canvas.Pen.Width := 2;
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [fsBold];
  Canvas.Brush.Style := bsClear;
  for I := 0 to 2 do
  begin
    case I of
      0: D := SlicerToCad(1, 0, 0);
      1: D := SlicerToCad(0, 1, 0);
    else
      D := SlicerToCad(0, 0, 1);
    end;
    EX := OX + Round(26 * VDot(D, FCam.Right));
    EY := OY - Round(26 * VDot(D, FCam.Up));
    Canvas.Pen.Color := COLS[I];
    Canvas.Line(OX, OY, EX, EY);
    Canvas.Font.Color := COLS[I];
    Canvas.TextOut(EX + Round(6 * VDot(D, FCam.Right)) - 3, EY - Round(6 * VDot(D, FCam.Up)) - 7, NAMES[I]);
  end;
  Canvas.Pen.Width := 1;
  Canvas.Font.Style := [];
  Canvas.Font.Color := $008B7464;
  if (FScene = nil) or (FScene.Count = 0) then
    HelpText := 'Abra um modelo STL ou 3MF'
  else
    if FPickFace then
      HelpText := 'Clique na face da peca que deve ficar apoiada na mesa  (Esc cancela)'
    else
    HelpText := 'Clique na peca para selecionar e arraste para mover  |  direito: girar  |  Shift: deslocar  |  roda: zoom  |  F: enquadrar';
  Canvas.TextOut(90, ClientHeight - 22, HelpText);
end;

function TSlicerView3D.BedPoint(PX, PY: Integer; out P: TVec3): Boolean;
var O, D: TCadVec3; T: Double;
begin
  Result := False;
  P.X := 0; P.Y := 0; P.Z := 0;
  FCam.ScreenRay(PX, PY, O, D);
  if Abs(D.Y) < 1e-9 then Exit;
  T := -O.Y / D.Y;          { plano da mesa: Y do CAD = 0 }
  P := CadToSlicer(VAdd(O, VScale(D, T)));
  P.Z := 0;
  Result := True;
end;

procedure TSlicerView3D.Paint;
begin
  if FDirty or (FRaster.Width * FFactor < ClientWidth - 1) or (FRaster.Height * FFactor < ClientHeight - 1) then
    Render;
  if FFactor > 1 then Canvas.StretchDraw(Rect(0, 0, ClientWidth, ClientHeight), FBmp)
  else Canvas.Draw(0, 0, FBmp);
  PaintOverlay;
end;

procedure TSlicerView3D.Resize;
begin
  inherited Resize;
  Redraw;
end;

procedure TSlicerView3D.RenderNow;
begin
  Render;
end;

function TSlicerView3D.PickObject(X, Y: Integer): Integer;
var Code, PTag, Face: Integer;
begin
  Result := -1;
  FInteractive := False;
  if FDirty or (FFactor <> 1) or (FRaster.Width <> ClientWidth) or (FRaster.Height <> ClientHeight) then Render;
  if (X < 0) or (Y < 0) or (X >= FRaster.Width) or (Y >= FRaster.Height) then Exit;
  Code := FRaster.IdAt(X, Y);
  if Code = 0 then Exit;
  CadPickDecode(Code, PTag, Face);
  if (PTag >= 1) and (FScene <> nil) and (PTag <= FScene.Count) then Result := PTag - 1;
end;

function TSlicerView3D.ObjectPixels(Index: Integer): Integer;
begin
  if FDirty then Render;
  Result := FRaster.CountId(CadPickCode(Index + 1, 0));
end;

procedure TSlicerView3D.SetPickFace(AValue: Boolean);
begin
  FPickFace := AValue;
  if AValue then Cursor := crCross else Cursor := crDefault;
end;

function TSlicerView3D.PickTriangle(X, Y: Integer; out ObjIndex: Integer): Integer;
var O, D: TCadVec3; OS, DS: TVec3; M: TMesh; I: Integer; T: TTriangle; Dist, Best: Double;
  A, B, C: TCadVec3;
begin
  Result := -1;
  ObjIndex := PickObject(X, Y);
  if ObjIndex < 0 then Exit;
  FCam.SetViewport(Max(1, ClientWidth), Max(1, ClientHeight));
  FCam.ScreenRay(X, Y, O, D);
  OS := CadToSlicer(O); DS := CadToSlicer(D);
  M := FScene[ObjIndex].WorldMesh;
  Best := MaxDouble;
  for I := 0 to M.Count - 1 do
  begin
    T := M.Triangle(I);
    A := V3(T.A.X, T.A.Y, T.A.Z); B := V3(T.B.X, T.B.Y, T.B.Z); C := V3(T.C.X, T.C.Y, T.C.Z);
    if CadRayTri(V3(OS.X, OS.Y, OS.Z), V3(DS.X, DS.Y, DS.Z), A, B, C, Dist) and (Dist < Best) then
    begin
      Best := Dist;
      Result := I;
    end;
  end;
end;

function TSlicerView3D.ScreenOf(const P: TVec3): TPoint;
var S: TCadScreenPt;
begin
  FCam.SetViewport(Max(1, ClientWidth), Max(1, ClientHeight));
  S := FCam.Project(SlicerToCad(P.X, P.Y, P.Z));
  Result := Point(Round(S.X), Round(S.Y));
end;

procedure TSlicerView3D.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var Tri, Obj: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  FDownX := X; FDownY := Y; FLastX := X; FLastY := Y;
  FDownShift := Shift;
  FMoved := False;
  if (ssShift in Shift) or ((ssCtrl in Shift) and (Button <> mbLeft)) then
    FMode := smmPan
  else if Button in [mbRight, mbMiddle] then
    FMode := smmOrbit
  else if Button = mbLeft then
  begin
    if FPickFace then
    begin
      FMode := smmNone;
      Tri := PickTriangle(X, Y, Obj);
      if Tri >= 0 then
      begin
        PickFaceMode := False;
        if Assigned(FOnFacePicked) then FOnFacePicked(Self, Obj, Tri);
      end;
      Exit;
    end;
    FDownObj := PickObject(X, Y);
    if FDownObj >= 0 then
    begin
      if ssCtrl in Shift then FScene.ToggleSelect(FDownObj)
      else if not FScene[FDownObj].Selected then FScene.SelectOnly(FDownObj);
      Redraw;
      if Assigned(FOnSelect) then FOnSelect(Self);
      if (not FScene[FDownObj].Locked) and BedPoint(X, Y, FDragFrom) then FMode := smmMove
      else FMode := smmNone;
    end
    else
      FMode := smmPending;   { clique limpa a selecao; arrastar gira }
  end;
end;

procedure TSlicerView3D.MouseMove(Shift: TShiftState; X, Y: Integer);
var P: TVec3; I: Integer; DX, DY: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if FMode = smmNone then Exit;
  if (FMode = smmPending) and ((Abs(X - FDownX) > 3) or (Abs(Y - FDownY) > 3)) then
    FMode := smmOrbit;
  FInteractive := FMode in [smmOrbit, smmPan];
  case FMode of
    smmOrbit:
      begin
        FCam.Orbit(X - FLastX, Y - FLastY);
        Redraw;
      end;
    smmPan:
      begin
        FCam.Pan(X - FLastX, Y - FLastY);
        Redraw;
      end;
    smmMove:
      if BedPoint(X, Y, P) then
      begin
        DX := P.X - FDragFrom.X; DY := P.Y - FDragFrom.Y;
        if (DX <> 0) or (DY <> 0) then
        begin
          if (not FMoved) and Assigned(FOnBeforeMove) then FOnBeforeMove(Self);
          for I := 0 to FScene.Count - 1 do
            if FScene[I].Selected then FScene[I].MoveBy(DX, DY);
          FScene.Touch;
          FDragFrom := P;
          FMoved := True;
          Redraw;
        end;
      end;
  end;
  FLastX := X; FLastY := Y;
end;

procedure TSlicerView3D.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (FMode = smmPending) and (FScene <> nil) and not (ssCtrl in FDownShift) then
  begin
    FScene.SelectOnly(-1);
    Redraw;
    if Assigned(FOnSelect) then FOnSelect(Self);
  end;
  if (FMode = smmMove) and FMoved and Assigned(FOnMoved) then FOnMoved(Self);
  if FInteractive then
  begin
    FInteractive := False;
    Redraw;     { volta a qualidade total }
  end;
  FMode := smmNone;
  FDownObj := -1;
end;

function TSlicerView3D.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then FCam.ZoomAt(1.15, MousePos.X, MousePos.Y)
  else if WheelDelta < 0 then FCam.ZoomAt(1 / 1.15, MousePos.X, MousePos.Y);
  Redraw;
end;

procedure TSlicerView3D.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F: begin FitBed; Redraw; Key := 0; end;
    VK_ESCAPE: if FPickFace then begin PickFaceMode := False; Key := 0; end;
    VK_DELETE:
      begin
        if Assigned(FOnDelete) then FOnDelete(Self);
        Key := 0;
      end;
  end;
  if Key <> 0 then inherited KeyDown(Key, Shift);
end;

procedure TSlicerView3D.FitBed;
var B: TCadBox3; H: Double;
begin
  FCam.SetViewport(Max(1, ClientWidth), Max(1, ClientHeight));
  B := BoxEmpty;
  if FScene = nil then
  begin
    BoxAdd(B, SlicerToCad(0, 0, 0));
    BoxAdd(B, SlicerToCad(220, 220, 40));
  end
  else
  begin
    { a mesa inteira e a altura das pecas (o volume todo deixaria a mesa pequena) }
    H := Max(30, Min(FScene.BedZ, FScene.Bounds.Max.Z));
    BoxAdd(B, SlicerToCad(0, 0, 0));
    BoxAdd(B, SlicerToCad(FScene.BedX, FScene.BedY, H));
  end;
  FCam.Fit(B);
  FCam.Scale := FCam.Scale * 1.08;
  Redraw;
end;

procedure TSlicerView3D.DefaultView;
begin
  { de frente e de cima, como o Cura abre }
  FCam.SetOrientation(VNorm(SlicerToCad(0.25, -1, 0.75)), V3(0, 1, 0));
  FNeedFit := True;
  Redraw;
end;

procedure TSlicerView3D.StdView(V: TCadStdView);
begin
  FCam.StdView(V);
  FitBed;
end;

procedure TSlicerView3D.ZoomBy(Factor: Double);
begin
  FCam.ZoomAt(Factor, ClientWidth / 2, ClientHeight / 2);
  Redraw;
end;

procedure TSlicerView3D.Orbit(DX, DY: Double);
begin
  FCam.Orbit(DX, DY);
  Redraw;
end;

end.
