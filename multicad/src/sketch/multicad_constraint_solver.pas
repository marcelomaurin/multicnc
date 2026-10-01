unit multicad_constraint_solver;

{$mode objfpc}{$H+}

{ Solver de restricoes geometricas do Sketch 2D.

  Cada restricao vira uma ou mais equacoes residuais sobre os parametros das
  entidades (linha: x1,y1,x2,y2; circulo: cx,cy,r). O sistema e resolvido por
  Levenberg-Marquardt (minimos quadrados amortecidos) - a mesma familia usada
  por solvers de CAD parametrico (planegcs/FreeCAD, SolveSpace): converge a
  partir do desenho aproximado do usuario e lida com sistemas sub ou
  super-determinados.

  Apos resolver, a analise de posto da Jacobiana informa os graus de
  liberdade restantes e classifica o sketch:
  - subrestrito (DOF > 0) - ainda pode ser arrastado;
  - totalmente restrito (DOF = 0) - o "verde" dos CADs comerciais;
  - redundante - restricoes repetidas mas consistentes;
  - conflitante - restricoes impossiveis de satisfazer juntas.

  Semantica:
  - Coincident(A,B,Value): Value 0 = A.P2 com B.P1 (encadeamento padrao),
    1 = A.P1/B.P1, 2 = A.P2/B.P2, 3 = A.P1/B.P2. Em circulos P1 e o centro.
  - Distance(A,-1,V): comprimento da linha A; Distance(A,B,V): distancia
    entre os pontos P1 (ou centros) de A e B.
  - Equal(A,B): comprimentos iguais (linhas) ou raios iguais (circulos).
  - Angle(A,B,graus): angulo orientado de A para B.
  - Fixed(A): P1/centro de A permanece onde esta. }

interface

uses SysUtils, Math, multicad_types, multicad_sketch;

type
  TSketchStatus = (ssUnderConstrained, ssFullyConstrained, ssRedundant, ssConflicting, ssEmpty);

  TSolveResult = record
    Converged: Boolean;
    Iterations: Integer;
    Residual: Double;          // norma RMS dos residuos (mm)
    Parameters, Equations, Rank, DOF: Integer;
    Status: TSketchStatus;
  end;

  TSketchSolver = class
  private
    FSketch: TCadSketch;
    FParamIndex: array of Integer;  // primeiro parametro de cada entidade
    FFixed: array of TCadVec2;      // ancoras de ckFixed
    function ParamCount: Integer;
    procedure Load(var P: array of Double);
    procedure Store(const P: array of Double);
    function Residuals(const P: array of Double; var R: array of Double): Integer;
    function EquationCount: Integer;
  public
    constructor Create(ASketch: TCadSketch);
    function Solve(MaxIterations: Integer = 200; Tolerance: Double = 1e-10): TSolveResult;
  end;

function SketchStatusText(S: TSketchStatus): string;

implementation

function SketchStatusText(S: TSketchStatus): string;
begin
  case S of
    ssUnderConstrained: Result := 'Subrestrito';
    ssFullyConstrained: Result := 'Totalmente restrito';
    ssRedundant: Result := 'Restricoes redundantes';
    ssConflicting: Result := 'Restricoes conflitantes';
  else
    Result := 'Vazio';
  end;
end;

function EntityParamCount(const E: TSketchEntity): Integer;
begin
  if E.Kind in [seCircle, seArc] then Result := 3 else Result := 4;
end;

constructor TSketchSolver.Create(ASketch: TCadSketch);
var I, N: Integer;
begin
  inherited Create;
  FSketch := ASketch;
  SetLength(FParamIndex, FSketch.EntityCount);
  N := 0;
  for I := 0 to FSketch.EntityCount - 1 do begin
    FParamIndex[I] := N;
    Inc(N, EntityParamCount(FSketch.Entity(I)));
  end;
  SetLength(FFixed, FSketch.ConstraintCount);
  for I := 0 to FSketch.ConstraintCount - 1 do
    if (FSketch.Constraint(I).Kind = ckFixed) and (FSketch.Constraint(I).EntityA >= 0) and
      (FSketch.Constraint(I).EntityA < FSketch.EntityCount) then
      FFixed[I] := FSketch.Entity(FSketch.Constraint(I).EntityA).P1;
end;

function TSketchSolver.ParamCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to FSketch.EntityCount - 1 do Inc(Result, EntityParamCount(FSketch.Entity(I)));
end;

