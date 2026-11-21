unit multicad_threadgeom;

{ MultiCAD - ferramenta de corte para rosca real em helice (sem LCL).

  Perfil metrico ISO 68-1 (60 graus), H = 0,866025 p:
  - rosca externa (parafuso): crista plana p/8 no diametro nominal d, raiz
    em d3 = d - 1,22687 p com fundo plano p/6 (aproxima o arredondado);
  - rosca interna (porca/furo): crista p/4 em D1 = D - 1,08253 p, raiz plana
    p/8 em D. A crista nunca fica menor que o furo existente: num furo de
    broca (D - p, como no assistente de furo) a rosca fica com a altura real
    de uma rosca feita com macho.
  - Folga radial (impressao 3D): a externa encolhe, a interna cresce.

  A ferramenta e um solido fechado, com eixo Z de 0 a Length e o inicio da
  helice em +X:
  - externa: regiao entre a superficie da rosca e um cilindro externo
    (corta os vaos do parafuso);
  - interna: regiao dentro da superficie da rosca (corta os vaos da porca).
  A superficie e r = f(z -/+ p.phi/2pi), com f periodico em p e linear por
  trechos. Cada coluna angular tem os pontos de quebra exatos do perfil; as
  colunas vizinhas sao costuradas em ordem de Z, entao cristas e raizes
  ficam como arestas helicoidais.
  Para a booleana nao receber faces quase coincidentes ou quase tangentes,
  a ferramenta entra 0,03 mm alem da parede existente (crista do parafuso
  levemente truncada, crista da porca levemente alem do furo): a parede
  inteira sai na regiao roscada e as unicas intersecoes sao transversais,
  nas pontas da rosca.

  Faces: <p>/rosca (helicoidal), <p>/inicio, <p>/fim (planos) e <p>/ext
  (cilindro externo da ferramenta externa). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multicad_types, multicad_mesh;

type
  TCadThreadSpec = record
    Internal: Boolean;
    MajorD: Double;      { diametro nominal (d / D) }
    Pitch: Double;       { passo }
    Length: Double;      { comprimento roscado }
    Clearance: Double;   { folga radial (mm) }
    LeftHand: Boolean;   { rosca esquerda }
    FaceRadius: Double;  { raio da face cilindrica que recebe a rosca }
    ChordTol: Double;
  end;

  { Pontos de quebra de um periodo: U crescente em [0, p), R em cada um. }
  TCadThreadProfile = record
    U, R: array of Double;
    RMin, RMax: Double;
  end;

{ Diametro menor (externa: d3; interna: D1). }
function CadThreadMinorD(MajorD, Pitch: Double; Internal: Boolean): Double;
{ Mensagem do primeiro parametro invalido (vazio = valido). }
function CadThreadValidate(const S: TCadThreadSpec): string;
{ Perfil da superficie da ferramenta num periodo. }
function CadThreadProfile(const S: TCadThreadSpec): TCadThreadProfile;
{ Raio da superficie da ferramenta no ponto (angulo Phi em rad, altura Z). }
function CadThreadRadius(const S: TCadThreadSpec; const P: TCadThreadProfile;
  Phi, Z: Double): Double;
{ Solido fechado da ferramenta (ver acima). nil e AError se falhar. }
function CadMakeThreadTool(const S: TCadThreadSpec; const Prefix: string;
  out AError: string): TCadMesh;
{ Volume analitico tirado pela rosca de um cilindro macico (externa) ou
  acrescentado ao furo (interna), sem as pontas: area do vao do perfil x
  2 pi x raio do centroide x numero de voltas (teorema de Pappus). }
function CadThreadRemovedVolume(const S: TCadThreadSpec): Double;

implementation

const
  SQRT3 = 1.7320508075688772;
  TAN30 = 0.5773502691896258;

function CadThreadMinorD(MajorD, Pitch: Double; Internal: Boolean): Double;
var
  H: Double;
begin
  H := SQRT3 / 2 * Pitch;
  if Internal then
    Result := MajorD - 2 * 5 / 8 * H
  else
    Result := MajorD - 2 * 17 / 24 * H;
end;

function CadThreadValidate(const S: TCadThreadSpec): string;
begin
  Result := '';
  if S.Pitch < 0.1 then
    Exit('Passo deve ser de pelo menos 0,1 mm');
  if S.MajorD <= 2 * S.Pitch then
    Exit('Diâmetro pequeno demais para o passo');
  if S.Length < S.Pitch * 0.5 then
    Exit('Comprimento da rosca deve ser de pelo menos meio passo');
  if (S.Clearance < 0) or (S.Clearance > S.Pitch / 2) then
    Exit('Folga deve ficar entre 0 e meio passo');
  if S.FaceRadius <= 0 then
    Exit('Face cilíndrica inválida');
  if not S.Internal and (S.FaceRadius < CadThreadMinorD(S.MajorD, S.Pitch, False) / 2 + S.Pitch * 0.15) then
    Exit('O cilindro é menor que o diâmetro de raiz da rosca');
  if not S.Internal and (S.FaceRadius > S.MajorD / 2 + S.Pitch * 0.5) then
    Exit(Format('O cilindro (Ø%s) é maior que a rosca Ø%s: ajuste a medida ou o diâmetro',
      [FormatFloat('0.###', 2 * S.FaceRadius), FormatFloat('0.###', S.MajorD)]));
  if S.Internal and (S.FaceRadius > S.MajorD / 2 - S.Pitch * 0.15) then
    Exit('O furo é maior que o diâmetro nominal da rosca');
end;

function ThreadDelta(const S: TCadThreadSpec): Double;
begin
  { quanto a ferramenta entra alem da parede existente: maior que o erro de
    corda da malha, para a parede inteira sair na regiao roscada }
  Result := Max(0.03, 2 * S.ChordTol);
end;

function CadThreadProfile(const S: TCadThreadSpec): TCadThreadProfile;
var
  P, H, RTop, RRoot, HC, HR, RCrest, RLow, HM, HN, RMaj, Dl: Double;

  procedure Pt(AU, AR: Double);
  var
    N: Integer;
  begin
    N := System.Length(Result.U);
    SetLength(Result.U, N + 1);
    SetLength(Result.R, N + 1);
    Result.U[N] := AU;
    Result.R[N] := AR;
  end;

begin
  Result.U := nil;
  Result.R := nil;
  P := S.Pitch;
  H := SQRT3 / 2 * P;
  Dl := ThreadDelta(S);
  if not S.Internal then
  begin
    { superficie interna da ferramenta: crista (r maximo) centrada em u=0;
      a crista fica um pouco abaixo do cilindro existente (truncada), com o
      patamar alargado pelos flancos de 60 graus }
    RCrest := S.MajorD / 2 - S.Clearance;
    RRoot := RCrest - 17 / 24 * H;
    RTop := Min(RCrest, S.FaceRadius - Dl);
    HC := P / 16 + (RCrest - RTop) * TAN30;
    HR := P / 12;
    if HC > P / 2 - HR - P / 40 then
      HC := P / 2 - HR - P / 40;
    Pt(0, RTop);
    Pt(HC, RTop);
    Pt(P / 2 - HR, RRoot);
    Pt(P / 2 + HR, RRoot);
    Pt(P - HC, RTop);
    Result.RMin := RRoot;
    Result.RMax := RTop;
  end
  else
  begin
    { superficie externa da ferramenta: raiz da porca (r maximo) em u=0; a
      crista da porca fica um pouco alem do furo existente }
    RMaj := S.MajorD / 2 + S.Clearance;
    RCrest := RMaj - 5 / 8 * H;          { D1/2 + folga }
    RLow := Max(RCrest, S.FaceRadius + Dl);
    HM := P / 16;
    HN := P / 8 + (RLow - RCrest) * TAN30;
    if HN > P / 2 - HM - P / 40 then
      HN := P / 2 - HM - P / 40;
    Pt(0, RMaj);
    Pt(HM, RMaj);
    Pt(P / 2 - HN, RLow);
    Pt(P / 2 + HN, RLow);
    Pt(P - HM, RMaj);
    Result.RMin := RLow;
    Result.RMax := RMaj;
  end;
end;

function ProfileAt(const P: TCadThreadProfile; Pitch, U: Double): Double;
var
  K, N: Integer;
  U0, U1, R0, R1: Double;
begin
  U := U - Floor(U / Pitch) * Pitch;
  N := Length(P.U);
  for K := 0 to N - 1 do
  begin
    U0 := P.U[K];
    R0 := P.R[K];
    if K < N - 1 then
    begin
      U1 := P.U[K + 1];
      R1 := P.R[K + 1];
    end
    else
    begin
      U1 := Pitch + P.U[0];
      R1 := P.R[0];
    end;
    if (U >= U0) and (U <= U1) then
    begin
      if U1 - U0 < 1E-12 then
        Exit(R1);
      Exit(R0 + (R1 - R0) * (U - U0) / (U1 - U0));
    end;
  end;
  Result := P.R[0];
end;

function HelixU(const S: TCadThreadSpec; Phi, Z: Double): Double;
begin
  if S.LeftHand then
    Result := Z + S.Pitch * Phi / (2 * Pi)
  else
    Result := Z - S.Pitch * Phi / (2 * Pi);
end;

function CadThreadRadius(const S: TCadThreadSpec; const P: TCadThreadProfile;
  Phi, Z: Double): Double;
begin
  Result := ProfileAt(P, S.Pitch, HelixU(S, Phi, Z));
end;

function CadThreadRemovedVolume(const S: TCadThreadSpec): Double;
const
  NS = 4000;
var
  P: TCadThreadProfile;
  K: Integer;
  R, Ref, Sum: Double;
begin
  { em cada altura z a secao percorre um periodo inteiro de u quando phi da
    a volta, entao a area tirada da secao e (pi / p) . integral de
    (Ref^2 - r^2) nos u em que a ferramenta entra na parede; o volume e essa
    area vezes o comprimento (exato, inclusive nas pontas planas) }
  P := CadThreadProfile(S);
  Ref := S.FaceRadius;
  Sum := 0;
  for K := 0 to NS - 1 do
  begin
    R := ProfileAt(P, S.Pitch, (K + 0.5) * S.Pitch / NS);
    if S.Internal then
    begin
      if R > Ref then
        Sum := Sum + (R * R - Ref * Ref);
    end
    else if R < Ref then
      Sum := Sum + (Ref * Ref - R * R);
  end;
  Result := Pi * Sum / NS * S.Length;
end;

function CadMakeThreadTool(const S: TCadThreadSpec; const Prefix: string;
  out AError: string): TCadMesh;
type
  TCol = array of TCadVec3;
var
  Pr: TCadThreadProfile;
  Cols: array of TCol;
  N, I, J, K, A, B, NA, NB: Integer;
  Phi, Z, Base, R, Gap, Gmin, ROut, Sg, Eps: Double;
  Zs: array of Double;
  M: TCadMesh;
  FThr, FIni, FFim, FExt: Integer;
  CA, CB: TCol;
  OA, OB, OA1, OB1, C0, C1: TCadVec3;

  procedure SortZ;
  var
    X, Y: Integer;
    T: Double;
  begin
    for X := 1 to High(Zs) do
    begin
      T := Zs[X];
      Y := X - 1;
      while (Y >= 0) and (Zs[Y] > T) do
      begin
        Zs[Y + 1] := Zs[Y];
        Dec(Y);
      end;
      Zs[Y + 1] := T;
    end;
  end;

  procedure Tri(const P1, P2, P3: TCadVec3);
  begin
    if S.Internal then
      M.AddTriP(P1, P2, P3, FThr)
    else
      M.AddTriP(P1, P3, P2, FThr);   { externa: a ferramenta fica por fora }
  end;

begin
  Result := nil;
  AError := CadThreadValidate(S);
  if AError <> '' then
    Exit;
  Pr := CadThreadProfile(S);
  { colunas: o deslocamento entre colunas vizinhas (p/N) precisa ser menor
    que o menor trecho do perfil para a costura casar crista com crista }
  Gmin := S.Pitch;
  for K := 0 to High(Pr.U) do
  begin
    if K < High(Pr.U) then
      Gap := Pr.U[K + 1] - Pr.U[K]
    else
      Gap := S.Pitch + Pr.U[0] - Pr.U[K];
    if Gap > 1E-9 then
      Gmin := Min(Gmin, Gap);
  end;
  N := Max(48, CadCircleSegments(Pr.RMax, S.ChordTol));
  N := Max(N, Ceil(1.5 * S.Pitch / Gmin));
  N := Min(N, 720);
  if S.LeftHand then Sg := -1 else Sg := 1;
  Eps := Max(0.002, S.Pitch * 1E-3);
  SetLength(Cols, N);
  for I := 0 to N - 1 do
  begin
    Phi := 2 * Pi * I / N;
    Zs := nil;
    SetLength(Zs, 2);
    Zs[0] := 0;
    Zs[1] := S.Length;
    for K := 0 to High(Pr.U) do
    begin
      { z = u + p.phi/2pi (direita) para cada ponto de quebra }
      Base := Pr.U[K] + Sg * S.Pitch * Phi / (2 * Pi);
      Base := Base - Floor(Base / S.Pitch) * S.Pitch;
      Z := Base;
      while Z < S.Length - Eps do
      begin
        if Z > Eps then
        begin
          SetLength(Zs, Length(Zs) + 1);
          Zs[High(Zs)] := Z;
        end;
        Z := Z + S.Pitch;
      end;
    end;
    SortZ;
    SetLength(Cols[I], Length(Zs));
    for J := 0 to High(Zs) do
    begin
      R := CadThreadRadius(S, Pr, Phi, Zs[J]);
      Cols[I][J] := V3(R * Cos(Phi), R * Sin(Phi), Zs[J]);
    end;
  end;
  M := TCadMesh.Create;
  try
    FThr := M.AddFace(CadFaceInfo(Prefix + '/rosca', skOther, V3(0, 0, 0), V3(0, 0, 1),
      S.MajorD / 2));
    FIni := M.AddPlaneFace(Prefix + '/inicio', V3(0, 0, 0), V3(0, 0, -1));
    FFim := M.AddPlaneFace(Prefix + '/fim', V3(0, 0, S.Length), V3(0, 0, 1));
    FExt := -1;
    ROut := Max(S.FaceRadius, Pr.RMax) + Max(0.5, 0.25 * S.Pitch);
    if not S.Internal then
      FExt := M.AddFace(CadFaceInfo(Prefix + '/ext', skCylinder, V3(0, 0, 0), V3(0, 0, 1), ROut));
    C0 := V3(0, 0, 0);
    C1 := V3(0, 0, S.Length);
    for I := 0 to N - 1 do
    begin
      CA := Cols[I];
      CB := Cols[(I + 1) mod N];
      NA := High(CA);
      NB := High(CB);
      { costura em ordem de Z (colunas comecam em 0 e terminam em L) }
      A := 0;
      B := 0;
      while (A < NA) or (B < NB) do
      begin
        if (A < NA) and ((B >= NB) or (CA[A + 1].Z <= CB[B + 1].Z)) then
        begin
          Tri(CA[A], CB[B], CA[A + 1]);
          Inc(A);
        end
        else
        begin
          Tri(CA[A], CB[B], CB[B + 1]);
          Inc(B);
        end;
      end;
      if S.Internal then
      begin
        { tampas em leque a partir do eixo }
        M.AddTriP(C0, CB[0], CA[0], FIni);
        M.AddTriP(C1, CA[NA], CB[NB], FFim);
      end
      else
      begin
        Phi := 2 * Pi * I / N;
        OA := V3(ROut * Cos(Phi), ROut * Sin(Phi), 0);
        Phi := 2 * Pi * ((I + 1) mod N) / N;
        OB := V3(ROut * Cos(Phi), ROut * Sin(Phi), 0);
        OA1 := V3(OA.X, OA.Y, S.Length);
        OB1 := V3(OB.X, OB.Y, S.Length);
        M.AddQuadP(CA[0], CB[0], OB, OA, FIni);
        M.AddQuadP(CA[NA], OA1, OB1, CB[NB], FFim);
        M.AddQuadP(OA, OB, OB1, OA1, FExt);
      end;
    end;
    if M.Volume < 0 then
      M.Flip;
    if not M.CheckClosed(AError) then
    begin
      AError := 'Rosca com malha aberta: ' + AError;
      Exit;
    end;
    Result := M;
    M := nil;
  finally
    M.Free;
  end;
end;

end.
