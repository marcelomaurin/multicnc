unit laserart_editor;

{ Area de trabalho do LaserArt (estilo LightBurn).

  - Reguas em mm, grade adaptativa, mesa branca com origem (0,0) no canto
    inferior esquerdo; Y para cima.
  - Roda do mouse: zoom no cursor. Botao do meio ou direito: mover a vista.
  - Ferramenta Selecionar: clique seleciona (Shift alterna), arrastar no
    vazio faz selecao por area, arrastar o objeto move, alcas redimensionam
    (cantos com Shift ou "travar proporcao" mantem a proporcao).
  - Ferramentas de desenho: retangulo, elipse, poligono (arrastar; Shift =
    proporcional), linha/polilinha (cliques; clicar no 1o ponto fecha; duplo
    clique ou Enter termina; Esc cancela) e texto (clique).
  - Previa: mostra o percurso do trabalho (corte na cor da camada,
    deslocamentos em vermelho tracejado) e o retangulo de enquadramento.

  O editor avisa OnBeforeChange antes de alterar o documento (o formulario
  guarda o estado para desfazer) e OnChange depois. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType, LCLIntf,
  laserart_model, laserart_geom, laserart_imaging, laserart_output;

type
  TLATool = (ltSelect, ltRect, ltEllipse, ltPolygon, ltLine, ltText);
  TRectArray = array of TRect;
  TLACursorEvent = procedure(Sender: TObject; X, Y: Double) of object;

  TLAEditor = class(TCustomControl)
  private type
    TDragMode = (dmNone, dmMove, dmScale, dmMarquee, dmCreate, dmPan);
    TOrig = record
      S: TLAShape;
      X, Y, W, H: Double;
    end;
  private
    FDoc: TLADocument;
    FSel: TList;
    FTool: TLATool;
    FScale, FOffX, FOffY: Double;
    FCurrentLayer: Integer;
    FPreviewJob: TLAJob;
    FShowPreview: Boolean;
    FLockRatio: Boolean;
    FPolygonSides: Integer;
    FDefaultFont: string;
    FDrag: TDragMode;
    FDownX, FDownY: Integer;
    FDownW, FLastW: TLAPoint;
    FHandle: Integer;
    FOrig: array of TOrig;
    FOrigBox: TLABox;
    FCreated: TLAShape;
    FPoly: array of TLAPoint;
    FHoverW: TLAPoint;
    FChangeNotified: Boolean;
    FFitted: Boolean;
    FOnBeforeChange, FOnChange, FOnSelectionChange, FOnToolChange: TNotifyEvent;
    FOnCursor: TLACursorEvent;
    procedure SetTool(Value: TLATool);
    procedure SetPreviewJob(Value: TLAJob);
    procedure SetShowPreview(Value: Boolean);
    procedure SetDocument(Value: TLADocument);
    function DrawRect: TRect;
    function W2S(X, Y: Double): TPoint;
    function HandleRects(const B: TLABox): TRectArray;
    function HitHandle(X, Y: Integer): Integer;
    function LayerVisible(L: Integer): Boolean;
    procedure DrawGrid(C: TCanvas);
    procedure DrawShape(C: TCanvas; S: TLAShape; Dim, Selected: Boolean);
    procedure DrawImagePreview(C: TCanvas; S: TLAShape; Dim: Boolean);
    procedure DrawPreviewJob(C: TCanvas);
    procedure DrawSelection(C: TCanvas);
    procedure DrawRulers(C: TCanvas);
    procedure DrawToolFeedback(C: TCanvas);
    procedure DrawPathScreen(C: TCanvas; const P: TLAPath);
    procedure BeforeChange;
    procedure Changed;
    procedure SelectionChanged;
    procedure SnapshotSelection;
    procedure UpdateCreated(const W: TLAPoint; Shift: TShiftState);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ScreenToWorld(X, Y: Integer): TLAPoint;
    function ShapeAt(const W: TLAPoint; Tol: Double): TLAShape;
    procedure ZoomFit;
    procedure ZoomBy(F: Double);
    procedure ZoomAt(F: Double; SX, SY: Integer);
    { selecao e edicao }
    function Selection: TList;
    function SelectionBox: TLABox;
    procedure ClearSelection;
    procedure SelectAll;
    procedure SelectShape(S: TLAShape; AddToSelection: Boolean = False);
    procedure DeleteSelection;
    procedure DuplicateSelection;
    procedure MoveSelection(DX, DY: Double);
    procedure MirrorSelection(Horizontal: Boolean);
    procedure SetSelectionLayer(L: Integer);
    procedure SetSelectionBounds(AX, AY, AW, AH: Double);
    procedure SetSelectionAngle(A: Double);
    procedure BringSelection(ToFront: Boolean);
    procedure FinishPolyline(Close: Boolean);
    procedure CancelTool;
    procedure DocumentReplaced;
    procedure InvalidatePreviews;
    function Busy: Boolean;
    property Document: TLADocument read FDoc write SetDocument;
    property Tool: TLATool read FTool write SetTool;
    property CurrentLayer: Integer read FCurrentLayer write FCurrentLayer;
    property PreviewJob: TLAJob read FPreviewJob write SetPreviewJob;
    property ShowPreview: Boolean read FShowPreview write SetShowPreview;
    property LockRatio: Boolean read FLockRatio write FLockRatio;
    property PolygonSides: Integer read FPolygonSides write FPolygonSides;
    property DefaultFont: string read FDefaultFont write FDefaultFont;
    property ViewScale: Double read FScale;
    property OnBeforeChange: TNotifyEvent read FOnBeforeChange write FOnBeforeChange;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnToolChange: TNotifyEvent read FOnToolChange write FOnToolChange;
    property OnCursor: TLACursorEvent read FOnCursor write FOnCursor;
  end;

implementation

const
  RULER = 24;
  HS = 4;   { meia aresta da alca }

function RGB3(R, G, B: Byte): TColor; inline;
begin
  Result := RGBToColor(R, G, B);
end;

function Lighten(C: TColor; T: Double): TColor;
var
  X: TColor;
begin
  X := ColorToRGB(C);
  Result := RGBToColor(Round(Red(X) + (255 - Red(X)) * T),
    Round(Green(X) + (255 - Green(X)) * T), Round(Blue(X) + (255 - Blue(X)) * T));
end;

{ ---------------------------------------------------------------------------- }

constructor TLAEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSel := TList.Create;
  FScale := 2;
  FOffX := 60;
  FOffY := 600;
  FCurrentLayer := 0;
  FPolygonSides := 6;
  FDefaultFont := {$IFDEF WINDOWS}'Arial'{$ELSE}'Sans'{$ENDIF};
  FHandle := -1;
  DoubleBuffered := True;
  TabStop := True;
  Color := RGB3(226, 230, 236);
end;

destructor TLAEditor.Destroy;
begin
  FPreviewJob.Free;
  FSel.Free;
  inherited Destroy;
end;

procedure TLAEditor.SetDocument(Value: TLADocument);
begin
  FDoc := Value;
  DocumentReplaced;
end;

procedure TLAEditor.DocumentReplaced;
begin
  FSel.Clear;
  FCreated := nil;
  SetLength(FPoly, 0);
  FDrag := dmNone;
  SetPreviewJob(nil);
  SelectionChanged;
  Invalidate;
end;

procedure TLAEditor.InvalidatePreviews;
var
  I: Integer;
begin
  if FDoc = nil then Exit;
  for I := 0 to FDoc.Count - 1 do
    FDoc.Shape(I).InvalidatePreview;
  Invalidate;
end;

function TLAEditor.Busy: Boolean;
begin
  Result := (FDrag <> dmNone) or (Length(FPoly) > 0);
end;

procedure TLAEditor.SetTool(Value: TLATool);
begin
  if Length(FPoly) > 0 then
    FinishPolyline(False);
  FTool := Value;
  FDrag := dmNone;
  if FTool = ltSelect then Cursor := crDefault else Cursor := crCross;
  if Assigned(FOnToolChange) then FOnToolChange(Self);
  Invalidate;
end;

procedure TLAEditor.SetPreviewJob(Value: TLAJob);
begin
  if FPreviewJob <> Value then
    FPreviewJob.Free;
  FPreviewJob := Value;
  Invalidate;
end;

procedure TLAEditor.SetShowPreview(Value: Boolean);
begin
  FShowPreview := Value;
  Invalidate;
end;

{ ---------------------------------------------------------------------------- }
{ Coordenadas                                                                  }

function TLAEditor.DrawRect: TRect;
begin
  Result := Rect(RULER, RULER, ClientWidth, ClientHeight);
end;

function TLAEditor.W2S(X, Y: Double): TPoint;
begin
  Result.X := Round(FOffX + X * FScale);
  Result.Y := Round(FOffY - Y * FScale);
end;

function TLAEditor.ScreenToWorld(X, Y: Integer): TLAPoint;
begin
  Result.X := (X - FOffX) / FScale;
  Result.Y := (FOffY - Y) / FScale;
end;

procedure TLAEditor.ZoomFit;
var
  R: TRect;
  BW, BH: Double;
begin
  if FDoc = nil then Exit;
  R := DrawRect;
  if (R.Right - R.Left < 20) or (R.Bottom - R.Top < 20) then Exit;
  BW := FDoc.BedW + 20;
  BH := FDoc.BedH + 20;
  FScale := Min((R.Right - R.Left) / BW, (R.Bottom - R.Top) / BH);
  FOffX := R.Left + ((R.Right - R.Left) - FDoc.BedW * FScale) / 2;
  FOffY := R.Bottom - ((R.Bottom - R.Top) - FDoc.BedH * FScale) / 2;
  FFitted := True;
  Invalidate;
end;

procedure TLAEditor.ZoomAt(F: Double; SX, SY: Integer);
var
  W: TLAPoint;
  NS: Double;
begin
  W := ScreenToWorld(SX, SY);
  NS := EnsureRange(FScale * F, 0.05, 200);
  FScale := NS;
  FOffX := SX - W.X * FScale;
  FOffY := SY + W.Y * FScale;
  Invalidate;
end;

procedure TLAEditor.ZoomBy(F: Double);
begin
  ZoomAt(F, (RULER + ClientWidth) div 2, (RULER + ClientHeight) div 2);
end;

procedure TLAEditor.Resize;
begin
  inherited Resize;
  if not FFitted then
    ZoomFit;
end;

function TLAEditor.LayerVisible(L: Integer): Boolean;
begin
  Result := (FDoc <> nil) and FDoc.Layers[EnsureRange(L, 0, LA_LAYER_COUNT - 1)].Show;
end;

{ ---------------------------------------------------------------------------- }
{ Desenho                                                                      }

procedure TLAEditor.DrawPathScreen(C: TCanvas; const P: TLAPath);
var
  Pts: array of TPoint;
  I, N: Integer;
begin
  N := Length(P.Pts);
  if N < 2 then Exit;
  if P.Closed then
    SetLength(Pts, N + 1)
  else
    SetLength(Pts, N);
  for I := 0 to N - 1 do
    Pts[I] := W2S(P.Pts[I].X, P.Pts[I].Y);
  if P.Closed then
    Pts[N] := Pts[0];
  C.Polyline(Pts);
end;

procedure TLAEditor.DrawGrid(C: TCanvas);
var
  Minor, Major, V: Double;
  Steps: array[0..7] of Double = (0.5, 1, 2, 5, 10, 20, 50, 100);
  I: Integer;
  A, B: TPoint;
  Sh: TRect;
begin
  { sombra e mesa }
  A := W2S(0, FDoc.BedH);
  B := W2S(FDoc.BedW, 0);
  Sh := Rect(A.X + 4, A.Y + 4, B.X + 4, B.Y + 4);
  C.Brush.Color := RGB3(200, 205, 214);
  C.Pen.Style := psClear;
  C.Rectangle(Sh);
  C.Brush.Color := clWhite;
  C.Rectangle(A.X, A.Y, B.X + 1, B.Y + 1);
  C.Pen.Style := psSolid;

  Minor := 100;
  for I := 0 to High(Steps) do
    if Steps[I] * FScale >= 9 then
    begin
      Minor := Steps[I];
      Break;
    end;
  if Minor < 10 then Major := 10 else Major := Minor * 5;

  C.Pen.Width := 1;
  V := 0;
  while V <= FDoc.BedW + 1e-6 do
  begin
    if Abs(Frac(V / Major + 1e-9)) < 1e-6 then
      C.Pen.Color := RGB3(214, 220, 230)
    else
      C.Pen.Color := RGB3(238, 241, 246);
    A := W2S(V, 0); B := W2S(V, FDoc.BedH);
    C.Line(A, B);
    V := V + Minor;
  end;
  V := 0;
  while V <= FDoc.BedH + 1e-6 do
  begin
    if Abs(Frac(V / Major + 1e-9)) < 1e-6 then
      C.Pen.Color := RGB3(214, 220, 230)
    else
      C.Pen.Color := RGB3(238, 241, 246);
    A := W2S(0, V); B := W2S(FDoc.BedW, V);
    C.Line(A, B);
    V := V + Minor;
  end;
  { borda da mesa e origem (0,0) }
  C.Pen.Color := RGB3(148, 163, 184);
  C.Brush.Style := bsClear;
  A := W2S(0, FDoc.BedH);
  B := W2S(FDoc.BedW, 0);
  C.Rectangle(A.X, A.Y, B.X + 1, B.Y + 1);
  C.Brush.Style := bsSolid;
  A := W2S(0, 0);
  C.Pen.Color := RGB3(22, 163, 74);
  C.Brush.Color := RGB3(34, 197, 94);
  C.Rectangle(A.X - 4, A.Y - 4, A.X + 5, A.Y + 5);
  if FDoc.StartFrom = sfUserOrigin then
  begin
    A := W2S(FDoc.UserOriginX, FDoc.UserOriginY);
    C.Pen.Color := RGB3(234, 88, 12);
    C.Pen.Width := 2;
    C.Line(A.X - 8, A.Y, A.X + 9, A.Y);
    C.Line(A.X, A.Y - 8, A.X, A.Y + 9);
    C.Pen.Width := 1;
  end;
end;

procedure TLAEditor.DrawImagePreview(C: TCanvas; S: TLAShape; Dim: Boolean);
var
  Key: string;
  G: TLAGray;
  Iv: Double;
  A, B: TPoint;
  Bmp: TBitmap;
  Cn: TLAPoints;
  Pts: array[0..4] of TPoint;
  I: Integer;
begin
  Iv := FDoc.Layers[S.Layer].Interval;
  if Iv <= 0 then Iv := 0.1;
  Key := Format('%s|%.3f|%.3f|%.3f|%d|%d|%d|%d|%d|%d',
    [S.ImageFile, S.W, S.H, Iv, Ord(S.Dither), S.Brightness, S.Contrast,
     Ord(S.Invert), Ord(S.MirrorX), Ord(S.MirrorY)]);
  if (S.Preview = nil) or (S.PreviewKey <> Key) then
  begin
    S.InvalidatePreview;
    G := ImageBurnGrid(S, Iv, 500);
    if G.W > 0 then
    begin
      S.Preview := BurnToBitmap(G, RGB3(28, 25, 23));
      S.PreviewKey := Key;
    end;
  end;
  if (S.Preview <> nil) and (S.Angle = 0) then
  begin
    Bmp := TBitmap(S.Preview);
    A := W2S(S.X, S.Y + S.H);
    B := W2S(S.X + S.W, S.Y);
    C.StretchDraw(Rect(A.X, A.Y, B.X, B.Y), Bmp);
    if Dim then
    begin
      C.Brush.Style := bsClear;
      C.Pen.Color := Lighten(LayerColor(S.Layer), 0.5);
      C.Rectangle(A.X, A.Y, B.X, B.Y);
    end;
  end
  else
  begin
    { imagem girada ou nao encontrada: contorno com X }
    Cn := ShapeCorners(S);
    for I := 0 to 3 do
      Pts[I] := W2S(Cn[I].X, Cn[I].Y);
    Pts[4] := Pts[0];
    C.Pen.Color := LayerColor(S.Layer);
    C.Polyline(Pts);
    C.Line(Pts[0], Pts[2]);
    C.Line(Pts[1], Pts[3]);
  end;
end;

procedure TLAEditor.DrawShape(C: TCanvas; S: TLAShape; Dim, Selected: Boolean);
var
  P: TLAPaths;
  I: Integer;
  Col: TColor;
begin
  if S.Kind = skImage then
  begin
    DrawImagePreview(C, S, Dim);
    Exit;
  end;
  P := ShapeWorldPaths(S);
  Col := LayerColor(S.Layer);
  if Dim then Col := Lighten(Col, 0.65);
  C.Pen.Color := Col;
  C.Pen.Width := 1;
  if Selected then C.Pen.Style := psDash else C.Pen.Style := psSolid;
  C.Brush.Style := bsClear;
  for I := 0 to High(P) do
    DrawPathScreen(C, P[I]);
  C.Pen.Style := psSolid;
end;

procedure TLAEditor.DrawPreviewJob(C: TCanvas);
var
  I: Integer;
  M: TLAMove;
  A, B: TPoint;
  OX, OY: Double;
begin
  if (FPreviewJob = nil) or (FPreviewJob.Count = 0) then Exit;
  OX := FPreviewJob.OffsetX;
  OY := FPreviewJob.OffsetY;
  A := W2S(OX, OY);
  for I := 0 to FPreviewJob.Count - 1 do
  begin
    M := FPreviewJob.Move(I);
    B := W2S(M.X + OX, M.Y + OY);
    case M.Kind of
      mkRapid:
        begin
          C.Pen.Width := 1;
          C.Pen.Style := psDot;
          C.Pen.Color := RGB3(239, 68, 68);
        end;
      mkBlank:
        begin
          C.Pen.Width := 1;
          C.Pen.Style := psDot;
          C.Pen.Color := RGB3(203, 213, 225);
        end;
    else
      C.Pen.Style := psSolid;
      C.Pen.Width := 2;
      C.Pen.Color := LayerColor(M.Layer);
    end;
    C.Line(A, B);
    A := B;
  end;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  { enquadramento }
  if FPreviewJob.Box.Valid then
  begin
    A := W2S(FPreviewJob.Box.X1 + OX, FPreviewJob.Box.Y2 + OY);
    B := W2S(FPreviewJob.Box.X2 + OX, FPreviewJob.Box.Y1 + OY);
    C.Pen.Color := RGB3(37, 99, 235);
    C.Pen.Style := psDash;
    C.Brush.Style := bsClear;
    C.Rectangle(A.X - 1, A.Y - 1, B.X + 2, B.Y + 2);
    C.Pen.Style := psSolid;
    { origem do trabalho }
    A := W2S(OX, OY);
    C.Pen.Color := RGB3(37, 99, 235);
    C.Brush.Color := RGB3(96, 165, 250);
    C.Brush.Style := bsSolid;
    C.Ellipse(A.X - 5, A.Y - 5, A.X + 6, A.Y + 6);
  end;
end;

function TLAEditor.HandleRects(const B: TLABox): TRectArray;
var
  P1, P2: TPoint;
  MX, MY: Integer;
begin
  SetLength(Result, 8);
  P1 := W2S(B.X1, B.Y2);
  P2 := W2S(B.X2, B.Y1);
  MX := (P1.X + P2.X) div 2;
  MY := (P1.Y + P2.Y) div 2;
  Result[0] := Rect(P1.X - HS, P1.Y - HS, P1.X + HS + 1, P1.Y + HS + 1);
  Result[1] := Rect(MX - HS, P1.Y - HS, MX + HS + 1, P1.Y + HS + 1);
  Result[2] := Rect(P2.X - HS, P1.Y - HS, P2.X + HS + 1, P1.Y + HS + 1);
  Result[3] := Rect(P2.X - HS, MY - HS, P2.X + HS + 1, MY + HS + 1);
  Result[4] := Rect(P2.X - HS, P2.Y - HS, P2.X + HS + 1, P2.Y + HS + 1);
  Result[5] := Rect(MX - HS, P2.Y - HS, MX + HS + 1, P2.Y + HS + 1);
  Result[6] := Rect(P1.X - HS, P2.Y - HS, P1.X + HS + 1, P2.Y + HS + 1);
  Result[7] := Rect(P1.X - HS, MY - HS, P1.X + HS + 1, MY + HS + 1);
end;

procedure TLAEditor.DrawSelection(C: TCanvas);
var
  B: TLABox;
  P1, P2: TPoint;
  R: TRectArray;
  I: Integer;
begin
  if FSel.Count = 0 then Exit;
  B := SelectionBox;
  if not B.Valid then Exit;
  P1 := W2S(B.X1, B.Y2);
  P2 := W2S(B.X2, B.Y1);
  C.Brush.Style := bsClear;
  C.Pen.Color := RGB3(100, 116, 139);
  C.Pen.Style := psDot;
  C.Rectangle(P1.X - 1, P1.Y - 1, P2.X + 2, P2.Y + 2);
  C.Pen.Style := psSolid;
  R := HandleRects(B);
  C.Brush.Style := bsSolid;
  C.Brush.Color := clWhite;
  C.Pen.Color := RGB3(37, 99, 235);
  for I := 0 to 7 do
    C.Rectangle(R[I]);
  { centro }
  C.Pen.Color := RGB3(37, 99, 235);
  C.Line((P1.X + P2.X) div 2 - 4, (P1.Y + P2.Y) div 2, (P1.X + P2.X) div 2 + 5, (P1.Y + P2.Y) div 2);
  C.Line((P1.X + P2.X) div 2, (P1.Y + P2.Y) div 2 - 4, (P1.X + P2.X) div 2, (P1.Y + P2.Y) div 2 + 5);
end;

procedure TLAEditor.DrawToolFeedback(C: TCanvas);
var
  A, B: TPoint;
  I: Integer;
  Pts: array of TPoint;
begin
  if FDrag = dmMarquee then
  begin
    A := W2S(FDownW.X, FDownW.Y);
    B := W2S(FLastW.X, FLastW.Y);
    C.Brush.Style := bsClear;
    C.Pen.Color := RGB3(37, 99, 235);
    C.Pen.Style := psDash;
    C.Rectangle(Min(A.X, B.X), Min(A.Y, B.Y), Max(A.X, B.X) + 1, Max(A.Y, B.Y) + 1);
    C.Pen.Style := psSolid;
  end;
  if Length(FPoly) > 0 then
  begin
    SetLength(Pts, Length(FPoly) + 1);
    for I := 0 to High(FPoly) do
      Pts[I] := W2S(FPoly[I].X, FPoly[I].Y);
    Pts[High(Pts)] := W2S(FHoverW.X, FHoverW.Y);
    C.Pen.Color := LayerColor(FCurrentLayer);
    C.Pen.Width := 1;
    C.Polyline(Pts);
    C.Brush.Color := clWhite;
    C.Brush.Style := bsSolid;
    for I := 0 to High(FPoly) do
      C.Rectangle(Pts[I].X - 3, Pts[I].Y - 3, Pts[I].X + 4, Pts[I].Y + 4);
    { indicacao para fechar }
    if (Length(FPoly) > 2) and (Hypot(Pts[High(Pts)].X - Pts[0].X, Pts[High(Pts)].Y - Pts[0].Y) < 8) then
    begin
      C.Pen.Color := RGB3(22, 163, 74);
      C.Brush.Style := bsClear;
      C.Ellipse(Pts[0].X - 7, Pts[0].Y - 7, Pts[0].X + 8, Pts[0].Y + 8);
    end;
  end;
end;

procedure TLAEditor.DrawRulers(C: TCanvas);
var
  Step, V, V0, V1: Double;
  Steps: array[0..9] of Double = (1, 2, 5, 10, 20, 50, 100, 200, 500, 1000);
  I, P, TW: Integer;
  S: string;
  W: TLAPoint;
begin
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGB3(248, 250, 252);
  C.Pen.Style := psClear;
  C.Rectangle(0, 0, ClientWidth + 1, RULER + 1);
  C.Rectangle(0, 0, RULER + 1, ClientHeight + 1);
  C.Pen.Style := psSolid;
  C.Pen.Color := RGB3(203, 213, 225);
  C.Line(0, RULER, ClientWidth, RULER);
  C.Line(RULER, 0, RULER, ClientHeight);

  Step := 1000;
  for I := 0 to High(Steps) do
    if Steps[I] * FScale >= 50 then
    begin
      Step := Steps[I];
      Break;
    end;
  C.Font.Size := 7;
  C.Font.Color := RGB3(100, 116, 139);
  C.Brush.Style := bsClear;

  { horizontal }
  W := ScreenToWorld(RULER, 0);
  V0 := Floor(W.X / Step) * Step;
  W := ScreenToWorld(ClientWidth, 0);
  V1 := W.X;
  V := V0;
  while V <= V1 do
  begin
    P := W2S(V, 0).X;
    if P >= RULER then
    begin
      C.Line(P, RULER - 8, P, RULER);
      S := FloatToStr(V);
      C.TextOut(P + 3, 3, S);
    end;
    for I := 1 to 9 do
    begin
      P := W2S(V + Step * I / 10, 0).X;
      if P >= RULER then
        if I = 5 then C.Line(P, RULER - 5, P, RULER) else C.Line(P, RULER - 3, P, RULER);
    end;
    V := V + Step;
  end;
  { vertical }
  W := ScreenToWorld(0, ClientHeight);
  V0 := Floor(W.Y / Step) * Step;
  W := ScreenToWorld(0, RULER);
  V1 := W.Y;
  V := V0;
  while V <= V1 do
  begin
    P := W2S(0, V).Y;
    if P >= RULER then
    begin
      C.Line(RULER - 8, P, RULER, P);
      S := FloatToStr(V);
      TW := C.TextWidth(S);
      if TW < RULER - 4 then
        C.TextOut(2, P + 2, S)
      else
        C.TextOut(2, P + 2, Copy(S, 1, 3));
    end;
    for I := 1 to 9 do
    begin
      P := W2S(0, V + Step * I / 10).Y;
      if P >= RULER then
        if I = 5 then C.Line(RULER - 5, P, RULER, P) else C.Line(RULER - 3, P, RULER, P);
    end;
    V := V + Step;
  end;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGB3(241, 245, 249);
  C.Pen.Color := RGB3(203, 213, 225);
  C.Rectangle(0, 0, RULER + 1, RULER + 1);
  C.Font.Size := 7;
  C.Brush.Style := bsClear;
  C.TextOut(4, 6, 'mm');
end;

procedure TLAEditor.Paint;
var
  I: Integer;
  S: TLAShape;
  C: TCanvas;
  Dim: Boolean;
begin
  C := Canvas;
  C.Brush.Color := Color;
  C.Brush.Style := bsSolid;
  C.FillRect(ClientRect);
  if FDoc = nil then Exit;
  DrawGrid(C);
  Dim := FShowPreview and (FPreviewJob <> nil);
  for I := 0 to FDoc.Count - 1 do
  begin
    S := FDoc.Shape(I);
    if not LayerVisible(S.Layer) then Continue;
    DrawShape(C, S, Dim, (not Dim) and (FSel.IndexOf(S) >= 0));
  end;
  if Dim then
    DrawPreviewJob(C)
  else
    DrawSelection(C);
  DrawToolFeedback(C);
  DrawRulers(C);
end;

{ ---------------------------------------------------------------------------- }
{ Selecao                                                                      }

function TLAEditor.Selection: TList;
begin
  Result := FSel;
end;

function TLAEditor.SelectionBox: TLABox;
var
  I: Integer;
begin
  Result := EmptyBox;
  for I := 0 to FSel.Count - 1 do
    Result := UnionBox(Result, ShapeBox(TLAShape(FSel[I])));
end;

procedure TLAEditor.SelectionChanged;
begin
  Invalidate;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TLAEditor.ClearSelection;
begin
  if FSel.Count = 0 then Exit;
  FSel.Clear;
  SelectionChanged;
end;

procedure TLAEditor.SelectAll;
var
  I: Integer;
begin
  FSel.Clear;
  for I := 0 to FDoc.Count - 1 do
    if LayerVisible(FDoc.Shape(I).Layer) then
      FSel.Add(FDoc.Shape(I));
  SelectionChanged;
end;

procedure TLAEditor.SelectShape(S: TLAShape; AddToSelection: Boolean);
begin
  if not AddToSelection then
    FSel.Clear;
  if (S <> nil) and (FSel.IndexOf(S) < 0) then
    FSel.Add(S);
  SelectionChanged;
end;

function TLAEditor.ShapeAt(const W: TLAPoint; Tol: Double): TLAShape;
var
  I, K: Integer;
  S: TLAShape;
  P: TLAPaths;
  Cn: TLAPoints;
  Poly: TLAPaths;
  Closed: Boolean;
begin
  Result := nil;
  if FDoc = nil then Exit;
  for I := FDoc.Count - 1 downto 0 do
  begin
    S := FDoc.Shape(I);
    if not LayerVisible(S.Layer) then Continue;
    if S.Kind = skImage then
    begin
      Cn := ShapeCorners(S);
      SetLength(Poly, 1);
      SetLength(Poly[0].Pts, 4);
      for K := 0 to 3 do Poly[0].Pts[K] := Cn[K];
      Poly[0].Closed := True;
      if PointInPaths(Poly, W.X, W.Y) then Exit(S);
      Continue;
    end;
    P := ShapeWorldPaths(S);
    if DistanceToPaths(P, W.X, W.Y) <= Tol then Exit(S);
    Closed := False;
    for K := 0 to High(P) do
      if P[K].Closed then Closed := True;
    if Closed and PointInPaths(P, W.X, W.Y) then Exit(S);
  end;
end;

procedure TLAEditor.SnapshotSelection;
var
  I: Integer;
  S: TLAShape;
begin
  SetLength(FOrig, FSel.Count);
  for I := 0 to FSel.Count - 1 do
  begin
    S := TLAShape(FSel[I]);
    FOrig[I].S := S;
    FOrig[I].X := S.X; FOrig[I].Y := S.Y;
    FOrig[I].W := S.W; FOrig[I].H := S.H;
  end;
  FOrigBox := SelectionBox;
end;

procedure TLAEditor.BeforeChange;
begin
  if FChangeNotified then Exit;
  FChangeNotified := True;
  if Assigned(FOnBeforeChange) then FOnBeforeChange(Self);
end;

procedure TLAEditor.Changed;
begin
  FChangeNotified := False;
  SetPreviewJob(nil);
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TLAEditor.DeleteSelection;
var
  I: Integer;
begin
  if FSel.Count = 0 then Exit;
  BeforeChange;
  for I := 0 to FSel.Count - 1 do
    FDoc.Remove(TLAShape(FSel[I]));
  FSel.Clear;
  FDoc.SyncLayerOrder;
  Changed;
  SelectionChanged;
end;

procedure TLAEditor.DuplicateSelection;
var
  I: Integer;
  N: TLAShape;
  NewSel: TList;
begin
  if FSel.Count = 0 then Exit;
  BeforeChange;
  NewSel := TList.Create;
  try
    for I := 0 to FSel.Count - 1 do
    begin
      N := TLAShape(FSel[I]).Clone;
      N.X := N.X + 5;
      N.Y := N.Y - 5;
      FDoc.Add(N);
      NewSel.Add(N);
    end;
    FSel.Assign(NewSel);
  finally
    NewSel.Free;
  end;
  Changed;
  SelectionChanged;
end;

procedure TLAEditor.MoveSelection(DX, DY: Double);
var
  I: Integer;
  S: TLAShape;
begin
  if FSel.Count = 0 then Exit;
  BeforeChange;
  for I := 0 to FSel.Count - 1 do
  begin
    S := TLAShape(FSel[I]);
    if S.Locked then Continue;
    S.X := S.X + DX;
    S.Y := S.Y + DY;
  end;
  Changed;
  SelectionChanged;
end;

procedure TLAEditor.MirrorSelection(Horizontal: Boolean);
var
  I: Integer;
  S: TLAShape;
  B: TLABox;
  CX, CY: Double;
begin
  if FSel.Count = 0 then Exit;
  BeforeChange;
  B := SelectionBox;
  CX := (B.X1 + B.X2) / 2;
  CY := (B.Y1 + B.Y2) / 2;
  for I := 0 to FSel.Count - 1 do
  begin
    S := TLAShape(FSel[I]);
    if Horizontal then
    begin
      S.MirrorX := not S.MirrorX;
      S.X := 2 * CX - (S.X + S.W);
      S.Angle := -S.Angle;
    end
    else
    begin
      S.MirrorY := not S.MirrorY;
      S.Y := 2 * CY - (S.Y + S.H);
      S.Angle := -S.Angle;
    end;
  end;
  Changed;
  SelectionChanged;
end;

procedure TLAEditor.SetSelectionLayer(L: Integer);
var
  I: Integer;
begin
  if FSel.Count = 0 then Exit;
  BeforeChange;
  for I := 0 to FSel.Count - 1 do
    TLAShape(FSel[I]).Layer := L;
  FDoc.SyncLayerOrder;
  Changed;
  SelectionChanged;
end;

{ X/Y = canto inferior esquerdo da caixa da selecao }
procedure TLAEditor.SetSelectionBounds(AX, AY, AW, AH: Double);
var
  I: Integer;
  B: TLABox;
  SX, SY, CX, CY: Double;
  S: TLAShape;
begin
  if FSel.Count = 0 then Exit;
  B := SelectionBox;
  if not B.Valid then Exit;
  AW := Max(AW, 0.01);
  AH := Max(AH, 0.01);
  if B.X2 - B.X1 > 1e-9 then SX := AW / (B.X2 - B.X1) else SX := 1;
  if B.Y2 - B.Y1 > 1e-9 then SY := AH / (B.Y2 - B.Y1) else SY := 1;
  BeforeChange;
  for I := 0 to FSel.Count - 1 do
  begin
    S := TLAShape(FSel[I]);
    CX := AX + (S.X + S.W / 2 - B.X1) * SX;
    CY := AY + (S.Y + S.H / 2 - B.Y1) * SY;
    S.W := Max(0.01, S.W * SX);
    S.H := Max(0.01, S.H * SY);
    S.X := CX - S.W / 2;
    S.Y := CY - S.H / 2;
  end;
  Changed;
  SelectionChanged;
end;

procedure TLAEditor.SetSelectionAngle(A: Double);
var
  I: Integer;
begin
  if FSel.Count = 0 then Exit;
  BeforeChange;
  for I := 0 to FSel.Count - 1 do
    TLAShape(FSel[I]).Angle := A;
  Changed;
  SelectionChanged;
end;

procedure TLAEditor.BringSelection(ToFront: Boolean);
var
  I: Integer;
begin
  if FSel.Count = 0 then Exit;
  BeforeChange;
  for I := 0 to FSel.Count - 1 do
    if ToFront then
      FDoc.MoveShape(TLAShape(FSel[I]), FDoc.Count - 1)
    else
      FDoc.MoveShape(TLAShape(FSel[I]), 0);
  Changed;
end;

{ ---------------------------------------------------------------------------- }
{ Ferramentas de desenho                                                       }

procedure TLAEditor.UpdateCreated(const W: TLAPoint; Shift: TShiftState);
var
  X1, Y1, DX, DY: Double;
begin
  if FCreated = nil then Exit;
  DX := W.X - FDownW.X;
  DY := W.Y - FDownW.Y;
  if ssShift in Shift then
  begin
    if Abs(DX) > Abs(DY) then DY := Sign(DY) * Abs(DX) else DX := Sign(DX) * Abs(DY);
  end;
  X1 := Min(FDownW.X, FDownW.X + DX);
  Y1 := Min(FDownW.Y, FDownW.Y + DY);
  FCreated.X := X1;
  FCreated.Y := Y1;
  FCreated.W := Max(Abs(DX), 0.01);
  FCreated.H := Max(Abs(DY), 0.01);
end;

procedure TLAEditor.FinishPolyline(Close: Boolean);
var
  S: TLAShape;
  W, H: Double;
  B: TLABox;
begin
  if Length(FPoly) < 2 then
  begin
    SetLength(FPoly, 0);
    Invalidate;
    Exit;
  end;
  BeforeChange;
  S := TLAShape.Create(skPath);
  S.Layer := FCurrentLayer;
  S.Name := 'Linha';
  SetLength(S.Local, 1);
  S.Local[0].Pts := Copy(FPoly);
  S.Local[0].Closed := Close and (Length(FPoly) > 2);
  B := PathsBox(S.Local);
  NormalizePaths(S.Local, W, H);
  S.LocalW := Max(W, 0.01);
  S.LocalH := Max(H, 0.01);
  S.W := S.LocalW;
  S.H := S.LocalH;
  S.X := B.X1;
  S.Y := B.Y1;
  FDoc.Add(S);
  SetLength(FPoly, 0);
  FSel.Clear;
  FSel.Add(S);
  Changed;
  SelectionChanged;
end;

procedure TLAEditor.CancelTool;
begin
  if Length(FPoly) > 0 then
  begin
    SetLength(FPoly, 0);
    Invalidate;
  end
  else if FTool <> ltSelect then
    SetTool(ltSelect)
  else
    ClearSelection;
end;

{ ---------------------------------------------------------------------------- }
{ Mouse                                                                        }

function TLAEditor.HitHandle(X, Y: Integer): Integer;
var
  R: TRectArray;
  I: Integer;
begin
  Result := -1;
  if FSel.Count = 0 then Exit;
  R := HandleRects(SelectionBox);
  for I := 0 to 7 do
    if PtInRect(Rect(R[I].Left - 2, R[I].Top - 2, R[I].Right + 2, R[I].Bottom + 2), Point(X, Y)) then
      Exit(I);
end;

procedure TLAEditor.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  W: TLAPoint;
  S: TLAShape;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  if FDoc = nil then Exit;
  FDownX := X; FDownY := Y;
  W := ScreenToWorld(X, Y);
  FDownW := W;
  FLastW := W;
  FChangeNotified := False;

  if (Button = mbMiddle) or (Button = mbRight) then
  begin
    FDrag := dmPan;
    Cursor := crSizeAll;
    Exit;
  end;
  if Button <> mbLeft then Exit;

  case FTool of
    ltSelect:
      begin
        FHandle := HitHandle(X, Y);
        if FHandle >= 0 then
        begin
          SnapshotSelection;
          FDrag := dmScale;
          Exit;
        end;
        S := ShapeAt(W, 5 / FScale);
        if S <> nil then
        begin
          if ssShift in Shift then
          begin
            if FSel.IndexOf(S) >= 0 then FSel.Remove(S) else FSel.Add(S);
            SelectionChanged;
            Exit;
          end;
          if FSel.IndexOf(S) < 0 then
            SelectShape(S);
          SnapshotSelection;
          FDrag := dmMove;
        end
        else
        begin
          if not (ssShift in Shift) then ClearSelection;
          FDrag := dmMarquee;
        end;
      end;
    ltRect, ltEllipse, ltPolygon:
      begin
        FDrag := dmCreate;
        FCreated := nil;
      end;
    ltLine:
      begin
        if (Length(FPoly) > 2) and
           (Hypot(X - W2S(FPoly[0].X, FPoly[0].Y).X, Y - W2S(FPoly[0].X, FPoly[0].Y).Y) < 8) then
        begin
          FinishPolyline(True);
          Exit;
        end;
        SetLength(FPoly, Length(FPoly) + 1);
        FPoly[High(FPoly)] := W;
        FHoverW := W;
        Invalidate;
      end;
    ltText:
      begin
        BeforeChange;
        S := TLAShape.Create(skText);
        S.Layer := FCurrentLayer;
        S.Name := 'Texto';
        S.Text := 'Texto';
        S.FontName := FDefaultFont;
        S.H := 10;
        RebuildTextShape(S);
        S.X := W.X;
        S.Y := W.Y;
        FDoc.Add(S);
        FSel.Clear;
        FSel.Add(S);
        Changed;
        SelectionChanged;
      end;
  end;
end;

procedure TLAEditor.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  W: TLAPoint;
  DX, DY, SX, SY, AX, AY, CX, CY, NW, NH: Double;
  I: Integer;
  S: TLAShape;
  B: TLABox;
begin
  inherited MouseMove(Shift, X, Y);
  if FDoc = nil then Exit;
  W := ScreenToWorld(X, Y);
  if Assigned(FOnCursor) then FOnCursor(Self, W.X, W.Y);
  case FDrag of
    dmPan:
      begin
        FOffX := FOffX + (X - FDownX);
        FOffY := FOffY + (Y - FDownY);
        FDownX := X; FDownY := Y;
        Invalidate;
      end;
    dmMove:
      begin
        DX := W.X - FDownW.X;
        DY := W.Y - FDownW.Y;
        if (Abs(X - FDownX) + Abs(Y - FDownY) < 3) then Exit;
        BeforeChange;
        for I := 0 to High(FOrig) do
          if not FOrig[I].S.Locked then
          begin
            FOrig[I].S.X := FOrig[I].X + DX;
            FOrig[I].S.Y := FOrig[I].Y + DY;
          end;
        Invalidate;
        if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
      end;
    dmScale:
      begin
        B := FOrigBox;
        if not B.Valid then Exit;
        { ancora = lado/canto oposto }
        case FHandle of
          0: begin AX := B.X2; AY := B.Y1; end;
          1: begin AX := (B.X1 + B.X2) / 2; AY := B.Y1; end;
          2: begin AX := B.X1; AY := B.Y1; end;
          3: begin AX := B.X1; AY := (B.Y1 + B.Y2) / 2; end;
          4: begin AX := B.X1; AY := B.Y2; end;
          5: begin AX := (B.X1 + B.X2) / 2; AY := B.Y2; end;
          6: begin AX := B.X2; AY := B.Y2; end;
        else
          begin AX := B.X2; AY := (B.Y1 + B.Y2) / 2; end;
        end;
        NW := Max(0.1, Abs(W.X - AX));
        NH := Max(0.1, Abs(W.Y - AY));
        if B.X2 - B.X1 > 1e-9 then SX := NW / (B.X2 - B.X1) else SX := 1;
        if B.Y2 - B.Y1 > 1e-9 then SY := NH / (B.Y2 - B.Y1) else SY := 1;
        if FHandle in [1, 5] then SX := 1;
        if FHandle in [3, 7] then SY := 1;
        if (FHandle in [0, 2, 4, 6]) and (FLockRatio or (ssShift in Shift)) then
        begin
          SX := Max(SX, SY);
          SY := SX;
        end;
        BeforeChange;
        for I := 0 to High(FOrig) do
        begin
          S := FOrig[I].S;
          if S.Locked then Continue;
          CX := AX + (FOrig[I].X + FOrig[I].W / 2 - AX) * SX;
          CY := AY + (FOrig[I].Y + FOrig[I].H / 2 - AY) * SY;
          S.W := Max(0.01, FOrig[I].W * SX);
          S.H := Max(0.01, FOrig[I].H * SY);
          S.X := CX - S.W / 2;
          S.Y := CY - S.H / 2;
        end;
        Invalidate;
        if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
      end;
    dmMarquee:
      begin
        FLastW := W;
        Invalidate;
      end;
    dmCreate:
      begin
        if FCreated = nil then
        begin
          if Abs(X - FDownX) + Abs(Y - FDownY) < 4 then Exit;
          BeforeChange;
          case FTool of
            ltRect:    FCreated := TLAShape.Create(skRect);
            ltEllipse: FCreated := TLAShape.Create(skEllipse);
          else
            begin
              FCreated := TLAShape.Create(skPolygon);
              FCreated.Sides := FPolygonSides;
            end;
          end;
          FCreated.Layer := FCurrentLayer;
          FCreated.Name := FCreated.KindName;
          FDoc.Add(FCreated);
          FSel.Clear;
          FSel.Add(FCreated);
        end;
        UpdateCreated(W, Shift);
        Invalidate;
        if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
      end;
  else
    if Length(FPoly) > 0 then
    begin
      FHoverW := W;
      Invalidate;
    end
    else if FTool = ltSelect then
    begin
      I := HitHandle(X, Y);
      case I of
        0, 4: Cursor := crSizeNWSE;
        2, 6: Cursor := crSizeNESW;
        1, 5: Cursor := crSizeNS;
        3, 7: Cursor := crSizeWE;
      else
        if ShapeAt(W, 5 / FScale) <> nil then Cursor := crSizeAll else Cursor := crDefault;
      end;
    end;
  end;
end;

procedure TLAEditor.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  B, SB: TLABox;
  I: Integer;
  S: TLAShape;
  Was: TDragMode;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Was := FDrag;
  FDrag := dmNone;
  case Was of
    dmPan:
      if FTool = ltSelect then Cursor := crDefault else Cursor := crCross;
    dmMove, dmScale:
      if FChangeNotified then Changed;
    dmMarquee:
      begin
        B.X1 := Min(FDownW.X, FLastW.X); B.X2 := Max(FDownW.X, FLastW.X);
        B.Y1 := Min(FDownW.Y, FLastW.Y); B.Y2 := Max(FDownW.Y, FLastW.Y);
        if (B.X2 - B.X1) * FScale > 3 then
        begin
          for I := 0 to FDoc.Count - 1 do
          begin
            S := FDoc.Shape(I);
            if not LayerVisible(S.Layer) then Continue;
            SB := ShapeBox(S);
            { cruza a area }
            if (SB.X2 >= B.X1) and (SB.X1 <= B.X2) and (SB.Y2 >= B.Y1) and (SB.Y1 <= B.Y2) and
               (FSel.IndexOf(S) < 0) then
              FSel.Add(S);
          end;
        end;
        SelectionChanged;
      end;
    dmCreate:
      begin
        if FCreated <> nil then
        begin
          FCreated := nil;
          Changed;
          SelectionChanged;
        end;
      end;
  end;
  Invalidate;
end;

procedure TLAEditor.DblClick;
begin
  inherited DblClick;
  if (FTool = ltLine) and (Length(FPoly) > 0) then
  begin
    { o duplo clique adicionou um ponto repetido }
    if (Length(FPoly) > 1) and (Hypot(FPoly[High(FPoly)].X - FPoly[High(FPoly) - 1].X,
        FPoly[High(FPoly)].Y - FPoly[High(FPoly) - 1].Y) * FScale < 4) then
      SetLength(FPoly, Length(FPoly) - 1);
    FinishPolyline(False);
  end;
end;

function TLAEditor.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then
    ZoomAt(1.2, MousePos.X, MousePos.Y)
  else
    ZoomAt(1 / 1.2, MousePos.X, MousePos.Y);
end;

end.
