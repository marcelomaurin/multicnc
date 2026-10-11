unit multicad_camera;

{ MultiCAD - camera da vista 3D (ARCHITECTURE 6.1 a 6.3). Sem LCL.

  Y para cima, como no SolidWorks. A camera olha para Target a partir de
  Target + Back * Distance; Right e Up formam a tela.
  Vistas padrao (Ctrl+1..7):
    Frontal   de +Z, cima +Y      Posterior de -Z, cima +Y
    Esquerda  de -X, cima +Y      Direita   de +X, cima +Y
    Superior  de +Y, cima -Z      Inferior  de -Y, cima +Z
    Isometrica de (+1,+1,+1), cima = projecao de +Y
  Ctrl+8 "Normal a": olha de frente para um plano (x do plano a direita,
  y para cima); repetido, vira para o outro lado. }

{$mode objfpc}{$H+}

interface

uses
  Math, multicad_types;

type
  TCadStdView = (svFront, svBack, svLeft, svRight, svTop, svBottom, svIso);

  TCadScreenPt = record
    X, Y: Double;     { pixels }
    Depth: Double;    { distancia ao longo da direcao de visao (maior = mais longe) }
  end;

  TCadCamera = class
  private
    FWidth, FHeight: Integer;
  public
    Target: TCadVec3;
    Right, Up, Back: TCadVec3;   { ortonormais; Back aponta para o observador }
    Distance: Double;            { mm do alvo ate a camera }
    Scale: Double;               { pixels por mm no alvo (ortografica) }
    Perspective: Boolean;
    FovDeg: Double;
    constructor Create;
    procedure SetViewport(AW, AH: Integer);
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    procedure SetOrientation(const ABack, AUp: TCadVec3);
    procedure StdView(V: TCadStdView);
    { Normal a um referencial (plano do esboco ou face). Flip = do outro lado. }
    procedure NormalTo(const F: TCadFrame; Flip: Boolean);
    { Orbita: arrastar DX, DY pixels (botao do meio) em torno do alvo. }
    procedure Orbit(DX, DY: Double);
    { Orbita em torno de um ponto (centro da peca ou entidade clicada com o
      botao do meio, como no SolidWorks): o ponto fica parado na tela. }
    procedure OrbitAbout(DX, DY: Double; const Pivot: TCadVec3);
    { Rolar: gira em torno do eixo da tela (Alt + botao do meio). }
    procedure Roll(DX: Double);
    { Ponto 3D do pixel com a profundidade do z-buffer. }
    function Unproject(PX, PY, Depth: Double): TCadVec3;
    { Desloca a vista (Ctrl + botao do meio). }
    procedure Pan(DX, DY: Double);
    { Zoom mantendo o ponto sob o cursor parado. Factor > 1 aproxima. }
    procedure ZoomAt(Factor, PX, PY: Double);
    { Enquadra a caixa (tecla F). }
    procedure Fit(const B: TCadBox3);
    function Project(const P: TCadVec3): TCadScreenPt;
    { Raio do pixel: origem e direcao (unitaria) no mundo. }
    procedure ScreenRay(PX, PY: Double; out O, D: TCadVec3);
    function Eye: TCadVec3;
    { Direcao de visao (do observador para a cena). }
    function ViewDir: TCadVec3;
    procedure Assign(Src: TCadCamera);
  end;

const
  CAD_STD_VIEW_NAMES: array[TCadStdView] of string = ('Frontal', 'Posterior',
    'Esquerda', 'Direita', 'Superior', 'Inferior', 'Isométrica');

implementation

constructor TCadCamera.Create;
begin
  inherited Create;
  FWidth := 800;
  FHeight := 600;
  Target := V3(0, 0, 0);
  Distance := 500;
  Scale := 4;
  FovDeg := 30;
  StdView(svIso);
end;

procedure TCadCamera.SetViewport(AW, AH: Integer);
begin
  FWidth := Max(1, AW);
  FHeight := Max(1, AH);
end;

