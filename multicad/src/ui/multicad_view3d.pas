unit multicad_view3d;

{ MultiCAD - controle da vista 3D (ARCHITECTURE 6.1 a 6.5).

  Desenha a peca reconstruida (corpos), os planos visiveis, os esbocos que
  ainda nao foram consumidos por operacoes, a origem e a previa da operacao
  em edicao. Usa o renderizador por software (multicad_softrender), que
  funciona igual no Windows e no Linux sem depender de driver de video.

  Mouse (como no SolidWorks):
    botao do meio arrastar        girar
    Ctrl + botao do meio          deslocar (pan)
    Shift + botao do meio         zoom
    roda                          zoom no cursor
    Alt + esquerdo / Alt+Ctrl     girar / deslocar (sem botao do meio)
    esquerdo                      selecionar (OnPick); Ctrl soma a selecao
  Teclado: Ctrl+1..7 vistas padrao, Ctrl+8 Normal a (OnNormalTo),
  F enquadrar, setas giram 15 graus.
  Cubo de vistas no canto superior direito (clicar numa face muda a vista)
  e triedro XYZ no canto inferior esquerdo. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, LCLIntf, GraphType,
  IntfGraphics, contnrs, multicad_types, multicad_mesh, multicad_document,
  multicad_feature, multicad_refgeom, multicad_sketch, multicad_rebuild,
  multicad_camera, multicad_softrender;

const
  CAD_TAG_FEATURE = 2001;   { Id de planos, eixos, esbocos e origem: face = indice da operacao }

type
  TCadPickEvent = procedure(Sender: TObject; const ARef: string; Shift: TShiftState) of object;
  TCadOverlay3DEvent = procedure(Sender: TObject; R: TCadRaster) of object;
  TCadOverlayEvent = procedure(Sender: TObject; C: TCanvas) of object;
  TCadMouseEvent = procedure(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
    X, Y: Integer; var Handled: Boolean) of object;
  TCadMoveEvent = procedure(Sender: TObject; Shift: TShiftState; X, Y: Integer;
    var Handled: Boolean) of object;

  TCadView3D = class(TCustomControl)
  private
    FDoc: TCadDocument;
    FRB: TCadRebuilder;
    FCam: TCadCamera;
    FRaster: TCadRaster;
    FBmp: TBitmap;
    FImg: TLazIntfImage;
    FCaches: TFPObjectList;
    FPreview: TCadMesh;
    FPreviewCache: TCadMeshCache;
    FPreviewCut: Boolean;
    FDirty: Boolean;
    FHover: string;
    FHoverCode: Integer;
    FSelected: TStringList;
    FShown: TStringList;       { Ids de planos padrao mostrados }
    FHiddenIds: TStringList;   { Ids ocultados pelo usuario }
    FPlaneHalf: Double;
    FModelBox: TCadBox3;
    FDragBtn: TMouseButton;
    FDragging: Boolean;
    FDragMode: Integer;        { 0 girar, 1 deslocar, 2 zoom }
    FLastX, FLastY, FDownX, FDownY: Integer;
    FSectionOn: Boolean;
    FSection: TCadFrame;
    FShowOrigin: Boolean;
    FActiveSketchId: Integer;
    FHighlightPrefix: string;
    FNeedFit: Boolean;           { enquadrar quando a vista tiver tamanho }
    FMoved: Boolean;             { arrastou (nao foi so clique) }
    FPivot: TCadVec3;            { centro de giro escolhido (clique do meio) }
    FPivotSet, FShowPivot: Boolean;
    FReverseWheel, FSkipPush: Boolean;
    FHistory: TFPObjectList;     { vistas anteriores (Ctrl+Shift+Z) }
    FOnPick: TCadPickEvent;
    FOnNormalTo: TNotifyEvent;
    FOnOverlay3D: TCadOverlay3DEvent;
    FOnOverlay: TCadOverlayEvent;
    FOnViewMouseDown: TCadMouseEvent;
    FOnViewMouseUp: TCadMouseEvent;
    FOnViewMouseMove: TCadMoveEvent;
    FOnHoverChange: TNotifyEvent;
    function GetStyle: TCadDisplayStyle;
    procedure SetStyle(AValue: TCadDisplayStyle);
    procedure RenderScene;
    procedure DrawPlanes;
    procedure DrawSketches;
    procedure DrawOrigin;
    procedure Blit;
    procedure PaintCube(C: TCanvas);
    procedure PaintTriad(C: TCanvas);
    function CubeHit(X, Y: Integer; out V: TCadStdView): Boolean;
    function ConsumedSketch(AId: Integer): Boolean;
    function PlaneVisible(P: TCadPlane): Boolean;
    function FeatureCode(AIndex: Integer): Integer;
    procedure UpdateHover(X, Y: Integer);
    function PivotPoint: TCadVec3;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetModel(ADoc: TCadDocument; ARB: TCadRebuilder);
    { Chamar depois de reconstruir: refaz os caches de desenho. }
    procedure ModelChanged;
    procedure Redraw;
    procedure FitAll;
    procedure SetView(V: TCadStdView);
    { Previa (malha nao possuida; nil apaga). }
    procedure SetPreview(AMesh: TCadMesh; AIsCut: Boolean);
    procedure SetSection(AOn: Boolean; const F: TCadFrame);
    { Referencia sob o pixel ("face:...", "plane:2", "sketch:5", "origin"). }
    function RefAt(X, Y: Integer): string;
    function CodeToRef(ACode: Integer): string;
    { Atalhos da vista (Ctrl+1..8, F, setas). Key = 0 se tratou. }
    procedure HandleKey(var Key: Word; Shift: TShiftState);
    { Guarda a vista atual para "Vista anterior". }
    procedure PushView;
    procedure PreviousView;
    { Roda do mouse invertida (padrao SolidWorks: para frente afasta). }
    property ReverseWheel: Boolean read FReverseWheel write FReverseWheel;
    procedure ShowStdPlane(AId: Integer; AShow: Boolean);
    function IsHidden(AId: Integer): Boolean;
    procedure SetHidden(AId: Integer; AHidden: Boolean);
    property Camera: TCadCamera read FCam;
    property Raster: TCadRaster read FRaster;
    property Style: TCadDisplayStyle read GetStyle write SetStyle;
    property Selected: TStringList read FSelected;
    property Hover: string read FHover;
    property SectionOn: Boolean read FSectionOn;
    property ShowOrigin: Boolean read FShowOrigin write FShowOrigin;
    { Esboco em edicao (desenhado pelo editor, nao pela vista). }
    property ActiveSketchId: Integer read FActiveSketchId write FActiveSketchId;
    property ModelBox: TCadBox3 read FModelBox;
    { Faces cujo nome comeca com este prefixo ("Extrude2/") ficam na cor da
      previa (operacao em edicao). }
    property HighlightPrefix: string read FHighlightPrefix write FHighlightPrefix;
    property OnPick: TCadPickEvent read FOnPick write FOnPick;
    property OnNormalTo: TNotifyEvent read FOnNormalTo write FOnNormalTo;
    property OnOverlay3D: TCadOverlay3DEvent read FOnOverlay3D write FOnOverlay3D;
    property OnOverlay: TCadOverlayEvent read FOnOverlay write FOnOverlay;
    property OnViewMouseDown: TCadMouseEvent read FOnViewMouseDown write FOnViewMouseDown;
    property OnViewMouseUp: TCadMouseEvent read FOnViewMouseUp write FOnViewMouseUp;
    property OnViewMouseMove: TCadMoveEvent read FOnViewMouseMove write FOnViewMouseMove;
    property OnHoverChange: TNotifyEvent read FOnHoverChange write FOnHoverChange;
  end;

{ Cor do raster ($00RRGGBB) para TColor. }
function CadToColor(C: LongWord): TColor;

implementation

const
  CUBE_SIZE = 44;
  CUBE_MARGIN = 14;
  CUBE_FACES: array[0..5] of TCadStdView = (svFront, svBack, svLeft, svRight, svTop, svBottom);
  CUBE_LABELS: array[0..5] of string = ('Frontal', 'Posterior', 'Esquerda', 'Direita',
    'Superior', 'Inferior');

function CadToColor(C: LongWord): TColor;
begin
  Result := RGBToColor((C shr 16) and $FF, (C shr 8) and $FF, C and $FF);
end;

function CubeNormal(I: Integer): TCadVec3;
begin
  case I of
    0: Result := V3(0, 0, 1);
    1: Result := V3(0, 0, -1);
    2: Result := V3(-1, 0, 0);
    3: Result := V3(1, 0, 0);
    4: Result := V3(0, 1, 0);
  else
    Result := V3(0, -1, 0);
  end;
end;

{ ---------- criacao ---------- }

constructor TCadView3D.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  DoubleBuffered := False;
  FCam := TCadCamera.Create;
  FRaster := TCadRaster.Create;
  FBmp := TBitmap.Create;
  FCaches := TFPObjectList.Create(True);
  FHistory := TFPObjectList.Create(True);
  FSelected := TStringList.Create;
  FShown := TStringList.Create;
  FHiddenIds := TStringList.Create;
  FModelBox := BoxEmpty;
  FPlaneHalf := 60;
  FShowOrigin := True;
  FDirty := True;
  FCam.StdView(svIso);
  FCam.Scale := 2;
end;

destructor TCadView3D.Destroy;
begin
  FPreviewCache.Free;
  FCaches.Free;
  FHistory.Free;
  FSelected.Free;
  FShown.Free;
  FHiddenIds.Free;
  FImg.Free;
  FBmp.Free;
  FRaster.Free;
  FCam.Free;
  inherited Destroy;
end;

procedure TCadView3D.SetModel(ADoc: TCadDocument; ARB: TCadRebuilder);
begin
  FDoc := ADoc;
  FRB := ARB;
  ModelChanged;
end;

procedure TCadView3D.ModelChanged;
var
  I: Integer;
  B: TCadBox3;
  S: TCadVec3;
begin
  FCaches.Clear;
  FModelBox := BoxEmpty;
  if Assigned(FRB) then
    for I := 0 to FRB.BodyCount - 1 do
    begin
      FCaches.Add(TCadMeshCache.Create(FRB.Body(I).Mesh));
      B := FRB.Body(I).Mesh.Bounds;
      if not B.Empty then
      begin
        BoxAdd(FModelBox, B.Min);
        BoxAdd(FModelBox, B.Max);
      end;
    end;
  if FModelBox.Empty then
    FPlaneHalf := 60
  else
  begin
    S := BoxSize(FModelBox);
    FPlaneHalf := Max(40, 0.6 * Max(S.X, Max(S.Y, S.Z)));
  end;
  Redraw;
end;

procedure TCadView3D.Redraw;
begin
  FDirty := True;
  Invalidate;
end;

function TCadView3D.GetStyle: TCadDisplayStyle;
begin
  Result := FRaster.Style;
end;

procedure TCadView3D.SetStyle(AValue: TCadDisplayStyle);
begin
  FRaster.Style := AValue;
  Redraw;
end;

procedure TCadView3D.FitAll;
var
  B: TCadBox3;
begin
  if (ClientWidth < 50) or (ClientHeight < 50) then
  begin
    FNeedFit := True;
    Exit;
  end;
  FNeedFit := False;
  if not FSkipPush and (FCam.Width > 1) then
    PushView;
  B := FModelBox;
  if B.Empty then
  begin
    BoxAdd(B, V3(-FPlaneHalf, -FPlaneHalf, -FPlaneHalf));
    BoxAdd(B, V3(FPlaneHalf, FPlaneHalf, FPlaneHalf));
  end;
  FCam.SetViewport(Max(1, ClientWidth), Max(1, ClientHeight));
  FCam.Fit(B);
  Redraw;
end;

procedure TCadView3D.SetView(V: TCadStdView);
begin
  PushView;
  FCam.StdView(V);
  FSkipPush := True;
  try
    FitAll;
  finally
    FSkipPush := False;
  end;
end;

procedure TCadView3D.SetPreview(AMesh: TCadMesh; AIsCut: Boolean);
begin
  FreeAndNil(FPreviewCache);
  FPreview := AMesh;
  FPreviewCut := AIsCut;
  if Assigned(AMesh) then
    FPreviewCache := TCadMeshCache.Create(AMesh);
  Redraw;
end;

procedure TCadView3D.SetSection(AOn: Boolean; const F: TCadFrame);
begin
  FSectionOn := AOn;
  FSection := F;
  Redraw;
end;

procedure TCadView3D.ShowStdPlane(AId: Integer; AShow: Boolean);
var
  I: Integer;
begin
  I := FShown.IndexOf(IntToStr(AId));
  if AShow and (I < 0) then
    FShown.Add(IntToStr(AId))
  else if not AShow and (I >= 0) then
    FShown.Delete(I);
  Redraw;
end;

function TCadView3D.IsHidden(AId: Integer): Boolean;
begin
  Result := FHiddenIds.IndexOf(IntToStr(AId)) >= 0;
end;

procedure TCadView3D.SetHidden(AId: Integer; AHidden: Boolean);
var
  I: Integer;
begin
  I := FHiddenIds.IndexOf(IntToStr(AId));
  if AHidden and (I < 0) then
    FHiddenIds.Add(IntToStr(AId))
  else if not AHidden and (I >= 0) then
    FHiddenIds.Delete(I);
  Redraw;
end;

{ ---------- referencias ---------- }

function TCadView3D.FeatureCode(AIndex: Integer): Integer;
begin
  Result := CadPickCode(CAD_TAG_FEATURE, AIndex);
end;

function TCadView3D.CodeToRef(ACode: Integer): string;
var
  PTag, Face: Integer;
  F: TCadFeature;
  M: TCadMesh;
begin
  Result := '';
  CadPickDecode(ACode, PTag, Face);
  if (PTag < 0) or (Face < 0) then
    Exit;
  if PTag = CAD_TAG_FEATURE then
  begin
    if (FDoc = nil) or (Face >= FDoc.Count) then
      Exit;
    F := FDoc.Feature(Face);
    case F.Kind of
      cfPlane: Result := 'plane:' + IntToStr(F.Id);
      cfAxis: Result := 'axis:' + IntToStr(F.Id);
      cfSketch: Result := 'sketch:' + IntToStr(F.Id);
      cfOrigin: Result := 'origin';
    end;
  end
  else if Assigned(FRB) and (PTag >= 1) and (PTag <= FRB.BodyCount) then
  begin
    M := FRB.Body(PTag - 1).Mesh;
    if Face < M.FaceCount then
      Result := 'face:' + M.Faces[Face].Name;
  end;
end;

function TCadView3D.RefAt(X, Y: Integer): string;
var
  DX, DY, Code, PTag, Face, Best, D: Integer;
begin
  { geometria fina (planos, esbocos) tem prioridade num raio de 4 px }
  Best := MaxInt;
  Code := 0;
  for DY := -4 to 4 do
    for DX := -4 to 4 do
    begin
      CadPickDecode(FRaster.IdAt(X + DX, Y + DY), PTag, Face);
      if PTag = CAD_TAG_FEATURE then
      begin
        D := DX * DX + DY * DY;
        if D < Best then
        begin
          Best := D;
          Code := FRaster.IdAt(X + DX, Y + DY);
        end;
      end;
    end;
  if Code = 0 then
    Code := FRaster.IdAt(X, Y);
  FHoverCode := Code;
  Result := CodeToRef(Code);
end;

function TCadView3D.ConsumedSketch(AId: Integer): Boolean;
var
  I, K: Integer;
  Deps: TCadIdArray;
begin
  Result := False;
  if FDoc = nil then
    Exit;
  for I := 0 to FDoc.Count - 1 do
  begin
    if FDoc.Feature(I).Kind in [cfSketch, cfPlane, cfAxis, cfOrigin] then
      Continue;
    if (FDoc.RollbackIndex >= 0) and (I >= FDoc.RollbackIndex) then
      Continue;
    Deps := FDoc.Feature(I).Dependencies;
    for K := 0 to High(Deps) do
      if Deps[K] = AId then
        Exit(True);
  end;
end;

function TCadView3D.PlaneVisible(P: TCadPlane): Boolean;
begin
  if IsHidden(P.Id) then
    Exit(False);
  if P.Id in [MCAD_ID_FRONTAL, MCAD_ID_SUPERIOR, MCAD_ID_LATERAL] then
    Result := (FShown.IndexOf(IntToStr(P.Id)) >= 0) or
      (FSelected.IndexOf('plane:' + IntToStr(P.Id)) >= 0)
  else
    Result := True;
end;

{ ---------- desenho ---------- }

procedure TCadView3D.DrawPlanes;
var
  I: Integer;
  F: TCadFeature;
  Fr: TCadFrame;
  Err, Ref: string;
  A, B, C, D, X, Y: TCadVec3;
  Border: LongWord;
  W: Integer;
begin
  if (FDoc = nil) or (FRB = nil) then
    Exit;
  for I := 0 to FDoc.Count - 1 do
  begin
    F := FDoc.Feature(I);
    if not (F is TCadPlane) or F.Suppressed then
      Continue;
    if (FDoc.RollbackIndex >= 0) and (I >= FDoc.RollbackIndex) then
      Continue;
    Ref := 'plane:' + IntToStr(F.Id);
    if not PlaneVisible(TCadPlane(F)) and (FHover <> Ref) then
      Continue;
    if not FRB.ResolvePlane(Ref, Fr, Err) then
      Continue;
    X := VScale(Fr.XDir, FPlaneHalf);
    Y := VScale(Fr.YDir, FPlaneHalf);
    A := VSub(VSub(Fr.Origin, X), Y);
    B := VSub(VAdd(Fr.Origin, X), Y);
    C := VAdd(VAdd(Fr.Origin, X), Y);
    D := VAdd(VSub(Fr.Origin, X), Y);
    Border := CadRGB(70, 120, 190);
    W := 1;
    if FSelected.IndexOf(Ref) >= 0 then
    begin
      Border := CAD_SELECT_COLOR;
      W := 2;
    end
    else if FHover = Ref then
    begin
      Border := CAD_HOVER_COLOR;
      W := 2;
    end;
    FRaster.DrawQuad3D(A, B, C, D, CadRGB(120, 170, 230), 0.16, FeatureCode(I));
    FRaster.DrawLine3D(A, B, Border, W, False, 0, FeatureCode(I));
    FRaster.DrawLine3D(B, C, Border, W, False, 0, FeatureCode(I));
    FRaster.DrawLine3D(C, D, Border, W, False, 0, FeatureCode(I));
    FRaster.DrawLine3D(D, A, Border, W, False, 0, FeatureCode(I));
  end;
end;

procedure TCadView3D.DrawSketches;
var
  I, K, J, N: Integer;
  F: TCadFeature;
  S: TCadSketch;
  Fr: TCadFrame;
  Err, Ref: string;
  E: TSketchEntity;
  Col: LongWord;
  A0, A1, Sweep, T: Double;
  P, Q: TCadVec3;
  Dash, Code: Integer;
begin
  if (FDoc = nil) or (FRB = nil) then
    Exit;
  for I := 0 to FDoc.Count - 1 do
  begin
    F := FDoc.Feature(I);
    if not (F is TCadSketch) or F.Suppressed or (F.Id = FActiveSketchId) then
      Continue;
    if (FDoc.RollbackIndex >= 0) and (I >= FDoc.RollbackIndex) then
      Continue;
    Ref := 'sketch:' + IntToStr(F.Id);
    if IsHidden(F.Id) then
      Continue;
    if ConsumedSketch(F.Id) and (FSelected.IndexOf(Ref) < 0) and (FHover <> Ref) then
      Continue;
    S := TCadSketch(F);
    if not FRB.SketchFrame(S, Fr, Err) then
      Continue;
    Col := CadRGB(30, 60, 150);
    if FSelected.IndexOf(Ref) >= 0 then
      Col := CAD_SELECT_COLOR
    else if FHover = Ref then
      Col := CAD_HOVER_COLOR;
    Code := FeatureCode(I);
    for K := 0 to S.EntityCount - 1 do
    begin
      E := S.Entity(K);
      Dash := 0;
      if E.Construction or E.Centerline then
        Dash := 6;
      case E.Kind of
        seLine:
          FRaster.DrawLine3D(FrameToWorld(Fr, E.P1), FrameToWorld(Fr, E.P2), Col, 1,
            True, Dash, Code);
        sePoint:
          FRaster.DrawPoint3D(FrameToWorld(Fr, E.P1), Col, 3, True, Code);
        seCircle, seArc:
          begin
            if E.Kind = seCircle then
            begin
              A0 := 0;
              Sweep := 2 * Pi;
            end
            else
            begin
              A0 := ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X);
              A1 := ArcTan2(E.P3.Y - E.P1.Y, E.P3.X - E.P1.X);
              Sweep := A1 - A0;
              while Sweep <= 0 do
                Sweep := Sweep + 2 * Pi;
            end;
            N := Max(8, Ceil(Sweep / (2 * Pi) * 64));
            P := FrameToWorld(Fr, V2(E.P1.X + E.Radius * Cos(A0), E.P1.Y + E.Radius * Sin(A0)));
            for J := 1 to N do
            begin
              T := A0 + Sweep * J / N;
              Q := FrameToWorld(Fr, V2(E.P1.X + E.Radius * Cos(T), E.P1.Y + E.Radius * Sin(T)));
              FRaster.DrawLine3D(P, Q, Col, 1, True, Dash, Code);
              P := Q;
            end;
          end;
      end;
    end;
  end;
