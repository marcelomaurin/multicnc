unit multiphysics_ode;

{$mode objfpc}{$H+}

{ Integradores numericos para os modelos dinamicos do MultiPhysics.

  - RK4: Runge-Kutta classico de 4a ordem, passo fixo.
  - DormandPrince45: Runge-Kutta embarcado 5(4) com controle adaptativo de
    passo por erro relativo/absoluto e FSAL - o mesmo metodo do ode45 do
    MATLAB e do solve_ivp(RK45) do SciPy. Ajusta o passo sozinho: grande em
    trechos suaves, pequeno em transitorios rapidos.
  - VelocityVerlet / SymplecticEuler: integradores simpleticos para sistemas
    mecanicos (massa-mola, corpos rigidos, eixos). Preservam a energia em
    longo prazo - Euler explicito ganha energia artificialmente e "explode".

  O sistema e descrito por um callback Derivs(T, Y, DY). }

interface

uses Math, SysUtils;

type
  TODEVector = array of Double;
  TODEDerivs = procedure(T: Double; const Y: TODEVector; var DY: TODEVector) of object;
  { Aceleracao para sistemas de 2a ordem: A = f(T, X, V) }
  TODEAccel = procedure(T: Double; const X, V: TODEVector; var A: TODEVector) of object;

  TAdaptiveStats = record
    Accepted, Rejected, Evaluations: Integer;
    LastStep, MinStep, MaxStep: Double;
    Success: Boolean;
  end;

procedure RK4Step(F: TODEDerivs; T, H: Double; var Y: TODEVector);
procedure RK4Integrate(F: TODEDerivs; T0, T1: Double; Steps: Integer; var Y: TODEVector);
function DormandPrince45(F: TODEDerivs; T0, T1: Double; var Y: TODEVector;
  RelTol: Double = 1e-6; AbsTol: Double = 1e-9; InitialStep: Double = 0;
  MaxSteps: Integer = 1000000): TAdaptiveStats;
procedure VelocityVerletStep(Acc: TODEAccel; T, H: Double; var X, V: TODEVector);
procedure SymplecticEulerStep(Acc: TODEAccel; T, H: Double; var X, V: TODEVector);
procedure ExplicitEulerStep(F: TODEDerivs; T, H: Double; var Y: TODEVector);

implementation

function Combine(const Y: TODEVector; const K: array of TODEVector; const C: array of Double; H: Double): TODEVector;
var I, J: Integer; S: Double;
begin
  SetLength(Result, Length(Y));
  for I := 0 to High(Y) do begin
    S := 0;
    for J := 0 to High(C) do
      if C[J] <> 0 then S := S + C[J] * K[J][I];
    Result[I] := Y[I] + H * S;
  end;
end;

procedure ExplicitEulerStep(F: TODEDerivs; T, H: Double; var Y: TODEVector);
var D: TODEVector; I: Integer;
begin
  SetLength(D, Length(Y));
  F(T, Y, D);
  for I := 0 to High(Y) do Y[I] := Y[I] + H * D[I];
end;

procedure RK4Step(F: TODEDerivs; T, H: Double; var Y: TODEVector);
var K: array[0..3] of TODEVector; Tmp: TODEVector; I, N: Integer;
begin
  N := Length(Y);
  for I := 0 to 3 do SetLength(K[I], N);
  F(T, Y, K[0]);
  Tmp := Combine(Y, K, [0.5], H);
  F(T + H / 2, Tmp, K[1]);
  Tmp := Combine(Y, K, [0, 0.5], H);
  F(T + H / 2, Tmp, K[2]);
  Tmp := Combine(Y, K, [0, 0, 1], H);
  F(T + H, Tmp, K[3]);
  for I := 0 to N - 1 do
    Y[I] := Y[I] + H / 6 * (K[0][I] + 2 * K[1][I] + 2 * K[2][I] + K[3][I]);
end;

procedure RK4Integrate(F: TODEDerivs; T0, T1: Double; Steps: Integer; var Y: TODEVector);
var I: Integer; H: Double;
begin
  if Steps < 1 then Steps := 1;
  H := (T1 - T0) / Steps;
  for I := 0 to Steps - 1 do RK4Step(F, T0 + I * H, H, Y);
end;

function DormandPrince45(F: TODEDerivs; T0, T1: Double; var Y: TODEVector;
  RelTol, AbsTol, InitialStep: Double; MaxSteps: Integer): TAdaptiveStats;
const
  C2 = 1/5; C3 = 3/10; C4 = 4/5; C5 = 8/9;
  A21 = 1/5;
  A31 = 3/40; A32 = 9/40;
  A41 = 44/45; A42 = -56/15; A43 = 32/9;
  A51 = 19372/6561; A52 = -25360/2187; A53 = 64448/6561; A54 = -212/729;
  A61 = 9017/3168; A62 = -355/33; A63 = 46732/5247; A64 = 49/176; A65 = -5103/18656;
  B1 = 35/384; B3 = 500/1113; B4 = 125/192; B5 = -2187/6784; B6 = 11/84;
  // erro = solucao de 5a ordem - embarcada de 4a ordem
  E1 = 71/57600; E3 = -71/16695; E4 = 71/1920; E5 = -17253/339200; E6 = 22/525; E7 = -1/40;
