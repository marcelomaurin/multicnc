unit multislicer_view;

{ MultiSlicer - vista central (Etapa 1 do docs/PLANO_TAREFAS.md).

  Dois modos, sempre em coordenadas da mesa (origem no canto inferior
  esquerdo, Y para cima, 1 unidade = 1 mm):
    svMesa     - mesa da impressora com grade de 10 mm e a projecao da peca
                 vista de cima (fora da mesa em vermelho);
    svCamadas  - trajetorias da camada escolhida, coloridas por papel, com o
                 mesmo resultado que gera o G-code (TModernSlicer.Layers).

  Roda do mouse: zoom no cursor; arrastar: deslocar; FitView volta a mesa inteira.
  Provisoria ate a vista 3D (Etapa 3): desenho por Canvas, sem OpenGL.
  O modo mesa guarda o desenho num bitmap e so redesenha quando a malha,
  a mesa ou o tamanho mudam (malhas grandes nao travam o redimensionamento). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, multislicer_types, multislicer_mesh,
  multislicer_pipeline;

type
  TSlicerViewMode = (svMesa, svCamadas);

  TSlicerView = class(TCustomControl)
  private
    FMesh: TMesh;
    FEngine: TModernSlicer;
    FLayer: Integer;
    FMode: TSlicerViewMode;
    FBedX, FBedY: Double;
    FCache: TBitmap;
    FCacheValid: Boolean;
    FScale, FOX, FOY: Double;
    FZoom, FPanX, FPanY: Double;
    FDragging: Boolean;
    FLastX, FLastY: Integer;
    procedure SetMode(AValue: TSlicerViewMode);
    procedure ComputeFit;
    function SX(X: Double): Integer;
    function SY(Y: Double): Integer;
    procedure DrawBed(C: TCanvas);
    procedure DrawMesh(C: TCanvas);
    procedure DrawLayer(C: TCanvas);
    procedure DrawLegend(C: TCanvas);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetMesh(AMesh: TMesh);
    procedure SetBed(ABedX, ABedY: Double);
    procedure SetSlice(AEngine: TModernSlicer; ALayer: Integer);
    procedure Refresh3D;
    procedure FitView;
    procedure ZoomAt(Factor: Double; X, Y: Integer);
    procedure ZoomIn;
    procedure ZoomOut;
    property Mode: TSlicerViewMode read FMode write SetMode;
    property Layer: Integer read FLayer;
  end;

function SlicerRoleColor(R: TPathRole): TColor;
function SlicerRoleName(R: TPathRole): string;

implementation

uses multisuite_controls;

function SlicerRoleColor(R: TPathRole): TColor;
begin
  case R of
    prSkirt: Result := SuiteRGB(100, 116, 139);
    prOuterWall: Result := SuiteRGB(220, 38, 38);
    prInnerWall: Result := SuiteRGB(22, 163, 74);
    prSolidInfill: Result := SuiteRGB(217, 119, 6);
    prSparseInfill: Result := SuiteRGB(124, 58, 237);
  else
    Result := clGray;
  end;
end;

function SlicerRoleName(R: TPathRole): string;
begin
  case R of
    prSkirt: Result := 'Saia';
    prOuterWall: Result := 'Parede externa';
    prInnerWall: Result := 'Parede interna';
    prSolidInfill: Result := 'Topo/fundo';
    prSparseInfill: Result := 'Preenchimento';
  else
    Result := '';
  end;
end;

constructor TSlicerView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  Color := clSuiteSurface;
  FBedX := 220; FBedY := 220;
  FLayer := -1;
  FZoom := 1;
  FCache := TBitmap.Create;
end;

destructor TSlicerView.Destroy;
begin
  FCache.Free;
  inherited Destroy;
end;

procedure TSlicerView.SetMode(AValue: TSlicerViewMode);
begin
  if FMode = AValue then Exit;
  FMode := AValue;
  Invalidate;
end;

procedure TSlicerView.SetMesh(AMesh: TMesh);
begin
  FMesh := AMesh;
  Refresh3D;
end;

procedure TSlicerView.SetBed(ABedX, ABedY: Double);
begin
  if (ABedX <= 0) or (ABedY <= 0) then Exit;
  if SameValue(ABedX, FBedX) and SameValue(ABedY, FBedY) then Exit;
  FBedX := ABedX; FBedY := ABedY;
  Refresh3D;
end;

procedure TSlicerView.SetSlice(AEngine: TModernSlicer; ALayer: Integer);
begin
  FEngine := AEngine;
  FLayer := ALayer;
  if FMode = svCamadas then Invalidate;
end;

procedure TSlicerView.Refresh3D;
begin
  FCacheValid := False;
  Invalidate;
end;

procedure TSlicerView.Resize;
begin
  inherited Resize;
  FCacheValid := False;
end;

procedure TSlicerView.ComputeFit;
const Margin = 36;
begin
  FScale := Min((ClientWidth - 2 * Margin) / FBedX, (ClientHeight - 2 * Margin - 24) / FBedY);
  if FScale <= 0 then FScale := 0.1;
  FScale := FScale * FZoom;
  FOX := (ClientWidth - FBedX * FScale) / 2 + FPanX;
  FOY := (ClientHeight - FBedY * FScale) / 2 + 8 + FPanY;
end;

procedure TSlicerView.FitView;
begin
  FZoom := 1; FPanX := 0; FPanY := 0;
  Refresh3D;
end;

procedure TSlicerView.ZoomAt(Factor: Double; X, Y: Integer);
var WX, WY, NewZoom: Double;
begin
  ComputeFit;
  WX := (X - FOX) / FScale;
  WY := (ClientHeight - Y - FOY) / FScale;
  NewZoom := EnsureRange(FZoom * Factor, 0.5, 40);
  if SameValue(NewZoom, FZoom) then Exit;
  FZoom := NewZoom;
  ComputeFit;
  { mantem o ponto da mesa sob o cursor no mesmo lugar }
  FPanX := FPanX + (X - WX * FScale) - FOX;
  FPanY := FPanY + (ClientHeight - Y - WY * FScale) - FOY;
  Refresh3D;
end;

procedure TSlicerView.ZoomIn;
begin
  ZoomAt(1.25, ClientWidth div 2, ClientHeight div 2);
end;

procedure TSlicerView.ZoomOut;
begin
  ZoomAt(1 / 1.25, ClientWidth div 2, ClientHeight div 2);
end;

procedure TSlicerView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragging := Button in [mbLeft, mbMiddle, mbRight];
  FLastX := X; FLastY := Y;
  if FDragging then Cursor := crSizeAll;
end;

procedure TSlicerView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  FPanX := FPanX + (X - FLastX);
  FPanY := FPanY - (Y - FLastY);
  FLastX := X; FLastY := Y;
  Refresh3D;
end;

procedure TSlicerView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
  Cursor := crDefault;
end;

function TSlicerView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then ZoomAt(1.2, MousePos.X, MousePos.Y)
  else if WheelDelta < 0 then ZoomAt(1 / 1.2, MousePos.X, MousePos.Y);
end;

function TSlicerView.SX(X: Double): Integer;
begin
  Result := Round(FOX + X * FScale);
end;

function TSlicerView.SY(Y: Double): Integer;
begin
  Result := Round(ClientHeight - FOY - Y * FScale);
end;

procedure TSlicerView.DrawBed(C: TCanvas);
var G: Integer; X, Y: Double;
begin
  C.Brush.Style := bsSolid;
  C.Brush.Color := clSuiteSurface;
  C.FillRect(0, 0, ClientWidth, ClientHeight);
  { sombra e mesa }
  C.Pen.Style := psClear;
  C.Brush.Color := SuiteMix(clSuiteNavy, clSuiteSurface, 0.06);
  C.Rectangle(SX(0) + 4, SY(FBedY) + 4, SX(FBedX) + 5, SY(0) + 5);
  C.Brush.Color := clSuiteCard;
  C.Rectangle(SX(0), SY(FBedY), SX(FBedX) + 1, SY(0) + 1);
  C.Pen.Style := psSolid;
  { grade de 10 mm, mais forte a cada 50 mm }
  G := 0; X := 0;
  while X <= FBedX + 1e-6 do
  begin
    if G mod 5 = 0 then C.Pen.Color := SuiteMix(clSuiteFaint, clSuiteCard, 0.55)
    else C.Pen.Color := clSuiteBorder;
    C.Line(SX(X), SY(0), SX(X), SY(FBedY));
    Inc(G); X := G * 10;
  end;
  G := 0; Y := 0;
  while Y <= FBedY + 1e-6 do
  begin
    if G mod 5 = 0 then C.Pen.Color := SuiteMix(clSuiteFaint, clSuiteCard, 0.55)
    else C.Pen.Color := clSuiteBorder;
    C.Line(SX(0), SY(Y), SX(FBedX), SY(Y));
    Inc(G); Y := G * 10;
  end;
  C.Brush.Style := bsClear;
  C.Pen.Color := clSuiteFaint;
  C.Rectangle(SX(0), SY(FBedY), SX(FBedX) + 1, SY(0) + 1);
  { triedro na origem }
  C.Pen.Width := 2;
  C.Pen.Color := clSuiteAxisX;
  C.Line(SX(0), SY(0), SX(0) + 34, SY(0));
  C.Pen.Color := clSuiteAxisY;
  C.Line(SX(0), SY(0), SX(0), SY(0) - 34);
  C.Pen.Width := 1;
  C.Font.Size := 8;
  C.Font.Color := clSuiteMuted;
  C.TextOut(SX(0) + 38, SY(0) - 8, 'X');
  C.TextOut(SX(0) - 4, SY(0) - 52, 'Y');
  C.TextOut(SX(FBedX) - C.TextWidth(Format('%.0f x %.0f mm', [FBedX, FBedY])),
    SY(0) + 6, Format('%.0f x %.0f mm', [FBedX, FBedY]));
end;

procedure TSlicerView.DrawMesh(C: TCanvas);
var
  I: Integer; T: TTriangle; P: array[0..2] of TPoint;
  Inside, Outside, Edge: TColor; IsOut: Boolean;
begin
  if (FMesh = nil) or (FMesh.Count = 0) then
  begin
    C.Font.Size := 10;
    C.Font.Color := clSuiteMuted;
    C.Brush.Style := bsClear;
    C.TextOut(SX(FBedX / 2) - C.TextWidth('Abra um STL ou 3MF') div 2, SY(FBedY / 2) - 8,
      'Abra um STL ou 3MF');
    Exit;
  end;
  Inside := SuiteMix(clSuitePrimary, clSuiteCard, 0.55);
  Outside := SuiteMix(clSuiteDanger, clSuiteCard, 0.60);
  Edge := SuiteMix(clSuitePrimary, clSuiteCard, 0.70);
  C.Pen.Style := psSolid;
  C.Brush.Style := bsSolid;
  for I := 0 to FMesh.Count - 1 do
  begin
    T := FMesh.Triangle(I);
    IsOut := (Min(T.A.X, Min(T.B.X, T.C.X)) < -1e-6) or (Min(T.A.Y, Min(T.B.Y, T.C.Y)) < -1e-6) or
      (Max(T.A.X, Max(T.B.X, T.C.X)) > FBedX + 1e-6) or (Max(T.A.Y, Max(T.B.Y, T.C.Y)) > FBedY + 1e-6);
    if IsOut then begin C.Brush.Color := Outside; C.Pen.Color := Outside; end
    else begin C.Brush.Color := Inside; C.Pen.Color := Edge; end;
    P[0] := Point(SX(T.A.X), SY(T.A.Y));
    P[1] := Point(SX(T.B.X), SY(T.B.Y));
    P[2] := Point(SX(T.C.X), SY(T.C.Y));
    C.Polygon(P);
  end;
end;

procedure TSlicerView.DrawLayer(C: TCanvas);
var D: TLayerData; I, J, K, Last: Integer;
begin
  if (FEngine = nil) or (FLayer < 0) or (FLayer >= Length(FEngine.Layers)) then
  begin
    C.Font.Size := 10;
    C.Font.Color := clSuiteMuted;
    C.Brush.Style := bsClear;
    C.TextOut(SX(FBedX / 2) - C.TextWidth('Fatie para ver as camadas') div 2, SY(FBedY / 2) - 8,
      'Fatie para ver as camadas');
    Exit;
  end;
  D := FEngine.Layers[FLayer];
  C.Pen.Width := Max(1, Round(0.4 * FScale));
  for I := 0 to High(D.Paths) do
  begin
    C.Pen.Color := SlicerRoleColor(D.Paths[I].Role);
    Last := High(D.Paths[I].Points);
    if not D.Paths[I].Closed then Dec(Last);
    for J := 0 to Last do
    begin
      K := (J + 1) mod Length(D.Paths[I].Points);
      C.Line(SX(D.Paths[I].Points[J].X), SY(D.Paths[I].Points[J].Y),
        SX(D.Paths[I].Points[K].X), SY(D.Paths[I].Points[K].Y));
    end;
  end;
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  C.Font.Size := 9;
  C.Font.Color := clSuiteText;
  C.TextOut(SX(0), SY(0) + 6, Format('Camada %d de %d  |  Z %.3f mm  |  altura %.3f mm',
    [FLayer + 1, Length(FEngine.Layers), D.Z, D.Height]));
end;

procedure TSlicerView.DrawLegend(C: TCanvas);
var R: TPathRole; X: Integer;
begin
  X := 14;
  C.Font.Size := 8;
  for R := Low(TPathRole) to High(TPathRole) do
  begin
    C.Pen.Style := psClear;
    C.Brush.Style := bsSolid;
    C.Brush.Color := SlicerRoleColor(R);
    C.Rectangle(X, 12, X + 12, 24);
    C.Pen.Style := psSolid;
    C.Brush.Style := bsClear;
    C.Font.Color := clSuiteMuted;
    C.TextOut(X + 16, 10, SlicerRoleName(R));
    X := X + 16 + C.TextWidth(SlicerRoleName(R)) + 16;
  end;
end;

procedure TSlicerView.Paint;
begin
  if (ClientWidth < 60) or (ClientHeight < 60) then Exit;
  ComputeFit;
  if FMode = svMesa then
  begin
    if not FCacheValid or (FCache.Width <> ClientWidth) or (FCache.Height <> ClientHeight) then
    begin
      FCache.SetSize(ClientWidth, ClientHeight);
      DrawBed(FCache.Canvas);
      DrawMesh(FCache.Canvas);
      FCacheValid := True;
    end;
    Canvas.Draw(0, 0, FCache);
  end
  else
  begin
    DrawBed(Canvas);
    DrawLayer(Canvas);
    DrawLegend(Canvas);
  end;
end;

end.