end;

procedure TCadView3D.DrawOrigin;
var
  L: Double;
  I, Code: Integer;
begin
  if not FShowOrigin or (FDoc = nil) then
    Exit;
  Code := 0;
  I := FDoc.IndexOfId(MCAD_ID_ORIGIN);
  if I >= 0 then
    Code := FeatureCode(I);
  L := 12 / Max(FCam.Scale, 1E-6);
  FRaster.DrawLine3D(V3(0, 0, 0), V3(L * 2, 0, 0), CadRGB(200, 40, 40), 2, False, 0, Code);
  FRaster.DrawLine3D(V3(0, 0, 0), V3(0, L * 2, 0), CadRGB(30, 150, 50), 2, False, 0, Code);
  FRaster.DrawLine3D(V3(0, 0, 0), V3(0, 0, L * 2), CadRGB(40, 80, 210), 2, False, 0, Code);
  FRaster.DrawPoint3D(V3(0, 0, 0), CadRGB(40, 80, 210), 5, False, Code);
end;

procedure TCadView3D.RenderScene;
var
  I, K, PTag, Face: Integer;
  Opt: TCadDrawOptions;
  M: TCadMesh;
  N: Integer;
begin
  FRaster.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  FCam.SetViewport(FRaster.Width, FRaster.Height);
  FRaster.BeginFrame(FCam);
  FRaster.SetSection(FSectionOn, FSection.Origin, FSection.Normal);
  CadPickDecode(FHoverCode, PTag, Face);
  for I := 0 to FCaches.Count - 1 do
  begin
    M := TCadMeshCache(FCaches[I]).Mesh;
    Opt := CadDrawOptions(CAD_PART_COLOR, I + 1);
    N := 0;
    if FHighlightPrefix <> '' then
      Opt.HiColor := CAD_PREVIEW_COLOR;
    for K := 0 to M.FaceCount - 1 do
      if ((FHighlightPrefix <> '') and (Pos(FHighlightPrefix, M.Faces[K].Name) = 1)) or
        ((FHighlightPrefix = '') and (FSelected.IndexOf('face:' + M.Faces[K].Name) >= 0)) then
      begin
        SetLength(Opt.HiFaces, N + 1);
        Opt.HiFaces[N] := K;
        Inc(N);
      end;
    if (PTag = I + 1) and (FHover <> '') then
      Opt.HoverFace := Face;
    FRaster.DrawMesh(TCadMeshCache(FCaches[I]), Opt);
  end;
  FRaster.SetSection(False, FSection.Origin, FSection.Normal);
  DrawPlanes;
  DrawSketches;
  DrawOrigin;
  if Assigned(FPreviewCache) then
  begin
    if FPreviewCut then
      Opt := CadDrawOptions(CadRGB(230, 90, 60), 0)
    else
      Opt := CadDrawOptions(CAD_PREVIEW_COLOR, 0);
    Opt.Alpha := 0.55;
    Opt.EdgeColor := CadRGB(150, 110, 20);
    K := Ord(FRaster.Style);
    if FRaster.Style <> dsWireframe then
      FRaster.Style := dsShadedEdges;
    FRaster.DrawMesh(FPreviewCache, Opt);
    FRaster.Style := TCadDisplayStyle(K);
  end;
  if Assigned(FOnOverlay3D) then
    FOnOverlay3D(Self, FRaster);
  Blit;
  FDirty := False;
