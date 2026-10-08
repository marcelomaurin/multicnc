unit multisuite_icons;

{ Icones vetoriais de traco (stroke) da suite MultiSuite.

  Os icones sao desenhados em uma grade de 24x24 unidades, em uma mascara
  super-amostrada (4x) e reduzidos com media de cobertura. O resultado e um
  TBitmap de 32 bits com canal alfa e bordas suavizadas (anti-aliasing),
  sem depender de pacotes externos (BGRABitmap etc.) nem de arquivos de imagem.

  Estilo: quadrado arredondado com contorno e glifo interno, no mesmo padrao
  dos "editable stroke icons". }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, GraphType, IntfGraphics, FPImage;

type
  TSuiteIconKind = (
    sikSuite, sikCAD, sikPCB, sikAssembly, sikPhysics, sikCAM, sikSlicer,
    sikLaserPCB, sikLaserArt, sikCNC, sikTests, sikPower, sikChevron,
    sikClose, sikSearch, sikArrowRight,
    { controle de maquina }
    sikPlay, sikPause, sikStop, sikFolder, sikFrame, sikHome, sikFlag,
    sikTarget, sikOrigin, sikPulse, sikUnlock, sikPlug, sikArrowUp,
    sikArrowDown, sikArrowLeft, sikSave, sikTrash, sikSend, sikFile,
    sikGear, sikTerminal, sikFlame, sikSnow, sikMove, sikThermo, sikGauge,
    { edicao grafica (LaserArt) }
    sikPointer, sikPen, sikRect, sikCircle, sikPolygon, sikText, sikImage,
    sikUndo, sikRedo, sikCopy, sikMirrorH, sikMirrorV, sikImport, sikEye,
    sikWand, sikFit, sikLayers, sikExport, sikNew, sikZoomIn, sikZoomOut,
    { ferramentas novas (no fim: os ordinais aparecem em caches) }
    sikMakePCB, sikRouterPCB, sikMakeRouter
  );

  { sifNone    - apenas o glifo, ocupando toda a area
    sifOutline - quadrado arredondado com contorno + glifo reduzido
    sifFilled  - quadrado arredondado preenchido (FillColor) + glifo reduzido }
  TSuiteIconFrame = (sifNone, sifOutline, sifFilled);

function RenderSuiteIcon(AKind: TSuiteIconKind; ASize: Integer; AColor: TColor;
  AFrame: TSuiteIconFrame = sifNone; AStroke: Single = 1.75;
  AFillColor: TColor = clNone; AFillAlpha: Single = 0): TBitmap;

{ Retangulo arredondado suavizado, com fundo transparente fora das bordas. }
function RenderRoundRect(AWidth, AHeight, ARadius: Integer; AFill: TColor;
  ABorder: TColor = clNone; ABorderWidth: Integer = 1): TBitmap;

implementation

const
  ICON_SS = 4;            // super-amostragem dos icones
  RECT_SS = 3;            // super-amostragem dos retangulos (maiores)
  GLYPH_IN_FRAME = 0.56;  // escala do glifo dentro do quadrado

type
  TCoverage = array of Single;

  TMaskPainter = class
  private
    FCanvas: TCanvas;
    FScale: Double;
    function P(X, Y: Double): TPoint;
    procedure DrawPoints(const Pts: array of Double; AClosed, AFilled: Boolean);
  public
    GlyphScale: Double;
    constructor Create(ACanvas: TCanvas; AScale, AStrokePx: Double);
    procedure Line(X1, Y1, X2, Y2: Double);
    procedure Poly(const Pts: array of Double; AClosed: Boolean = False);
    procedure FillPoly(const Pts: array of Double);
    procedure Circle(CX, CY, R: Double);
    procedure Dot(CX, CY, R: Double);
    procedure Arc(CX, CY, R, A0, A1: Double);
    procedure Ellipse(CX, CY, RX, RY, AngleDeg: Double);
    procedure RoundBox(X1, Y1, X2, Y2, R: Double; AFilled: Boolean);
  end;

{ ---------------------------------------------------------------------------- }

constructor TMaskPainter.Create(ACanvas: TCanvas; AScale, AStrokePx: Double);
begin
  inherited Create;
  FCanvas := ACanvas;
  FScale := AScale;
  GlyphScale := 1.0;
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Color := clWhite;
  FCanvas.Pen.Cosmetic := False;
  FCanvas.Pen.EndCap := pecRound;
  FCanvas.Pen.JoinStyle := pjsRound;
  FCanvas.Pen.Width := Max(1, Round(AStrokePx));
  FCanvas.Brush.Color := clWhite;
  FCanvas.Brush.Style := bsClear;
