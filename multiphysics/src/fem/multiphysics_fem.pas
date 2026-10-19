unit multiphysics_fem;

{ Solver FEM proprio: elasticidade linear, conducao termica e modal em
  tetraedros TET4/TET10 de lados retos.

  Integracao exata: as funcoes de forma sao polinomios nas coordenadas
  baricentricas L0..L3 e o mapeamento e afim, entao todas as integrais saem
  da formula  int L0^a L1^b L2^c L3^d dV = 6V a!b!c!d!/(a+b+c+d+3)!
  (triangulo: 2A a!b!c!/(a+b+c+2)!). As tabelas por tipo de elemento sao
  calculadas uma vez (InitTables) e cada elemento so precisa de V e dos
  gradientes de L.

  Analises:
  - estatica linear (fixacoes, deslocamento prescrito, forca total na face,
    pressao, gravidade, carga termica alfa*dT);
  - termica em regime permanente (temperatura, fluxo, conveccao, potencia);
  - modal K phi = w^2 M phi por iteracao em subespaco.

  Unidades SI. Resultado sempre com a malha/solver usados; a fidelidade e
  decidida por quem chama (ver multiphysics_analysis). }

{$mode objfpc}{$H+}
{ laços numericos pesados: otimiza mesmo quando o projeto compila com -O1 }
{$OPTIMIZATION LEVEL3}

interface

uses
  Classes, SysUtils, Math, multiphysics_vector, multiphysics_geometry,
  multiphysics_mesh, multiphysics_sparse, multiphysics_contact;

type
  TFEMMaterial = record
    Name: string;
    E, Nu, Rho, K, Alpha, Yield: Double;
  end;

  TFEMLoadKind = (
    flFix,          { fixa os graus de Mask (0=x 1=y 2=z) na face }
    flDisplacement, { deslocamento prescrito Vec nos graus de Mask }
    flForce,        { forca total Vec distribuida pela area da face }
    flPressure,     { pressao Value (Pa), positiva empurra a face para dentro }
    flTemperature,  { temperatura Value (C) na face }
    flHeatFlux,     { fluxo Value (W/m2) entrando pela face }
    flConvection,   { h = Value (W/m2K), T ambiente = Value2 (C) }
    flHeatPower);   { potencia Value (W) gerada no volume da peca Part }

  TFEMLoad = record
    Kind: TFEMLoadKind;
    Tag: Integer;          { face (indice em Mesh.FaceNames) }
    Part: Integer;         { flHeatPower }
    Mask: array[0..2] of Boolean;
    Vec: TVector3;
    Value, Value2: Double;
  end;

  TStaticResult = record
    Ok: Boolean;
    Message: string;
    U: TDoubleArray;            { 3 por no }
    VonMises: TDoubleArray;     { por no (media dos elementos) }
    MaxDisp, MaxVonMises, MinSafety: Double;
    MaxDispNode, MaxVonMisesNode: Integer;
    Reaction: TVector3;         { soma das reacoes nas fixacoes }
    Solve: TSolveInfo;
    Dofs: Integer;
  end;

  TThermalResult = record
    Ok: Boolean;
    Message: string;
    T: TDoubleArray;
    MaxT, MinT: Double;
    HeatIn: Double;             { potencia que entra pelas faces com temperatura fixa (W) }
    Solve: TSolveInfo;
  end;

  TModalResult = record
    Ok: Boolean;
    Message: string;
    Freq: TDoubleArray;         { Hz }
    Shapes: array of TDoubleArray;   { normalizadas pela massa }
    Iterations: Integer;
    EffMass: array of array[0..2] of Double;   { fracao da massa total em x, y, z por modo }
    TotalMass: Double;
  end;

  TBoolArrayHelper = array of Boolean;

  TFEMModel = class
  private
    FLastMethod: string;
    function Mat(Part: Integer): TFEMMaterial;
    procedure ElemGeometry(E: Integer; out V: Double; out G: array of TVector3);
    procedure AssembleStiffness(K: TCSRMatrix);
    procedure AssembleMass(M: TCSRMatrix);
    procedure FixedDofs(out Fixed: TBoolArrayHelper; out Values: TDoubleArray);
    procedure ElasticLoads(var F: TDoubleArray);
    function Factorize(K: TCSRMatrix; Block: Integer; Ch: TDirectCholesky; out Direct: Boolean): Boolean;
    function TieGroups: TIntGroups;
    procedure AddTiePenalty(K: TCSRMatrix; Block: Integer);
  public
    Mesh: TFEMMesh;            { nao e liberada pelo modelo }
    Materials: array of TFEMMaterial;   { por peca }
    Loads: array of TFEMLoad;
    Gravity: TVector3;
    RefTemperature: Double;    { C: temperatura sem tensao termica }
    Temperature: TDoubleArray; { por no, de uma analise termica (vazio = sem carga termica) }
    Tolerance: Double;
    MaxIterations: Integer;
    ForceIterative: Boolean;   { testes: usa PCG mesmo quando o direto caberia }
    MaxEnvelope: Int64;        { limite de valores do fator de Cholesky (memoria) }
    Ties: TMeshTies;           { contatos colados (penalidade) }
    TiePenalty: Double;        { fator sobre a maior rigidez da diagonal }
    constructor Create(AMesh: TFEMMesh);
    procedure AddLoad(const L: TFEMLoad);
    procedure ClearLoads;
    function SolveStatic(out R: TStaticResult): Boolean;
    function SolveThermal(out R: TThermalResult): Boolean;
    function SolveModal(Modes: Integer; out R: TModalResult): Boolean;
    { forcas nodais equivalentes das cargas de forca total (3 por no), para exportar *CLOAD }
    function ForceLoadVector: TDoubleArray;
  end;

function FEMMaterial(const Name: string; E, Nu, Rho, K, Alpha, Yield: Double): TFEMMaterial;
function FixLoad(Tag: Integer): TFEMLoad;
function ForceLoad(Tag: Integer; const F: TVector3): TFEMLoad;
function PressureLoad(Tag: Integer; P: Double): TFEMLoad;
function TemperatureLoad(Tag: Integer; T: Double): TFEMLoad;
function HeatFluxLoad(Tag: Integer; Q: Double): TFEMLoad;
function ConvectionLoad(Tag: Integer; H, TAmb: Double): TFEMLoad;
function HeatPowerLoad(Part: Integer; W: Double): TFEMLoad;
function VonMisesOf(const S: array of Double): Double;   { sxx syy szz sxy syz szx }

implementation

const
  MAXN = 10;

