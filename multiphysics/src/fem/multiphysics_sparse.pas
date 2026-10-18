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

interface

uses
  SysUtils, Math, multiphysics_mesh;

type
  TDoubleArray = array of Double;

  TCSRMatrix = class
  public
    N: Integer;
    RowPtr: array of Integer;
    Col: array of Integer;
    Val: TDoubleArray;
    { padrao pela malha: nos que dividem um elemento ficam acoplados }
    procedure BuildFromMesh(M: TFEMMesh; BlockSize: Integer);
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
    function Factor(A: TCSRMatrix; BlockSize: Integer): Boolean;
    procedure Solve(const B: TDoubleArray; var X: TDoubleArray);
    property LastError: string read FError;
  end;

function SolvePCG(A: TCSRMatrix; const B: TDoubleArray; var X: TDoubleArray;
  Tol: Double; MaxIter: Integer): TSolveInfo;
function Dot(const A, B: TDoubleArray): Double;
{ ordem RCM dos nos (Cuthill-McKee reverso) pelo padrao em blocos }
function RCMOrder(A: TCSRMatrix; BlockSize: Integer): TIntArray;

implementation

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
var
  Keys: array of Int64;
  NPE, E, A, B, NK, U, I, NN, Row, Cnt, Node, Nb, D, D2: Integer;
  NodeStart, NodeAdj: array of Integer;
  Key: Int64;
begin
  NPE := M.NodesPerElement;
  NN := M.NodeCount;
  SetLength(Keys, Int64(M.ElemCount) * NPE * NPE);
  NK := 0;
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

procedure TCSRMatrix.ApplyDirichlet(const Fixed: array of Boolean; const Values: TDoubleArray;
  var RHS: TDoubleArray);
var
  I, P, J: Integer;
begin
  for I := 0 to N - 1 do
    for P := RowPtr[I] to RowPtr[I + 1] - 1 do
    begin
      J := Col[P];
      if Fixed[I] then
      begin
        if J = I then Val[P] := 1 else Val[P] := 0;
      end
      else if Fixed[J] then
      begin
        RHS[I] := RHS[I] - Val[P] * Values[J];
        Val[P] := 0;
      end;
    end;
  for I := 0 to N - 1 do
    if Fixed[I] then RHS[I] := Values[I];
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
  NN, I, P, Head, Tail, Node, Nb, Start, Best, J, K, T: Integer;
  Deg: array of Integer;
  Visited: array of Boolean;
  Queue: array of Integer;
  Nbrs: array of Integer;
begin
  NN := A.N div BlockSize;
  Result := nil;
  SetLength(Deg, NN);
  for I := 0 to NN - 1 do
    Deg[I] := (A.RowPtr[I * BlockSize + 1] - A.RowPtr[I * BlockSize]) div BlockSize;
  SetLength(Visited, NN);
  SetLength(Queue, NN);
  Tail := 0;
  while Tail < NN do
  begin
    { novo componente: comeca pelo no de menor grau ainda livre }
    Start := -1; Best := MaxInt;
    for I := 0 to NN - 1 do
      if not Visited[I] and (Deg[I] < Best) then begin Best := Deg[I]; Start := I; end;
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

function TSkylineCholesky.Factor(A: TCSRMatrix; BlockSize: Integer): Boolean;
var
  Perm, Inv, First: TIntArray;
  I, J, K, P, Row, C, K0: Integer;
  Total, RI, RJ: Int64;
  S, Piv, MaxDiag: Double;
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
    RI := FStart[I] - FFirst[I];
    for J := FFirst[I] to I do
    begin
      RJ := FStart[J] - FFirst[J];
      K0 := Max(FFirst[I], FFirst[J]);
      S := FL[RI + J];
      for K := K0 to J - 1 do S := S - FL[RI + K] * FL[RJ + K];
      if J < I then
        FL[RI + J] := S / FL[RJ + J]
      else
      begin
        Piv := S;
        if Piv <= 1e-13 * Max(MaxDiag, 1e-300) then
        begin
          FError := Format('Pivo nao positivo no grau %d (no %d): estrutura sem fixacao suficiente ou material invalido',
            [FPerm[I], FPerm[I] div BlockSize]);
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