end;

function TMaskPainter.P(X, Y: Double): TPoint;
begin
  X := 12 + (X - 12) * GlyphScale;
  Y := 12 + (Y - 12) * GlyphScale;
  Result := Point(Round(X * FScale), Round(Y * FScale));
end;

procedure TMaskPainter.DrawPoints(const Pts: array of Double; AClosed, AFilled: Boolean);
var
  A: array of TPoint;
  I, N: Integer;
  OldPen: TPenStyle;
begin
  N := Length(Pts) div 2;
  if N < 2 then
    Exit;
  SetLength(A, N);
  for I := 0 to N - 1 do
    A[I] := P(Pts[I * 2], Pts[I * 2 + 1]);

  if AFilled then
  begin
    OldPen := FCanvas.Pen.Style;
    FCanvas.Pen.Style := psClear;
    FCanvas.Brush.Style := bsSolid;
    FCanvas.Polygon(A);
    FCanvas.Brush.Style := bsClear;
    FCanvas.Pen.Style := OldPen;
  end
  else if AClosed then
  begin
    FCanvas.Brush.Style := bsClear;
    FCanvas.Polygon(A);
  end
  else
    FCanvas.Polyline(A);
end;

procedure TMaskPainter.Line(X1, Y1, X2, Y2: Double);
begin
  DrawPoints([X1, Y1, X2, Y2], False, False);
end;

procedure TMaskPainter.Poly(const Pts: array of Double; AClosed: Boolean);
begin
  DrawPoints(Pts, AClosed, False);
end;

procedure TMaskPainter.FillPoly(const Pts: array of Double);
begin
  DrawPoints(Pts, True, True);
end;

procedure TMaskPainter.Ellipse(CX, CY, RX, RY, AngleDeg: Double);
const
  SEG = 48;
var
  Pts: array of Double;
  I: Integer;
  T, CA, SA, X, Y: Double;
begin
  SetLength(Pts, SEG * 2);
  CA := Cos(DegToRad(AngleDeg));
  SA := Sin(DegToRad(AngleDeg));
  for I := 0 to SEG - 1 do
  begin
    T := 2 * Pi * I / SEG;
    X := RX * Cos(T);
    Y := RY * Sin(T);
    Pts[I * 2] := CX + X * CA - Y * SA;
    Pts[I * 2 + 1] := CY + X * SA + Y * CA;
  end;
  DrawPoints(Pts, True, False);
end;

procedure TMaskPainter.Circle(CX, CY, R: Double);
begin
  Ellipse(CX, CY, R, R, 0);
end;

procedure TMaskPainter.Dot(CX, CY, R: Double);
const
  SEG = 24;
var
  Pts: array of Double;
  I: Integer;
begin
  SetLength(Pts, SEG * 2);
  for I := 0 to SEG - 1 do
  begin
    Pts[I * 2] := CX + R * Cos(2 * Pi * I / SEG);
    Pts[I * 2 + 1] := CY + R * Sin(2 * Pi * I / SEG);
  end;
  DrawPoints(Pts, True, True);
end;

procedure TMaskPainter.Arc(CX, CY, R, A0, A1: Double);
var
  Pts: array of Double;
  I, N: Integer;
  A: Double;
begin
  N := Max(4, Round(Abs(A1 - A0) / 6));
  SetLength(Pts, (N + 1) * 2);
  for I := 0 to N do
  begin
    A := DegToRad(A0 + (A1 - A0) * I / N);
    Pts[I * 2] := CX + R * Cos(A);
    Pts[I * 2 + 1] := CY + R * Sin(A);
  end;
  DrawPoints(Pts, False, False);
end;

procedure TMaskPainter.RoundBox(X1, Y1, X2, Y2, R: Double; AFilled: Boolean);
const
  SEG = 10;
var
  Pts: array of Double;
  K: Integer;
  A: Double;

  procedure Corner(ACX, ACY, AStart: Double);
  var
    J: Integer;
  begin
    for J := 0 to SEG do
    begin
      A := DegToRad(AStart + 90 * J / SEG);
      Pts[K] := ACX + R * Cos(A);
      Pts[K + 1] := ACY + R * Sin(A);
      Inc(K, 2);
    end;
  end;

begin
  SetLength(Pts, 4 * (SEG + 1) * 2);
  K := 0;
  Corner(X2 - R, Y1 + R, 270);
  Corner(X2 - R, Y2 - R, 0);
  Corner(X1 + R, Y2 - R, 90);
  Corner(X1 + R, Y1 + R, 180);
  DrawPoints(Pts, True, AFilled);
end;

{ ---------------------------------------------------------------------------- }