type
  TTables = record
    N: Integer;                                   { nos do tetraedro }
    Q: array[0..MAXN - 1] of Double;              { int N_a / V }
    MM: array[0..MAXN - 1, 0..MAXN - 1] of Double;
    T: array[0..MAXN - 1, 0..MAXN - 1, 0..3, 0..3] of Double;  { int dN_a/dL_k dN_b/dL_l / V }
    S: array[0..MAXN - 1, 0..MAXN - 1, 0..3] of Double;        { int N_c dN_a/dL_k / V }
    FN: Integer;                                  { nos do triangulo }
    FQ: array[0..5] of Double;                    { int N_a / A }
    FMM: array[0..5, 0..5] of Double;
  end;

  TTerm = record
    C: Double;
    E: array[0..3] of Integer;
  end;
  TPoly = array of TTerm;

var
  Tab: array[1..2] of TTables;
  TablesReady: Boolean = False;

function Fact(N: Integer): Double;
var
  I: Integer;
begin
  Result := 1;
  for I := 2 to N do Result := Result * I;
end;

procedure PAdd(var P: TPoly; C: Double; E0, E1, E2, E3: Integer);
var
  N: Integer;
begin
  N := Length(P);
  SetLength(P, N + 1);
  P[N].C := C; P[N].E[0] := E0; P[N].E[1] := E1; P[N].E[2] := E2; P[N].E[3] := E3;
end;

function PMul(const A, B: TPoly): TPoly;
var
  I, J, K, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(A) * Length(B));
  N := 0;
  for I := 0 to High(A) do
    for J := 0 to High(B) do
    begin
      Result[N].C := A[I].C * B[J].C;
      for K := 0 to 3 do Result[N].E[K] := A[I].E[K] + B[J].E[K];
      Inc(N);
    end;
end;

function PDiff(const A: TPoly; K: Integer): TPoly;
var
  I, N: Integer;
begin
  Result := nil;
  N := 0;
  for I := 0 to High(A) do
    if A[I].E[K] > 0 then
    begin
      SetLength(Result, N + 1);
      Result[N] := A[I];
      Result[N].C := A[I].C * A[I].E[K];
      Dec(Result[N].E[K]);
      Inc(N);
    end;
end;

{ integral sobre o tetraedro dividida por V (Dim = 3) ou sobre o triangulo
  dividida por A (Dim = 2, so L0..L2) }
function PInt(const A: TPoly; Dim: Integer): Double;
var
  I, K, S: Integer;
  P: Double;
begin
  Result := 0;
  for I := 0 to High(A) do
  begin
    P := 1; S := 0;
    for K := 0 to 3 do
    begin
      P := P * Fact(A[I].E[K]);
      S := S + A[I].E[K];
    end;
    if Dim = 3 then Result := Result + A[I].C * 6 * P / Fact(S + 3)
    else Result := Result + A[I].C * 2 * P / Fact(S + 2);
  end;
end;

{ funcoes de forma: Order 1 = lineares; 2 = quadraticas. Nv = 4 (tetra) ou 3 (triangulo) }
function Shape(Order, Nv, A: Integer): TPoly;
const
  TE: array[0..5, 0..1] of Integer = ((0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3));
  TR: array[0..2, 0..1] of Integer = ((0, 1), (1, 2), (2, 0));
var
  E: array[0..3] of Integer;
  I, J: Integer;
begin
  Result := nil;
  if (Order = 1) or (A < Nv) then
  begin
    FillChar(E, SizeOf(E), 0);
    E[A] := 1;
    if Order = 1 then
      PAdd(Result, 1, E[0], E[1], E[2], E[3])
    else
    begin
      { L(2L - 1) }
      E[A] := 2; PAdd(Result, 2, E[0], E[1], E[2], E[3]);
      E[A] := 1; PAdd(Result, -1, E[0], E[1], E[2], E[3]);
    end;
    Exit;
  end;
  if Nv = 4 then begin I := TE[A - 4, 0]; J := TE[A - 4, 1]; end
  else begin I := TR[A - 3, 0]; J := TR[A - 3, 1]; end;
  FillChar(E, SizeOf(E), 0);
  E[I] := 1; E[J] := 1;
  PAdd(Result, 4, E[0], E[1], E[2], E[3]);
end;

procedure InitTables;
var
  O, N, FN, A, B, C, K, L: Integer;
  Sh, FSh: array[0..MAXN - 1] of TPoly;
  D: array[0..MAXN - 1, 0..3] of TPoly;
begin
  if TablesReady then Exit;
  for O := 1 to 2 do
  begin
    if O = 1 then begin N := 4; FN := 3; end else begin N := 10; FN := 6; end;
    FillChar(Tab[O], SizeOf(TTables), 0);
    Tab[O].N := N; Tab[O].FN := FN;
    for A := 0 to N - 1 do
    begin
      Sh[A] := Shape(O, 4, A);
      for K := 0 to 3 do D[A, K] := PDiff(Sh[A], K);
    end;
    for A := 0 to N - 1 do
    begin
      Tab[O].Q[A] := PInt(Sh[A], 3);
      for B := 0 to N - 1 do
      begin
        Tab[O].MM[A, B] := PInt(PMul(Sh[A], Sh[B]), 3);
        for K := 0 to 3 do
          for L := 0 to 3 do
            Tab[O].T[A, B, K, L] := PInt(PMul(D[A, K], D[B, L]), 3);
      end;
      for C := 0 to N - 1 do
        for K := 0 to 3 do
          Tab[O].S[C, A, K] := PInt(PMul(Sh[C], D[A, K]), 3);
    end;
    for A := 0 to FN - 1 do FSh[A] := Shape(O, 3, A);
    for A := 0 to FN - 1 do
    begin
      Tab[O].FQ[A] := PInt(FSh[A], 2);
      for B := 0 to FN - 1 do
        Tab[O].FMM[A, B] := PInt(PMul(FSh[A], FSh[B]), 2);
    end;
  end;
  TablesReady := True;
end;

{ dN_a/dL_k no ponto L }
function ShapeDeriv(Order, A, K: Integer; const L: array of Double): Double;
const
  TE: array[0..5, 0..1] of Integer = ((0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3));
var
  I, J: Integer;
begin
  if Order = 1 then
  begin
    if A = K then Exit(1) else Exit(0);
  end;
  if A < 4 then
  begin
    if A = K then Exit(4 * L[A] - 1) else Exit(0);
  end;
  I := TE[A - 4, 0]; J := TE[A - 4, 1];
  Result := 0;
  if I = K then Result := Result + 4 * L[J];
  if J = K then Result := Result + 4 * L[I];
end;

{ coordenadas baricentricas do no local A (cantos e meios de aresta) }
procedure NodeBary(A: Integer; out L: array of Double);
const
  TE: array[0..5, 0..1] of Integer = ((0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3));
