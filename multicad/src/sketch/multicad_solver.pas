unit multicad_solver;

{ MultiCAD - solver de restricoes do esboco (decisao D4, ARCHITECTURE 3).

  Variaveis: coordenadas dos pontos e raios dos circulos.
    ponto   x, y
    linha   x1, y1, x2, y2
    circulo cx, cy, r
    arco    cx, cy, sx, sy, ex, ey   (+ equacao interna |s-c| = |e-c|)
  Cada restricao vira uma ou mais equacoes f(x) = 0.

  Resolucao: Newton amortecido com passo de norma minima
    dx = -J^T (J J^T + lambda I)^-1 F
  partindo da posicao atual. O passo de norma minima mexe o menos possivel
  no desenho, por isso o esboco fica "parecido" ao mudar uma cota.

  Graus de liberdade: base ortonormal das linhas do jacobiano (Gram-Schmidt).
    posto r, GL = n - r;
    linha que nao aumenta o posto = restricao redundante (superdefinido);
    variavel determinada se o vetor unitario dela esta no espaco das linhas.
  Cores como no SolidWorks: azul (livre), preto (definido), vermelho
  (conflito ou redundante). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multicad_types, multicad_sketch;

type
  TSketchStatus = (ssEmpty, ssUnderDefined, ssFullyDefined, ssOverDefined, ssConflict);
  TSketchEntityState = (esFree, esDefined, esProblem);
  TSketchConstraintState = (csOk, csRedundant, csConflict, csInvalid);

  TSketchSolveResult = record
    Status: TSketchStatus;
    Converged: Boolean;
    DOF: Integer;
    VarCount, EqCount, Rank: Integer;
    Iterations: Integer;
    Residual: Double;
    Message: string;
    EntityState: array of TSketchEntityState;      { por indice de entidade }
    ConstraintState: array of TSketchConstraintState; { por indice de restricao }
  end;

const
  CAD_SKETCH_STATUS_NAMES: array[TSketchStatus] of string = ('Vazio',
    'Subdefinido', 'Totalmente definido', 'Superdefinido', 'Conflito');

{ Resolve o esboco. Se convergir, grava as posicoes; se nao, deixa o esboco
  como estava e marca as restricoes em conflito. Cotas dirigidas recebem o
  valor medido. }
function CadSolveSketch(S: TCadSketch; AMaxIter: Integer = 200): TSketchSolveResult;
{ So analisa (sem mover nada): GL e estados. }
function CadAnalyzeSketch(S: TCadSketch): TSketchSolveResult;
{ Valor medido de uma cota (mm ou graus), pela geometria atual. }
function CadMeasureDimension(S: TCadSketch; AIndex: Integer; out AValue: Double): Boolean;

implementation

const
  SOLVE_TOL = 1E-9;
  RANK_TOL = 1E-7;
  FD_STEP = 1E-7;

type
  TDoubleArray = array of Double;

  TPtRef = record
    Valid: Boolean;
    Constant: Boolean;   { origem }
    IX, IY: Integer;     { indices em X }
  end;

  TEntInfo = record
    Kind: TSketchEntityKind;
    Base: Integer;       { primeiro indice em X }
    Count: Integer;
  end;

  TSystem = class
  public
    S: TCadSketch;
    X: TDoubleArray;
    Ents: array of TEntInfo;
    N: Integer;          { variaveis }
    M: Integer;          { equacoes }
    RowCon: array of Integer;   { restricao de cada linha (-1 = interna do arco) }
    RowEnt: array of Integer;   { entidade da linha interna }
    ConRows: array of Integer;  { quantas linhas por restricao }
    ConValid: array of Boolean;
    Signs: array of Double;     { sinal "pegajoso" por restricao }
    Signs2: array of Double;
    { tangencia com extremidade comum (forma de primeira ordem):
      TanPtA/TanPtB = indice do ponto comum em A e em B (0 = sem) }
    TanPtA, TanPtB: array of Integer;
    procedure FindTangentJoints;
    constructor Create(ASketch: TCadSketch);
    function Pt(AEnt, APt: Integer): TPtRef;
    function PX(const P: TPtRef; const AX: TDoubleArray): Double;
    function PY(const P: TPtRef; const AX: TDoubleArray): Double;
    function EntIdx(AEnt: Integer): Integer;
    function Radius(EI: Integer; const AX: TDoubleArray): Double;
    function CenterRef(EI: Integer): TPtRef;
    function RowsFor(CI: Integer): Integer;
    procedure Residuals(const AX: TDoubleArray; var F: TDoubleArray);
    procedure ConResiduals(CI: Integer; const AX: TDoubleArray; var F: TDoubleArray; Row: Integer);
    procedure Jacobian(const AX: TDoubleArray; var J: TDoubleArray);
    procedure InitSigns;
    procedure WriteBack;
  end;

function Norm2(const V: TDoubleArray): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(V) do
    Result := Result + V[I] * V[I];
  Result := Sqrt(Result);
end;

function NormInf(const V: TDoubleArray): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(V) do
    Result := Max(Result, Abs(V[I]));
end;

function WrapPi(A: Double): Double;
begin
  while A > Pi do
    A := A - 2 * Pi;
  while A <= -Pi do
    A := A + 2 * Pi;
  Result := A;
end;

function SignOf(V: Double): Double;
begin
  if V < 0 then
    Result := -1
  else
    Result := 1;
end;

{ ---------- sistema ---------- }

constructor TSystem.Create(ASketch: TCadSketch);
var
  I, K: Integer;
  E: TSketchEntity;
begin
  inherited Create;
  S := ASketch;
  SetLength(Ents, S.EntityCount);
  N := 0;
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    Ents[I].Kind := E.Kind;
    Ents[I].Base := N;
    case E.Kind of
      sePoint: Ents[I].Count := 2;
      seLine: Ents[I].Count := 4;
      seCircle: Ents[I].Count := 3;
      seArc: Ents[I].Count := 6;
    else
      Ents[I].Count := 0;
    end;
    Inc(N, Ents[I].Count);
  end;
  SetLength(X, N);
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    K := Ents[I].Base;
    case E.Kind of
      sePoint: begin X[K] := E.P1.X; X[K + 1] := E.P1.Y; end;
      seLine:
        begin
          X[K] := E.P1.X; X[K + 1] := E.P1.Y;
          X[K + 2] := E.P2.X; X[K + 3] := E.P2.Y;
        end;
      seCircle: begin X[K] := E.P1.X; X[K + 1] := E.P1.Y; X[K + 2] := E.Radius; end;
      seArc:
        begin
          X[K] := E.P1.X; X[K + 1] := E.P1.Y;
          X[K + 2] := E.P2.X; X[K + 3] := E.P2.Y;
          X[K + 4] := E.P3.X; X[K + 5] := E.P3.Y;
        end;
    end;
  end;
  { linhas: internas dos arcos + restricoes }
  M := 0;
  RowCon := nil;
  RowEnt := nil;
  for I := 0 to S.EntityCount - 1 do
    if Ents[I].Kind = seArc then
    begin
      SetLength(RowCon, M + 1);
      SetLength(RowEnt, M + 1);
      RowCon[M] := -1;
      RowEnt[M] := I;
      Inc(M);
    end;
  SetLength(ConRows, S.ConstraintCount);
  SetLength(ConValid, S.ConstraintCount);
  SetLength(Signs, S.ConstraintCount);
  SetLength(Signs2, S.ConstraintCount);
  SetLength(TanPtA, S.ConstraintCount);
  SetLength(TanPtB, S.ConstraintCount);
  for I := 0 to S.ConstraintCount - 1 do
  begin
    ConRows[I] := RowsFor(I);
    ConValid[I] := ConRows[I] >= 0;
    if ConRows[I] < 0 then
      ConRows[I] := 0;
    for K := 1 to ConRows[I] do
    begin
      SetLength(RowCon, M + 1);
      SetLength(RowEnt, M + 1);
      RowCon[M] := I;
      RowEnt[M] := -1;
      Inc(M);
    end;
  end;
  FindTangentJoints;
  InitSigns;
end;

{ Linha e arco (ou dois arcos) tangentes que tambem tem uma restricao
  coincidente entre extremidades: a tangencia vira "direcao perpendicular ao
  raio no ponto comum". A forma pela distancia tem derivada nula quando o
  ponto ja esta na curva, o que derruba o posto do jacobiano. }
procedure TSystem.FindTangentJoints;
var
  I, K: Integer;
  C, D: TSketchConstraint;
begin
  for I := 0 to S.ConstraintCount - 1 do
  begin
    TanPtA[I] := 0;
    TanPtB[I] := 0;
    C := S.Constraint(I);
    if (C.Kind <> ckTangent) or not ConValid[I] or (ConRows[I] = 0) then
      Continue;
    for K := 0 to S.ConstraintCount - 1 do
    begin
      D := S.Constraint(K);
      if (D.Kind <> ckCoincident) or (D.PointA = 0) or (D.PointB = 0) then
        Continue;
      if (D.EntityA = C.EntityA) and (D.EntityB = C.EntityB) then
      begin
        TanPtA[I] := D.PointA;
        TanPtB[I] := D.PointB;
      end
      else if (D.EntityA = C.EntityB) and (D.EntityB = C.EntityA) then
      begin
        TanPtA[I] := D.PointB;
        TanPtB[I] := D.PointA;
      end
      else
        Continue;
      { so extremidades de linha (1,2) e de arco (2,3) }
      if ((Ents[EntIdx(C.EntityA)].Kind = seArc) and (TanPtA[I] = 1)) or
        ((Ents[EntIdx(C.EntityB)].Kind = seArc) and (TanPtB[I] = 1)) or
        (Ents[EntIdx(C.EntityA)].Kind = seCircle) or (Ents[EntIdx(C.EntityB)].Kind = seCircle) then
      begin
        TanPtA[I] := 0;
        TanPtB[I] := 0;
        Continue;
      end;
      Break;
    end;
  end;
end;

function TSystem.EntIdx(AEnt: Integer): Integer;
begin
  if (AEnt = 0) or (AEnt = CAD_SKETCH_ORIGIN) then
    Exit(-1);
  Result := S.EntityIndex(AEnt);
end;

function TSystem.Pt(AEnt, APt: Integer): TPtRef;
var
  EI, B: Integer;
begin
  Result.Valid := False;
  Result.Constant := False;
  Result.IX := -1;
  Result.IY := -1;
  if AEnt = CAD_SKETCH_ORIGIN then
  begin
    Result.Valid := True;
    Result.Constant := True;
    Exit;
  end;
  EI := EntIdx(AEnt);
  if EI < 0 then
    Exit;
  B := Ents[EI].Base;
  case Ents[EI].Kind of
    sePoint:
      if APt in [0, 1] then
      begin
        Result.IX := B; Result.IY := B + 1; Result.Valid := True;
      end;
    seLine:
      if APt in [1, 2] then
      begin
        Result.IX := B + 2 * (APt - 1); Result.IY := Result.IX + 1; Result.Valid := True;
      end;
    seCircle:
      if APt = 1 then
      begin
        Result.IX := B; Result.IY := B + 1; Result.Valid := True;
      end;
    seArc:
      if APt in [1, 2, 3] then
      begin
        Result.IX := B + 2 * (APt - 1); Result.IY := Result.IX + 1; Result.Valid := True;
      end;
  end;
end;

function TSystem.CenterRef(EI: Integer): TPtRef;
begin
  Result.Valid := Ents[EI].Kind in [seCircle, seArc];
  Result.Constant := False;
  Result.IX := Ents[EI].Base;
  Result.IY := Ents[EI].Base + 1;
end;

function TSystem.PX(const P: TPtRef; const AX: TDoubleArray): Double;
begin
  if P.Constant then
    Result := 0
  else
    Result := AX[P.IX];
end;

function TSystem.PY(const P: TPtRef; const AX: TDoubleArray): Double;
begin
  if P.Constant then
    Result := 0
  else
    Result := AX[P.IY];
end;

function TSystem.Radius(EI: Integer; const AX: TDoubleArray): Double;
var
  B: Integer;
begin
  B := Ents[EI].Base;
  if Ents[EI].Kind = seCircle then
    Result := AX[B + 2]
  else
    Result := Sqrt(Sqr(AX[B + 2] - AX[B]) + Sqr(AX[B + 3] - AX[B + 1]));
end;

function IsCurve(K: TSketchEntityKind): Boolean;
begin
  Result := K in [seCircle, seArc];
end;

{ Numero de linhas de cada restricao; -1 = combinacao invalida. }
function TSystem.RowsFor(CI: Integer): Integer;
var
  C: TSketchConstraint;
  A, B, CC: Integer;
  KA, KB: TSketchEntityKind;
  function IsPtRef(AEnt, APt: Integer): Boolean;
  begin
    Result := Pt(AEnt, APt).Valid and ((APt > 0) or (AEnt = CAD_SKETCH_ORIGIN) or
      ((EntIdx(AEnt) >= 0) and (Ents[EntIdx(AEnt)].Kind = sePoint)));
  end;
begin
  Result := -1;
  C := S.Constraint(CI);
  if IsDimensionKind(C.Kind) and not C.Driving then
    Exit(0);
  A := EntIdx(C.EntityA);
  B := EntIdx(C.EntityB);
  if A >= 0 then KA := Ents[A].Kind else KA := sePoint;
  if B >= 0 then KB := Ents[B].Kind else KB := sePoint;
  case C.Kind of
    ckCoincident:
      if IsPtRef(C.EntityA, C.PointA) and IsPtRef(C.EntityB, C.PointB) then
        Result := 2
      else if IsPtRef(C.EntityA, C.PointA) and (B >= 0) and (C.PointB = 0) and
        (KB in [seLine, seCircle, seArc]) then
        Result := 1
      else if IsPtRef(C.EntityB, C.PointB) and (A >= 0) and (C.PointA = 0) and
        (KA in [seLine, seCircle, seArc]) then
        Result := 1;
    ckHorizontal, ckVertical:
      if (A >= 0) and (KA = seLine) and (C.EntityB = 0) then
        Result := 1
      else if IsPtRef(C.EntityA, C.PointA) and IsPtRef(C.EntityB, C.PointB) then
        Result := 1;
    ckParallel, ckPerpendicular:
      if (A >= 0) and (B >= 0) and (KA = seLine) and (KB = seLine) then
        Result := 1;
    ckTangent:
      if (A >= 0) and (B >= 0) and ((KA = seLine) and IsCurve(KB) or
        IsCurve(KA) and (KB = seLine) or IsCurve(KA) and IsCurve(KB)) then
        Result := 1;
    ckEqual:
      if (A >= 0) and (B >= 0) and ((KA = seLine) and (KB = seLine) or
        IsCurve(KA) and IsCurve(KB)) then
        Result := 1;
    ckConcentric:
      if (A >= 0) and (B >= 0) and IsCurve(KA) and IsCurve(KB) then
        Result := 2
      else if (A >= 0) and IsCurve(KA) and IsPtRef(C.EntityB, C.PointB) then
        Result := 2;
    ckMidpoint:
      if IsPtRef(C.EntityA, C.PointA) and (B >= 0) and (KB = seLine) then
        Result := 2;
    ckSymmetric:
      begin
        CC := EntIdx(C.EntityC);
        if IsPtRef(C.EntityA, C.PointA) and IsPtRef(C.EntityB, C.PointB) and
          (CC >= 0) and (Ents[CC].Kind = seLine) then
          Result := 2;
      end;
    ckFixed:
      if (A >= 0) then
      begin
        if C.PointA > 0 then
        begin
          if Pt(C.EntityA, C.PointA).Valid and (Length(C.Fix) = 2) then
            Result := 2;
        end
        else if Length(C.Fix) = Ents[A].Count then
          Result := Length(C.Fix);
      end;
    ckDistance:
      if (A >= 0) and (KA = seLine) and (C.EntityB = 0) then
        Result := 1
      else if (Pt(C.EntityA, Max(C.PointA, 1)).Valid or IsCurve(KA)) and
        (Pt(C.EntityB, Max(C.PointB, 1)).Valid or ((B >= 0) and (KB in [seLine, seCircle, seArc]))) then
        Result := 1;
    ckHorizontalDistance, ckVerticalDistance:
      if (A >= 0) and (KA = seLine) and (C.EntityB = 0) then
        Result := 1
      else if Pt(C.EntityA, Max(C.PointA, 1)).Valid and Pt(C.EntityB, Max(C.PointB, 1)).Valid then
        Result := 1;
    ckRadius, ckDiameter:
      if (A >= 0) and IsCurve(KA) then
        Result := 1;
    ckAngle:
      if (A >= 0) and (B >= 0) and (KA = seLine) and (KB = seLine) then
        Result := 1;
  end;
end;

{ ---------- residuos ---------- }

type
  TLineGeo = record
    AX, AY, BX, BY: Double;
  end;

function LineOf(Sys: TSystem; EI: Integer; const X: TDoubleArray): TLineGeo;
var
  B: Integer;
begin
  B := Sys.Ents[EI].Base;
  Result.AX := X[B]; Result.AY := X[B + 1];
  Result.BX := X[B + 2]; Result.BY := X[B + 3];
end;

{ Distancia com sinal do ponto a reta (positivo a esquerda de A->B). }
function SignedDist(const L: TLineGeo; PX, PY: Double): Double;
var
  DX, DY, Len: Double;
begin
  DX := L.BX - L.AX;
  DY := L.BY - L.AY;
  Len := Sqrt(DX * DX + DY * DY);
  if Len < 1E-12 then
    Exit(Sqrt(Sqr(PX - L.AX) + Sqr(PY - L.AY)));
  Result := (DX * (PY - L.AY) - DY * (PX - L.AX)) / Len;
end;

function LineLen(const L: TLineGeo): Double;
begin
  Result := Sqrt(Sqr(L.BX - L.AX) + Sqr(L.BY - L.AY));
end;

function LineAngle(const L1, L2: TLineGeo): Double;
var
  DX1, DY1, DX2, DY2: Double;
begin
  DX1 := L1.BX - L1.AX; DY1 := L1.BY - L1.AY;
  DX2 := L2.BX - L2.AX; DY2 := L2.BY - L2.AY;
  Result := ArcTan2(DX1 * DY2 - DY1 * DX2, DX1 * DX2 + DY1 * DY2);
end;

{ Ponto de referencia para cotas: ponto explicito, centro de curva ou P1. }
function DimPoint(Sys: TSystem; AEnt, APt: Integer; out P: TPtRef): Boolean;
var
  EI: Integer;
begin
  if (APt = 0) and (AEnt <> CAD_SKETCH_ORIGIN) then
  begin
    EI := Sys.EntIdx(AEnt);
    if (EI >= 0) and IsCurve(Sys.Ents[EI].Kind) then
    begin
      P := Sys.CenterRef(EI);
      Exit(True);
    end;
    P := Sys.Pt(AEnt, 1);
    Exit(P.Valid and (EI >= 0) and (Sys.Ents[EI].Kind = sePoint));
  end;
  P := Sys.Pt(AEnt, APt);
  Result := P.Valid;
end;

{ Cota medida com sinal (distancia a reta, horizontal, vertical, angulo)? }
function SignedDim(Sys: TSystem; CI: Integer): Boolean;
var
  C: TSketchConstraint;
  A, B: Integer;
  LineA, LineB: Boolean;
begin
  C := Sys.S.Constraint(CI);
  if C.Kind <> ckDistance then
    Exit(C.Kind in [ckHorizontalDistance, ckVerticalDistance, ckAngle]);
  A := Sys.EntIdx(C.EntityA);
  B := Sys.EntIdx(C.EntityB);
  LineA := (A >= 0) and (Sys.Ents[A].Kind = seLine) and (C.PointA = 0);
  LineB := (B >= 0) and (Sys.Ents[B].Kind = seLine) and (C.PointB = 0);
  if LineA and (C.EntityB = 0) then
    Exit(False);   { comprimento da linha }
  Result := LineA or LineB;
end;

{ Valor "medido" bruto de uma cota, com o sinal usado nas equacoes. }
function RawMeasure(Sys: TSystem; CI: Integer; const X: TDoubleArray; out V: Double): Boolean;
var
  C: TSketchConstraint;
  A, B: Integer;
  PA, PB: TPtRef;
begin
  Result := False;
  V := 0;
  C := Sys.S.Constraint(CI);
  A := Sys.EntIdx(C.EntityA);
  B := Sys.EntIdx(C.EntityB);
  case C.Kind of
    ckDistance:
      begin
        if (A >= 0) and (Sys.Ents[A].Kind = seLine) and (C.EntityB = 0) then
          V := LineLen(LineOf(Sys, A, X))
        else if (B >= 0) and (Sys.Ents[B].Kind = seLine) and (C.PointB = 0) then
        begin
          if (A >= 0) and (Sys.Ents[A].Kind = seLine) and (C.PointA = 0) then
            PA := Sys.Pt(C.EntityA, 1)
          else if not DimPoint(Sys, C.EntityA, C.PointA, PA) then
            Exit;
          V := SignedDist(LineOf(Sys, B, X), Sys.PX(PA, X), Sys.PY(PA, X));
        end
        else if (A >= 0) and (Sys.Ents[A].Kind = seLine) and (C.PointA = 0) then
        begin
          if not DimPoint(Sys, C.EntityB, C.PointB, PB) then
            Exit;
          V := SignedDist(LineOf(Sys, A, X), Sys.PX(PB, X), Sys.PY(PB, X));
        end
        else
        begin
          if not DimPoint(Sys, C.EntityA, C.PointA, PA) or
            not DimPoint(Sys, C.EntityB, C.PointB, PB) then
            Exit;
          V := Sqrt(Sqr(Sys.PX(PB, X) - Sys.PX(PA, X)) + Sqr(Sys.PY(PB, X) - Sys.PY(PA, X)));
        end;
      end;
    ckHorizontalDistance, ckVerticalDistance:
      begin
        if (A >= 0) and (Sys.Ents[A].Kind = seLine) and (C.EntityB = 0) then
        begin
          PA := Sys.Pt(C.EntityA, 1);
          PB := Sys.Pt(C.EntityA, 2);
        end
        else if not DimPoint(Sys, C.EntityA, C.PointA, PA) or
          not DimPoint(Sys, C.EntityB, C.PointB, PB) then
          Exit;
        if C.Kind = ckHorizontalDistance then
          V := Sys.PX(PB, X) - Sys.PX(PA, X)
        else
          V := Sys.PY(PB, X) - Sys.PY(PA, X);
      end;
    ckRadius:
      if A >= 0 then
        V := Sys.Radius(A, X)
      else
        Exit;
    ckDiameter:
      if A >= 0 then
        V := 2 * Sys.Radius(A, X)
      else
        Exit;
    ckAngle:
      if (A >= 0) and (B >= 0) then
        V := LineAngle(LineOf(Sys, A, X), LineOf(Sys, B, X))
      else
        Exit;
  else
    Exit;
  end;
  Result := True;
end;

procedure TSystem.InitSigns;
var
  I, A, B: Integer;
  C: TSketchConstraint;
  V, D, R1, R2: Double;
  L: TLineGeo;
  P: TPtRef;
begin
  for I := 0 to S.ConstraintCount - 1 do
  begin
    Signs[I] := 1;
    Signs2[I] := 1;
    if not ConValid[I] or (ConRows[I] = 0) then
      Continue;
    C := S.Constraint(I);
    A := EntIdx(C.EntityA);
    B := EntIdx(C.EntityB);
    case C.Kind of
      ckDistance, ckHorizontalDistance, ckVerticalDistance, ckAngle:
        if RawMeasure(Self, I, X, V) then
          Signs[I] := SignOf(V);
      ckTangent:
        begin
          if (Ents[A].Kind = seLine) or (Ents[B].Kind = seLine) then
          begin
            if Ents[A].Kind = seLine then
            begin
              L := LineOf(Self, A, X);
              P := CenterRef(B);
            end
            else
            begin
              L := LineOf(Self, B, X);
              P := CenterRef(A);
            end;
            Signs[I] := SignOf(SignedDist(L, PX(P, X), PY(P, X)));
          end
          else
          begin
            { circulo-circulo: externa (+1) ou interna (-1), a mais proxima }
            D := Sqrt(Sqr(X[Ents[A].Base] - X[Ents[B].Base]) +
              Sqr(X[Ents[A].Base + 1] - X[Ents[B].Base + 1]));
            R1 := Radius(A, X);
            R2 := Radius(B, X);
            if Abs(D - (R1 + R2)) <= Abs(D - Abs(R1 - R2)) then
              Signs[I] := 1
            else
            begin
              Signs[I] := -1;
              Signs2[I] := SignOf(R1 - R2);
            end;
          end;
        end;
      ckParallel:
        { paralela pode ser no mesmo sentido ou oposto: usa o seno, nao precisa }
        ;
    end;
  end;
end;

procedure TSystem.ConResiduals(CI: Integer; const AX: TDoubleArray; var F: TDoubleArray; Row: Integer);
var
  C: TSketchConstraint;
  A, B, CC, K: Integer;
  PA, PB, PC: TPtRef;
  L1, L2: TLineGeo;
  V, D, DX1, DY1, DX2, DY2, N1, N2, R1, R2, MX, MY: Double;
begin
  C := S.Constraint(CI);
  A := EntIdx(C.EntityA);
  B := EntIdx(C.EntityB);
  case C.Kind of
    ckCoincident:
      if ConRows[CI] = 2 then
      begin
        PA := Pt(C.EntityA, Max(C.PointA, 1));
        PB := Pt(C.EntityB, Max(C.PointB, 1));
        F[Row] := PX(PA, AX) - PX(PB, AX);
        F[Row + 1] := PY(PA, AX) - PY(PB, AX);
      end
      else
      begin
        { ponto sobre linha ou curva }
        if (B >= 0) and (C.PointB = 0) and (Ents[B].Kind in [seLine, seCircle, seArc]) then
        begin
          PA := Pt(C.EntityA, Max(C.PointA, 1));
          K := B;
        end
        else
        begin
          PA := Pt(C.EntityB, Max(C.PointB, 1));
          K := A;
        end;
        if Ents[K].Kind = seLine then
          F[Row] := SignedDist(LineOf(Self, K, AX), PX(PA, AX), PY(PA, AX))
        else
        begin
          PC := CenterRef(K);
          F[Row] := Sqrt(Sqr(PX(PA, AX) - PX(PC, AX)) + Sqr(PY(PA, AX) - PY(PC, AX))) - Radius(K, AX);
        end;
      end;
    ckHorizontal, ckVertical:
      begin
        if C.EntityB = 0 then
        begin
          PA := Pt(C.EntityA, 1);
          PB := Pt(C.EntityA, 2);
        end
        else
        begin
          PA := Pt(C.EntityA, Max(C.PointA, 1));
          PB := Pt(C.EntityB, Max(C.PointB, 1));
        end;
        if C.Kind = ckHorizontal then
          F[Row] := PY(PB, AX) - PY(PA, AX)
        else
          F[Row] := PX(PB, AX) - PX(PA, AX);
      end;
    ckParallel, ckPerpendicular:
      begin
        L1 := LineOf(Self, A, AX);
        L2 := LineOf(Self, B, AX);
        DX1 := L1.BX - L1.AX; DY1 := L1.BY - L1.AY;
        DX2 := L2.BX - L2.AX; DY2 := L2.BY - L2.AY;
        N1 := Max(Sqrt(DX1 * DX1 + DY1 * DY1), 1E-12);
        N2 := Max(Sqrt(DX2 * DX2 + DY2 * DY2), 1E-12);
        if C.Kind = ckParallel then
          F[Row] := (DX1 * DY2 - DY1 * DX2) / (N1 * N2)
        else
          F[Row] := (DX1 * DX2 + DY1 * DY2) / (N1 * N2);
      end;
    ckTangent:
      if TanPtA[CI] > 0 then
      begin
        { forma de primeira ordem no ponto comum }
        if Ents[A].Kind = seLine then
        begin
          L1 := LineOf(Self, A, AX);
          DX1 := L1.BX - L1.AX; DY1 := L1.BY - L1.AY;
          PC := CenterRef(B);
          PA := Pt(C.EntityB, TanPtB[CI]);
          DX2 := PX(PA, AX) - PX(PC, AX); DY2 := PY(PA, AX) - PY(PC, AX);
        end
        else if Ents[B].Kind = seLine then
        begin
          L1 := LineOf(Self, B, AX);
          DX1 := L1.BX - L1.AX; DY1 := L1.BY - L1.AY;
          PC := CenterRef(A);
          PA := Pt(C.EntityA, TanPtA[CI]);
          DX2 := PX(PA, AX) - PX(PC, AX); DY2 := PY(PA, AX) - PY(PC, AX);
        end
        else
        begin
          { dois arcos: raios no ponto comum alinhados (produto vetorial nulo) }
          PC := CenterRef(A);
          PA := Pt(C.EntityA, TanPtA[CI]);
          DX1 := PX(PA, AX) - PX(PC, AX); DY1 := PY(PA, AX) - PY(PC, AX);
          PC := CenterRef(B);
          PB := Pt(C.EntityB, TanPtB[CI]);
          DX2 := PX(PB, AX) - PX(PC, AX); DY2 := PY(PB, AX) - PY(PC, AX);
          N1 := Max(Sqrt(DX1 * DX1 + DY1 * DY1), 1E-12);
          N2 := Max(Sqrt(DX2 * DX2 + DY2 * DY2), 1E-12);
          F[Row] := (DX1 * DY2 - DY1 * DX2) / (N1 * N2);
          Exit;
        end;
        N1 := Max(Sqrt(DX1 * DX1 + DY1 * DY1), 1E-12);
        N2 := Max(Sqrt(DX2 * DX2 + DY2 * DY2), 1E-12);
        F[Row] := (DX1 * DX2 + DY1 * DY2) / (N1 * N2);
      end
      else if (Ents[A].Kind = seLine) or (Ents[B].Kind = seLine) then
      begin
        if Ents[A].Kind = seLine then
        begin
          L1 := LineOf(Self, A, AX);
          K := B;
        end
        else
        begin
          L1 := LineOf(Self, B, AX);
          K := A;
        end;
        PC := CenterRef(K);
        F[Row] := SignedDist(L1, PX(PC, AX), PY(PC, AX)) - Signs[CI] * Radius(K, AX);
      end
      else
      begin
        D := Sqrt(Sqr(AX[Ents[A].Base] - AX[Ents[B].Base]) +
          Sqr(AX[Ents[A].Base + 1] - AX[Ents[B].Base + 1]));
        R1 := Radius(A, AX);
        R2 := Radius(B, AX);
        if Signs[CI] > 0 then
          F[Row] := D - (R1 + R2)
        else
          F[Row] := D - Signs2[CI] * (R1 - R2);
      end;
    ckEqual:
      if Ents[A].Kind = seLine then
        F[Row] := LineLen(LineOf(Self, A, AX)) - LineLen(LineOf(Self, B, AX))
      else
        F[Row] := Radius(A, AX) - Radius(B, AX);
    ckConcentric:
      begin
        PA := CenterRef(A);
        if B >= 0 then
          PB := CenterRef(B)
        else
          PB := Pt(C.EntityB, Max(C.PointB, 1));
        F[Row] := PX(PA, AX) - PX(PB, AX);
        F[Row + 1] := PY(PA, AX) - PY(PB, AX);
      end;
    ckMidpoint:
      begin
        PA := Pt(C.EntityA, Max(C.PointA, 1));
        L1 := LineOf(Self, B, AX);
        F[Row] := PX(PA, AX) - (L1.AX + L1.BX) / 2;
        F[Row + 1] := PY(PA, AX) - (L1.AY + L1.BY) / 2;
      end;
    ckSymmetric:
      begin
        CC := EntIdx(C.EntityC);
        PA := Pt(C.EntityA, Max(C.PointA, 1));
        PB := Pt(C.EntityB, Max(C.PointB, 1));
        L1 := LineOf(Self, CC, AX);
        MX := (PX(PA, AX) + PX(PB, AX)) / 2;
        MY := (PY(PA, AX) + PY(PB, AX)) / 2;
        F[Row] := SignedDist(L1, MX, MY);
        DX1 := L1.BX - L1.AX; DY1 := L1.BY - L1.AY;
        N1 := Max(Sqrt(DX1 * DX1 + DY1 * DY1), 1E-12);
        F[Row + 1] := ((PX(PB, AX) - PX(PA, AX)) * DX1 + (PY(PB, AX) - PY(PA, AX)) * DY1) / N1;
      end;
    ckFixed:
      if C.PointA > 0 then
      begin
        PA := Pt(C.EntityA, C.PointA);
        F[Row] := PX(PA, AX) - C.Fix[0];
        F[Row + 1] := PY(PA, AX) - C.Fix[1];
      end
      else
        for K := 0 to High(C.Fix) do
          F[Row + K] := AX[Ents[A].Base + K] - C.Fix[K];
    ckDistance, ckHorizontalDistance, ckVerticalDistance:
      begin
        RawMeasure(Self, CI, AX, V);
        if SignedDim(Self, CI) then
          F[Row] := V - Signs[CI] * C.Value
        else
          F[Row] := V - C.Value;     { comprimento ou ponto-ponto: sempre positivo }
      end;
    ckRadius:
      F[Row] := Radius(A, AX) - C.Value;
    ckDiameter:
      F[Row] := 2 * Radius(A, AX) - C.Value;
    ckAngle:
      begin
        RawMeasure(Self, CI, AX, V);
        F[Row] := WrapPi(V - Signs[CI] * DegToRadC(C.Value));
      end;
  end;
end;

procedure TSystem.Residuals(const AX: TDoubleArray; var F: TDoubleArray);
var
  R, I, B: Integer;
begin
  if Length(F) <> M then
    SetLength(F, M);
  R := 0;
  while (R < M) and (RowCon[R] = -1) do
  begin
    I := RowEnt[R];
    B := Ents[I].Base;
    { |s - c| - |e - c| }
    F[R] := Sqrt(Sqr(AX[B + 2] - AX[B]) + Sqr(AX[B + 3] - AX[B + 1])) -
      Sqrt(Sqr(AX[B + 4] - AX[B]) + Sqr(AX[B + 5] - AX[B + 1]));
    Inc(R);
  end;
  for I := 0 to S.ConstraintCount - 1 do
    if ConRows[I] > 0 then
    begin
      ConResiduals(I, AX, F, R);
      Inc(R, ConRows[I]);
    end;
end;

procedure TSystem.Jacobian(const AX: TDoubleArray; var J: TDoubleArray);
var
  F0, F1, XX: TDoubleArray;
  I, K: Integer;
  H: Double;
begin
  SetLength(J, M * N);
  F0 := nil;
  F1 := nil;
  Residuals(AX, F0);
  XX := Copy(AX);
  for K := 0 to N - 1 do
  begin
    H := FD_STEP * Max(1, Abs(AX[K]));
    XX[K] := AX[K] + H;
    Residuals(XX, F1);
    XX[K] := AX[K] - H;
    Residuals(XX, F0);
    XX[K] := AX[K];
    for I := 0 to M - 1 do
      J[I * N + K] := (F1[I] - F0[I]) / (2 * H);
  end;
end;

procedure TSystem.WriteBack;
var
  I, K: Integer;
  E: TSketchEntity;
begin
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    K := Ents[I].Base;
    case E.Kind of
      sePoint: E.P1 := V2(X[K], X[K + 1]);
      seLine:
        begin
          E.P1 := V2(X[K], X[K + 1]);
          E.P2 := V2(X[K + 2], X[K + 3]);
        end;
      seCircle:
        begin
          E.P1 := V2(X[K], X[K + 1]);
          E.Radius := Abs(X[K + 2]);
        end;
      seArc:
        begin
          E.P1 := V2(X[K], X[K + 1]);
          E.P2 := V2(X[K + 2], X[K + 3]);
          E.P3 := V2(X[K + 4], X[K + 5]);
          E.Radius := Radius(I, X);
        end;
    end;
    S.SetEntity(I, E);
  end;
end;

{ ---------- algebra ---------- }

{ Resolve A y = b (A m x m, densa) por eliminacao com pivo parcial. }
function SolveDense(var A: TDoubleArray; var B: TDoubleArray; M: Integer): Boolean;
var
  I, J, K, P: Integer;
  T, Mx: Double;
begin
  for K := 0 to M - 1 do
  begin
    P := K;
    Mx := Abs(A[K * M + K]);
    for I := K + 1 to M - 1 do
      if Abs(A[I * M + K]) > Mx then
      begin
        Mx := Abs(A[I * M + K]);
        P := I;
      end;
    if Mx < 1E-300 then
      Exit(False);
    if P <> K then
    begin
      for J := 0 to M - 1 do
      begin
        T := A[K * M + J]; A[K * M + J] := A[P * M + J]; A[P * M + J] := T;
      end;
      T := B[K]; B[K] := B[P]; B[P] := T;
    end;
    for I := K + 1 to M - 1 do
    begin
      T := A[I * M + K] / A[K * M + K];
      if T <> 0 then
      begin
        for J := K to M - 1 do
          A[I * M + J] := A[I * M + J] - T * A[K * M + J];
        B[I] := B[I] - T * B[K];
      end;
    end;
  end;
  for I := M - 1 downto 0 do
  begin
    T := B[I];
    for J := I + 1 to M - 1 do
      T := T - A[I * M + J] * B[J];
    B[I] := T / A[I * M + I];
  end;
  Result := True;
end;

{ Passo de norma minima amortecido: dx = -J^T (J J^T + L I)^-1 F. }
function DampedStep(const J, F: TDoubleArray; M, N: Integer; Lambda: Double;
  out DX: TDoubleArray): Boolean;
var
  A, Y: TDoubleArray;
  I, K, C: Integer;
  S: Double;
begin
  SetLength(A, M * M);
  for I := 0 to M - 1 do
    for K := I to M - 1 do
    begin
      S := 0;
      for C := 0 to N - 1 do
        S := S + J[I * N + C] * J[K * N + C];
      A[I * M + K] := S;
      A[K * M + I] := S;
    end;
  for I := 0 to M - 1 do
    A[I * M + I] := A[I * M + I] + Lambda;
  Y := Copy(F);
  Result := SolveDense(A, Y, M);
  SetLength(DX, N);
  if not Result then
    Exit;
  for C := 0 to N - 1 do
  begin
    S := 0;
    for I := 0 to M - 1 do
      S := S + J[I * N + C] * Y[I];
    DX[C] := -S;
  end;
end;

{ ---------- analise de graus de liberdade ---------- }

procedure Analyze(Sys: TSystem; var R: TSketchSolveResult; Converged: Boolean;
  const F: TDoubleArray);
var
  J, Q, V: TDoubleArray;
  Rank, I, K, C, Row, E: Integer;
  Dot, Nrm, Nrm0, Proj: Double;
  RowRedundant: array of Boolean;
  VarDet: array of Boolean;
  Problem: array of Boolean;
  Any: Boolean;
  procedure MarkCon(CI: Integer; St: TSketchConstraintState);
  begin
    if (CI >= 0) and (R.ConstraintState[CI] = csOk) then
      R.ConstraintState[CI] := St;
  end;
  procedure MarkEnt(AEnt: Integer);
  var
    EI: Integer;
  begin
    EI := Sys.EntIdx(AEnt);
    if EI >= 0 then
      Problem[EI] := True;
  end;
begin
  R.VarCount := Sys.N;
  R.EqCount := Sys.M;
  SetLength(R.ConstraintState, Sys.S.ConstraintCount);
  SetLength(R.EntityState, Sys.S.EntityCount);
  for I := 0 to High(R.ConstraintState) do
    if Sys.ConValid[I] then
      R.ConstraintState[I] := csOk
    else
      R.ConstraintState[I] := csInvalid;
  SetLength(Problem, Sys.S.EntityCount);
  for I := 0 to High(Problem) do
    Problem[I] := False;

  J := nil;
  if (Sys.M > 0) and (Sys.N > 0) then
    Sys.Jacobian(Sys.X, J);
  { Gram-Schmidt modificado com reortogonalizacao }
  SetLength(Q, 0);
  SetLength(RowRedundant, Sys.M);
  SetLength(V, Sys.N);
  Rank := 0;
  for Row := 0 to Sys.M - 1 do
  begin
    for C := 0 to Sys.N - 1 do
      V[C] := J[Row * Sys.N + C];
    Nrm0 := 0;
    for C := 0 to Sys.N - 1 do
      Nrm0 := Nrm0 + V[C] * V[C];
    Nrm0 := Sqrt(Nrm0);
    for E := 1 to 2 do
      for K := 0 to Rank - 1 do
      begin
        Dot := 0;
        for C := 0 to Sys.N - 1 do
          Dot := Dot + V[C] * Q[K * Sys.N + C];
        for C := 0 to Sys.N - 1 do
          V[C] := V[C] - Dot * Q[K * Sys.N + C];
      end;
    Nrm := 0;
    for C := 0 to Sys.N - 1 do
      Nrm := Nrm + V[C] * V[C];
    Nrm := Sqrt(Nrm);
    if (Nrm0 < 1E-12) or (Nrm <= RANK_TOL * Max(1, Nrm0)) then
      RowRedundant[Row] := True
    else
    begin
      RowRedundant[Row] := False;
      SetLength(Q, (Rank + 1) * Sys.N);
      for C := 0 to Sys.N - 1 do
        Q[Rank * Sys.N + C] := V[C] / Nrm;
      Inc(Rank);
    end;
  end;
  R.Rank := Rank;
  R.DOF := Sys.N - Rank;

  { variaveis determinadas }
  SetLength(VarDet, Sys.N);
  for C := 0 to Sys.N - 1 do
  begin
    Proj := 0;
    for K := 0 to Rank - 1 do
      Proj := Proj + Sqr(Q[K * Sys.N + C]);
    VarDet[C] := Proj > 1 - 1E-6;
  end;

  { restricoes redundantes e em conflito }
  for Row := 0 to Sys.M - 1 do
  begin
    C := Sys.RowCon[Row];
    if C < 0 then
      Continue;
    if not Converged and (Abs(F[Row]) > 1E-6) then
      MarkCon(C, csConflict)
    else if RowRedundant[Row] then
      MarkCon(C, csRedundant);
  end;
  Any := False;
  for I := 0 to High(R.ConstraintState) do
    if R.ConstraintState[I] in [csRedundant, csConflict, csInvalid] then
    begin
      Any := True;
      MarkEnt(Sys.S.Constraint(I).EntityA);
      MarkEnt(Sys.S.Constraint(I).EntityB);
      MarkEnt(Sys.S.Constraint(I).EntityC);
    end;

  for I := 0 to Sys.S.EntityCount - 1 do
  begin
    if Problem[I] then
      R.EntityState[I] := esProblem
    else
    begin
      R.EntityState[I] := esDefined;
      for K := 0 to Sys.Ents[I].Count - 1 do
        if not VarDet[Sys.Ents[I].Base + K] then
        begin
          R.EntityState[I] := esFree;
          Break;
        end;
    end;
  end;

  if Sys.S.EntityCount = 0 then
    R.Status := ssEmpty
  else if not Converged then
    R.Status := ssConflict
  else if Any then
    R.Status := ssOverDefined
  else if R.DOF = 0 then
    R.Status := ssFullyDefined
  else
    R.Status := ssUnderDefined;
end;

procedure MeasureDriven(Sys: TSystem);
var
  I: Integer;
  V: Double;
  C: TSketchConstraint;
begin
  for I := 0 to Sys.S.ConstraintCount - 1 do
  begin
    C := Sys.S.Constraint(I);
    if IsDimensionKind(C.Kind) and not C.Driving then
      if CadMeasureDimension(Sys.S, I, V) then
        Sys.S.SetConstraintValue(I, V);
  end;
end;

function CadMeasureDimension(S: TCadSketch; AIndex: Integer; out AValue: Double): Boolean;
var
  Sys: TSystem;
  V: Double;
begin
  AValue := 0;
  Sys := TSystem.Create(S);
  try
    Result := RawMeasure(Sys, AIndex, Sys.X, V);
    if Result then
    begin
      if S.Constraint(AIndex).Kind = ckAngle then
        AValue := Abs(RadToDegC(V))
      else
        AValue := Abs(V);
    end;
  finally
    Sys.Free;
  end;
end;

function CadAnalyzeSketch(S: TCadSketch): TSketchSolveResult;
var
  Sys: TSystem;
  F: TDoubleArray;
begin
  Result := Default(TSketchSolveResult);
  Sys := TSystem.Create(S);
  try
    F := nil;
    Sys.Residuals(Sys.X, F);
    Result.Residual := NormInf(F);
    Result.Converged := Result.Residual <= 1E-6;
    Analyze(Sys, Result, Result.Converged, F);
  finally
    Sys.Free;
  end;
end;

function CadSolveSketch(S: TCadSketch; AMaxIter: Integer): TSketchSolveResult;
var
  Sys: TSystem;
  F, FN, J, DX, XN, X0: TDoubleArray;
  Lambda, E0, E1: Double;
  It, I: Integer;
  Inner: Integer;
  Accepted: Boolean;
begin
  Result := Default(TSketchSolveResult);
  Sys := TSystem.Create(S);
  try
    for I := 0 to S.ConstraintCount - 1 do
      if not Sys.ConValid[I] then
      begin
        Result.Message := Format('Restrição %d (%s) com entidades incompatíveis',
          [S.Constraint(I).Id, CadConstraintName(S.Constraint(I).Kind)]);
        Break;
      end;
    X0 := Copy(Sys.X);
    F := nil;
    FN := nil;
    Sys.Residuals(Sys.X, F);
    E0 := Norm2(F);
    Lambda := 1E-6;
    It := 0;
    while (It < AMaxIter) and (NormInf(F) > SOLVE_TOL) and (Sys.M > 0) do
    begin
      Inc(It);
      Sys.Jacobian(Sys.X, J);
      Accepted := False;
      for Inner := 1 to 30 do
      begin
        if not DampedStep(J, F, Sys.M, Sys.N, Lambda, DX) then
        begin
          Lambda := Lambda * 10;
          Continue;
        end;
        XN := Copy(Sys.X);
        for I := 0 to Sys.N - 1 do
          XN[I] := XN[I] + DX[I];
        Sys.Residuals(XN, FN);
        E1 := Norm2(FN);
        if E1 < E0 then
        begin
          Sys.X := XN;
          F := Copy(FN);
          E0 := E1;
          Lambda := Max(Lambda / 10, 1E-12);
          Accepted := True;
          Break;
        end;
        Lambda := Lambda * 10;
        if Lambda > 1E8 then
          Break;
      end;
      if not Accepted then
        Break;
    end;
    Result.Iterations := It;
    Result.Residual := NormInf(F);
    Result.Converged := Result.Residual <= 1E-6;
    if Result.Converged then
    begin
      Sys.WriteBack;
      Analyze(Sys, Result, True, F);
    end
    else
    begin
      { analisa no ponto alcancado para apontar o conflito, mas nao grava }
      Analyze(Sys, Result, False, F);
      Sys.X := X0;
      if Result.Message = '' then
        Result.Message := 'As restrições e cotas não podem ser satisfeitas ao mesmo tempo';
    end;
  finally
    Sys.Free;
  end;
  { cotas dirigidas: mede depois de gravar }
  Sys := TSystem.Create(S);
  try
    MeasureDriven(Sys);
  finally
    Sys.Free;
  end;
  case Result.Status of
    ssUnderDefined:
      if Result.Message = '' then
        Result.Message := Format('Subdefinido: %d grau(s) de liberdade', [Result.DOF]);
    ssFullyDefined:
      if Result.Message = '' then
        Result.Message := 'Totalmente definido';
    ssOverDefined:
      if Result.Message = '' then
        Result.Message := 'Superdefinido: há restrições ou cotas redundantes (torne a cota dirigida ou exclua)';
  end;
end;

end.
