unit makerouter_view;

{ Vista do MakeRouter.

  - Desenho: material (cor da madeira), grade de 10 mm, reguas em mm, marca do
    zero virtual, formas (selecionadas em azul) e os percursos calculados (cor
    por percurso; o percurso ativo mais grosso).
  - Simulacao: a imagem sombreada do material (makerouter_sim) no lugar da
    madeira, com o mesmo zoom e deslocamento.
  - Mouse: roda = zoom no cursor; botao do meio ou direito arrasta a vista;
    clique seleciona (Shift soma); arrastar uma forma selecionada move a
    selecao (passo de 1 mm; Alt = livre). Duplo clique = ajustar. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, LCLIntf, GraphType,
  IntfGraphics, FPImage, laserpcb_geom, makerouter_types, makerouter_project,
  makerouter_sim, multisuite_controls;

type
  TMRViewMode = (vmDesign, vmSim);
  TMRIds = array of Integer;
  TMRMoveEvent = procedure(Sender: TObject; DX, DY: Double) of object;
  TMRPointEvent = procedure(Sender: TObject; X, Y: Double) of object;

  TMRView = class(TCustomControl)
  private
    FProject: TMRProject;
    FScale, FOffX, FOffY: Double;      { tela = projeto * escala + desloc. }
    FSelected: array of Integer;
    FMode: TMRViewMode;
    FSim: TBitmap;
    FActive: Integer;                  { percurso em destaque }
    FPanning, FDragging, FMoved: Boolean;
    FDownX, FDownY: Integer;
    FLastMMX, FLastMMY: Double;
    FDragDX, FDragDY: Double;
    FShowPaths, FShowRapids: Boolean;
    FOnSelect: TNotifyEvent;
    FOnMoveShapes: TMRMoveEvent;
    FOnCursor: TMRPointEvent;
    function SX(X: Double): Integer; inline;
    function SY(Y: Double): Integer; inline;
    function ShapeAt(X, Y: Integer): Integer;
    procedure DrawRulers;
    procedure DrawPath(const P: TLPPath; Closed: Boolean);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure FitMaterial;
    procedure ZoomBy(F: Double);
    function ToMM(X, Y: Integer): TLPPoint;
    function IsSelected(AId: Integer): Boolean;
    procedure SelectOnly(AId: Integer);
    procedure ClearSelection;
    function SelectedIds: TMRIds;
    function SelectedCount: Integer;
    procedure SetSimPixels(const Px: TMRPixels; W, H: Integer);
    property Project: TMRProject read FProject write FProject;
    property Mode: TMRViewMode read FMode write FMode;
    property ActiveToolpath: Integer read FActive write FActive;
    property ShowPaths: Boolean read FShowPaths write FShowPaths;
    property ShowRapids: Boolean read FShowRapids write FShowRapids;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnMoveShapes: TMRMoveEvent read FOnMoveShapes write FOnMoveShapes;
    property OnCursor: TMRPointEvent read FOnCursor write FOnCursor;
  end;

const
  { cores dos percursos (RGB) }
  MR_PATH_COLORS: array[0..7] of TColor = ($00C05A1E, $001E8CDC, $0050A028, $00A03CB4,
    $00287AC8, $00B4823C, $003C3CC8, $00808000);

implementation

const
  RULER = 22;

constructor TMRView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  Color := clSuiteSurface;
  FScale := 2; FOffX := 60; FOffY := 400;
  FActive := -1;
  FShowPaths := True;
  FShowRapids := False;
  TabStop := True;
end;

destructor TMRView.Destroy;
begin
  FSim.Free;
  inherited Destroy;
end;

function TMRView.SX(X: Double): Integer;
begin
  Result := Round(X * FScale + FOffX);
end;

function TMRView.SY(Y: Double): Integer;
begin
  Result := Round(FOffY - Y * FScale);
end;

function TMRView.ToMM(X, Y: Integer): TLPPoint;
begin
  Result := LPPoint((X - FOffX) / FScale, (FOffY - Y) / FScale);
end;

procedure TMRView.FitMaterial;
var W, H, AW, AH: Double;
begin
  if FProject = nil then Exit;
  W := Max(1, FProject.Material.Width); H := Max(1, FProject.Material.Height);
  AW := Max(50, ClientWidth - RULER - 60); AH := Max(50, ClientHeight - RULER - 60);
  FScale := Min(AW / W, AH / H);
  FOffX := RULER + (ClientWidth - RULER - W * FScale) / 2;
  FOffY := RULER + (ClientHeight - RULER + H * FScale) / 2;
  Invalidate;
end;

procedure TMRView.ZoomBy(F: Double);
var CX, CY: Integer; P: TLPPoint;
begin
  CX := ClientWidth div 2; CY := ClientHeight div 2;
  P := ToMM(CX, CY);
  FScale := EnsureRange(FScale * F, 0.02, 400);
  FOffX := CX - P.X * FScale;
  FOffY := CY + P.Y * FScale;
  Invalidate;
end;

function TMRView.IsSelected(AId: Integer): Boolean;
var I: Integer;
begin
  for I := 0 to High(FSelected) do if FSelected[I] = AId then Exit(True);
  Result := False;
end;

procedure TMRView.SelectOnly(AId: Integer);
begin
  SetLength(FSelected, 1);
  FSelected[0] := AId;
  Invalidate;
end;

procedure TMRView.ClearSelection;
begin
  FSelected := nil;
  Invalidate;
end;

function TMRView.SelectedIds: TMRIds;
begin
  Result := Copy(FSelected);
end;

function TMRView.SelectedCount: Integer;
begin
  Result := Length(FSelected);
end;

procedure TMRView.SetSimPixels(const Px: TMRPixels; W, H: Integer);
var Img: TLazIntfImage; X, Y: Integer; C: LongWord; FC: TFPColor;
begin
  FreeAndNil(FSim);
  if (W <= 0) or (H <= 0) or (Length(Px) < W * H) then Exit;
  Img := TLazIntfImage.Create(W, H, [riqfRGB]);
  try
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        C := Px[Y * W + X];   { $00BBGGRR }
        FC.Red := (C and $FF) * 257;
        FC.Green := ((C shr 8) and $FF) * 257;
        FC.Blue := ((C shr 16) and $FF) * 257;
        FC.Alpha := $FFFF;
        Img.Colors[X, Y] := FC;
      end;
    FSim := TBitmap.Create;
    FSim.LoadFromIntfImage(Img);
  finally
    Img.Free;
  end;
  Invalidate;
end;

procedure TMRView.DrawPath(const P: TLPPath; Closed: Boolean);
var Pts: array of TPoint; I: Integer;
begin
  if Length(P) < 2 then Exit;
  SetLength(Pts, Length(P));
  for I := 0 to High(P) do
  begin
    Pts[I].X := SX(P[I].X);
    Pts[I].Y := SY(P[I].Y);
  end;
  Canvas.Polyline(Pts);
  if Closed then ;
end;

procedure TMRView.DrawRulers;
var Step, V, Start: Double; X, Y: Integer; S: string;
begin
  Canvas.Brush.Color := clSuiteCard;
  Canvas.Pen.Color := clSuiteBorder;
  Canvas.FillRect(0, 0, ClientWidth, RULER);
  Canvas.FillRect(0, 0, RULER, ClientHeight);
  Canvas.Font.Size := 7;
  Canvas.Font.Color := clSuiteMuted;
  Step := 10;
  while Step * FScale < 40 do
    if Step < 50 then Step := Step * 5 else Step := Step * 2;
  Start := Floor(ToMM(RULER, 0).X / Step) * Step;
  V := Start;
  while SX(V) < ClientWidth do
  begin
    X := SX(V);
    if X > RULER then
    begin
      Canvas.Line(X, RULER - 6, X, RULER);
      S := FormatFloat('0', V);
      Canvas.TextOut(X + 2, 3, S);
    end;
    V := V + Step;
  end;
  Start := Floor(ToMM(0, ClientHeight).Y / Step) * Step;
  V := Start;
  while SY(V) > 0 do
  begin
    Y := SY(V);
    if Y > RULER then
    begin
      Canvas.Line(RULER - 6, Y, RULER, Y);
      Canvas.TextOut(2, Y + 1, FormatFloat('0', V));
    end;
    V := V + Step;
  end;
  Canvas.Brush.Color := clSuiteCard;
  Canvas.FillRect(0, 0, RULER, RULER);
  Canvas.TextOut(3, 5, 'mm');
end;

procedure TMRView.Paint;
var M: TMRMaterial; R: TRect; I, J, K: Integer; S: TMRShape; Q: TLPPaths;
  T: TMRToolpath; G: Double; D: TLPPoint; Mv: TMRMoves; X0, Y0: Integer;
begin
  Canvas.Brush.Color := clSuiteSurface;
  Canvas.FillRect(ClientRect);
  if FProject = nil then Exit;
  M := FProject.Material;
  R := Rect(SX(0), SY(M.Height), SX(M.Width), SY(0));
  { material }
  if (FMode = vmSim) and (FSim <> nil) then
    Canvas.StretchDraw(R, FSim)
  else
  begin
    Canvas.Brush.Color := TColor(MR_WOOD_LIGHT[EnsureRange(M.Visual, 0, High(MR_WOODS))]);
    Canvas.Pen.Color := TColor(MR_WOOD_DARK[EnsureRange(M.Visual, 0, High(MR_WOODS))]);
    Canvas.Rectangle(R);
    { grade de 10 mm }
    if 10 * FScale >= 6 then
    begin
      Canvas.Pen.Color := TColor(MR_WOOD_DARK[EnsureRange(M.Visual, 0, High(MR_WOODS))]);
      Canvas.Pen.Style := psDot;
      G := 10;
      while G < M.Width do begin Canvas.Line(SX(G), R.Top + 1, SX(G), R.Bottom - 1); G := G + 10; end;
      G := 10;
      while G < M.Height do begin Canvas.Line(R.Left + 1, SY(G), R.Right - 1, SY(G)); G := G + 10; end;
      Canvas.Pen.Style := psSolid;
    end;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := clSuiteText;
  Canvas.Rectangle(R);
  { percursos }
  if FShowPaths and (FMode = vmDesign) then
    for I := 0 to FProject.ToolpathCount - 1 do
    begin
      T := FProject.Toolpaths[I];
      if not T.Enabled or (Length(T.Moves) = 0) then Continue;
      Mv := T.Moves;
      Canvas.Pen.Color := MR_PATH_COLORS[I mod Length(MR_PATH_COLORS)];
      if I = FActive then Canvas.Pen.Width := 2 else Canvas.Pen.Width := 1;
      for J := 1 to High(Mv) do
      begin
        if Mv[J].Rapid then
        begin
          if not FShowRapids then Continue;
          Canvas.Pen.Style := psDot;
        end
        else Canvas.Pen.Style := psSolid;
        Canvas.Line(SX(Mv[J - 1].X), SY(Mv[J - 1].Y), SX(Mv[J].X), SY(Mv[J].Y));
      end;
      Canvas.Pen.Style := psSolid;
      Canvas.Pen.Width := 1;
    end;
  { formas }
  for I := 0 to FProject.ShapeCount - 1 do
  begin
    S := FProject.Shapes[I];
    Q := S.Paths(Max(0.01, 0.5 / FScale));
    if IsSelected(S.Id) then
    begin
      Canvas.Pen.Color := clSuitePrimary; Canvas.Pen.Width := 2;
    end
    else
    begin
      Canvas.Pen.Color := $00303030; Canvas.Pen.Width := 1;
    end;
    for K := 0 to High(Q) do
    begin
      if FDragging and IsSelected(S.Id) then
        for J := 0 to High(Q[K]) do
        begin
          Q[K][J].X := Q[K][J].X + FDragDX;
          Q[K][J].Y := Q[K][J].Y + FDragDY;
        end;
      DrawPath(Q[K], S.IsClosed);
    end;
  end;
  Canvas.Pen.Width := 1;
  { zero virtual }
  D := FProject.DatumPoint;
  X0 := SX(D.X); Y0 := SY(D.Y);
  Canvas.Pen.Color := clSuiteDanger; Canvas.Pen.Width := 2;
  Canvas.Line(X0, Y0, X0 + 26, Y0);
  Canvas.Pen.Color := clSuiteSuccess;
  Canvas.Line(X0, Y0, X0, Y0 - 26);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clSuiteText;
  Canvas.Pen.Color := clWhite;
  Canvas.Ellipse(X0 - 6, Y0 - 6, X0 + 7, Y0 + 7);
  Canvas.Font.Size := 8; Canvas.Font.Color := clSuiteText; Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X0 + 8, Y0 + 4, 'X0 Y0');
  DrawRulers;
