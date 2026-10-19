unit multiphysics_sparse;

{ Algebra esparsa do FEM.

  TCSRMatrix: matriz simetrica guardada inteira em CSR (linhas com colunas
  ordenadas), padrao montado pela conectividade da malha com BlockSize graus
  de liberdade por no (3 = elastico, 1 = termico).

  Solvers:
  - SolvePCG: gradiente conjugado com precondicionador Jacobi;
  - TSkylineCholesky: Cholesky em perfil (envelope) apos reordenacao RCM dos
    nos; fatora uma vez e resolve muitas vezes (modal). Usado quando o
    envelope cabe na memoria (EnvelopeSize). }

{$mode objfpc}{$H+}
{ laços numericos pesados: otimiza mesmo quando o projeto compila com -O1 }
{$OPTIMIZATION LEVEL3}

interface

uses
  SysUtils, Math, multiphysics_vector, multiphysics_mesh;

type
  TDoubleArray = array of Double;
  TIntGroups = array of TIntArray;

  TCSRMatrix = class
  public
    N: Integer;
    RowPtr: array of Integer;
    Col: array of Integer;
    Val: TDoubleArray;
    { padrao pela malha: nos que dividem um elemento ficam acoplados }
    { Groups: conjuntos extras de nos totalmente acoplados (amarracoes) }
    procedure BuildFromMesh(M: TFEMMesh; BlockSize: Integer); overload;
    procedure BuildFromMesh(M: TFEMMesh; BlockSize: Integer; const Groups: TIntGroups); overload;
    procedure CopyPatternFrom(Src: TCSRMatrix);
    procedure Zero;
    function Find(I, J: Integer): Integer;   { -1 se fora do padrao }
    procedure Add(I, J: Integer; V: Double); inline;
    function Get(I, J: Integer): Double;
    procedure MulVec(const X: TDoubleArray; var Y: TDoubleArray);
    function Diagonal: TDoubleArray;
    { Dirichlet simetrico: linha e coluna zeradas, diagonal 1, RHS ajustado.
      Fixed[i] = True fixa o grau i no valor Values[i]. }
    procedure ApplyDirichlet(const Fixed: array of Boolean; const Values: TDoubleArray;
      var RHS: TDoubleArray);
    { zera linha e coluna dos graus fixos (usada na massa do modal) }
    procedure ZeroFixed(const Fixed: array of Boolean);
    function NonZeros: Integer;
  end;

  TSolveInfo = record
    Iterations: Integer;
    Residual: Double;
    Converged: Boolean;
    Method: string;
  end;

  { Cholesky esparso (algoritmo "up-looking" com arvore de eliminacao, como
    o cs_chol do CSparse) com ordenacao por disseccao aninhada geometrica dos
    nos (bissecao pela mediana do eixo mais longo; separadores por ultimo).
    Muito menos preenchimento que o perfil em pecas 3D compactas. }
  TSparseCholesky = class
  private
    FN: Integer;
    FPerm, FInv: TIntArray;          { FPerm[novo] = antigo }
    FLp: array of Int64;
    FLi: TIntArray;
    FLx: TDoubleArray;
    FError: string;
    FNnzL: Int64;
    FTooBig: Boolean;
    FBlock: Integer;
    FFlops: Double;
    FCp, FCi, FParent, FCnt: TIntArray;
    FCx: TDoubleArray;
  public
    MaxNonZeros: Int64;              { limite de memoria do fator (0 = sem limite) }
    { simbolico: ordem, arvore e contagem por coluna; Flops estima o custo }
    function Analyze(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): Boolean;
    function Numeric: Boolean;
    { Coords: coordenadas dos nos (BlockSize graus por no) }
    function Factor(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): Boolean;
    property Flops: Double read FFlops;
    procedure Solve(const B: TDoubleArray; var X: TDoubleArray);
    property LastError: string read FError;
    property NonZerosL: Int64 read FNnzL;
    property TooBig: Boolean read FTooBig;
  end;

  TSkylineCholesky = class
  private
    FN: Integer;
    FPerm, FInv: array of Integer;   { FPerm[novo] = antigo }
    FFirst: array of Integer;        { primeira coluna da linha (permutada) }
    FStart: array of Int64;          { inicio da linha no vetor FL }
    FL: TDoubleArray;
    FError: string;
  public
    { tamanho do envelope (numero de valores) para a matriz reordenada }
    class function EnvelopeSize(A: TCSRMatrix; BlockSize: Integer): Int64;
    { custo estimado da fatoracao (soma dos quadrados das linhas do perfil) }
    class function ProfileFlops(A: TCSRMatrix; BlockSize: Integer): Double;
    function Factor(A: TCSRMatrix; BlockSize: Integer): Boolean;
    procedure Solve(const B: TDoubleArray; var X: TDoubleArray);
    property LastError: string read FError;
  end;