procedure TCadCamera.Assign(Src: TCadCamera);
begin
  FWidth := Src.FWidth;
  FHeight := Src.FHeight;
  Target := Src.Target;
  Right := Src.Right;
  Up := Src.Up;
  Back := Src.Back;
  Distance := Src.Distance;
  Scale := Src.Scale;
  Perspective := Src.Perspective;
  FovDeg := Src.FovDeg;
end;

procedure TCadCamera.SetOrientation(const ABack, AUp: TCadVec3);
var
  B, U: TCadVec3;
begin
  B := VNorm(ABack);
  U := VSub(AUp, VScale(B, VDot(AUp, B)));
  if VLen(U) < 1E-9 then
  begin
    { cima paralelo a direcao: escolhe outro }
    U := VSub(V3(0, 0, -1), VScale(B, VDot(V3(0, 0, -1), B)));
    if VLen(U) < 1E-9 then
      U := VSub(V3(1, 0, 0), VScale(B, VDot(V3(1, 0, 0), B)));
  end;
  Up := VNorm(U);
  Back := B;
  Right := VCross(Up, Back);
end;

procedure TCadCamera.StdView(V: TCadStdView);
begin
  case V of
    svFront: SetOrientation(V3(0, 0, 1), V3(0, 1, 0));
    svBack: SetOrientation(V3(0, 0, -1), V3(0, 1, 0));
    svLeft: SetOrientation(V3(-1, 0, 0), V3(0, 1, 0));
    svRight: SetOrientation(V3(1, 0, 0), V3(0, 1, 0));
    svTop: SetOrientation(V3(0, 1, 0), V3(0, 0, -1));
    svBottom: SetOrientation(V3(0, -1, 0), V3(0, 0, 1));
    svIso: SetOrientation(V3(1, 1, 1), V3(0, 1, 0));
  end;
end;

procedure TCadCamera.NormalTo(const F: TCadFrame; Flip: Boolean);
begin
  if Flip then
    SetOrientation(VNeg(F.Normal), F.YDir)
  else
    SetOrientation(F.Normal, F.YDir);
end;

procedure TCadCamera.Orbit(DX, DY: Double);
var
  M: TCadMat4;
begin
  { horizontal: em torno do Y do mundo (como o SolidWorks); vertical: em
    torno do Right da tela }
  M := MatMul(MatRotate(V3(0, 1, 0), -DX * 0.4), MatRotate(Right, -DY * 0.4));
  Back := VNorm(MatDir(M, Back));
  Up := VNorm(MatDir(M, Up));
  Right := VNorm(VCross(Up, Back));
  Up := VCross(Back, Right);
end;

procedure TCadCamera.OrbitAbout(DX, DY: Double; const Pivot: TCadVec3);
var
  M: TCadMat4;
begin
  M := MatMul(MatRotate(V3(0, 1, 0), -DX * 0.4), MatRotate(Right, -DY * 0.4));
  Target := VAdd(Pivot, MatDir(M, VSub(Target, Pivot)));
  Back := VNorm(MatDir(M, Back));
  Up := VNorm(MatDir(M, Up));
  Right := VNorm(VCross(Up, Back));
  Up := VCross(Back, Right);
end;

procedure TCadCamera.Roll(DX: Double);
var
  M: TCadMat4;
begin
  M := MatRotate(Back, -DX * 0.4);
  Up := VNorm(MatDir(M, Up));
  Right := VNorm(VCross(Up, Back));
  Up := VCross(Back, Right);
end;

function TCadCamera.Unproject(PX, PY, Depth: Double): TCadVec3;
var
  O, D: TCadVec3;
  Den, T: Double;
begin
  ScreenRay(PX, PY, O, D);
  Den := VDot(D, Back);
  if Abs(Den) < 1E-12 then
    Exit(O);
  { profundidade = Distance - (P - Target).Back }
  T := (Distance - Depth - VDot(VSub(O, Target), Back)) / Den;
  Result := VAdd(O, VScale(D, T));
end;