end;

function TMRView.ShapeAt(X, Y: Integer): Integer;
var I, K, J: Integer; P: TLPPoint; Q: TLPPaths; Tol, D, DX, DY, T: Double; A, B: TLPPoint;
  Best: Double;
begin
  Result := -1;
  if FProject = nil then Exit;
  P := ToMM(X, Y);
  Tol := 5 / FScale;
  Best := MaxDouble;
  for I := FProject.ShapeCount - 1 downto 0 do
  begin
    Q := FProject.Shapes[I].Paths(Max(0.05, 0.5 / FScale));
    for K := 0 to High(Q) do
      for J := 1 to High(Q[K]) do
      begin
        A := Q[K][J - 1]; B := Q[K][J];
        DX := B.X - A.X; DY := B.Y - A.Y;
        if DX * DX + DY * DY < 1e-12 then T := 0
        else T := EnsureRange(((P.X - A.X) * DX + (P.Y - A.Y) * DY) / (DX * DX + DY * DY), 0, 1);
        D := Hypot(P.X - (A.X + T * DX), P.Y - (A.Y + T * DY));
        if (D <= Tol) and (D < Best) then
        begin
          Best := D;
          Result := FProject.Shapes[I].Id;
        end;
      end;
  end;
end;

procedure TMRView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var Id, I: Integer; P: TLPPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  FDownX := X; FDownY := Y;
  FMoved := False;
  if Button in [mbMiddle, mbRight] then
  begin
    FPanning := True;
    Exit;
  end;
  if FMode <> vmDesign then begin FPanning := True; Exit; end;
  Id := ShapeAt(X, Y);
  if ssShift in Shift then
  begin
    if Id >= 0 then
    begin
      if IsSelected(Id) then
      begin
        for I := 0 to High(FSelected) do
          if FSelected[I] = Id then
          begin
            FSelected[I] := FSelected[High(FSelected)];
            SetLength(FSelected, Length(FSelected) - 1);
            Break;
          end;
      end
      else
      begin
        SetLength(FSelected, Length(FSelected) + 1);
        FSelected[High(FSelected)] := Id;
      end;
    end;
  end
  else if Id < 0 then FSelected := nil
  else if not IsSelected(Id) then SelectOnly(Id);
  if Assigned(FOnSelect) then FOnSelect(Self);
  if (Id >= 0) and IsSelected(Id) and not (ssShift in Shift) then
  begin
    FDragging := True;
    P := ToMM(X, Y);
    FLastMMX := P.X; FLastMMY := P.Y;
    FDragDX := 0; FDragDY := 0;
  end;
  Invalidate;