function NewMask(W, H: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(W, H);
  Result.Canvas.Brush.Style := bsSolid;
  Result.Canvas.Brush.Color := clBlack;
  Result.Canvas.FillRect(0, 0, W, H);
end;

function Coverage(AMask: TBitmap; W, H, SS: Integer): TCoverage;
var
  Img: TLazIntfImage;
  X, Y, I, J: Integer;
  Sum: Cardinal;
begin
  SetLength(Result, W * H);
  Img := AMask.CreateIntfImage;
  try
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        Sum := 0;
        for J := 0 to SS - 1 do
          for I := 0 to SS - 1 do
            Inc(Sum, Img.Colors[X * SS + I, Y * SS + J].Red);
        Result[Y * W + X] := Sum / (SS * SS * 65535);
      end;
  finally
    Img.Free;
  end;
end;

{ Compoe a camada Top (cor + cobertura) sobre a camada Bottom
  (cor + cobertura * AlphaBottom) gerando um bitmap com alfa. }
function Compose(W, H: Integer; const CovTop: TCoverage; ColTop: TColor;
  const CovBottom: TCoverage; ColBottom: TColor; AlphaBottom: Single): TBitmap;
var
  Img: TLazIntfImage;
  X, Y, Idx: Integer;
  RT, GT, BT, RB, GB, BB: Integer;
  AT, AB, A, R, G, B: Double;
  C: TColor;
  Px: TFPColor;
begin
  C := ColorToRGB(ColTop);
  RT := Red(C); GT := Green(C); BT := Blue(C);
  if ColBottom = clNone then
    C := ColorToRGB(ColTop)
  else
    C := ColorToRGB(ColBottom);
  RB := Red(C); GB := Green(C); BB := Blue(C);

  Img := TLazIntfImage.Create(0, 0, [riqfRGB, riqfAlpha]);
  try
    Img.SetSize(W, H);
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        Idx := Y * W + X;
        AT := 0;
        AB := 0;
        if Length(CovTop) > 0 then
          AT := CovTop[Idx];
        if Length(CovBottom) > 0 then
          AB := CovBottom[Idx] * AlphaBottom;
        A := AT + AB * (1 - AT);
        if A <= 0.0005 then
        begin
          Px.Red := 0; Px.Green := 0; Px.Blue := 0; Px.Alpha := 0;
        end
        else
        begin
          R := (RT * AT + RB * AB * (1 - AT)) / A;
          G := (GT * AT + GB * AB * (1 - AT)) / A;
          B := (BT * AT + BB * AB * (1 - AT)) / A;
          Px.Red := Round(EnsureRange(R, 0, 255)) * 257;
          Px.Green := Round(EnsureRange(G, 0, 255)) * 257;
          Px.Blue := Round(EnsureRange(B, 0, 255)) * 257;
          Px.Alpha := Round(EnsureRange(A, 0, 1) * 65535);
        end;
        Img.Colors[X, Y] := Px;
      end;
    Result := TBitmap.Create;
    Result.LoadFromIntfImage(Img);
  finally
    Img.Free;
  end;
end;

{ ---------------------------------------------------------------------------- }

procedure DrawGlyph(Pn: TMaskPainter; AKind: TSuiteIconKind);
var
  T: Integer;
  B: Double;
  Pts: array of Double;
begin
  case AKind of
    sikSuite:
      begin
        Pn.Dot(6, 6, 2); Pn.Dot(12, 6, 2); Pn.Dot(18, 6, 2);
        Pn.Dot(6, 12, 2); Pn.Dot(12, 12, 2); Pn.Dot(18, 12, 2);
        Pn.Dot(6, 18, 2); Pn.Dot(12, 18, 2); Pn.Dot(18, 18, 2);
      end;

    sikCAD:
      begin
        Pn.Poly([12, 2.5, 20.5, 7.25, 20.5, 16.75, 12, 21.5, 3.5, 16.75, 3.5, 7.25], True);
        Pn.Poly([3.5, 7.25, 12, 12, 20.5, 7.25]);
        Pn.Line(12, 12, 12, 21.5);
      end;

    sikPCB:
      begin
        Pn.RoundBox(6, 6, 18, 18, 2, False);
        Pn.RoundBox(9.5, 9.5, 14.5, 14.5, 1, False);
        Pn.Line(9, 2.5, 9, 6);   Pn.Line(15, 2.5, 15, 6);
        Pn.Line(9, 18, 9, 21.5); Pn.Line(15, 18, 15, 21.5);
        Pn.Line(2.5, 9, 6, 9);   Pn.Line(2.5, 15, 6, 15);
        Pn.Line(18, 9, 21.5, 9); Pn.Line(18, 15, 21.5, 15);
      end;

    sikAssembly:
      begin
        SetLength(Pts, 8 * 4 * 2);
        for T := 0 to 7 do
        begin
          B := T * 45;
          Pts[T * 8 + 0] := 12 + 7.2 * Cos(DegToRad(B - 15));
          Pts[T * 8 + 1] := 12 + 7.2 * Sin(DegToRad(B - 15));
          Pts[T * 8 + 2] := 12 + 9.8 * Cos(DegToRad(B - 8));
          Pts[T * 8 + 3] := 12 + 9.8 * Sin(DegToRad(B - 8));
          Pts[T * 8 + 4] := 12 + 9.8 * Cos(DegToRad(B + 8));
          Pts[T * 8 + 5] := 12 + 9.8 * Sin(DegToRad(B + 8));
          Pts[T * 8 + 6] := 12 + 7.2 * Cos(DegToRad(B + 15));
          Pts[T * 8 + 7] := 12 + 7.2 * Sin(DegToRad(B + 15));
        end;
        Pn.Poly(Pts, True);
        Pn.Circle(12, 12, 3);
      end;

    sikPhysics:
      begin
        Pn.Dot(12, 12, 1.8);
        Pn.Ellipse(12, 12, 10, 4, 0);
        Pn.Ellipse(12, 12, 10, 4, 60);
        Pn.Ellipse(12, 12, 10, 4, 120);
      end;

    sikCAM:
      begin
        Pn.Poly([9.5, 2.5, 14.5, 2.5, 14.5, 8, 9.5, 8], True);
        Pn.Poly([7.5, 8, 16.5, 8, 16.5, 16.5, 12, 21.5, 7.5, 16.5], True);
        Pn.Line(7.5, 12.5, 16.5, 10);
        Pn.Line(7.5, 16.5, 16.5, 14);
      end;

    sikSlicer:
      begin
        Pn.Poly([12, 2.5, 21.5, 7.5, 12, 12.5, 2.5, 7.5], True);
        Pn.Poly([2.5, 12, 12, 17, 21.5, 12]);
        Pn.Poly([2.5, 16.5, 12, 21.5, 21.5, 16.5]);
      end;

    sikLaserPCB:
      begin
        Pn.RoundBox(7.5, 2.5, 16.5, 8.5, 1.5, False);
        Pn.Line(12, 8.5, 12, 15.5);
        Pn.Dot(12, 18, 1.6);
        Pn.Line(8.8, 16.6, 6.6, 15.4);
        Pn.Line(15.2, 16.6, 17.4, 15.4);
        Pn.Line(2.5, 21.5, 21.5, 21.5);
      end;

    sikLaserArt:
      begin
        Pn.RoundBox(2.5, 3.5, 21.5, 20.5, 3, False);
        Pn.Circle(8.5, 9, 1.8);
        Pn.Poly([2.5, 17.5, 9, 11.5, 13.5, 16, 16.5, 13, 21.5, 18]);
      end;

    sikCNC:
      begin
        Pn.Line(2.5, 21.5, 21.5, 21.5);
        Pn.Line(5, 21.5, 5, 4.5);
        Pn.Line(19, 21.5, 19, 4.5);
        Pn.Line(3.5, 4.5, 20.5, 4.5);
        Pn.RoundBox(9.5, 3, 14.5, 9, 1, False);
        Pn.Line(12, 9, 12, 13);
        Pn.Poly([10.5, 13, 12, 15.5, 13.5, 13], True);
        Pn.Poly([8, 21.5, 8, 18.5, 16, 18.5, 16, 21.5]);
      end;

    sikTests:
      begin
        Pn.Circle(12, 12, 9.5);
        Pn.Poly([7.8, 12.3, 10.8, 15.3, 16.5, 9.3]);
      end;

    sikPower:
      begin
        Pn.Arc(12, 13, 8.5, -55, 235);
        Pn.Line(12, 2.5, 12, 11);
      end;

    sikChevron:
      Pn.Poly([9, 5.5, 15.5, 12, 9, 18.5]);

    sikClose:
      begin
        Pn.Line(6, 6, 18, 18);
        Pn.Line(18, 6, 6, 18);
      end;

    sikSearch:
      begin
        Pn.Circle(10.5, 10.5, 6.5);
        Pn.Line(15.5, 15.5, 20.5, 20.5);
      end;

    sikArrowRight:
      begin
        Pn.Line(4.5, 12, 19, 12);
        Pn.Poly([13, 6, 19, 12, 13, 18]);
      end;

    sikArrowLeft:
      begin
        Pn.Line(19.5, 12, 5, 12);
        Pn.Poly([11, 6, 5, 12, 11, 18]);
      end;

    sikArrowUp:
      begin
        Pn.Line(12, 19.5, 12, 5);
        Pn.Poly([6, 11, 12, 5, 18, 11]);
      end;

    sikArrowDown:
      begin
        Pn.Line(12, 4.5, 12, 19);
        Pn.Poly([6, 13, 12, 19, 18, 13]);
      end;

    sikPlay:
      Pn.Poly([7.5, 4.5, 19.5, 12, 7.5, 19.5], True);

    sikPause:
      begin
        Pn.RoundBox(6.5, 4.5, 10, 19.5, 1, False);
        Pn.RoundBox(14, 4.5, 17.5, 19.5, 1, False);
      end;

    sikStop:
      begin
        SetLength(Pts, 16);
        for T := 0 to 7 do
        begin
          B := DegToRad(22.5 + T * 45);
          Pts[T * 2] := 12 + 10 * Cos(B);
          Pts[T * 2 + 1] := 12 + 10 * Sin(B);
        end;
        Pn.Poly(Pts, True);
        Pn.Line(12, 7, 12, 13);
        Pn.Dot(12, 16.8, 1.3);
      end;

    sikFolder:
      Pn.Poly([2.5, 5.5, 9.5, 5.5, 11.5, 8.5, 21.5, 8.5, 21.5, 19.5, 2.5, 19.5], True);

    sikFrame:
      begin
        Pn.Poly([3, 8, 3, 3, 8, 3]);
        Pn.Poly([16, 3, 21, 3, 21, 8]);
        Pn.Poly([21, 16, 21, 21, 16, 21]);
        Pn.Poly([8, 21, 3, 21, 3, 16]);
        Pn.Dot(12, 12, 1.6);
      end;

    sikHome:
      begin
        Pn.Poly([2.5, 11.5, 12, 3, 21.5, 11.5]);
        Pn.Poly([5.5, 9, 5.5, 21, 18.5, 21, 18.5, 9]);
        Pn.Poly([10, 21, 10, 15, 14, 15, 14, 21]);
      end;

    sikFlag:
      begin
        Pn.Line(5, 21.5, 5, 3);
        Pn.Poly([5, 4, 19, 4, 15.5, 8.5, 19, 13, 5, 13]);
      end;

    sikTarget:
      begin
        Pn.Circle(12, 12, 7.5);
        Pn.Line(12, 2, 12, 6.5);   Pn.Line(12, 17.5, 12, 22);
        Pn.Line(2, 12, 6.5, 12);   Pn.Line(17.5, 12, 22, 12);
        Pn.Dot(12, 12, 1.8);
      end;

    sikOrigin:
      begin
        Pn.Poly([5, 3, 5, 19, 21, 19]);
        Pn.Poly([2.5, 6, 5, 3, 7.5, 6]);
        Pn.Poly([18, 16.5, 21, 19, 18, 21.5]);
        Pn.Dot(5, 19, 2.3);
      end;

    sikPulse:
      Pn.Poly([2.5, 12, 7, 12, 9.5, 5.5, 14.5, 18.5, 17, 12, 21.5, 12]);

    sikUnlock:
      begin
        Pn.RoundBox(4.5, 11, 19.5, 21.5, 2.5, False);
        Pn.Arc(12, 7.5, 4, 180, 340);
        Pn.Line(8, 7.5, 8, 11);
        Pn.Dot(12, 16, 1.5);
      end;

    sikPlug:
      begin
        Pn.Line(9, 2.5, 9, 7);
        Pn.Line(15, 2.5, 15, 7);
        Pn.Poly([6, 7, 18, 7, 18, 11, 14.5, 16, 9.5, 16, 6, 11], True);
        Pn.Line(12, 16, 12, 21.5);
      end;

    sikSave:
      begin
        Pn.Poly([3, 3, 17, 3, 21, 7, 21, 21, 3, 21], True);
        Pn.Poly([7.5, 3, 7.5, 8, 15, 8, 15, 3]);
        Pn.Poly([7, 21, 7, 14, 17, 14, 17, 21]);
      end;

    sikTrash:
      begin
        Pn.Line(3.5, 6.5, 20.5, 6.5);
        Pn.Poly([9, 6.5, 9, 3.5, 15, 3.5, 15, 6.5]);
        Pn.Poly([5.5, 6.5, 6.5, 21, 17.5, 21, 18.5, 6.5]);
        Pn.Line(10, 10.5, 10, 17);
        Pn.Line(14, 10.5, 14, 17);
      end;

    sikSend:
      begin
        Pn.Poly([21.5, 2.5, 2.5, 10, 10.5, 13.5, 14, 21.5], True);
        Pn.Line(21.5, 2.5, 10.5, 13.5);
      end;

    sikFile:
      begin
        Pn.Poly([5, 2.5, 14.5, 2.5, 19.5, 7.5, 19.5, 21.5, 5, 21.5], True);
        Pn.Poly([14.5, 2.5, 14.5, 7.5, 19.5, 7.5]);
        Pn.Line(8.5, 12, 16, 12);
        Pn.Line(8.5, 16, 16, 16);
      end;

    sikGear:
      DrawGlyph(Pn, sikAssembly);

    sikTerminal:
      begin
        Pn.RoundBox(2.5, 3.5, 21.5, 20.5, 2.5, False);
        Pn.Poly([6.5, 9, 10, 12, 6.5, 15]);
        Pn.Line(12.5, 15.5, 17.5, 15.5);
      end;

    sikFlame:
      Pn.Poly([12, 2.5, 16.5, 8, 18.5, 13, 17.5, 18, 12, 21.5, 6.5, 18,
        5.5, 13, 8, 9, 10, 12, 10.5, 7], True);

    sikSnow:
      begin
        Pn.Line(12, 2.5, 12, 21.5);
        Pn.Line(3.8, 7.25, 20.2, 16.75);
        Pn.Line(3.8, 16.75, 20.2, 7.25);
        Pn.Poly([9.5, 4, 12, 6, 14.5, 4]);
        Pn.Poly([9.5, 20, 12, 18, 14.5, 20]);
      end;

    sikMove:
      begin
        Pn.Line(12, 2.5, 12, 21.5);
        Pn.Line(2.5, 12, 21.5, 12);
        Pn.Poly([9, 5.5, 12, 2.5, 15, 5.5]);
        Pn.Poly([9, 18.5, 12, 21.5, 15, 18.5]);
        Pn.Poly([5.5, 9, 2.5, 12, 5.5, 15]);
        Pn.Poly([18.5, 9, 21.5, 12, 18.5, 15]);
      end;

    sikThermo:
      begin
        Pn.Poly([9.5, 14, 9.5, 5, 14.5, 5, 14.5, 14]);
        Pn.Arc(12, 5, 2.5, 180, 360);
        Pn.Arc(12, 17.5, 4, -50, 230);
        Pn.Line(12, 9, 12, 17.5);
      end;

    sikGauge:
      begin
        Pn.Arc(12, 15, 9, 180, 360);
        Pn.Line(3, 15, 21, 15);
        Pn.Line(12, 15, 16.5, 8.5);
        Pn.Dot(12, 15, 1.6);
      end;

    sikPointer:
      Pn.Poly([5, 3, 5, 19, 9.5, 14.5, 12.5, 21, 15.5, 19.5, 12.5, 13.5, 18.5, 13.5], True);

    sikMakePCB:
      begin
        { placa com trilhas e pads + lapis: desenhar a placa }
        Pn.RoundBox(2.5, 5.5, 17, 20.5, 2, False);
        Pn.Dot(6.5, 9.5, 1.5);
        Pn.Line(6.5, 9.5, 10, 9.5);
        Pn.Line(10, 9.5, 13, 12.5);
        Pn.Line(13, 12.5, 13, 16.5);
        Pn.Dot(13, 16.5, 1.5);
        Pn.Dot(6.5, 16.5, 1.5);
        Pn.Line(6.5, 16.5, 9.5, 16.5);
        Pn.Poly([18.5, 2.5, 21.5, 5.5, 14.5, 12.5, 11, 13.5, 12, 10], True);
      end;

    sikRouterPCB:
      begin
        { fresa descendo sobre a placa e o sulco da isolacao }
        Pn.RoundBox(2.5, 14.5, 21.5, 21, 1.5, False);
        Pn.Line(5, 17.75, 9.5, 17.75);
        Pn.Line(14.5, 17.75, 19, 17.75);
        Pn.Dot(5, 17.75, 1.2);
        Pn.Dot(19, 17.75, 1.2);
        Pn.RoundBox(9, 1.5, 15, 6.5, 1, False);
        Pn.Poly([9.5, 6.5, 14.5, 6.5, 14.5, 9.5, 12, 13, 9.5, 9.5], True);
        Pn.Line(10, 8, 14, 9.5);
      end;

    sikMakeRouter:
      begin
        { peca de madeira com bolsao curvo e a fresa reta acima }
        Pn.RoundBox(2.5, 12.5, 21.5, 21, 1.5, False);
        Pn.Poly([6, 16, 9, 18.5, 15, 18.5, 18, 16], False);
        Pn.Line(5, 14.5, 7, 14.5);
        Pn.Line(17, 14.5, 19, 14.5);
        Pn.RoundBox(9.5, 1.5, 14.5, 5.5, 1, False);
        Pn.Line(10.5, 5.5, 10.5, 10.5);
        Pn.Line(13.5, 5.5, 13.5, 10.5);
        Pn.Line(10.5, 10.5, 13.5, 10.5);
        Pn.Line(10.5, 7, 13.5, 9);
      end;

    sikPen:
      begin
        Pn.Poly([16, 3.5, 20.5, 8, 9, 19.5, 3.5, 20.5, 4.5, 15], True);
        Pn.Line(13.5, 6, 18, 10.5);
      end;

    sikRect:
      Pn.RoundBox(3.5, 5.5, 20.5, 18.5, 1.5, False);

    sikCircle:
      Pn.Circle(12, 12, 8.5);

    sikPolygon:
      begin
        SetLength(Pts, 12);
        for T := 0 to 5 do
        begin
          B := DegToRad(-90 + T * 60);
          Pts[T * 2] := 12 + 9 * Cos(B);
          Pts[T * 2 + 1] := 12.5 + 9 * Sin(B);
        end;
        Pn.Poly(Pts, True);
      end;

    sikText:
      begin
        Pn.Poly([5, 20, 12, 3.5, 19, 20]);
        Pn.Line(7.8, 14, 16.2, 14);
      end;

    sikImage:
      begin
        Pn.RoundBox(2.5, 4, 21.5, 20, 2.5, False);
        Pn.Circle(8, 9, 1.8);
        Pn.Poly([2.5, 17, 8.5, 12, 12.5, 15.5, 15.5, 12.5, 21.5, 17.5]);
      end;

    sikUndo:
      begin
        Pn.Arc(13, 13.5, 6.5, -90, 120);
        Pn.Line(13, 7, 5, 7);
        Pn.Poly([8.5, 3.5, 5, 7, 8.5, 10.5]);
      end;

    sikRedo:
      begin
        Pn.Arc(11, 13.5, 6.5, 60, 270);
        Pn.Line(11, 7, 19, 7);
        Pn.Poly([15.5, 3.5, 19, 7, 15.5, 10.5]);
      end;

    sikCopy:
      begin
        Pn.RoundBox(8, 8, 20.5, 20.5, 2, False);
        Pn.Poly([16, 8, 16, 3.5, 3.5, 3.5, 3.5, 16, 8, 16]);
      end;

    sikMirrorH:
      begin
        Pn.Line(12, 2.5, 12, 21.5);
        Pn.Poly([9, 6, 3, 12, 9, 18], True);
        Pn.Poly([15, 6, 21, 12, 15, 18], True);
      end;

    sikMirrorV:
      begin
        Pn.Line(2.5, 12, 21.5, 12);
        Pn.Poly([6, 9, 12, 3, 18, 9], True);
        Pn.Poly([6, 15, 12, 21, 18, 15], True);
      end;

    sikImport:
      begin
        Pn.Line(12, 3, 12, 15);
        Pn.Poly([7, 10, 12, 15, 17, 10]);
        Pn.Poly([3.5, 15, 3.5, 20.5, 20.5, 20.5, 20.5, 15]);
      end;

    sikExport:
      begin
        Pn.Line(12, 15, 12, 3);
        Pn.Poly([7, 8, 12, 3, 17, 8]);
        Pn.Poly([3.5, 15, 3.5, 20.5, 20.5, 20.5, 20.5, 15]);
      end;

    sikEye:
      begin
        Pn.Poly([2, 12, 6, 7, 12, 5, 18, 7, 22, 12, 18, 17, 12, 19, 6, 17], True);
        Pn.Circle(12, 12, 3.2);
      end;

    sikWand:
      begin
        Pn.Line(4, 20, 15, 9);
        Pn.Line(17, 3, 17, 7);  Pn.Line(15, 5, 19, 5);
        Pn.Line(20.5, 9.5, 20.5, 12.5); Pn.Line(19, 11, 22, 11);
        Pn.Line(9, 4, 9, 7); Pn.Line(7.5, 5.5, 10.5, 5.5);
      end;

    sikFit:
      begin
        Pn.Poly([3, 8.5, 3, 3, 8.5, 3]);
        Pn.Poly([15.5, 3, 21, 3, 21, 8.5]);
        Pn.Poly([21, 15.5, 21, 21, 15.5, 21]);
        Pn.Poly([8.5, 21, 3, 21, 3, 15.5]);
        Pn.RoundBox(8, 8, 16, 16, 1, False);
      end;

    sikLayers:
      DrawGlyph(Pn, sikSlicer);

    sikNew:
      begin
        Pn.Poly([5, 2.5, 14.5, 2.5, 19.5, 7.5, 19.5, 21.5, 5, 21.5], True);
        Pn.Line(12, 10.5, 12, 17.5);
        Pn.Line(8.5, 14, 15.5, 14);
      end;

    sikZoomIn:
      begin
        Pn.Circle(10.5, 10.5, 6.5);
        Pn.Line(15.5, 15.5, 20.5, 20.5);
        Pn.Line(10.5, 7.5, 10.5, 13.5);
        Pn.Line(7.5, 10.5, 13.5, 10.5);
      end;

    sikZoomOut:
      begin
        Pn.Circle(10.5, 10.5, 6.5);
        Pn.Line(15.5, 15.5, 20.5, 20.5);
        Pn.Line(7.5, 10.5, 13.5, 10.5);
      end;
  end;
end;

function RenderSuiteIcon(AKind: TSuiteIconKind; ASize: Integer; AColor: TColor;
  AFrame: TSuiteIconFrame; AStroke: Single; AFillColor: TColor;
  AFillAlpha: Single): TBitmap;
var
  StrokeMask, FillMask: TBitmap;
  Pn: TMaskPainter;
  Scale: Double;
  CovStroke, CovFill: TCoverage;
  Big: Integer;
begin
  if ASize < 4 then
    ASize := 4;
  Big := ASize * ICON_SS;
  Scale := Big / 24;

  StrokeMask := NewMask(Big, Big);
  FillMask := nil;
  try
    Pn := TMaskPainter.Create(StrokeMask.Canvas, Scale, AStroke * Scale);
    try
      if AFrame = sifOutline then
        Pn.RoundBox(2, 2, 22, 22, 6, False);
      if AFrame <> sifNone then
        Pn.GlyphScale := GLYPH_IN_FRAME;
      DrawGlyph(Pn, AKind);
    finally
      Pn.Free;
    end;
    CovStroke := Coverage(StrokeMask, ASize, ASize, ICON_SS);

    SetLength(CovFill, 0);
    if (AFrame <> sifNone) and (AFillAlpha > 0) then
    begin
      FillMask := NewMask(Big, Big);
      Pn := TMaskPainter.Create(FillMask.Canvas, Scale, AStroke * Scale);
      try
        if AFrame = sifFilled then
          Pn.RoundBox(1, 1, 23, 23, 6.5, True)
        else
          Pn.RoundBox(2, 2, 22, 22, 6, True);
      finally
        Pn.Free;
      end;
      CovFill := Coverage(FillMask, ASize, ASize, ICON_SS);
    end;

    if AFillColor = clNone then
      AFillColor := AColor;
    Result := Compose(ASize, ASize, CovStroke, AColor, CovFill, AFillColor, AFillAlpha);
  finally
    StrokeMask.Free;
    FillMask.Free;
  end;
end;

function RenderRoundRect(AWidth, AHeight, ARadius: Integer; AFill: TColor;
  ABorder: TColor; ABorderWidth: Integer): TBitmap;
var
  Outer, Inner: TBitmap;
  Pn: TMaskPainter;
  CovOuter, CovInner: TCoverage;
  BW: Double;
begin
  AWidth := Max(AWidth, 2);
  AHeight := Max(AHeight, 2);
  Outer := NewMask(AWidth * RECT_SS, AHeight * RECT_SS);
  Inner := nil;
  try
    Pn := TMaskPainter.Create(Outer.Canvas, RECT_SS, 1);
    try
      Pn.RoundBox(0, 0, AWidth, AHeight, ARadius, True);
    finally
      Pn.Free;
    end;
    CovOuter := Coverage(Outer, AWidth, AHeight, RECT_SS);

    if (ABorder = clNone) or (ABorderWidth <= 0) then
      Result := Compose(AWidth, AHeight, CovOuter, AFill, nil, clNone, 0)
    else
    begin
      BW := ABorderWidth;
      Inner := NewMask(AWidth * RECT_SS, AHeight * RECT_SS);
      Pn := TMaskPainter.Create(Inner.Canvas, RECT_SS, 1);
      try
        Pn.RoundBox(BW, BW, AWidth - BW, AHeight - BW, Max(0, ARadius - BW), True);
      finally
        Pn.Free;
      end;
      CovInner := Coverage(Inner, AWidth, AHeight, RECT_SS);
      Result := Compose(AWidth, AHeight, CovInner, AFill, CovOuter, ABorder, 1);
    end;
  finally
    Outer.Free;
    Inner.Free;
  end;
end;

end.