type
  { Cholesky direto: escolhe a ordem de menor custo (perfil com RCM ou
    esparso com disseccao aninhada) pelo calculo simbolico das duas }
  TDirectCholesky = class
  private
    FSky: TSkylineCholesky;
    FSp: TSparseCholesky;
    FUseSparse, FTooBig: Boolean;
    FError, FMethod: string;
  public
    MaxNonZeros: Int64;
    MaxFlops: Double;         { acima disso o direto nao compensa (0 = sem limite) }
    Flops: Double;            { custo estimado da ordem escolhida }
    destructor Destroy; override;
    function Factor(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): Boolean;
    procedure Solve(const B: TDoubleArray; var X: TDoubleArray);
    property LastError: string read FError;
    property TooBig: Boolean read FTooBig;
    property Method: string read FMethod;
  end;

function SolvePCG(A: TCSRMatrix; const B: TDoubleArray; var X: TDoubleArray;
  Tol: Double; MaxIter: Integer): TSolveInfo;
{ cancelamento cooperativo (resolucao em segundo plano): os laços longos
  chamam CheckCancel, que levanta EAbort quando FEMCancelRequested = True }
procedure CheckCancel;
function Dot(const A, B: TDoubleArray): Double;
{ ordem RCM dos nos (Cuthill-McKee reverso) pelo padrao em blocos }
function RCMOrder(A: TCSRMatrix; BlockSize: Integer): TIntArray;
{ ordem dos nos por disseccao aninhada geometrica }
function NestedDissectionOrder(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): TIntArray;

var
  FEMCancelRequested: Boolean = False;

implementation

procedure CheckCancel;
begin
  if FEMCancelRequested then raise EAbort.Create('Calculo cancelado pelo usuario');
end;

function Dot(const A, B: TDoubleArray): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(A) do Result := Result + A[I] * B[I];
end;

procedure SortInt64(var K: array of Int64; L, R: Integer);
var
  P, Q: Integer;
  Pv, T: Int64;
begin
  while L < R do
  begin
    Pv := K[(L + R) shr 1]; P := L; Q := R;
    repeat
      while K[P] < Pv do Inc(P);
      while Pv < K[Q] do Dec(Q);
      if P <= Q then
      begin
        T := K[P]; K[P] := K[Q]; K[Q] := T;
        Inc(P); Dec(Q);
      end;
    until P > Q;
    if Q - L < R - P then begin SortInt64(K, L, Q); L := P; end
    else begin SortInt64(K, P, R); R := Q; end;
  end;
end;

{ ---------------- TCSRMatrix ---------------- }

procedure TCSRMatrix.BuildFromMesh(M: TFEMMesh; BlockSize: Integer);
begin
  BuildFromMesh(M, BlockSize, nil);
end;

procedure TCSRMatrix.BuildFromMesh(M: TFEMMesh; BlockSize: Integer; const Groups: TIntGroups);
var
  G, GA, GB, Extra: Integer;
  Keys: array of Int64;
  NPE, E, A, B, NK, U, I, NN, Row, Cnt, Node, Nb, D, D2: Integer;
  NodeStart, NodeAdj: array of Integer;
  Key: Int64;
begin
  NPE := M.NodesPerElement;
  NN := M.NodeCount;
  Extra := 0;
  for G := 0 to High(Groups) do Extra := Extra + Sqr(Length(Groups[G]));
  SetLength(Keys, Int64(M.ElemCount) * NPE * NPE + Extra);
  NK := 0;
  for G := 0 to High(Groups) do
    for GA := 0 to High(Groups[G]) do
      for GB := 0 to High(Groups[G]) do
      begin
        Keys[NK] := Int64(Groups[G][GA]) * NN + Groups[G][GB];
        Inc(NK);
      end;
  for E := 0 to M.ElemCount - 1 do
    for A := 0 to NPE - 1 do
      for B := 0 to NPE - 1 do
      begin
        Keys[NK] := Int64(M.Elems[E].N[A]) * NN + M.Elems[E].N[B];
        Inc(NK);
      end;
  { nos soltos (sem elemento) ainda ganham a diagonal }
  SetLength(Keys, NK + NN);
  for I := 0 to NN - 1 do
  begin
    Keys[NK] := Int64(I) * NN + I;
    Inc(NK);
  end;
  if NK > 1 then SortInt64(Keys, 0, NK - 1);
  U := 0;
  for I := 0 to NK - 1 do
    if (U = 0) or (Keys[I] <> Keys[U - 1]) then
    begin
      Keys[U] := Keys[I];
      Inc(U);
    end;
  { adjacencia por no }
  SetLength(NodeStart, NN + 1);
  SetLength(NodeAdj, U);
  for I := 0 to U - 1 do
  begin
    Key := Keys[I];
    NodeAdj[I] := Key mod NN;
    Inc(NodeStart[Key div NN + 1]);
  end;
  for I := 0 to NN - 1 do NodeStart[I + 1] := NodeStart[I + 1] + NodeStart[I];
  Keys := nil;
  { expande em blocos }
  N := NN * BlockSize;
  SetLength(RowPtr, N + 1);
  SetLength(Col, Int64(U) * BlockSize * BlockSize);
  Cnt := 0;
  for Node := 0 to NN - 1 do
    for D := 0 to BlockSize - 1 do
    begin
      Row := Node * BlockSize + D;
      RowPtr[Row] := Cnt;
      for I := NodeStart[Node] to NodeStart[Node + 1] - 1 do
      begin
        Nb := NodeAdj[I];
        for D2 := 0 to BlockSize - 1 do
        begin
          Col[Cnt] := Nb * BlockSize + D2;
          Inc(Cnt);
        end;
      end;
    end;
  RowPtr[N] := Cnt;
  SetLength(Val, Cnt);