end;

procedure TCadView3D.Blit;
var
  W, H, Y: Integer;
  Desc: TRawImageDescription;
begin
  { raster $00RRGGBB = bytes B,G,R,0 em little-endian: mesmo formato de
    BPP32_B8G8R8; a LCL converte para o formato do dispositivo }
  W := FRaster.Width;
  H := FRaster.Height;
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

procedure TCadView3D.PaintTriad(C: TCanvas);
const
  AX: array[0..2] of string = ('X', 'Y', 'Z');
var
  OX, OY, I: Integer;
  D: TCadVec3;
  Col: TColor;
  EX, EY: Integer;
begin
  OX := 40;
  OY := ClientHeight - 40;
  C.Pen.Width := 2;
  C.Font.Height := -12;
  C.Font.Style := [fsBold];
  C.Brush.Style := bsClear;
  for I := 0 to 2 do
  begin
    case I of
      0: begin D := V3(1, 0, 0); Col := RGBToColor(200, 40, 40); end;
      1: begin D := V3(0, 1, 0); Col := RGBToColor(30, 150, 50); end;
    else
      begin D := V3(0, 0, 1); Col := RGBToColor(40, 80, 210); end;
    end;
    EX := OX + Round(VDot(D, FCam.Right) * 26);
    EY := OY - Round(VDot(D, FCam.Up) * 26);
    C.Pen.Color := Col;
    C.Line(OX, OY, EX, EY);
    C.Font.Color := Col;
    C.TextOut(EX + Round(VDot(D, FCam.Right) * 6) - 4, EY - Round(VDot(D, FCam.Up) * 6) - 7, AX[I]);
  end;
  C.Pen.Width := 1;