procedure TSketchSolver.Load(var P: array of Double);
var I, K: Integer; E: TSketchEntity;
begin
  for I := 0 to FSketch.EntityCount - 1 do begin
    E := FSketch.Entity(I);
    K := FParamIndex[I];
    P[K] := E.P1.X; P[K + 1] := E.P1.Y;
    if E.Kind in [seCircle, seArc] then P[K + 2] := E.Radius
    else begin P[K + 2] := E.P2.X; P[K + 3] := E.P2.Y; end;
  end;
end;

procedure TSketchSolver.Store(const P: array of Double);
var I, K: Integer; E: TSketchEntity;
begin
  for I := 0 to FSketch.EntityCount - 1 do begin
    E := FSketch.Entity(I);
    K := FParamIndex[I];
    E.P1.X := P[K]; E.P1.Y := P[K + 1];
    if E.Kind in [seCircle, seArc] then E.Radius := P[K + 2]
    else begin E.P2.X := P[K + 2]; E.P2.Y := P[K + 3]; end;
    FSketch.SetEntity(I, E);
  end;
end;

function TSketchSolver.EquationCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to FSketch.ConstraintCount - 1 do
    case FSketch.Constraint(I).Kind of
      ckCoincident, ckFixed: Inc(Result, 2);
    else
      Inc(Result);
    end;
end;

function TSketchSolver.Residuals(const P: array of Double; var R: array of Double): Integer;
var
  I, N, A, B, KA, KB: Integer;
  C: TSketchConstraint;
  EA, EB: TSketchEntity;
  AX1, AY1, AX2, AY2, BX1, BY1, BX2, BY2, DAX, DAY, DBX, DBY, LA, LB, Ang: Double;
  PAX, PAY, PBX, PBY: Double;
  IsCircA, IsCircB: Boolean;
begin
  N := 0;
  for I := 0 to FSketch.ConstraintCount - 1 do begin
    C := FSketch.Constraint(I);
    A := C.EntityA; B := C.EntityB;
    if (A < 0) or (A >= FSketch.EntityCount) then begin R[N] := 0; Inc(N); Continue; end;
    EA := FSketch.Entity(A);
    KA := FParamIndex[A];
    IsCircA := EA.Kind in [seCircle, seArc];
    AX1 := P[KA]; AY1 := P[KA + 1];
    if IsCircA then begin AX2 := AX1; AY2 := AY1; end else begin AX2 := P[KA + 2]; AY2 := P[KA + 3]; end;
    DAX := AX2 - AX1; DAY := AY2 - AY1;
    LA := Hypot(DAX, DAY);
    if (B >= 0) and (B < FSketch.EntityCount) then begin
      EB := FSketch.Entity(B);
      KB := FParamIndex[B];
      IsCircB := EB.Kind in [seCircle, seArc];
      BX1 := P[KB]; BY1 := P[KB + 1];
      if IsCircB then begin BX2 := BX1; BY2 := BY1; end else begin BX2 := P[KB + 2]; BY2 := P[KB + 3]; end;
    end else begin
      KB := -1; IsCircB := False;
      BX1 := 0; BY1 := 0; BX2 := 0; BY2 := 0;
    end;
    DBX := BX2 - BX1; DBY := BY2 - BY1;
    LB := Hypot(DBX, DBY);
    case C.Kind of
      ckHorizontal: begin R[N] := AY2 - AY1; Inc(N); end;
      ckVertical: begin R[N] := AX2 - AX1; Inc(N); end;
      ckCoincident: begin
        case Round(C.Value) of
          1: begin PAX := AX1; PAY := AY1; PBX := BX1; PBY := BY1; end;
          2: begin PAX := AX2; PAY := AY2; PBX := BX2; PBY := BY2; end;
          3: begin PAX := AX1; PAY := AY1; PBX := BX2; PBY := BY2; end;
        else
          begin PAX := AX2; PAY := AY2; PBX := BX1; PBY := BY1; end;
        end;
        if KB < 0 then begin PBX := PAX; PBY := PAY; end;
        R[N] := PAX - PBX; R[N + 1] := PAY - PBY;
        Inc(N, 2);
      end;
      ckParallel: begin
        if (KB < 0) or (LA < 1e-12) or (LB < 1e-12) then R[N] := 0
        else R[N] := (DAX * DBY - DAY * DBX) / LB; // escala em mm (comprimento de A)
        Inc(N);
      end;
      ckPerpendicular: begin
        if (KB < 0) or (LA < 1e-12) or (LB < 1e-12) then R[N] := 0
        else R[N] := (DAX * DBX + DAY * DBY) / LB;
        Inc(N);
      end;
      ckEqual: begin
        if KB < 0 then R[N] := 0
        else if IsCircA and IsCircB then R[N] := P[KA + 2] - P[KB + 2]
        else if IsCircA then R[N] := 2 * P[KA + 2] - LB   // diametro = comprimento
        else if IsCircB then R[N] := LA - 2 * P[KB + 2]
        else R[N] := LA - LB;
        Inc(N);
      end;
      ckDistance: begin
        if KB < 0 then R[N] := LA - C.Value
        else R[N] := Hypot(BX1 - AX1, BY1 - AY1) - C.Value;
        Inc(N);
      end;
      ckRadius: begin
        if IsCircA then R[N] := P[KA + 2] - C.Value else R[N] := LA / 2 - C.Value;
        Inc(N);
      end;
      ckAngle: begin
        if (KB < 0) or (LA < 1e-12) or (LB < 1e-12) then R[N] := 0
        else begin
          Ang := ArcTan2(DAX * DBY - DAY * DBX, DAX * DBX + DAY * DBY) - DegToRad(C.Value);
          while Ang > Pi do Ang := Ang - 2 * Pi;
          while Ang < -Pi do Ang := Ang + 2 * Pi;
          R[N] := Ang * Max(LA, 1); // residuo em mm aproximado (arco)
        end;
        Inc(N);
      end;
      ckFixed: begin
        R[N] := AX1 - FFixed[I].X; R[N + 1] := AY1 - FFixed[I].Y;
        Inc(N, 2);
      end;
    end;
  end;
  Result := N;