end;

procedure TCSRMatrix.CopyPatternFrom(Src: TCSRMatrix);
begin
  N := Src.N;
  RowPtr := Copy(Src.RowPtr);
  Col := Copy(Src.Col);
  SetLength(Val, Length(Col));
  Zero;
end;

procedure TCSRMatrix.Zero;
var
  I: Integer;
begin
  for I := 0 to High(Val) do Val[I] := 0;
end;

function TCSRMatrix.Find(I, J: Integer): Integer;
var
  Lo, Hi, M: Integer;
begin
  Lo := RowPtr[I]; Hi := RowPtr[I + 1] - 1;
  while Lo <= Hi do
  begin
    M := (Lo + Hi) shr 1;
    if Col[M] < J then Lo := M + 1
    else if Col[M] > J then Hi := M - 1
    else Exit(M);
  end;
  Result := -1;
end;

procedure TCSRMatrix.Add(I, J: Integer; V: Double);
var
  P: Integer;
begin
  P := Find(I, J);
  if P >= 0 then Val[P] := Val[P] + V;
end;

function TCSRMatrix.Get(I, J: Integer): Double;
var
  P: Integer;
begin
  P := Find(I, J);
  if P >= 0 then Result := Val[P] else Result := 0;
end;

procedure TCSRMatrix.MulVec(const X: TDoubleArray; var Y: TDoubleArray);
var
  I, P: Integer;
  S: Double;
begin
  if Length(Y) <> N then SetLength(Y, N);
  for I := 0 to N - 1 do
  begin
    S := 0;
    for P := RowPtr[I] to RowPtr[I + 1] - 1 do S := S + Val[P] * X[Col[P]];
    Y[I] := S;
  end;
end;

function TCSRMatrix.Diagonal: TDoubleArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do Result[I] := Get(I, I);
end;

{ a linha fixa mantem a propria rigidez na diagonal (em vez de 1): o pivo
  fica na escala da matriz, o que importa com penalidades grandes }
procedure TCSRMatrix.ApplyDirichlet(const Fixed: array of Boolean; const Values: TDoubleArray;
  var RHS: TDoubleArray);
var
  I, P, J: Integer;
  Dg: TDoubleArray;
begin
  Dg := Diagonal;
  for I := 0 to N - 1 do
    if Dg[I] <= 0 then Dg[I] := 1;
  for I := 0 to N - 1 do
    for P := RowPtr[I] to RowPtr[I + 1] - 1 do
    begin
      J := Col[P];
      if Fixed[I] then
      begin
        if J = I then Val[P] := Dg[I] else Val[P] := 0;
      end
      else if Fixed[J] then
      begin
        RHS[I] := RHS[I] - Val[P] * Values[J];
        Val[P] := 0;
      end;
    end;
  for I := 0 to N - 1 do
    if Fixed[I] then RHS[I] := Dg[I] * Values[I];
end;

procedure TCSRMatrix.ZeroFixed(const Fixed: array of Boolean);
var
  I, P: Integer;
begin
  for I := 0 to N - 1 do
    for P := RowPtr[I] to RowPtr[I + 1] - 1 do
      if Fixed[I] or Fixed[Col[P]] then Val[P] := 0;
end;

function TCSRMatrix.NonZeros: Integer;
begin
  Result := Length(Val);
end;

{ ---------------- PCG ---------------- }

function SolvePCG(A: TCSRMatrix; const B: TDoubleArray; var X: TDoubleArray;
  Tol: Double; MaxIter: Integer): TSolveInfo;
var
  N, I, K: Integer;
  R, Z, P, Q, Dg: TDoubleArray;
  Rz, RzOld, Alpha, Beta, BNorm, RNorm: Double;