end;

procedure CubeFace(Cam: TCadCamera; I, CX, CY: Integer; out Pts: array of TPoint; out Depth: Double);
var
  N, U, V, P: TCadVec3;
  K: Integer;
  S: Double;
begin
  N := CubeNormal(I);
  if Abs(N.Y) > 0.5 then
    U := V3(1, 0, 0)
  else
    U := V3(0, 1, 0);
  V := VCross(N, U);
  S := CUBE_SIZE / 2;
  Depth := 0;
  for K := 0 to 3 do
  begin
    case K of
      0: P := VAdd(N, VAdd(VNeg(U), VNeg(V)));
      1: P := VAdd(N, VAdd(U, VNeg(V)));
      2: P := VAdd(N, VAdd(U, V));
    else
      P := VAdd(N, VAdd(VNeg(U), V));
    end;
    Pts[K].X := CX + Round(VDot(P, Cam.Right) * S * 0.75);
    Pts[K].Y := CY - Round(VDot(P, Cam.Up) * S * 0.75);
  end;
  Depth := VDot(N, Cam.Back);
end;

procedure TCadView3D.PaintCube(C: TCanvas);
var
  CX, CY, I, J, K, Cnt: Integer;
  Pts: array[0..3] of TPoint;
  D: Double;
  Order: array[0..5] of Integer;
  Dep: array[0..5] of Double;
  Hov: TCadStdView;
  HovOk: Boolean;
  P: TPoint;
  Lbl: string;
  TW: Integer;