end;

{ Posto numerico por eliminacao gaussiana com pivoteamento total. }
function MatrixRank(M: array of Double; Rows, Cols: Integer; Tol: Double): Integer;
var Step, I, J, PR, PC: Integer; Best, F, T: Double;
begin
  Result := 0;
  for Step := 0 to Min(Rows, Cols) - 1 do begin
    Best := 0; PR := -1; PC := -1;
    for I := Step to Rows - 1 do
      for J := 0 to Cols - 1 do
        if Abs(M[I * Cols + J]) > Best then begin Best := Abs(M[I * Cols + J]); PR := I; PC := J; end;
    if Best <= Tol then Exit;
    if PR <> Step then
      for J := 0 to Cols - 1 do begin
        T := M[PR * Cols + J]; M[PR * Cols + J] := M[Step * Cols + J]; M[Step * Cols + J] := T;
      end;
    for I := Step + 1 to Rows - 1 do begin
      F := M[I * Cols + PC] / M[Step * Cols + PC];
      if F <> 0 then
        for J := 0 to Cols - 1 do M[I * Cols + J] := M[I * Cols + J] - F * M[Step * Cols + J];
    end;
    Inc(Result);
  end;
end;

function SolveSymmetric(var A: array of Double; var B: array of Double; N: Integer): Boolean;
var I, J, K, P: Integer; Mx, T, F: Double;
begin
  Result := False;
  for I := 0 to N - 1 do begin
    P := I; Mx := Abs(A[I * N + I]);
    for K := I + 1 to N - 1 do if Abs(A[K * N + I]) > Mx then begin Mx := Abs(A[K * N + I]); P := K; end;
    if Mx < 1e-300 then Exit;
    if P <> I then begin
      for J := 0 to N - 1 do begin T := A[I * N + J]; A[I * N + J] := A[P * N + J]; A[P * N + J] := T; end;
      T := B[I]; B[I] := B[P]; B[P] := T;
    end;
    for K := I + 1 to N - 1 do begin
      F := A[K * N + I] / A[I * N + I];
      if F = 0 then Continue;
      for J := I to N - 1 do A[K * N + J] := A[K * N + J] - F * A[I * N + J];
      B[K] := B[K] - F * B[I];
    end;
  end;
  for I := N - 1 downto 0 do begin
    T := B[I];
    for J := I + 1 to N - 1 do T := T - A[I * N + J] * B[J];
    B[I] := T / A[I * N + I];
  end;
  Result := True;
end;