begin
  N := A.N;
  Result.Method := 'PCG/Jacobi';
  Result.Iterations := 0; Result.Converged := False; Result.Residual := 0;
  if Length(X) <> N then
  begin
    SetLength(X, N);
    for I := 0 to N - 1 do X[I] := 0;
  end;
  Dg := A.Diagonal;
  for I := 0 to N - 1 do
    if Dg[I] <> 0 then Dg[I] := 1 / Dg[I] else Dg[I] := 1;
  SetLength(R, N); SetLength(Z, N); SetLength(P, N); SetLength(Q, N);
  A.MulVec(X, Q);
  for I := 0 to N - 1 do R[I] := B[I] - Q[I];
  BNorm := Sqrt(Dot(B, B));
  if BNorm = 0 then
  begin
    for I := 0 to N - 1 do X[I] := 0;
    Result.Converged := True;
    Exit;
  end;
  for I := 0 to N - 1 do Z[I] := Dg[I] * R[I];
  P := Copy(Z);
  Rz := Dot(R, Z);
  for K := 1 to MaxIter do
  begin
    if K and 63 = 0 then CheckCancel;
    A.MulVec(P, Q);
    Alpha := Dot(P, Q);
    if Alpha <= 0 then Break;     { matriz nao positiva definida }
    Alpha := Rz / Alpha;
    for I := 0 to N - 1 do
    begin
      X[I] := X[I] + Alpha * P[I];
      R[I] := R[I] - Alpha * Q[I];
    end;
    RNorm := Sqrt(Dot(R, R));
    Result.Iterations := K;
    Result.Residual := RNorm / BNorm;
    if Result.Residual < Tol then
    begin
      Result.Converged := True;
      Exit;
    end;
    for I := 0 to N - 1 do Z[I] := Dg[I] * R[I];
    RzOld := Rz;
    Rz := Dot(R, Z);
    Beta := Rz / RzOld;
    for I := 0 to N - 1 do P[I] := Z[I] + Beta * P[I];
  end;
end;

{ ---------------- RCM ---------------- }

function RCMOrder(A: TCSRMatrix; BlockSize: Integer): TIntArray;
var
  NN, I, P, Head, Tail, Node, Nb, Start, Best, J, K, T, Pass, Stamp, Last, Q0: Integer;
  Deg, Seen: array of Integer;
  Visited: array of Boolean;
  Queue, Tmp: array of Integer;
  Nbrs: array of Integer;

  { BFS a partir de S (sem marcar Visited); devolve o no de menor grau do
    ultimo nivel: o candidato a no pseudo-periferico }
  function Farthest(S: Integer): Integer;
  var
    H, Tl, U, V, PP, LevelStart, Lvl: Integer;
  begin
    Inc(Stamp);
    H := 0; Tl := 0;
    Tmp[Tl] := S; Inc(Tl); Seen[S] := Stamp;
    LevelStart := 0; Lvl := Tl;
    while H < Tl do
    begin
      if H = Lvl then begin LevelStart := H; Lvl := Tl; end;
      U := Tmp[H]; Inc(H);
      PP := A.RowPtr[U * BlockSize];
      while PP < A.RowPtr[U * BlockSize + 1] do
      begin
        V := A.Col[PP] div BlockSize;
        if (Seen[V] <> Stamp) and not Visited[V] then
        begin
          Seen[V] := Stamp;
          Tmp[Tl] := V; Inc(Tl);
        end;
        Inc(PP, BlockSize);
      end;
    end;
    Result := Tmp[LevelStart];
    for U := LevelStart to Tl - 1 do
      if Deg[Tmp[U]] < Deg[Result] then Result := Tmp[U];
  end;

begin
  NN := A.N div BlockSize;
  Result := nil;
  SetLength(Deg, NN);
  for I := 0 to NN - 1 do
    Deg[I] := (A.RowPtr[I * BlockSize + 1] - A.RowPtr[I * BlockSize]) div BlockSize;
  SetLength(Visited, NN);
  SetLength(Seen, NN);
  SetLength(Queue, NN);
  SetLength(Tmp, NN);
  Stamp := 0;
  Tail := 0;
  Q0 := 0;
  while Tail < NN do
  begin
    { novo componente: comeca no no livre de menor grau e anda para a periferia }
    Start := -1; Best := MaxInt;
    while (Q0 < NN) and Visited[Q0] do Inc(Q0);
    for I := Q0 to NN - 1 do
      if not Visited[I] and (Deg[I] < Best) then begin Best := Deg[I]; Start := I; end;
    for Pass := 1 to 2 do
    begin
      Last := Farthest(Start);
      if Last = Start then Break;
      Start := Last;
    end;
    Head := Tail;
    Queue[Tail] := Start; Inc(Tail); Visited[Start] := True;
    while Head < Tail do
    begin
      Node := Queue[Head]; Inc(Head);
      { vizinhos ainda livres em ordem crescente de grau }
      Nbrs := nil;
      P := A.RowPtr[Node * BlockSize];
      while P < A.RowPtr[Node * BlockSize + 1] do
      begin
        Nb := A.Col[P] div BlockSize;
        if not Visited[Nb] then
        begin
          Visited[Nb] := True;
          SetLength(Nbrs, Length(Nbrs) + 1);
          Nbrs[High(Nbrs)] := Nb;
        end;
        Inc(P, BlockSize);
      end;
      for J := 1 to High(Nbrs) do
      begin
        T := Nbrs[J]; K := J - 1;
        while (K >= 0) and ((Deg[Nbrs[K]] > Deg[T]) or ((Deg[Nbrs[K]] = Deg[T]) and (Nbrs[K] > T))) do
        begin
          Nbrs[K + 1] := Nbrs[K];
          Dec(K);
        end;
        Nbrs[K + 1] := T;
      end;
      for J := 0 to High(Nbrs) do
      begin
        Queue[Tail] := Nbrs[J];
        Inc(Tail);
      end;
    end;
  end;
  SetLength(Result, NN);
  for I := 0 to NN - 1 do Result[I] := Queue[NN - 1 - I];