begin
  CX := ClientWidth - CUBE_MARGIN - CUBE_SIZE;
  CY := CUBE_MARGIN + CUBE_SIZE;
  P := ScreenToClient(Mouse.CursorPos);
  HovOk := CubeHit(P.X, P.Y, Hov);
  for I := 0 to 5 do
  begin
    Order[I] := I;
    CubeFace(FCam, I, CX, CY, Pts, Dep[I]);
  end;
  { de tras para a frente }
  for I := 0 to 4 do
    for J := I + 1 to 5 do
      if Dep[Order[J]] < Dep[Order[I]] then
      begin
        K := Order[I];
        Order[I] := Order[J];
        Order[J] := K;
      end;
  C.Font.Height := -10;
  C.Font.Style := [];
  Cnt := 0;
  for I := 0 to 5 do
  begin
    K := Order[I];
    if Dep[K] <= 0.05 then
      Continue;
    Inc(Cnt);
    CubeFace(FCam, K, CX, CY, Pts, D);
    C.Pen.Color := RGBToColor(110, 125, 150);
    if HovOk and (CUBE_FACES[K] = Hov) then
      C.Brush.Color := RGBToColor(255, 214, 150)
    else
      C.Brush.Color := RGBToColor(Round(200 + 40 * D), Round(208 + 38 * D), Round(222 + 30 * D));
    C.Brush.Style := bsSolid;
    C.Polygon(Pts);
    if D > 0.62 then
    begin
      Lbl := CUBE_LABELS[K];
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(40, 50, 70);
      TW := C.TextWidth(Lbl);
      C.TextOut((Pts[0].X + Pts[2].X) div 2 - TW div 2,
        (Pts[0].Y + Pts[2].Y) div 2 - C.TextHeight(Lbl) div 2, Lbl);
    end;
  end;
  C.Brush.Style := bsSolid;
  if Cnt = 0 then;