function TSketchSolver.Solve(MaxIterations: Integer; Tolerance: Double): TSolveResult;
var
  NP, NE, It, I, J, K: Integer;
  P, PTry, R, RTry, RP, RM, J0, JtJ, Damped, Jtr, Delta: array of Double;
  Lambda, Cost, CostTry, H, Save: Double;
begin
  FillChar(Result, SizeOf(Result), 0);
  NP := ParamCount;
  NE := EquationCount;
  Result.Parameters := NP;
  Result.Equations := NE;
  if NP = 0 then begin Result.Status := ssEmpty; Result.Converged := True; Exit; end;
  SetLength(P, NP); SetLength(PTry, NP);
  SetLength(R, NE); SetLength(RTry, NE); SetLength(RP, NE); SetLength(RM, NE);
  SetLength(J0, NE * NP); SetLength(JtJ, NP * NP); SetLength(Damped, NP * NP);
  SetLength(Jtr, NP); SetLength(Delta, NP);
  Load(P);
  Lambda := 1e-3;
  if NE > 0 then begin
    Residuals(P, R);
    Cost := 0;
    for I := 0 to NE - 1 do Cost := Cost + Sqr(R[I]);
    for It := 1 to MaxIterations do begin
      Result.Iterations := It;
      if Cost < Sqr(Tolerance) * NE then Break;
      // Jacobiana por diferencas centrais
      for J := 0 to NP - 1 do begin
        H := 1e-7 * Max(1, Abs(P[J]));
        Save := P[J];
        P[J] := Save + H; Residuals(P, RP);
        P[J] := Save - H; Residuals(P, RM);
        P[J] := Save;
        for I := 0 to NE - 1 do J0[I * NP + J] := (RP[I] - RM[I]) / (2 * H);
      end;
      // JtJ e Jt r
      for J := 0 to NP - 1 do begin
        Jtr[J] := 0;
        for I := 0 to NE - 1 do Jtr[J] := Jtr[J] + J0[I * NP + J] * R[I];
        for K := J to NP - 1 do begin
          Save := 0;
          for I := 0 to NE - 1 do Save := Save + J0[I * NP + J] * J0[I * NP + K];
          JtJ[J * NP + K] := Save;
          JtJ[K * NP + J] := Save;
        end;
      end;
      // tenta passos com amortecimento crescente ate reduzir o custo:
      // (JtJ + lambda*(diag(JtJ) + I)) delta = -Jt r
      repeat
        for J := 0 to NP * NP - 1 do Damped[J] := JtJ[J];
        for J := 0 to NP - 1 do begin
          Damped[J * NP + J] := Damped[J * NP + J] + Lambda * (JtJ[J * NP + J] + 1);
          Delta[J] := -Jtr[J];
        end;
        if SolveSymmetric(Damped, Delta, NP) then begin
          for J := 0 to NP - 1 do PTry[J] := P[J] + Delta[J];
          Residuals(PTry, RTry);
          CostTry := 0;
          for I := 0 to NE - 1 do CostTry := CostTry + Sqr(RTry[I]);
          if CostTry < Cost then begin
            P := Copy(PTry);
            R := Copy(RTry);
            Cost := CostTry;
            Lambda := Max(Lambda / 10, 1e-12);
            Break;
          end;
        end;
        Lambda := Lambda * 10;
      until Lambda > 1e12;
      if Lambda > 1e12 then Break; // estagnou (sistema conflitante)
    end;
    Result.Residual := Sqrt(Cost / NE);
    Result.Converged := Result.Residual < Max(Tolerance * 100, 1e-8);
  end else begin
    Result.Converged := True;
    Result.Residual := 0;
  end;
  Store(P);
  // analise de graus de liberdade na solucao
  if NE > 0 then begin
    for J := 0 to NP - 1 do begin
      H := 1e-7 * Max(1, Abs(P[J]));
      Save := P[J];
      P[J] := Save + H; Residuals(P, RP);
      P[J] := Save - H; Residuals(P, RM);
      P[J] := Save;
      for I := 0 to NE - 1 do J0[I * NP + J] := (RP[I] - RM[I]) / (2 * H);
    end;
    Result.Rank := MatrixRank(J0, NE, NP, 1e-6);
  end else
    Result.Rank := 0;
  Result.DOF := NP - Result.Rank;
  if not Result.Converged then Result.Status := ssConflicting
  else if Result.Rank < NE then Result.Status := ssRedundant
  else if Result.DOF > 0 then Result.Status := ssUnderConstrained
  else Result.Status := ssFullyConstrained;
end;

end.