var
  K: Integer;
begin
  for K := 0 to 3 do L[K] := 0;
  if A < 4 then L[A] := 1
  else
  begin
    L[TE[A - 4, 0]] := 0.5;
    L[TE[A - 4, 1]] := 0.5;
  end;
end;

function VonMisesOf(const S: array of Double): Double;
begin
  Result := Sqrt(0.5 * (Sqr(S[0] - S[1]) + Sqr(S[1] - S[2]) + Sqr(S[2] - S[0])) +
    3 * (Sqr(S[3]) + Sqr(S[4]) + Sqr(S[5])));
end;

function FEMMaterial(const Name: string; E, Nu, Rho, K, Alpha, Yield: Double): TFEMMaterial;
begin
  Result.Name := Name; Result.E := E; Result.Nu := Nu; Result.Rho := Rho;
  Result.K := K; Result.Alpha := Alpha; Result.Yield := Yield;
end;

function BlankLoad(Kind: TFEMLoadKind; Tag: Integer): TFEMLoad;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := Kind; Result.Tag := Tag; Result.Part := -1;
end;

function FixLoad(Tag: Integer): TFEMLoad;
begin
  Result := BlankLoad(flFix, Tag);
  Result.Mask[0] := True; Result.Mask[1] := True; Result.Mask[2] := True;
end;

function ForceLoad(Tag: Integer; const F: TVector3): TFEMLoad;
begin
  Result := BlankLoad(flForce, Tag);
  Result.Vec := F;
end;

function PressureLoad(Tag: Integer; P: Double): TFEMLoad;
begin
  Result := BlankLoad(flPressure, Tag);
  Result.Value := P;
end;

function TemperatureLoad(Tag: Integer; T: Double): TFEMLoad;
begin
  Result := BlankLoad(flTemperature, Tag);
  Result.Value := T;
end;

function HeatFluxLoad(Tag: Integer; Q: Double): TFEMLoad;
begin
  Result := BlankLoad(flHeatFlux, Tag);
  Result.Value := Q;
end;

function ConvectionLoad(Tag: Integer; H, TAmb: Double): TFEMLoad;
begin
  Result := BlankLoad(flConvection, Tag);
  Result.Value := H; Result.Value2 := TAmb;
end;

function HeatPowerLoad(Part: Integer; W: Double): TFEMLoad;
begin
  Result := BlankLoad(flHeatPower, -1);
  Result.Part := Part; Result.Value := W;
end;

{ ---------------- TFEMModel ---------------- }

constructor TFEMModel.Create(AMesh: TFEMMesh);
begin
  inherited Create;
  InitTables;
  Mesh := AMesh;
  Gravity := V3(0, 0, 0);
  RefTemperature := 20;
  Tolerance := 1e-10;
  MaxIterations := 20000;
  MaxEnvelope := 80000000;
  TiePenalty := 1e3;
end;

function TFEMModel.TieGroups: TIntGroups;
var
  I, J: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Ties));
  for I := 0 to High(Ties) do
  begin
    SetLength(Result[I], Ties[I].NM + 1);
    Result[I][0] := Ties[I].Slave;
    for J := 0 to Ties[I].NM - 1 do Result[I][J + 1] := Ties[I].Masters[J];
  end;
end;

{ penalidade kp (c c^T) por grau, c = (1, -w1, ..., -wn); kp proporcional
  a rigidez local (diagonal dos nos da amarracao), nao a maxima global:
  pecas com elementos de tamanhos muito diferentes nao perdem precisao }
procedure TFEMModel.AddTiePenalty(K: TCSRMatrix; Block: Integer);
var
  I, A, B, D, NA, NB: Integer;
  Kloc, Kp, CA, CB: Double;
  Dg: TDoubleArray;
begin
  if Length(Ties) = 0 then Exit;
  Dg := K.Diagonal;   { antes das penalidades: nao acumula entre amarracoes }
  for I := 0 to High(Ties) do
  begin
    Kloc := Dg[Block * Ties[I].Slave];
    for A := 0 to Ties[I].NM - 1 do
      Kloc := Max(Kloc, Dg[Block * Ties[I].Masters[A]]);
    Kp := TiePenalty * Kloc;
    for A := 0 to Ties[I].NM do
    begin
      if A = 0 then begin NA := Ties[I].Slave; CA := 1; end
      else begin NA := Ties[I].Masters[A - 1]; CA := -Ties[I].W[A - 1]; end;
      for B := 0 to Ties[I].NM do
      begin
        if B = 0 then begin NB := Ties[I].Slave; CB := 1; end
        else begin NB := Ties[I].Masters[B - 1]; CB := -Ties[I].W[B - 1]; end;
        for D := 0 to Block - 1 do
          K.Add(Block * NA + D, Block * NB + D, Kp * CA * CB);
      end;
    end;
  end;
end;

procedure TFEMModel.AddLoad(const L: TFEMLoad);
begin
  SetLength(Loads, Length(Loads) + 1);
  Loads[High(Loads)] := L;
end;

procedure TFEMModel.ClearLoads;
begin
  Loads := nil;
end;

function TFEMModel.Mat(Part: Integer): TFEMMaterial;
begin
  if (Part >= 0) and (Part < Length(Materials)) then Result := Materials[Part]
  else if Length(Materials) > 0 then Result := Materials[0]
  else Result := FEMMaterial('Aco', 200e9, 0.3, 7850, 50, 12e-6, 250e6);
end;

procedure TFEMModel.ElemGeometry(E: Integer; out V: Double; out G: array of TVector3);
var
  X0, A, B, C: TVector3;
  Det: Double;
  Inv: array[0..2, 0..2] of Double;
begin
  X0 := Mesh.Nodes[Mesh.Elems[E].N[0]];
  A := VSub(Mesh.Nodes[Mesh.Elems[E].N[1]], X0);
  B := VSub(Mesh.Nodes[Mesh.Elems[E].N[2]], X0);
  C := VSub(Mesh.Nodes[Mesh.Elems[E].N[3]], X0);
  { J = [A B C] em colunas; det = A . (B x C) }
  Det := VDot(A, VCross(B, C));
  V := Det / 6;
  if Det = 0 then Det := 1e-300;
  { linhas de J^-1 = (B x C, C x A, A x B) / det }
  with VScale(VCross(B, C), 1 / Det) do begin Inv[0, 0] := X; Inv[0, 1] := Y; Inv[0, 2] := Z; end;
  with VScale(VCross(C, A), 1 / Det) do begin Inv[1, 0] := X; Inv[1, 1] := Y; Inv[1, 2] := Z; end;
  with VScale(VCross(A, B), 1 / Det) do begin Inv[2, 0] := X; Inv[2, 1] := Y; Inv[2, 2] := Z; end;
  G[1] := V3(Inv[0, 0], Inv[0, 1], Inv[0, 2]);
  G[2] := V3(Inv[1, 0], Inv[1, 1], Inv[1, 2]);
  G[3] := V3(Inv[2, 0], Inv[2, 1], Inv[2, 2]);
  G[0] := VScale(VAdd(VAdd(G[1], G[2]), G[3]), -1);