end;

function PointInQuad(const Q: array of TPoint; X, Y: Integer): Boolean;
var
  I, J: Integer;
  Inside: Boolean;
begin
  Inside := False;
  J := 3;
  for I := 0 to 3 do
  begin
    if ((Q[I].Y > Y) <> (Q[J].Y > Y)) and
      (X < (Q[J].X - Q[I].X) * (Y - Q[I].Y) / Max(1E-9, (Q[J].Y - Q[I].Y)) + Q[I].X) then
      Inside := not Inside;
    J := I;
  end;
  Result := Inside;
end;

function TCadView3D.CubeHit(X, Y: Integer; out V: TCadStdView): Boolean;
var
  CX, CY, I: Integer;
  Pts: array[0..3] of TPoint;
  D, Best: Double;
begin
  Result := False;
  V := svIso;
  CX := ClientWidth - CUBE_MARGIN - CUBE_SIZE;
  CY := CUBE_MARGIN + CUBE_SIZE;
  if (Abs(X - CX) > CUBE_SIZE) or (Abs(Y - CY) > CUBE_SIZE) then
    Exit;
  Best := 0.05;
  for I := 0 to 5 do
  begin
    CubeFace(FCam, I, CX, CY, Pts, D);
    if (D > Best) and PointInQuad(Pts, X, Y) then
    begin
      Best := D;
      V := CUBE_FACES[I];
      Result := True;
    end;
  end;