procedure TCadCamera.Pan(DX, DY: Double);
begin
  Target := VSub(Target, VScale(Right, DX / Scale));
  Target := VAdd(Target, VScale(Up, DY / Scale));
end;

procedure TCadCamera.ZoomAt(Factor, PX, PY: Double);
var
  OffX, OffY: Double;
  Before, After: TCadVec3;
begin
  if Factor <= 0 then
    Exit;
  { ponto do plano do alvo sob o cursor fica parado }
  OffX := (PX - FWidth / 2) / Scale;
  OffY := -(PY - FHeight / 2) / Scale;
  Before := VAdd(Target, VAdd(VScale(Right, OffX), VScale(Up, OffY)));
  Scale := EnsureRange(Scale * Factor, 1E-4, 1E6);
  After := VAdd(Target, VAdd(VScale(Right, (PX - FWidth / 2) / Scale),
    VScale(Up, -(PY - FHeight / 2) / Scale)));
  Target := VAdd(Target, VSub(Before, After));
end;

procedure TCadCamera.Fit(const B: TCadBox3);
var
  C, S: TCadVec3;
  I: Integer;
  P: TCadVec3;
  MinX, MaxX, MinY, MaxY, X, Y, Sx, Sy: Double;
begin
  if B.Empty then
  begin
    Target := V3(0, 0, 0);
    Scale := Min(FWidth, FHeight) / 200;
    Exit;
  end;
  C := VScale(VAdd(B.Min, B.Max), 0.5);
  Target := C;
  MinX := 1E300; MaxX := -1E300; MinY := 1E300; MaxY := -1E300;
  for I := 0 to 7 do
  begin
    if (I and 1) = 0 then P.X := B.Min.X else P.X := B.Max.X;
    if (I and 2) = 0 then P.Y := B.Min.Y else P.Y := B.Max.Y;
    if (I and 4) = 0 then P.Z := B.Min.Z else P.Z := B.Max.Z;
    X := VDot(VSub(P, C), Right);
    Y := VDot(VSub(P, C), Up);
    MinX := Min(MinX, X); MaxX := Max(MaxX, X);
    MinY := Min(MinY, Y); MaxY := Max(MaxY, Y);
  end;
  S := BoxSize(B);
  Sx := Max(MaxX - MinX, 1E-3);
  Sy := Max(MaxY - MinY, 1E-3);
  Scale := 0.85 * Min(FWidth / Sx, FHeight / Sy);
  Distance := Max(VLen(S) * 2, 50);
end;

function TCadCamera.Eye: TCadVec3;
begin
  Result := VAdd(Target, VScale(Back, Distance));
end;

function TCadCamera.ViewDir: TCadVec3;
begin
  Result := VNeg(Back);
end;

function TCadCamera.Project(const P: TCadVec3): TCadScreenPt;
var
  R: TCadVec3;
  X, Y, Z, F: Double;
begin
  R := VSub(P, Target);
  X := VDot(R, Right);
  Y := VDot(R, Up);
  Z := VDot(R, Back);      { positivo = na frente do alvo (mais perto) }
  if Perspective then
  begin
    F := Distance / Max(Distance - Z, 1E-3);
    X := X * F;
    Y := Y * F;
  end;
  Result.X := FWidth / 2 + X * Scale;
  Result.Y := FHeight / 2 - Y * Scale;
  Result.Depth := Distance - Z;
end;

procedure TCadCamera.ScreenRay(PX, PY: Double; out O, D: TCadVec3);
var
  X, Y: Double;
  P: TCadVec3;
begin
  X := (PX - FWidth / 2) / Scale;
  Y := -(PY - FHeight / 2) / Scale;
  P := VAdd(Target, VAdd(VScale(Right, X), VScale(Up, Y)));
  if Perspective then
  begin
    O := Eye;
    D := VNorm(VSub(P, O));
  end
  else
  begin
    O := VAdd(P, VScale(Back, Distance * 4));
    D := VNeg(Back);
  end;
end;

end.