var
  K: array[0..6] of TODEVector;
  YNew, Tmp: TODEVector;
  N, I, Steps: Integer;
  T, H, Err, Sc, Fac, Dir: Double;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.MinStep := MaxDouble;
  N := Length(Y);
  if (N = 0) or (T1 = T0) then begin Result.Success := True; Exit; end;
  for I := 0 to 6 do SetLength(K[I], N);
  Dir := Sign(T1 - T0);
  T := T0;
  F(T, Y, K[0]);
  Inc(Result.Evaluations);
  // passo inicial (heuristica de Hairer)
  if InitialStep > 0 then H := InitialStep
  else begin
    Sc := 0; Fac := 0;
    for I := 0 to N - 1 do begin
      Sc := Sc + Sqr(Y[I] / (AbsTol + Abs(Y[I]) * RelTol));
      Fac := Fac + Sqr(K[0][I] / (AbsTol + Abs(Y[I]) * RelTol));
    end;
    Sc := Sqrt(Sc / N); Fac := Sqrt(Fac / N);
    if (Sc < 1e-5) or (Fac < 1e-5) then H := 1e-6 else H := 0.01 * Sc / Fac;
    H := Min(H, Abs(T1 - T0));
  end;
  H := Abs(H) * Dir;
  SetLength(YNew, N);
  Steps := 0;
  while (T1 - T) * Dir > 1e-15 * Max(1, Abs(T1)) do begin
    if Steps >= MaxSteps then Exit;
    Inc(Steps);
    if (T + H - T1) * Dir > 0 then H := T1 - T;
    Tmp := Combine(Y, K, [A21], H); F(T + C2 * H, Tmp, K[1]);
    Tmp := Combine(Y, K, [A31, A32], H); F(T + C3 * H, Tmp, K[2]);
    Tmp := Combine(Y, K, [A41, A42, A43], H); F(T + C4 * H, Tmp, K[3]);
    Tmp := Combine(Y, K, [A51, A52, A53, A54], H); F(T + C5 * H, Tmp, K[4]);
    Tmp := Combine(Y, K, [A61, A62, A63, A64, A65], H); F(T + H, Tmp, K[5]);
    YNew := Combine(Y, K, [B1, 0, B3, B4, B5, B6], H);
    F(T + H, YNew, K[6]);
    Inc(Result.Evaluations, 6);
    Err := 0;
    for I := 0 to N - 1 do begin
      Sc := AbsTol + RelTol * Max(Abs(Y[I]), Abs(YNew[I]));
      Err := Err + Sqr(H * (E1 * K[0][I] + E3 * K[2][I] + E4 * K[3][I] + E5 * K[4][I] +
        E6 * K[5][I] + E7 * K[6][I]) / Sc);
    end;
    Err := Sqrt(Err / N);
    if (Err <= 1) or (Abs(H) < 1e-14 * Max(1, Abs(T))) then begin
      T := T + H;
      Y := Copy(YNew);
      K[0] := Copy(K[6]); // FSAL: ultima avaliacao vira a primeira do proximo passo
      Inc(Result.Accepted);
      Result.LastStep := Abs(H);
      Result.MinStep := Min(Result.MinStep, Abs(H));
      Result.MaxStep := Max(Result.MaxStep, Abs(H));
    end else
      Inc(Result.Rejected);
    // novo passo: fator de seguranca 0.9, limitado a [0.2, 5]
    if Err = 0 then Fac := 5 else Fac := Min(5, Max(0.2, 0.9 * Power(Err, -0.2)));
    H := H * Fac;
  end;
  Result.Success := True;
end;

procedure VelocityVerletStep(Acc: TODEAccel; T, H: Double; var X, V: TODEVector);
var A0, A1: TODEVector; I, N: Integer;
begin
  N := Length(X);
  SetLength(A0, N);
  SetLength(A1, N);
  Acc(T, X, V, A0);
  for I := 0 to N - 1 do X[I] := X[I] + H * V[I] + 0.5 * H * H * A0[I];
  // aceleracao depende so da posicao (forcas conservativas); V e usado
  // como estimativa para termos dissipativos leves
  Acc(T + H, X, V, A1);
  for I := 0 to N - 1 do V[I] := V[I] + 0.5 * H * (A0[I] + A1[I]);
end;

procedure SymplecticEulerStep(Acc: TODEAccel; T, H: Double; var X, V: TODEVector);
var A: TODEVector; I: Integer;
begin
  SetLength(A, Length(X));
  Acc(T, X, V, A);
  for I := 0 to High(X) do begin
    V[I] := V[I] + H * A[I];
    X[I] := X[I] + H * V[I];
  end;
end;

end.