end;

procedure TCadView3D.Paint;
var
  S: string;
begin
  if FNeedFit and (ClientWidth >= 50) and (ClientHeight >= 50) then
    FitAll;
  if FDirty or (FRaster.Width <> ClientWidth) or (FRaster.Height <> ClientHeight) then
    RenderScene;
  Canvas.Draw(0, 0, FBmp);
  if Assigned(FOnOverlay) then
    FOnOverlay(Self, Canvas);
  PaintTriad(Canvas);
  PaintCube(Canvas);
  if FShowPivot then
    with FCam.Project(PivotPoint) do
    begin
      Canvas.Pen.Color := RGBToColor(220, 60, 40);
      Canvas.Pen.Width := 2;
      Canvas.Brush.Style := bsClear;
      Canvas.Ellipse(Round(X) - 6, Round(Y) - 6, Round(X) + 7, Round(Y) + 7);
      Canvas.Line(Round(X) - 10, Round(Y), Round(X) + 11, Round(Y));
      Canvas.Line(Round(X), Round(Y) - 10, Round(X), Round(Y) + 11);
      Canvas.Pen.Width := 1;
      Canvas.Brush.Style := bsSolid;
    end;
  if FSectionOn then
  begin
    S := 'Vista de seção';
    Canvas.Font.Height := -12;
    Canvas.Font.Color := RGBToColor(150, 60, 40);
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(12, 10, S);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TCadView3D.Resize;
begin
  inherited Resize;
  Redraw;
end;

{ ---------- mouse e teclado ---------- }

procedure TCadView3D.UpdateHover(X, Y: Integer);
var
  R: string;
begin
  if FDirty then
    Exit;
  R := RefAt(X, Y);
  if R <> FHover then
  begin
    FHover := R;
    if Assigned(FOnHoverChange) then
      FOnHoverChange(Self);
    Redraw;
  end;
end;

function TCadView3D.PivotPoint: TCadVec3;
begin
  if FPivotSet then
    Result := FPivot
  else if not FModelBox.Empty then
    Result := VScale(VAdd(FModelBox.Min, FModelBox.Max), 0.5)
  else
    Result := FCam.Target;
end;

procedure TCadView3D.PushView;
var
  C: TCadCamera;
begin
  C := TCadCamera.Create;
  C.Assign(FCam);
  FHistory.Add(C);
  while FHistory.Count > 30 do
    FHistory.Delete(0);
end;

procedure TCadView3D.PreviousView;
var
  W, H: Integer;
begin
  if FHistory.Count = 0 then
    Exit;
  W := FCam.Width;
  H := FCam.Height;
  FCam.Assign(TCadCamera(FHistory[FHistory.Count - 1]));
  FCam.SetViewport(W, H);
  FHistory.Delete(FHistory.Count - 1);
  Redraw;
end;

procedure TCadView3D.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Handled: Boolean;
  V: TCadStdView;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then
    SetFocus;
  FLastX := X;
  FLastY := Y;
  FDownX := X;
  FDownY := Y;
  FMoved := False;
  if (Button = mbLeft) and CubeHit(X, Y, V) then
  begin
    SetView(V);
    Exit;
  end;
  if Button = mbMiddle then
  begin
    { duplo clique do meio: enquadrar (SolidWorks) }
    if ssDouble in Shift then
    begin
      FitAll;
      Exit;
    end;
    FDragging := True;
    FDragBtn := Button;
    if ssCtrl in Shift then
      FDragMode := 1        { deslocar }
    else if ssShift in Shift then
      FDragMode := 2        { zoom }
    else if ssAlt in Shift then
      FDragMode := 3        { rolar }
    else
      FDragMode := 0;       { girar }
    PushView;
    Exit;
  end;
  if (Button = mbLeft) and (ssAlt in Shift) then
  begin
    { sem botao do meio: Alt + esquerdo gira, Alt+Ctrl desloca, Alt+Shift zoom }
    FDragging := True;
    FDragBtn := Button;
    if ssCtrl in Shift then
      FDragMode := 1
    else if ssShift in Shift then
      FDragMode := 2
    else
      FDragMode := 0;
    PushView;
    Exit;
  end;
  Handled := False;
  if Assigned(FOnViewMouseDown) then
    FOnViewMouseDown(Self, Button, Shift, X, Y, Handled);
end;

procedure TCadView3D.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
  Handled: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  DX := X - FLastX;
  DY := Y - FLastY;
  FLastX := X;
  FLastY := Y;
  if FDragging then
  begin
    if (Abs(X - FDownX) > 2) or (Abs(Y - FDownY) > 2) then
      FMoved := True;
    if not FMoved then
      Exit;
    case FDragMode of
      0:
        begin
          FCam.OrbitAbout(DX, DY, PivotPoint);
          FShowPivot := True;
        end;
      1: FCam.Pan(DX, DY);
      { arrastar para cima aproxima (Zoom do SolidWorks) }
      2: FCam.ZoomAt(Power(1.01, -DY), FDownX, FDownY);
      3: FCam.Roll(DX);
    end;
    Redraw;
    Exit;
  end;
  Handled := False;
  if Assigned(FOnViewMouseMove) then
    FOnViewMouseMove(Self, Shift, X, Y, Handled);
  if not Handled then
    UpdateHover(X, Y)
  else
    Invalidate;