end;

function Comp(const V: TVector3; I: Integer): Double; inline;
begin
  case I of
    0: Result := V.X;
    1: Result := V.Y;
    else Result := V.Z;
  end;
end;

{ H[a][b][i][j] = int dN_a/dx_i dN_b/dx_j dV }
procedure GradProducts(const Tb: TTables; V: Double; const G: array of TVector3;
  out H: array of Double);
var
  A, B, I, J, K, L, N: Integer;
  GG: array[0..3, 0..2] of Double;
  W: array[0..3, 0..2] of Double;
  S: Double;
begin
  N := Tb.N;
  for K := 0 to 3 do
    for I := 0 to 2 do GG[K, I] := Comp(G[K], I);
  for A := 0 to N - 1 do
    for B := 0 to N - 1 do
    begin
      { W[k][j] = sum_l T[a][b][k][l] G[l][j] }
      for K := 0 to 3 do
        for J := 0 to 2 do
        begin
          S := 0;
          for L := 0 to 3 do S := S + Tb.T[A, B, K, L] * GG[L, J];
          W[K, J] := S;
        end;
      for I := 0 to 2 do
        for J := 0 to 2 do
        begin
          S := 0;
          for K := 0 to 3 do S := S + GG[K, I] * W[K, J];
          H[((A * N + B) * 3 + I) * 3 + J] := S * V;
        end;
    end;
end;

procedure TFEMModel.AssembleStiffness(K: TCSRMatrix);
var
  E, A, B, I, J, N, O: Integer;
  V, Lam, Mu, Tr: Double;
  G: array[0..3] of TVector3;
  H: array of Double;
  M: TFEMMaterial;
  NA, NB: Integer;
begin
  O := Mesh.Order;
  N := Tab[O].N;
  SetLength(H, N * N * 9);
  for E := 0 to Mesh.ElemCount - 1 do
  begin
    M := Mat(Mesh.Elems[E].Part);
    Lam := M.E * M.Nu / ((1 + M.Nu) * (1 - 2 * M.Nu));
    Mu := M.E / (2 * (1 + M.Nu));
    ElemGeometry(E, V, G);
    GradProducts(Tab[O], V, G, H);
    for A := 0 to N - 1 do
    begin
      NA := Mesh.Elems[E].N[A];
      for B := 0 to N - 1 do
      begin
        NB := Mesh.Elems[E].N[B];
        Tr := H[((A * N + B) * 3 + 0) * 3 + 0] + H[((A * N + B) * 3 + 1) * 3 + 1] + H[((A * N + B) * 3 + 2) * 3 + 2];
        for I := 0 to 2 do
          for J := 0 to 2 do
            K.Add(3 * NA + I, 3 * NB + J,
              Lam * H[((A * N + B) * 3 + I) * 3 + J] + Mu * H[((A * N + B) * 3 + J) * 3 + I] +
              IfThen(I = J, Mu * Tr, 0));
      end;
    end;
  end;
end;

procedure TFEMModel.AssembleMass(M: TCSRMatrix);
var
  E, A, B, I, N, O: Integer;
  V, Rho: Double;
  G: array[0..3] of TVector3;
begin
  O := Mesh.Order;
  N := Tab[O].N;
  for E := 0 to Mesh.ElemCount - 1 do
  begin
    Rho := Mat(Mesh.Elems[E].Part).Rho;
    ElemGeometry(E, V, G);
    for A := 0 to N - 1 do
      for B := 0 to N - 1 do
        for I := 0 to 2 do
          M.Add(3 * Mesh.Elems[E].N[A] + I, 3 * Mesh.Elems[E].N[B] + I, Rho * V * Tab[O].MM[A, B]);
  end;
end;

procedure TFEMModel.FixedDofs(out Fixed: TBoolArrayHelper; out Values: TDoubleArray);
var
  L, I, D: Integer;
  Ids: TIntArray;
begin
  Fixed := nil; Values := nil;
  SetLength(Fixed, 3 * Mesh.NodeCount);
  SetLength(Values, 3 * Mesh.NodeCount);
  for L := 0 to High(Loads) do
    if Loads[L].Kind in [flFix, flDisplacement] then
    begin
      Ids := Mesh.NodesOfTag(Loads[L].Tag);
      for I := 0 to High(Ids) do
        for D := 0 to 2 do
          if Loads[L].Mask[D] then
          begin
            Fixed[3 * Ids[I] + D] := True;
            if Loads[L].Kind = flDisplacement then Values[3 * Ids[I] + D] := Comp(Loads[L].Vec, D)
            else Values[3 * Ids[I] + D] := 0;
          end;
    end;
end;

procedure TFEMModel.ElasticLoads(var F: TDoubleArray);
var
  L, Fc, A, D, E, C, K, N, O, FNn, NA: Integer;
  Area, TotalArea, V, Lam, Mu, Coef, DT: Double;
  T: TVector3;
  G: array[0..3] of TVector3;
  M: TFEMMaterial;
  Gsum: TVector3;