end;

{ ---------------- disseccao aninhada ---------------- }

function NestedDissectionOrder(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): TIntArray;
var
  NN, Outp: Integer;
  Side: array of ShortInt;     { 0 = livre, 1 = esquerda, 2 = direita }
  Work: TIntArray;
  Res: TIntArray;

  function Comp(const V: TVector3; Ax: Integer): Double; inline;
  begin
    case Ax of
      0: Result := V.X;
      1: Result := V.Y;
      else Result := V.Z;
    end;
  end;

  procedure SelectK(var Arr: TIntArray; L, R, K, Ax: Integer);
  var
    I, J, T: Integer;
    Pv: Double;
  begin
    while L < R do
    begin
      Pv := Comp(Coords[Arr[(L + R) shr 1]], Ax);
      I := L; J := R;
      repeat
        while Comp(Coords[Arr[I]], Ax) < Pv do Inc(I);
        while Pv < Comp(Coords[Arr[J]], Ax) do Dec(J);
        if I <= J then
        begin
          T := Arr[I]; Arr[I] := Arr[J]; Arr[J] := T;
          Inc(I); Dec(J);
        end;
      until I > J;
      if J < K then L := I;
      if K < I then R := J;
    end;
  end;

  procedure Emit(const Nodes: TIntArray);
  var
    I: Integer;
  begin
    for I := 0 to High(Nodes) do
    begin
      Res[Outp] := Nodes[I];
      Inc(Outp);
    end;
  end;

  procedure Dissect(Nodes: TIntArray);
  var
    N, I, P, Ax, Mid, NL, NR, NS, Nb: Integer;
    Lo, Hi: TVector3;
    Lft, Rgt, Sep: TIntArray;
    HasRight: Boolean;
  begin
    N := Length(Nodes);
    if N = 0 then Exit;
    if N <= 48 then
    begin
      Emit(Nodes);
      Exit;
    end;
    Lo := Coords[Nodes[0]]; Hi := Lo;
    for I := 1 to N - 1 do
    begin
      Lo := V3(Min(Lo.X, Coords[Nodes[I]].X), Min(Lo.Y, Coords[Nodes[I]].Y), Min(Lo.Z, Coords[Nodes[I]].Z));
      Hi := V3(Max(Hi.X, Coords[Nodes[I]].X), Max(Hi.Y, Coords[Nodes[I]].Y), Max(Hi.Z, Coords[Nodes[I]].Z));
    end;
    if (Hi.X - Lo.X >= Hi.Y - Lo.Y) and (Hi.X - Lo.X >= Hi.Z - Lo.Z) then Ax := 0
    else if Hi.Y - Lo.Y >= Hi.Z - Lo.Z then Ax := 1 else Ax := 2;
    Mid := N div 2;
    SelectK(Nodes, 0, N - 1, Mid, Ax);
    for I := 0 to N - 1 do
      if I < Mid then Side[Nodes[I]] := 1 else Side[Nodes[I]] := 2;
    { separador: nos da esquerda com vizinho na direita }
    SetLength(Lft, N); SetLength(Rgt, N); SetLength(Sep, N);
    NL := 0; NR := 0; NS := 0;
    for I := 0 to N - 1 do
      if Side[Nodes[I]] = 1 then
      begin
        HasRight := False;
        P := A.RowPtr[Nodes[I] * BlockSize];
        while P < A.RowPtr[Nodes[I] * BlockSize + 1] do
        begin
          Nb := A.Col[P] div BlockSize;
          if Side[Nb] = 2 then begin HasRight := True; Break; end;
          Inc(P, BlockSize);
        end;
        if HasRight then begin Sep[NS] := Nodes[I]; Inc(NS); end
        else begin Lft[NL] := Nodes[I]; Inc(NL); end;
      end
      else
      begin
        Rgt[NR] := Nodes[I];
        Inc(NR);
      end;
    for I := 0 to N - 1 do Side[Nodes[I]] := 0;
    SetLength(Lft, NL); SetLength(Rgt, NR); SetLength(Sep, NS);
    if (NL = 0) or (NR = 0) then
    begin
      Emit(Nodes);    { particao degenerada: ordena como esta }
      Exit;
    end;
    Dissect(Lft);
    Dissect(Rgt);
    Emit(Sep);
  end;

var
  I: Integer;
begin
  NN := A.N div BlockSize;
  Res := nil;
  SetLength(Res, NN);
  SetLength(Side, NN);
  SetLength(Work, NN);
  for I := 0 to NN - 1 do Work[I] := I;
  Outp := 0;
  Dissect(Work);
  Result := Res;
end;

{ ---------------- Cholesky esparso ---------------- }

function TSparseCholesky.Analyze(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): Boolean;
var
  NodeOrd: TIntArray;
  N, NN, I, D, K, P, R, C, J: Integer;
  Ancestor, Flag, Nxt: TIntArray;