end;

procedure TCadView3D.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Handled: Boolean;
  R: string;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging and (Button = FDragBtn) then
  begin
    FDragging := False;
    FShowPivot := False;
    if not FMoved then
    begin
      { so clicou: some o historico desta "vista" }
      if FHistory.Count > 0 then
        FHistory.Delete(FHistory.Count - 1);
      if Button = mbMiddle then
      begin
        { clique do meio numa entidade: passa a girar em torno dela; no
          fundo: volta para o centro da peca }
        if FDirty then
          RenderScene;
        FPivotSet := FRaster.DepthAt(X, Y) < 1E29;
        if FPivotSet then
          FPivot := FCam.Unproject(X + 0.5, Y + 0.5, FRaster.DepthAt(X, Y));
      end;
    end;
    Redraw;
    Exit;
  end;
  Handled := False;
  if Assigned(FOnViewMouseUp) then
    FOnViewMouseUp(Self, Button, Shift, X, Y, Handled);
  if Handled then
    Exit;
  if (Button = mbLeft) and (Abs(X - FDownX) < 4) and (Abs(Y - FDownY) < 4) then
  begin
    if FDirty then
      RenderScene;
    R := RefAt(X, Y);
    if Assigned(FOnPick) then
      FOnPick(Self, R, Shift)
    else
    begin
      if not (ssCtrl in Shift) then
        FSelected.Clear;
      if R <> '' then
      begin
        if FSelected.IndexOf(R) >= 0 then
          FSelected.Delete(FSelected.IndexOf(R))
        else
          FSelected.Add(R);
      end;
      Redraw;
    end;
  end;
end;

procedure TCadView3D.MouseLeave;
begin
  inherited MouseLeave;
  if FHover <> '' then
  begin
    FHover := '';
    FHoverCode := 0;
    if Assigned(FOnHoverChange) then
      FOnHoverChange(Self);
    Redraw;
  end;
end;

function TCadView3D.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  { SolidWorks: rolar para frente (para longe) afasta, para tras aproxima,
    sempre em torno do cursor; ReverseWheel inverte }
  if FReverseWheel then
    FCam.ZoomAt(Power(1.15, WheelDelta / 120), MousePos.X, MousePos.Y)
  else
    FCam.ZoomAt(Power(1.15, -WheelDelta / 120), MousePos.X, MousePos.Y);
  Redraw;
  Result := True;
end;

procedure TCadView3D.KeyDown(var Key: Word; Shift: TShiftState);
begin
  HandleKey(Key, Shift);
  inherited KeyDown(Key, Shift);
end;

procedure TCadView3D.HandleKey(var Key: Word; Shift: TShiftState);
var
  St: Double;
begin
  { setas: 15 graus; Shift + setas: 90 graus; Alt + esquerda/direita: rolar;
    Ctrl + setas: deslocar; Z / Shift+Z: afastar/aproximar;
    Ctrl+Shift+Z: vista anterior (como no SolidWorks) }
  if (ssCtrl in Shift) and (ssShift in Shift) and (Key = VK_Z) then
  begin
    PreviousView;
    Key := 0;
    Exit;
  end;
  if ssCtrl in Shift then
    case Key of
      VK_1..VK_7:
        begin
          SetView(TCadStdView(Key - VK_1));
          Key := 0;
        end;
      VK_8:
        begin
          if Assigned(FOnNormalTo) then
            FOnNormalTo(Self);
          Key := 0;
        end;
      VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN:
        begin
          St := Max(ClientWidth, ClientHeight) * 0.1;
          case Key of
            VK_LEFT: FCam.Pan(-St, 0);
            VK_RIGHT: FCam.Pan(St, 0);
            VK_UP: FCam.Pan(0, -St);
            VK_DOWN: FCam.Pan(0, St);
          end;
          Redraw;
          Key := 0;
        end;
    end
  else
    case Key of
      VK_F:
        begin
          FitAll;
          Key := 0;
        end;
      VK_Z:
        begin
          PushView;
          if ssShift in Shift then
            FCam.ZoomAt(1.25, ClientWidth / 2, ClientHeight / 2)
          else
            FCam.ZoomAt(1 / 1.25, ClientWidth / 2, ClientHeight / 2);
          Redraw;
          Key := 0;
        end;
      VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN:
        begin
          PushView;
          if ssShift in Shift then
            St := 225       { 90 graus (0,4 grau por unidade) }
          else
            St := 37.5;     { 15 graus }
          if (ssAlt in Shift) and (Key in [VK_LEFT, VK_RIGHT]) then
          begin
            if Key = VK_LEFT then FCam.Roll(-37.5) else FCam.Roll(37.5);
          end
          else
            case Key of
              VK_LEFT: FCam.OrbitAbout(-St, 0, PivotPoint);
              VK_RIGHT: FCam.OrbitAbout(St, 0, PivotPoint);
              VK_UP: FCam.OrbitAbout(0, -St, PivotPoint);
              VK_DOWN: FCam.OrbitAbout(0, St, PivotPoint);
            end;
          Redraw;
          Key := 0;
        end;
    end;
end;

end.