begin
  O := Mesh.Order;
  N := Tab[O].N; FNn := Tab[O].FN;
  for L := 0 to High(Loads) do
    case Loads[L].Kind of
      flForce, flPressure:
        begin
          TotalArea := Mesh.TagArea(Loads[L].Tag);
          if TotalArea <= 0 then Continue;
          for Fc := 0 to Mesh.FaceCount - 1 do
          begin
            if Mesh.Faces[Fc].Tag <> Loads[L].Tag then Continue;
            Area := Mesh.FaceArea(Fc);
            if Loads[L].Kind = flForce then T := VScale(Loads[L].Vec, 1 / TotalArea)
            else T := VScale(Mesh.FaceNormal(Fc), -Loads[L].Value);
            for A := 0 to FNn - 1 do
              for D := 0 to 2 do
                F[3 * Mesh.Faces[Fc].N[A] + D] := F[3 * Mesh.Faces[Fc].N[A] + D] + Comp(T, D) * Area * Tab[O].FQ[A];
          end;
        end;
    end;
  { gravidade e carga termica }
  for E := 0 to Mesh.ElemCount - 1 do
  begin
    M := Mat(Mesh.Elems[E].Part);
    ElemGeometry(E, V, G);
    if VLength(Gravity) > 0 then
      for A := 0 to N - 1 do
        for D := 0 to 2 do
          F[3 * Mesh.Elems[E].N[A] + D] := F[3 * Mesh.Elems[E].N[A] + D] + M.Rho * Comp(Gravity, D) * V * Tab[O].Q[A];
    if (Length(Temperature) = Mesh.NodeCount) and (M.Alpha <> 0) then
    begin
      Lam := M.E * M.Nu / ((1 + M.Nu) * (1 - 2 * M.Nu));
      Mu := M.E / (2 * (1 + M.Nu));
      Coef := (3 * Lam + 2 * Mu) * M.Alpha * V;
      for A := 0 to N - 1 do
      begin
        NA := Mesh.Elems[E].N[A];
        { f_a = (3l+2m) a sum_c dT_c int N_c grad N_a }
        Gsum := V3(0, 0, 0);
        for C := 0 to N - 1 do
        begin
          DT := Temperature[Mesh.Elems[E].N[C]] - RefTemperature;
          if DT = 0 then Continue;
          for K := 0 to 3 do
            Gsum := VAdd(Gsum, VScale(G[K], DT * Tab[O].S[C, A, K]));
        end;
        F[3 * NA] := F[3 * NA] + Coef * Gsum.X;
        F[3 * NA + 1] := F[3 * NA + 1] + Coef * Gsum.Y;
        F[3 * NA + 2] := F[3 * NA + 2] + Coef * Gsum.Z;
      end;
    end;
  end;
end;

{ direto (Cholesky esparso com disseccao aninhada) quando o fator cabe na
  memoria; senao gradiente conjugado }
function TFEMModel.Factorize(K: TCSRMatrix; Block: Integer; Ch: TDirectCholesky; out Direct: Boolean): Boolean;
begin
  Direct := False;
  Result := True;
  if ForceIterative then Exit;
  Ch.MaxNonZeros := MaxEnvelope;
  Direct := True;
  Result := Ch.Factor(K, Block, Copy(Mesh.Nodes, 0, Mesh.NodeCount));
  FLastMethod := Ch.Method;
  if not Result and Ch.TooBig then
  begin
    Direct := False;
    Result := True;
  end;
end;

function TFEMModel.SolveStatic(out R: TStaticResult): Boolean;
var
  K, K0: TCSRMatrix;
  F, F0, Values, KU: TDoubleArray;
  Fixed: TBoolArrayHelper;
  Ch: TDirectCholesky;
  Direct, AnyFix: Boolean;
  I, E, A, B, D, J, O, N, NN: Integer;
  V, Lam, Mu, DT, Tr, Sf: Double;
  G: array[0..3] of TVector3;
  L: array[0..3] of Double;
  Grad: array[0..2, 0..2] of Double;
  Eps, Sig: array[0..5] of Double;
  Cnt: array of Integer;
  M: TFEMMaterial;
  DN: TVector3;
begin
  FillChar(R, SizeOf(R), 0);
  R.MinSafety := MaxDouble;
  NN := Mesh.NodeCount;
  O := Mesh.Order; N := Tab[O].N;
  R.Dofs := 3 * NN;
  FixedDofs(Fixed, Values);
  AnyFix := False;
  for I := 0 to High(Fixed) do if Fixed[I] then begin AnyFix := True; Break; end;
  if not AnyFix then
  begin
    R.Message := 'Nenhuma fixacao: a estrutura esta livre (movimento de corpo rigido). Fixe ao menos uma face.';
    Exit(False);
  end;
  K := TCSRMatrix.Create; K0 := TCSRMatrix.Create; Ch := TDirectCholesky.Create;
  try
    K.BuildFromMesh(Mesh, 3, TieGroups);
    AssembleStiffness(K);
    AddTiePenalty(K, 3);
    K0.CopyPatternFrom(K);
    K0.Val := Copy(K.Val);
    SetLength(F, 3 * NN);
    ElasticLoads(F);
    F0 := Copy(F);
    K.ApplyDirichlet(Fixed, Values, F);
    if not Factorize(K, 3, Ch, Direct) then
    begin
      R.Message := Ch.LastError;
      Exit(False);
    end;
    if Direct then
    begin
      Ch.Solve(F, R.U);
      R.Solve.Method := FLastMethod;
      R.Solve.Converged := True;
    end
    else
    begin
      R.Solve := SolvePCG(K, F, R.U, Tolerance, MaxIterations);
      if not R.Solve.Converged then
      begin
        R.Message := Format('PCG nao convergiu (%d iteracoes, residuo %.2e)', [R.Solve.Iterations, R.Solve.Residual]);
        Exit(False);
      end;
    end;
    { reacoes = K0 u - f nas fixacoes }
    K0.MulVec(R.U, KU);
    R.Reaction := V3(0, 0, 0);
    for I := 0 to NN - 1 do
    begin
      if Fixed[3 * I] then R.Reaction.X := R.Reaction.X + KU[3 * I] - F0[3 * I];
      if Fixed[3 * I + 1] then R.Reaction.Y := R.Reaction.Y + KU[3 * I + 1] - F0[3 * I + 1];
      if Fixed[3 * I + 2] then R.Reaction.Z := R.Reaction.Z + KU[3 * I + 2] - F0[3 * I + 2];
    end;
    { tensoes nos nos de cada elemento, media nodal }
    SetLength(R.VonMises, NN);
    SetLength(Cnt, NN);
    for E := 0 to Mesh.ElemCount - 1 do
    begin
      M := Mat(Mesh.Elems[E].Part);
      Lam := M.E * M.Nu / ((1 + M.Nu) * (1 - 2 * M.Nu));
      Mu := M.E / (2 * (1 + M.Nu));
      ElemGeometry(E, V, G);
      for A := 0 to N - 1 do
      begin
        NodeBary(A, L);
        FillChar(Grad, SizeOf(Grad), 0);
        for B := 0 to N - 1 do
        begin
          DN := V3(0, 0, 0);
          for J := 0 to 3 do DN := VAdd(DN, VScale(G[J], ShapeDeriv(O, B, J, L)));
          for D := 0 to 2 do
          begin
            Grad[D, 0] := Grad[D, 0] + R.U[3 * Mesh.Elems[E].N[B] + D] * DN.X;
            Grad[D, 1] := Grad[D, 1] + R.U[3 * Mesh.Elems[E].N[B] + D] * DN.Y;
            Grad[D, 2] := Grad[D, 2] + R.U[3 * Mesh.Elems[E].N[B] + D] * DN.Z;
          end;
        end;
        Eps[0] := Grad[0, 0]; Eps[1] := Grad[1, 1]; Eps[2] := Grad[2, 2];
        Eps[3] := (Grad[0, 1] + Grad[1, 0]) / 2;
        Eps[4] := (Grad[1, 2] + Grad[2, 1]) / 2;
        Eps[5] := (Grad[2, 0] + Grad[0, 2]) / 2;
        Tr := Eps[0] + Eps[1] + Eps[2];
        if Length(Temperature) = NN then DT := Temperature[Mesh.Elems[E].N[A]] - RefTemperature else DT := 0;
        for D := 0 to 2 do Sig[D] := Lam * Tr + 2 * Mu * Eps[D] - (3 * Lam + 2 * Mu) * M.Alpha * DT;
        for D := 3 to 5 do Sig[D] := 2 * Mu * Eps[D];
        I := Mesh.Elems[E].N[A];
        R.VonMises[I] := R.VonMises[I] + VonMisesOf(Sig);
        Inc(Cnt[I]);
        if M.Yield > 0 then
        begin
          Sf := M.Yield / Max(VonMisesOf(Sig), 1e-30);
          if Sf < R.MinSafety then R.MinSafety := Sf;
        end;
      end;
    end;
    R.MaxDispNode := 0; R.MaxVonMisesNode := 0;
    for I := 0 to NN - 1 do
    begin
      if Cnt[I] > 0 then R.VonMises[I] := R.VonMises[I] / Cnt[I];
      V := Sqrt(Sqr(R.U[3 * I]) + Sqr(R.U[3 * I + 1]) + Sqr(R.U[3 * I + 2]));
      if V > R.MaxDisp then begin R.MaxDisp := V; R.MaxDispNode := I; end;
      if R.VonMises[I] > R.MaxVonMises then begin R.MaxVonMises := R.VonMises[I]; R.MaxVonMisesNode := I; end;
    end;
    R.Ok := True;
    R.Message := Format('Estatico linear: %d nos, %d elementos TET%d, %s',
      [NN, Mesh.ElemCount, N, R.Solve.Method]);
    Result := True;
  finally
    Ch.Free; K0.Free; K.Free;
  end;