begin
  FError := '';
  FBlock := BlockSize;
  N := A.N;
  FN := N;
  NN := N div BlockSize;
  if Length(Coords) >= NN then NodeOrd := NestedDissectionOrder(A, BlockSize, Coords)
  else NodeOrd := RCMOrder(A, BlockSize);
  SetLength(FPerm, N); SetLength(FInv, N);
  for I := 0 to NN - 1 do
    for D := 0 to BlockSize - 1 do
    begin
      FPerm[I * BlockSize + D] := NodeOrd[I] * BlockSize + D;
      FInv[NodeOrd[I] * BlockSize + D] := I * BlockSize + D;
    end;
  { parte superior de C = P A P^T, por colunas }
  FCp := nil;
  SetLength(FCp, N + 1);
  for R := 0 to N - 1 do
    for P := A.RowPtr[R] to A.RowPtr[R + 1] - 1 do
      if FInv[R] <= FInv[A.Col[P]] then Inc(FCp[FInv[A.Col[P]] + 1]);
  for J := 0 to N - 1 do FCp[J + 1] := FCp[J + 1] + FCp[J];
  SetLength(FCi, FCp[N]); SetLength(FCx, FCp[N]);
  SetLength(Nxt, N);
  for J := 0 to N - 1 do Nxt[J] := FCp[J];
  for R := 0 to N - 1 do
    for P := A.RowPtr[R] to A.RowPtr[R + 1] - 1 do
    begin
      I := FInv[R]; C := FInv[A.Col[P]];
      if I <= C then
      begin
        FCi[Nxt[C]] := I;
        FCx[Nxt[C]] := A.Val[P];
        Inc(Nxt[C]);
      end;
    end;
  { arvore de eliminacao (com compressao de caminho) }
  SetLength(FParent, N); SetLength(Ancestor, N);
  for K := 0 to N - 1 do
  begin
    FParent[K] := -1; Ancestor[K] := -1;
    for P := FCp[K] to FCp[K + 1] - 1 do
    begin
      I := FCi[P];
      while (I <> -1) and (I < K) do
      begin
        J := Ancestor[I];
        Ancestor[I] := K;
        if J = -1 then begin FParent[I] := K; Break; end;
        I := J;
      end;
    end;
  end;
  { cada linha k de L alcanca, pela arvore, as colunas do seu padrao }
  SetLength(Flag, N);
  FCnt := nil;
  SetLength(FCnt, N);
  for K := 0 to N - 1 do Flag[K] := -1;
  for K := 0 to N - 1 do
  begin
    Flag[K] := K;
    Inc(FCnt[K]);
    for P := FCp[K] to FCp[K + 1] - 1 do
    begin
      I := FCi[P];
      while (I < K) and (Flag[I] <> K) do
      begin
        Inc(FCnt[I]);
        Flag[I] := K;
        I := FParent[I];
      end;
    end;
  end;
  SetLength(FLp, N + 1);
  FLp[0] := 0;
  FFlops := 0;
  for K := 0 to N - 1 do
  begin
    FLp[K + 1] := FLp[K] + FCnt[K];
    FFlops := FFlops + Sqr(Double(FCnt[K]));
  end;
  FNnzL := FLp[N];
  FTooBig := (MaxNonZeros > 0) and (FNnzL > MaxNonZeros);
  if FTooBig then FError := Format('Fator com %d valores passa do limite de memoria', [FNnzL]);
  Result := not FTooBig;
end;

function TSparseCholesky.Numeric: Boolean;
var
  N, I, K, P, Top, Len, J: Integer;
  Flag, Stack, Cnt, Pattern: TIntArray;
  X: TDoubleArray;
  Q: Int64;
  Dk, Lki, D0: Double;
begin
  N := FN;
  SetLength(FLi, FNnzL); SetLength(FLx, FNnzL);
  SetLength(X, N); SetLength(Flag, N); SetLength(Stack, N); SetLength(Cnt, N); SetLength(Pattern, N);
  for K := 0 to N - 1 do begin Cnt[K] := 0; Flag[K] := -1; end;
  for K := 0 to N - 1 do
  begin
    if K and 255 = 0 then CheckCancel;
    Top := N;
    Flag[K] := K;
    for P := FCp[K] to FCp[K + 1] - 1 do
    begin
      I := FCi[P];
      X[I] := X[I] + FCx[P];
      if I = K then Continue;
      Len := 0;
      while Flag[I] <> K do
      begin
        Stack[Len] := I;
        Inc(Len);
        Flag[I] := K;
        I := FParent[I];
      end;
      while Len > 0 do
      begin
        Dec(Top); Dec(Len);
        Pattern[Top] := Stack[Len];
      end;
    end;
    D0 := X[K];
    Dk := X[K];
    X[K] := 0;
    for J := Top to N - 1 do
    begin
      I := Pattern[J];
      Lki := X[I] / FLx[FLp[I]];
      X[I] := 0;
      Q := FLp[I] + 1;
      while Q < FLp[I] + Cnt[I] do
      begin
        X[FLi[Q]] := X[FLi[Q]] - FLx[Q] * Lki;
        Inc(Q);
      end;
      Dk := Dk - Lki * Lki;
      Q := FLp[I] + Cnt[I];
      FLi[Q] := K;
      FLx[Q] := Lki;
      Inc(Cnt[I]);
    end;
    if (Dk <= 1e-12 * Abs(D0)) or (Dk <= 1e-300) then
    begin
      FError := Format('Pivo nao positivo no grau %d (no %d): estrutura sem fixacao suficiente (movimento livre) ou material invalido',
        [FPerm[K], FPerm[K] div FBlock]);
      Exit(False);
    end;
    Q := FLp[K];
    FLi[Q] := K;
    FLx[Q] := Sqrt(Dk);
    Cnt[K] := 1;
  end;
  FCx := nil; FCi := nil;
  Result := True;
