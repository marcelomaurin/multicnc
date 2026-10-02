program test_newton_ode;
{$mode objfpc}{$H+}
{ MultiPhysics: MNA Newton-Raphson nao linear (diodo, MOSFET, retificador,
  RC/LC trapezoidal) e integradores RK4 / Dormand-Prince 45 / Verlet. }
uses SysUtils, Math, multiphysics_circuit_newton, multiphysics_ode;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

type
  TSystems = class
    Calls: Integer;
    procedure Decay(T: Double; const Y: TODEVector; var DY: TODEVector);
    procedure Oscillator(T: Double; const Y: TODEVector; var DY: TODEVector);
    procedure VanDerPol(T: Double; const Y: TODEVector; var DY: TODEVector);
    procedure Spring(T: Double; const X, V: TODEVector; var A: TODEVector);
  end;

procedure TSystems.Decay(T: Double; const Y: TODEVector; var DY: TODEVector);
begin Inc(Calls); DY[0] := -Y[0]; end;

procedure TSystems.Oscillator(T: Double; const Y: TODEVector; var DY: TODEVector);
begin DY[0] := Y[1]; DY[1] := -Y[0]; end;

procedure TSystems.VanDerPol(T: Double; const Y: TODEVector; var DY: TODEVector);
begin DY[0] := Y[1]; DY[1] := 1.0 * (1 - Sqr(Y[0])) * Y[1] - Y[0]; end;

procedure TSystems.Spring(T: Double; const X, V: TODEVector; var A: TODEVector);
begin A[0] := -X[0]; end;

var
  C: TNewtonCircuit;
  Vd, Id, Vout, VMax, VMin, Exact, ErrTrap, ErrBE, Amp, E0, E1: Double;
  D, Cap, Ind, M, I, Steps: Integer;
  Sys: TSystems;
  Y, X, V: TODEVector;
  St: TAdaptiveStats;
  Crossings: Integer;
  TPrev, YPrev, Period: Double;