end;

function TFEMModel.SolveThermal(out R: TThermalResult): Boolean;
var
  K, K0: TCSRMatrix;
  F, F0, Values, KT: TDoubleArray;
  Fixed: TBoolArrayHelper;
  Ch: TDirectCholesky;
  Direct, AnyFix: Boolean;
  I, E, A, B, L, Fc, N, O, FNn, NN: Integer;
  V, Kc, Tr, Area, PV: Double;
  G: array[0..3] of TVector3;
  H: array of Double;
  Ids: TIntArray;
  M: TFEMMaterial;
begin
  FillChar(R, SizeOf(R), 0);
  NN := Mesh.NodeCount;
  O := Mesh.Order; N := Tab[O].N; FNn := Tab[O].FN;
  SetLength(Fixed, NN); SetLength(Values, NN);
  AnyFix := False;
  for L := 0 to High(Loads) do
    if Loads[L].Kind = flTemperature then
    begin
      Ids := Mesh.NodesOfTag(Loads[L].Tag);
      for I := 0 to High(Ids) do
      begin
        Fixed[Ids[I]] := True;
        Values[Ids[I]] := Loads[L].Value;
        AnyFix := True;
      end;
    end
    else if Loads[L].Kind = flConvection then AnyFix := True;
  if not AnyFix then
  begin
    R.Message := 'Sem temperatura fixa nem conveccao: o problema termico nao tem solucao unica.';
    Exit(False);
  end;
  K := TCSRMatrix.Create; K0 := TCSRMatrix.Create; Ch := TDirectCholesky.Create;
  try
    K.BuildFromMesh(Mesh, 1, TieGroups);
    SetLength(F, NN);
    SetLength(H, N * N * 9);
    for E := 0 to Mesh.ElemCount - 1 do
    begin
      M := Mat(Mesh.Elems[E].Part);
      Kc := M.K;
      ElemGeometry(E, V, G);
      GradProducts(Tab[O], V, G, H);
      for A := 0 to N - 1 do
        for B := 0 to N - 1 do
        begin
          Tr := H[((A * N + B) * 3 + 0) * 3 + 0] + H[((A * N + B) * 3 + 1) * 3 + 1] + H[((A * N + B) * 3 + 2) * 3 + 2];
          K.Add(Mesh.Elems[E].N[A], Mesh.Elems[E].N[B], Kc * Tr);
        end;
      { potencia gerada na peca }
      for L := 0 to High(Loads) do
        if (Loads[L].Kind = flHeatPower) and (Loads[L].Part = Mesh.Elems[E].Part) then
        begin
          PV := Mesh.PartVolume(Loads[L].Part);
          if PV > 0 then
            for A := 0 to N - 1 do
              F[Mesh.Elems[E].N[A]] := F[Mesh.Elems[E].N[A]] + Loads[L].Value / PV * V * Tab[O].Q[A];
        end;
    end;
    for L := 0 to High(Loads) do
      if Loads[L].Kind in [flHeatFlux, flConvection] then
        for Fc := 0 to Mesh.FaceCount - 1 do
        begin
          if Mesh.Faces[Fc].Tag <> Loads[L].Tag then Continue;
          Area := Mesh.FaceArea(Fc);
          for A := 0 to FNn - 1 do
          begin
            if Loads[L].Kind = flHeatFlux then
              F[Mesh.Faces[Fc].N[A]] := F[Mesh.Faces[Fc].N[A]] + Loads[L].Value * Area * Tab[O].FQ[A]
            else
            begin
              F[Mesh.Faces[Fc].N[A]] := F[Mesh.Faces[Fc].N[A]] + Loads[L].Value * Loads[L].Value2 * Area * Tab[O].FQ[A];
              for B := 0 to FNn - 1 do
                K.Add(Mesh.Faces[Fc].N[A], Mesh.Faces[Fc].N[B], Loads[L].Value * Area * Tab[O].FMM[A, B]);
            end;
          end;
        end;
    AddTiePenalty(K, 1);
    K0.CopyPatternFrom(K);
    K0.Val := Copy(K.Val);
    F0 := Copy(F);
    K.ApplyDirichlet(Fixed, Values, F);
    if not Factorize(K, 1, Ch, Direct) then
    begin
      R.Message := Ch.LastError;
      Exit(False);
    end;
    if Direct then
    begin
      Ch.Solve(F, R.T);
      R.Solve.Method := FLastMethod;
      R.Solve.Converged := True;
    end
    else
    begin
      R.Solve := SolvePCG(K, F, R.T, Tolerance, MaxIterations);
      if not R.Solve.Converged then
      begin
        R.Message := Format('PCG nao convergiu (%d iteracoes)', [R.Solve.Iterations]);
        Exit(False);
      end;
    end;
    K0.MulVec(R.T, KT);
    R.HeatIn := 0;
    for I := 0 to NN - 1 do
      if Fixed[I] and (KT[I] - F0[I] > 0) then R.HeatIn := R.HeatIn + KT[I] - F0[I];
    R.MaxT := -MaxDouble; R.MinT := MaxDouble;
    for I := 0 to NN - 1 do
    begin
      R.MaxT := Max(R.MaxT, R.T[I]);
      R.MinT := Min(R.MinT, R.T[I]);
    end;
    R.Ok := True;
    R.Message := Format('Termico permanente: %d nos, %s', [NN, R.Solve.Method]);
    Result := True;
  finally
    Ch.Free; K0.Free; K.Free;
  end;