end;

function TSparseCholesky.Factor(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): Boolean;
begin
  Result := Analyze(A, BlockSize, Coords) and Numeric;
end;

procedure TSparseCholesky.Solve(const B: TDoubleArray; var X: TDoubleArray);
var
  Y: TDoubleArray;
  J: Integer;
  Q: Int64;
  S: Double;
begin
  SetLength(Y, FN);
  for J := 0 to FN - 1 do Y[J] := B[FPerm[J]];
  { L y = b (por colunas) }
  for J := 0 to FN - 1 do
  begin
    Y[J] := Y[J] / FLx[FLp[J]];
    for Q := FLp[J] + 1 to FLp[J + 1] - 1 do Y[FLi[Q]] := Y[FLi[Q]] - FLx[Q] * Y[J];
  end;
  { L^T x = y }
  for J := FN - 1 downto 0 do
  begin
    S := Y[J];
    for Q := FLp[J] + 1 to FLp[J + 1] - 1 do S := S - FLx[Q] * Y[FLi[Q]];
    Y[J] := S / FLx[FLp[J]];
  end;
  if Length(X) <> FN then SetLength(X, FN);
  for J := 0 to FN - 1 do X[FPerm[J]] := Y[J];
end;

{ ---------------- escolha do direto ---------------- }

destructor TDirectCholesky.Destroy;
begin
  FSky.Free;
  FSp.Free;
  inherited Destroy;
end;

function TDirectCholesky.Factor(A: TCSRMatrix; BlockSize: Integer; const Coords: array of TVector3): Boolean;
var
  SkyFlops: Double;
  Env: Int64;
begin
  FreeAndNil(FSky); FreeAndNil(FSp);
  FError := ''; FTooBig := False;
  Env := TSkylineCholesky.EnvelopeSize(A, BlockSize);
  SkyFlops := TSkylineCholesky.ProfileFlops(A, BlockSize);
  FSp := TSparseCholesky.Create;
  FSp.MaxNonZeros := MaxNonZeros;
  FSp.Analyze(A, BlockSize, Coords);
  FUseSparse := (FSp.Flops < SkyFlops) and not FSp.TooBig;
  if FUseSparse then Flops := FSp.Flops else Flops := SkyFlops;
  { o PCG resolve blocos 3D compactos muito mais rapido que um fator caro }
  if (MaxFlops > 0) and (Flops > MaxFlops) then
  begin
    FreeAndNil(FSp);
    FTooBig := True;
    FError := Format('Fator direto caro demais (%.2g operacoes)', [Flops]);
    Exit(False);
  end;
  if not FUseSparse then
  begin
    FreeAndNil(FSp);
    if (MaxNonZeros > 0) and (Env > MaxNonZeros) then
    begin
      FTooBig := True;
      FError := 'Fator direto grande demais para a memoria';
      Exit(False);
    end;
    FSky := TSkylineCholesky.Create;
    FMethod := 'Cholesky em perfil (RCM)';
    Result := FSky.Factor(A, BlockSize);
    if not Result then FError := FSky.LastError;
  end
  else
  begin
    FMethod := 'Cholesky esparso (disseccao aninhada)';
    Result := FSp.Numeric;
    if not Result then FError := FSp.LastError;
  end;
end;

procedure TDirectCholesky.Solve(const B: TDoubleArray; var X: TDoubleArray);
begin
  if FUseSparse then FSp.Solve(B, X) else FSky.Solve(B, X);
end;

{ ---------------- Skyline Cholesky ---------------- }

procedure BuildProfile(A: TCSRMatrix; BlockSize: Integer; out Perm, Inv, First: TIntArray);
var
  NodeOrd: TIntArray;
  NN, I, D, Row, P, C: Integer;
begin
  NodeOrd := RCMOrder(A, BlockSize);
  NN := Length(NodeOrd);
  Perm := nil; Inv := nil; First := nil;
  SetLength(Perm, A.N); SetLength(Inv, A.N); SetLength(First, A.N);
  for I := 0 to NN - 1 do
    for D := 0 to BlockSize - 1 do
    begin
      Perm[I * BlockSize + D] := NodeOrd[I] * BlockSize + D;
      Inv[NodeOrd[I] * BlockSize + D] := I * BlockSize + D;
    end;
  for I := 0 to A.N - 1 do
  begin
    Row := Perm[I];
    First[I] := I;
    for P := A.RowPtr[Row] to A.RowPtr[Row + 1] - 1 do
    begin
      C := Inv[A.Col[P]];
      if C < First[I] then First[I] := C;
    end;
  end;