begin
  C := TNewtonCircuit.Create;
  Sys := TSystems.Create;
  try
    { 1. Diodo 1N4148 + resistor: KCL satisfeita na solucao }
    C.AddVSource('in', '0', 5);
    C.AddResistor('in', 'a', 1000);
    D := C.AddDiode('a', '0', 2.52e-9, 1.752);
    Check(C.SolveDC, 'DC do diodo: ' + C.LastError);
    Vd := C.NodeVoltage('a');
    Id := C.ElementCurrent(D);
    Check((Vd > 0.6) and (Vd < 0.75), Format('queda do diodo %.4f V', [Vd]));
    Check(Abs((5 - Vd) / 1000 - Id) < 1e-7, 'KCL no diodo');
    Check(C.LastIterations < 60, Format('convergencia em %d iteracoes', [C.LastIterations]));

    { 2. Convergencia a partir de condicao dificil: 100 V em dois diodos }
    C.Clear;
    C.AddVSource('in', '0', 100);
    C.AddResistor('in', 'a', 10);
    C.AddDiode('a', 'b', 1e-14, 1);
    C.AddDiode('b', '0', 1e-14, 1);
    Check(C.SolveDC, 'convergencia com limitacao de juncao: ' + C.LastError);
    Check((C.NodeVoltage('a') > 1.4) and (C.NodeVoltage('a') < 2.2), 'dois diodos em serie');

    { 3. NMOS como chave }
    C.Clear;
    C.AddVSource('vdd', '0', 12);
    I := C.AddVSource('g', '0', 10);
    C.AddResistor('vdd', 'd', 100);
    M := C.AddNMOS('d', 'g', '0', 2, 1, 0.01);
    Check(C.SolveDC, 'DC do MOSFET: ' + C.LastError);
    Check(C.NodeVoltage('d') < 0.5, Format('MOSFET saturado como chave (Vds=%.3f)', [C.NodeVoltage('d')]));
    Check(Abs(C.ElementCurrent(M) - (12 - C.NodeVoltage('d')) / 100) < 1e-6, 'corrente de dreno');
    C.SetSourceValue(I, 0);
    Check(C.SolveDC and (Abs(C.NodeVoltage('d') - 12) < 1e-3), 'MOSFET cortado');
    C.Clear;
    C.AddVSource('vdd', '0', 12);
    C.AddVSource('g', '0', 3);
    C.AddResistor('vdd', 'd', 10);
    M := C.AddNMOS('d', 'g', '0', 2, 1, 0.01);
    Check(C.SolveDC, 'regiao de saturacao');
    Check(C.NodeVoltage('d') > 1, 'Vds acima de Vov (saturacao)');
    // Id = K/2 (Vgs-Vt)^2 (1+lambda Vds) = 0.5*1*1*(1+0.01*Vds)
    Check(Abs(C.ElementCurrent(M) - 0.5 * (1 + 0.01 * C.NodeVoltage('d'))) < 1e-4, 'equacao de saturacao');

    { 4. RC: trapezoidal muito mais preciso que Euler implicito }
    C.Clear;
    C.AddVSource('in', '0', 10);
    C.AddResistor('in', 'out', 1000);
    Cap := C.AddCapacitor('out', '0', 1e-6);  // tau = 1 ms
    C.BeginTransient(5e-5, True, imTrapezoidal);
    for I := 1 to 20 do Check(C.StepTransient, 'passo RC');
    Exact := 10 * (1 - Exp(-1));
    ErrTrap := Abs(C.NodeVoltage('out') - Exact);
    C.BeginTransient(5e-5, True, imBackwardEuler);
    for I := 1 to 20 do C.StepTransient;
    ErrBE := Abs(C.NodeVoltage('out') - Exact);
    Check(ErrTrap < 0.01, Format('RC trapezoidal (erro %.5f V)', [ErrTrap]));
    Check(ErrTrap < ErrBE / 3, Format('trapezio melhor que Euler (%.5f vs %.5f)', [ErrTrap, ErrBE]));
    Check(Abs(C.ElementCurrent(Cap)) > 0, 'corrente do capacitor');

    { 5. Tanque LC: amplitude preservada pelo trapezio }
    C.Clear;
    Cap := C.AddCapacitor('x', '0', 1e-6);
    Ind := C.AddInductor('x', '0', 1e-3);    // f0 = 5.03 kHz
    C.SetInitialVoltage(Cap, 1);
    C.BeginTransient(2e-6, True, imTrapezoidal);
    Amp := 0;
    Steps := Round(10 * 2 * Pi * Sqrt(1e-3 * 1e-6) / 2e-6); // 10 periodos
    for I := 1 to Steps do begin
      Check(C.StepTransient, 'passo LC');
      if I > Steps - 120 then Amp := Max(Amp, Abs(C.NodeVoltage('x')));
    end;
    Check(Abs(Amp - 1) < 0.02, Format('LC sem amortecimento numerico (amp %.4f)', [Amp]));
    Check(Abs(C.ElementCurrent(Ind)) <= 1 / Sqrt(1e-3 / 1e-6) * 1.02, 'corrente maxima do indutor');

    { 6. Retificador de meia onda com filtro capacitivo }
    C.Clear;
    C.AddSineSource('ac', '0', 0, 10, 50);
    C.AddDiode('ac', 'out', 2.52e-9, 1.752);
    C.AddResistor('out', '0', 1000);
    C.AddCapacitor('out', '0', 100e-6);
    Check(C.BeginTransient(1e-4), 'inicio do retificador');
    VMax := -1e9; VMin := 1e9;
    for I := 1 to 1000 do begin   // 100 ms = 5 ciclos
      Check(C.StepTransient, 'passo do retificador em t=' + FloatToStr(C.Time) + ': ' + C.LastError);
      if C.Time > 0.06 then begin
        Vout := C.NodeVoltage('out');
        VMax := Max(VMax, Vout); VMin := Min(VMin, Vout);
      end;
    end;
    Check((VMax > 8.8) and (VMax < 9.6), Format('pico retificado %.3f V', [VMax]));
    // ondulacao ~ I/(f*C) = 9 mA / (50 Hz * 100 uF) = 1.8 V
    Check((VMax - VMin > 1.2) and (VMax - VMin < 2.4), Format('ondulacao %.3f V', [VMax - VMin]));

    { 7. Integradores }
    SetLength(Y, 1); Y[0] := 1;
    St := DormandPrince45(@Sys.Decay, 0, 5, Y, 1e-9, 1e-12);
    Check(St.Success and (Abs(Y[0] - Exp(-5)) < 1e-9), Format('DP45 exponencial (%.3e)', [Abs(Y[0] - Exp(-5))]));
    Check(St.Accepted < 200, Format('DP45 passos adaptativos (%d)', [St.Accepted]));
    SetLength(Y, 1); Y[0] := 1;
    RK4Integrate(@Sys.Decay, 0, 5, 100, Y);
    Check(Abs(Y[0] - Exp(-5)) < 1e-6, 'RK4');
    // Van der Pol (mu=1): periodo do ciclo limite ~ 6.6633
    SetLength(Y, 2); Y[0] := 2; Y[1] := 0;
    St := DormandPrince45(@Sys.VanDerPol, 0, 30, Y, 1e-8, 1e-10); // transiente
    Crossings := 0; TPrev := 30; YPrev := Y[0]; Period := 0;
    for I := 1 to 3000 do begin
      DormandPrince45(@Sys.VanDerPol, 30 + (I - 1) * 0.01, 30 + I * 0.01, Y, 1e-9, 1e-11);
      if (YPrev < 0) and (Y[0] >= 0) then begin
        if Crossings > 0 then Period := (30 + I * 0.01) - TPrev;
        TPrev := 30 + I * 0.01;
        Inc(Crossings);
      end;
      YPrev := Y[0];
    end;
    Check(Abs(Period - 6.6633) < 0.02, Format('periodo de Van der Pol %.4f', [Period]));
    // Energia: Verlet conserva, Euler explicito diverge
    SetLength(X, 1); SetLength(V, 1); X[0] := 1; V[0] := 0;
    E0 := 0.5 * (Sqr(X[0]) + Sqr(V[0]));
    for I := 1 to 100000 do VelocityVerletStep(@Sys.Spring, I * 0.05, 0.05, X, V);
    E1 := 0.5 * (Sqr(X[0]) + Sqr(V[0]));
    Check(Abs(E1 - E0) / E0 < 1e-3, Format('Verlet conserva energia (%.2e)', [Abs(E1 - E0) / E0]));
    SetLength(Y, 2); Y[0] := 1; Y[1] := 0;
    for I := 1 to 1000 do ExplicitEulerStep(@Sys.Oscillator, I * 0.05, 0.05, Y);
    Check(0.5 * (Sqr(Y[0]) + Sqr(Y[1])) > 2 * E0, 'Euler explicito ganha energia (referencia)');
    WriteLn(Format('MultiPhysics Newton/ODE: OK (Vd=%.4f V, ripple=%.2f V, DP45 %d passos, Van der Pol T=%.4f)',
      [Vd, VMax - VMin, St.Accepted, Period]));
  finally
    Sys.Free;
    C.Free;
  end;
end.