end;

{ autovalores generalizados densos A z = l B z (B positiva definida):
  Cholesky de B, Jacobi em C = L^-1 A L^-T, z = L^-T y }
procedure DenseGenEig(N: Integer; var A, B: array of Double; out Lam: TDoubleArray; out Z: TDoubleArray);
var
  L, C, Vv: array of Double;
  I, J, K, P, Q, Sweep: Integer;
  S, Th, T, Cs, Sn, Off, Apq, App, Aqq: Double;
  Tmp: Double;
begin
  SetLength(L, N * N); SetLength(C, N * N); SetLength(Vv, N * N);
  Lam := nil; Z := nil;
  SetLength(Lam, N); SetLength(Z, N * N);
  { B = L L^T }
  for I := 0 to N - 1 do
    for J := 0 to I do
    begin
      S := B[I * N + J];
      for K := 0 to J - 1 do S := S - L[I * N + K] * L[J * N + K];
      if I = J then L[I * N + I] := Sqrt(Max(S, 1e-300)) else L[I * N + J] := S / L[J * N + J];
    end;
  { C = L^-1 A L^-T: primeiro W = L^-1 A (por colunas), depois C = W L^-T }
  for J := 0 to N - 1 do
    for I := 0 to N - 1 do
    begin
      S := A[I * N + J];
      for K := 0 to I - 1 do S := S - L[I * N + K] * C[K * N + J];
      C[I * N + J] := S / L[I * N + I];
    end;
  for I := 0 to N - 1 do
    for J := 0 to N - 1 do
    begin
      S := C[I * N + J];
      for K := 0 to J - 1 do S := S - Vv[I * N + K] * L[J * N + K];
      Vv[I * N + J] := S / L[J * N + J];
    end;
  for I := 0 to N * N - 1 do C[I] := Vv[I];
  for I := 0 to N - 1 do
    for J := 0 to N - 1 do
      if I = J then Vv[I * N + J] := 1 else Vv[I * N + J] := 0;
  { Jacobi ciclico }
  for Sweep := 1 to 100 do
  begin
    Off := 0;
    for P := 0 to N - 1 do
      for Q := P + 1 to N - 1 do Off := Off + Sqr(C[P * N + Q]);
    if Off < 1e-30 then Break;
    for P := 0 to N - 2 do
      for Q := P + 1 to N - 1 do
      begin
        Apq := C[P * N + Q];
        if Abs(Apq) < 1e-300 then Continue;
        App := C[P * N + P]; Aqq := C[Q * N + Q];
        Th := (Aqq - App) / (2 * Apq);
        T := Sign(Th) / (Abs(Th) + Sqrt(Th * Th + 1));
        if Th = 0 then T := 1;
        Cs := 1 / Sqrt(T * T + 1); Sn := T * Cs;
        for K := 0 to N - 1 do
        begin
          Tmp := C[K * N + P];
          C[K * N + P] := Cs * Tmp - Sn * C[K * N + Q];
          C[K * N + Q] := Sn * Tmp + Cs * C[K * N + Q];
        end;
        for K := 0 to N - 1 do
        begin
          Tmp := C[P * N + K];
          C[P * N + K] := Cs * Tmp - Sn * C[Q * N + K];
          C[Q * N + K] := Sn * Tmp + Cs * C[Q * N + K];
        end;
        for K := 0 to N - 1 do
        begin
          Tmp := Vv[K * N + P];
          Vv[K * N + P] := Cs * Tmp - Sn * Vv[K * N + Q];
          Vv[K * N + Q] := Sn * Tmp + Cs * Vv[K * N + Q];
        end;
      end;
  end;
  for I := 0 to N - 1 do Lam[I] := C[I * N + I];
  { z = L^-T y (coluna a coluna) }
  for J := 0 to N - 1 do
    for I := N - 1 downto 0 do
    begin
      S := Vv[I * N + J];
      for K := I + 1 to N - 1 do S := S - L[K * N + I] * Z[K * N + J];
      Z[I * N + J] := S / L[I * N + I];
    end;
end;

function TFEMModel.ForceLoadVector: TDoubleArray;
var
  L, Fc, A, D, O, FNn: Integer;
  Area, TotalArea: Double;
  T: TVector3;
begin
  Result := nil;
  SetLength(Result, 3 * Mesh.NodeCount);
  O := Mesh.Order;
  FNn := Tab[O].FN;
  for L := 0 to High(Loads) do
    if Loads[L].Kind = flForce then
    begin
      TotalArea := Mesh.TagArea(Loads[L].Tag);
      if TotalArea <= 0 then Continue;
      T := VScale(Loads[L].Vec, 1 / TotalArea);
      for Fc := 0 to Mesh.FaceCount - 1 do
      begin
        if Mesh.Faces[Fc].Tag <> Loads[L].Tag then Continue;
        Area := Mesh.FaceArea(Fc);
        for A := 0 to FNn - 1 do
          for D := 0 to 2 do
            Result[3 * Mesh.Faces[Fc].N[A] + D] := Result[3 * Mesh.Faces[Fc].N[A] + D] + Comp(T, D) * Area * Tab[O].FQ[A];
      end;
    end;
end;

function TFEMModel.SolveModal(Modes: Integer; out R: TModalResult): Boolean;
var
  K, M, KS: TCSRMatrix;
  Fixed: TBoolArrayHelper;
  Values, Lam, LamOld, Zm, Tmp, Mx: TDoubleArray;
  X, Y, KY, MY: array of TDoubleArray;
  Ch: TDirectCholesky;
  Direct, AnyFix, Conv: Boolean;
  N, Q, I, J, C, It, NFree, Seed: Integer;
  Kr, Mr: array of Double;
  Sigma, S, Rk, Rm: Double;
  Order: array of Integer;
  Info: TSolveInfo;