end;

class function TSkylineCholesky.EnvelopeSize(A: TCSRMatrix; BlockSize: Integer): Int64;
var
  Perm, Inv, First: TIntArray;
  I: Integer;
begin
  BuildProfile(A, BlockSize, Perm, Inv, First);
  Result := 0;
  for I := 0 to A.N - 1 do Result := Result + (I - First[I] + 1);
end;

class function TSkylineCholesky.ProfileFlops(A: TCSRMatrix; BlockSize: Integer): Double;
var
  Perm, Inv, First: TIntArray;
  I: Integer;
begin
  BuildProfile(A, BlockSize, Perm, Inv, First);
  Result := 0;
  for I := 0 to A.N - 1 do Result := Result + Sqr(Double(I - First[I] + 1));
end;

function TSkylineCholesky.Factor(A: TCSRMatrix; BlockSize: Integer): Boolean;
var
  Perm, Inv, First: TIntArray;
  I, J, K, P, Row, C, K0: Integer;
  Total, RI, RJ: Int64;
  S, Piv, MaxDiag, D0: Double;
  PA, PB: PDouble;
begin
  FError := '';
  FN := A.N;
  BuildProfile(A, BlockSize, Perm, Inv, First);
  FPerm := Perm; FInv := Inv; FFirst := First;
  SetLength(FStart, FN + 1);
  Total := 0;
  for I := 0 to FN - 1 do
  begin
    FStart[I] := Total;
    Total := Total + (I - FFirst[I] + 1);
  end;
  FStart[FN] := Total;
  SetLength(FL, Total);
  for I := 0 to High(FL) do FL[I] := 0;
  { copia a parte inferior da matriz permutada; L[i][j] em FL[FStart[i] + j - FFirst[i]] }
  MaxDiag := 0;
  for I := 0 to FN - 1 do
  begin
    Row := FPerm[I];
    for P := A.RowPtr[Row] to A.RowPtr[Row + 1] - 1 do
    begin
      C := FInv[A.Col[P]];
      if C <= I then FL[FStart[I] + C - FFirst[I]] := FL[FStart[I] + C - FFirst[I]] + A.Val[P];
      if C = I then MaxDiag := Max(MaxDiag, Abs(A.Val[P]));
    end;
  end;
  { Cholesky linha a linha no envelope }
  for I := 0 to FN - 1 do
  begin
    if I and 255 = 0 then CheckCancel;
    RI := FStart[I] - FFirst[I];
    for J := FFirst[I] to I do
    begin
      RJ := FStart[J] - FFirst[J];
      K0 := Max(FFirst[I], FFirst[J]);
      S := FL[RI + J];
      if J = I then D0 := FL[RI + I];   { diagonal original da linha }
      PA := @FL[RI + K0];
      PB := @FL[RJ + K0];
      for K := K0 to J - 1 do
      begin
        S := S - PA^ * PB^;
        Inc(PA); Inc(PB);
      end;
      if J < I then
        FL[RI + J] := S / FL[RJ + J]
      else
      begin
        Piv := S;
        { pivo perto de zero em relacao a propria diagonal = mecanismo livre }
        if (Piv <= 1e-12 * Abs(D0)) or (Piv <= 1e-300) then
        begin
          FError := Format('Pivo nao positivo no grau %d (no %d, pivo %.3e, diagonal max %.3e): estrutura sem fixacao suficiente ou material invalido',
            [FPerm[I], FPerm[I] div BlockSize, Piv, MaxDiag]);
          Exit(False);
        end;
        FL[RI + I] := Sqrt(Piv);
      end;
    end;
  end;
  Result := True;
end;

procedure TSkylineCholesky.Solve(const B: TDoubleArray; var X: TDoubleArray);
var
  Y: TDoubleArray;
  I, K: Integer;
  RI: Int64;
  S: Double;
begin
  SetLength(Y, FN);
  for I := 0 to FN - 1 do Y[I] := B[FPerm[I]];
  { L y = b }
  for I := 0 to FN - 1 do
  begin
    RI := FStart[I] - FFirst[I];
    S := Y[I];
    for K := FFirst[I] to I - 1 do S := S - FL[RI + K] * Y[K];
    Y[I] := S / FL[RI + I];
  end;
  { L^T x = y (por colunas) }
  for I := FN - 1 downto 0 do
  begin
    RI := FStart[I] - FFirst[I];
    Y[I] := Y[I] / FL[RI + I];
    for K := FFirst[I] to I - 1 do Y[K] := Y[K] - FL[RI + K] * Y[I];
  end;
  if Length(X) <> FN then SetLength(X, FN);
  for I := 0 to FN - 1 do X[FPerm[I]] := Y[I];
end;

end.