end;

procedure TMRView.MouseMove(Shift: TShiftState; X, Y: Integer);
var P: TLPPoint;
begin
  inherited MouseMove(Shift, X, Y);
  P := ToMM(X, Y);
  if Assigned(FOnCursor) then FOnCursor(Self, P.X, P.Y);
  if (Abs(X - FDownX) > 2) or (Abs(Y - FDownY) > 2) then FMoved := True;
  if FPanning then
  begin
    FOffX := FOffX + (X - FDownX);
    FOffY := FOffY + (Y - FDownY);
    FDownX := X; FDownY := Y;
    Invalidate;
  end
  else if FDragging and FMoved then
  begin
    FDragDX := P.X - FLastMMX;
    FDragDY := P.Y - FLastMMY;
    if not (ssAlt in Shift) then
    begin
      FDragDX := Round(FDragDX);
      FDragDY := Round(FDragDY);
    end;
    Invalidate;
  end;
end;

procedure TMRView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging and FMoved and ((Abs(FDragDX) > 1e-9) or (Abs(FDragDY) > 1e-9)) then
    if Assigned(FOnMoveShapes) then FOnMoveShapes(Self, FDragDX, FDragDY);
  FPanning := False;
  FDragging := False;
  FDragDX := 0; FDragDY := 0;
  Invalidate;
end;

function TMRView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var P: TLPPoint; F: Double;
begin
  Result := True;
  P := ToMM(MousePos.X, MousePos.Y);
  if WheelDelta > 0 then F := 1.2 else F := 1 / 1.2;
  FScale := EnsureRange(FScale * F, 0.02, 400);
  FOffX := MousePos.X - P.X * FScale;
  FOffY := MousePos.Y + P.Y * FScale;
  Invalidate;
end;

procedure TMRView.DblClick;
begin
  inherited DblClick;
  FitMaterial;
end;

end.