begin
  FillChar(R, SizeOf(R), 0);
  N := 3 * Mesh.NodeCount;
  FixedDofs(Fixed, Values);
  NFree := 0; AnyFix := False;
  for I := 0 to N - 1 do if Fixed[I] then AnyFix := True else Inc(NFree);
  Modes := Max(1, Min(Modes, NFree - 1));
  Q := Min(NFree, Max(2 * Modes, Modes + 8));
  K := TCSRMatrix.Create; M := TCSRMatrix.Create; KS := TCSRMatrix.Create; Ch := TDirectCholesky.Create;
  try
    K.BuildFromMesh(Mesh, 3, TieGroups);
    AssembleStiffness(K);
    AddTiePenalty(K, 3);
    M.CopyPatternFrom(K);
    AssembleMass(M);
    { graus fixos: K com 1 na diagonal, M nula (modo de frequencia infinita) }
    Tmp := nil; SetLength(Tmp, N);
    K.ApplyDirichlet(Fixed, Values, Tmp);
    M.ZeroFixed(Fixed);
    { modelo livre: desloca o espectro (K + sigma M) }
    Sigma := 0;
    if not AnyFix then
    begin
      Rk := 0; Rm := 0;
      for I := 0 to N - 1 do begin Rk := Rk + K.Get(I, I); Rm := Rm + M.Get(I, I); end;
      Sigma := 1e-4 * Rk / Max(Rm, 1e-300);
    end;
    KS.CopyPatternFrom(K);
    for I := 0 to High(KS.Val) do KS.Val[I] := K.Val[I] + Sigma * M.Val[I];
    if not Factorize(KS, 3, Ch, Direct) then
    begin
      R.Message := Ch.LastError;
      Exit(False);
    end;
    { vetores iniciais deterministicos }
    SetLength(X, Q); SetLength(Y, Q); SetLength(KY, Q); SetLength(MY, Q);
    Seed := 12345;
    for J := 0 to Q - 1 do
    begin
      SetLength(X[J], N);
      for I := 0 to N - 1 do
      begin
        Seed := (Seed * 1103515245 + 12345) and $7FFFFFFF;
        if Fixed[I] then X[J][I] := 0
        else if J = 0 then X[J][I] := 1
        else X[J][I] := Seed / $7FFFFFFF - 0.5;
      end;
    end;
    SetLength(Kr, Q * Q); SetLength(Mr, Q * Q);
    SetLength(LamOld, Q);
    for I := 0 to Q - 1 do LamOld[I] := 0;
    Conv := False;
    for It := 1 to 60 do
    begin
      CheckCancel;
      for J := 0 to Q - 1 do
      begin
        M.MulVec(X[J], Mx);
        if Direct then Ch.Solve(Mx, Y[J])
        else
        begin
          Info := SolvePCG(KS, Mx, Y[J], 1e-10, MaxIterations);
          if not Info.Converged then
          begin
            R.Message := 'PCG nao convergiu no modal';
            Exit(False);
          end;
        end;
        KS.MulVec(Y[J], KY[J]);
        M.MulVec(Y[J], MY[J]);
      end;
      for I := 0 to Q - 1 do
        for J := 0 to Q - 1 do
        begin
          Kr[I * Q + J] := Dot(Y[I], KY[J]);
          Mr[I * Q + J] := Dot(Y[I], MY[J]);
        end;
      { simetriza (arredondamento) }
      for I := 0 to Q - 1 do
        for J := I + 1 to Q - 1 do
        begin
          S := (Kr[I * Q + J] + Kr[J * Q + I]) / 2; Kr[I * Q + J] := S; Kr[J * Q + I] := S;
          S := (Mr[I * Q + J] + Mr[J * Q + I]) / 2; Mr[I * Q + J] := S; Mr[J * Q + I] := S;
        end;
      DenseGenEig(Q, Kr, Mr, Lam, Zm);
      { ordena crescente }
      SetLength(Order, Q);
      for I := 0 to Q - 1 do Order[I] := I;
      for I := 1 to Q - 1 do
      begin
        C := Order[I]; J := I - 1;
        while (J >= 0) and (Lam[Order[J]] > Lam[C]) do begin Order[J + 1] := Order[J]; Dec(J); end;
        Order[J + 1] := C;
      end;
      { X = Y Z }
      for J := 0 to Q - 1 do
      begin
        for I := 0 to N - 1 do X[J][I] := 0;
        for C := 0 to Q - 1 do
        begin
          S := Zm[C * Q + Order[J]];
          if S <> 0 then
            for I := 0 to N - 1 do X[J][I] := X[J][I] + S * Y[C][I];
        end;
      end;
      Conv := True;
      for I := 0 to Modes - 1 do
      begin
        if Abs(Lam[Order[I]] - LamOld[I]) > 1e-7 * Max(Abs(Lam[Order[I]]), 1e-300) then Conv := False;
        LamOld[I] := Lam[Order[I]];
      end;
      for I := Modes to Q - 1 do LamOld[I] := Lam[Order[I]];
      R.Iterations := It;
      if Conv and (It > 1) then Break;
    end;
    SetLength(R.Freq, Modes);
    SetLength(R.Shapes, Modes);
    SetLength(R.EffMass, Modes);
    for I := 0 to Modes - 1 do
    begin
      S := LamOld[I] - Sigma;
      if S < 0 then S := 0;
      R.Freq[I] := Sqrt(S) / (2 * Pi);
      R.Shapes[I] := Copy(X[I]);
    end;
    { massa efetiva: Gamma = phi^T M r (r = translacao unitaria na direcao),
      fracao = Gamma^2 / (r^T M r); phi normalizado pela massa }
    SetLength(Tmp, N);
    for C := 0 to 2 do
    begin
      for I := 0 to N - 1 do
        if I mod 3 = C then Tmp[I] := 1 else Tmp[I] := 0;
      M.MulVec(Tmp, Mx);
      Rm := Dot(Tmp, Mx);
      if C = 0 then R.TotalMass := Rm;
      for I := 0 to Modes - 1 do
        if Rm > 0 then R.EffMass[I][C] := Sqr(Dot(R.Shapes[I], Mx)) / Rm else R.EffMass[I][C] := 0;
    end;
    R.Ok := True;
    if Conv then
      R.Message := Format('Modal: %d modos em %d iteracoes de subespaco', [Modes, R.Iterations])
    else
      R.Message := Format('Modal: %d modos, iteracao de subespaco nao convergiu totalmente', [Modes]);
    Result := True;
  finally
    Ch.Free; KS.Free; M.Free; K.Free;
  end;
end;

end.
