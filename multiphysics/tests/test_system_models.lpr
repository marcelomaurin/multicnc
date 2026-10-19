program test_system_models;

{ Modelos de sistema da Fase 7 contra casos analiticos:
  motor DC (velocidade final V/Ke e constante de tempo J R/(Kt Ke)),
  controle em malha fechada, maquina CNC (posicao final, rampa, curva de
  torque, homing, falhas), MNA (fonte de corrente, ponte de Wheatstone, no
  flutuante), eletronica (buck, boost, 555), bateria, solenoide e saturacao,
  acoplamento runtime -> FEM e gravador CSV. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, multiphysics_types, multiphysics_runtime, multiphysics_runtime_types,
  multiphysics_components, multiphysics_machine_runtime, multiphysics_machine_faults,
  multiphysics_mna, multiphysics_digital_power, multiphysics_energy_chemistry,
  multiphysics_electromagnetics, multiphysics_coupling, multiphysics_project,
  multiphysics_instruments, multiphysics_check;

var
  Ok: Boolean;

procedure TestOpenLoop;
var
  R: TSimulationRuntime;
  M: TDCMotor;
  L: TAxisLoad;
  Tau, WInf, J, T63: Double;
  I: Integer;
begin
  Section('Motor DC: velocidade final e constante de tempo');
  R := TSimulationRuntime.Create;
  try
    M := R.Motor; M.ViscousFriction := 0; M.Inductance := 1e-5; R.Motor := M;
    L := R.Load; L.Friction := 0; L.ExternalTorque := 0; R.Load := L;
    R.Reset;
    R.Dt := 1e-4;
    R.ManualPWM := 1;
    R.ControlEnabled := False;
    J := M.Inertia + L.Inertia;
    WInf := 24 / M.Ke;
    Tau := J * M.Resistance / (M.Kt * M.Ke);
    R.Start;
    T63 := -1;
    for I := 1 to Round(10 * Tau / 1e-4) do
    begin
      R.Step;
      if (T63 < 0) and (R.Snapshot.Mechanical.Velocity >= WInf * (1 - Exp(-1))) then T63 := R.Snapshot.Clock.Time;
    end;
    CheckNear(R.Snapshot.Mechanical.Velocity, WInf, 0.01, 'velocidade final a vazio = V / Ke');
    CheckNear(T63, Tau, 0.03, 'constante de tempo mecanica J R / (Kt Ke)');
  finally
    R.Free;
  end;
end;

procedure TestClosedLoop;
var
  R: TSimulationRuntime;
  I: Integer;
begin
  Section('Controle PI de velocidade');
  R := TSimulationRuntime.Create;
  try
    R.Start;
    for I := 1 to 6000 do R.Step;
    CheckNear(R.Snapshot.Mechanical.Velocity, R.Snapshot.Control.SetPoint, 0.02,
      Format('velocidade chega a referencia (%.1f rad/s)', [R.Snapshot.Control.SetPoint]));
  finally
    R.Free;
  end;
end;

procedure TestMachine;
var
  M: TMachineRuntime;
  A: TAxisRuntime;
  T, Vmax: Double;
  I: Integer;
begin
  Section('Maquina CNC: posicao, rampa, torque, homing');
  M := TMachineRuntime.Create;
  try
    A := M.AddAxis('X', 0, 300, 80, 1.2);
    A.Accel := 500;
    M.Start;
    M.CommandAxis('X', 100, 50);
    Vmax := 0;
    for I := 1 to 20000 do
    begin
      M.Step;
      Vmax := Max(Vmax, Abs(A.State.VelocityMMs));
      if (Abs(A.State.PositionMM - 100) < 1e-9) and (A.State.VelocityMMs = 0) then Break;
    end;
    CheckNear(A.State.PositionMM, 100, 1 / 80 / 100, 'X = 100 mm exato (dentro de um passo)');
    Check(Vmax <= 50 + 1e-9, Format('velocidade maxima respeitada (%.2f mm/s)', [Vmax]));
    { tempo do trapezio: d/v + v/a }
    CheckNear(M.Time, 100 / 50 + 50 / 500, 0.03, 'tempo do movimento trapezoidal d/v + v/a');
    { curva de torque: carga que o motor vence devagar mas nao rapido }
    A.NoLoadSpeed := 100;
    A.Motor.LoadTorque := 0.8;      { disponivel: 1,2 (1 - v/100) }
    M.CommandAxis('X', 120, 10);    { a 10 mm/s: 1,08 > 0,8: anda }
    M.RunUntilIdle(10);
    CheckNear(A.State.PositionMM, 120, 1 / 80 / 100, 'devagar: carga vencida, chega ao alvo');
    Check(A.State.LostSteps = 0, 'devagar: nenhum passo perdido');
    A.Accel := 0;
    M.CommandAxis('X', 200, 60);    { a 60 mm/s: 0,48 < 0,8: estol }
    for I := 1 to 500 do M.Step;
    Check(A.State.LostSteps > 0, Format('rapido: estol com %d passos perdidos', [A.State.LostSteps]));
    A.Motor.LoadTorque := 0;
    { homing }
    Ok := M.HomeAxis('X', 200);
    Check(Ok and A.Homed and (Abs(A.ReadPositionMM - 0) < 1e-9), 'homing encontra o fim de curso e zera');
  finally
    M.Free;
  end;
end;

procedure TestFaults;
var
  M: TMachineRuntime;
  A: TAxisRuntime;
  I: Integer;
  Pos0: Double;
begin
  Section('Falhas da maquina');
  M := TMachineRuntime.Create;
  try
    A := M.AddAxis('X', 0, 300, 80, 1.2);
    M.Start;
    InjectAxisFault(A, mfShortCircuit);
    M.CommandAxis('X', 10, 20);
    M.Step;
    Check(Pos('SOBRECORRENTE', M.TripReason) > 0, 'curto-circuito desarma por sobrecorrente: ' + M.TripReason);
    ClearAxisFaults(A);
    M.Start;
    InjectAxisFault(A, mfAxisLocked);
    M.CommandAxis('X', 50, 20);
    Pos0 := A.State.PositionMM;
    for I := 1 to 200 do M.Step;
    Check((A.State.LostSteps > 0) and (Abs(A.State.PositionMM - Pos0) < 1e-9), 'eixo travado: nao anda e perde passos');
    ClearAxisFaults(A);
    InjectAxisFault(A, mfSensorFailed);
    M.CommandAxis('X', 50, 50);
    M.RunUntilIdle(10);
    CheckNear(A.State.PositionMM, 45, 1e-3, 'sensor com erro de 5 mm: o eixo para 5 mm antes');
    ClearAxisFaults(A);
    M.CommandAxis('X', 30, 50);
    M.RunUntilIdle(10);
    InjectAxisFault(A, mfLimitStuck);
    Ok := M.HomeAxis('X', 50);
    Check(Ok and (Abs(A.ReadPositionMM) < 1e-9) and (Abs(A.State.PositionMM - 30) < 1e-3),
      'fim de curso preso: homing zera a 30 mm da posicao real');
    ClearAxisFaults(A);
    InjectAxisFault(A, mfCorrosion);
    Check(SameValue(A.ResistanceFactor, 1.6), 'corrosao aumenta o aquecimento I2R');
    InjectAxisFault(A, mfOverCurrent);
    M.Start;
    M.CommandAxis('X', 100, 20);
    M.Step;
    Check(Pos('SOBRECORRENTE', M.TripReason) > 0, 'sobrecorrente desarma');
  finally
    M.Free;
  end;
end;

procedure TestMNA;
var
  S: TMNASolver;
  V, A, B, C: Integer;
begin
  Section('MNA');
  S := TMNASolver.Create;
  try
    S.Clear;
    A := S.AddNode('A');
    S.AddCurrentSource(0, A, 0.002);      { 2 mA entrando em A }
    S.AddResistor(A, 0, 1000);
    Ok := S.Solve;
    Check(Ok and SameValue(S.NodeVoltage(A), 2, 1e-9), 'fonte de corrente 2 mA em 1 k = 2 V');
    S.Clear;
    V := S.AddNode('V'); A := S.AddNode('A'); B := S.AddNode('B');
    S.AddVoltageSource(V, 0, 10);
    S.AddResistor(V, A, 1000); S.AddResistor(A, 0, 2000);
    S.AddResistor(V, B, 1500); S.AddResistor(B, 0, 3000);
    S.AddResistor(A, B, 500);
    Ok := S.Solve;
    Check(Ok and (Abs(S.NodeVoltage(A) - S.NodeVoltage(B)) < 1e-9), 'ponte de Wheatstone equilibrada: V(A) = V(B)');
    S.Clear;
    A := S.AddNode('A'); C := S.AddNode('ILHA');
    S.AddVoltageSource(A, 0, 5);
    S.AddResistor(A, 0, 100);
    S.AddCurrentSource(0, C, 0.001);
    Ok := S.Solve;
    Check(not Ok and (Pos('ILHA', S.LastError) > 0), 'no flutuante identificado: ' + S.LastError);
  finally
    S.Free;
  end;
end;

procedure TestElectronics;
var
  T: TTimer555;
  B: TBatteryModel;
  I: Integer;
  C: TCoilModel;
begin
  Section('Eletronica, bateria e eletromagnetismo');
  CheckNear(BuckOutput(24, 0.5, 1), 12, 1e-12, 'buck ideal: Vout = D Vin');
  CheckNear(BoostOutput(12, 0.5, 1), 24, 1e-12, 'boost ideal: Vout = Vin / (1 - D)');
  T.R1 := 1000; T.R2 := 10000; T.C := 1e-6; T.Phase := 0; T.Output := False;
  CheckNear(Timer555Frequency(T), 1.44 / ((1000 + 20000) * 1e-6), 1e-12, '555 astavel: f = 1,44 / ((R1 + 2 R2) C)');
  B := LiIonCell(2);
  B.SOC := 1;
  for I := 1 to 3600 do BatteryStep(B, 1, 1);
  CheckNear(B.SOC, 0.5, 1e-9, 'bateria 2 Ah a 1 A: metade em 1 h');
  for I := 1 to 3600 do BatteryStep(B, 1, 1);
  Check(B.SOC < 1e-9, 'descarregada em 2 h');
  FillChar(C, SizeOf(C), 0);
  C.Turns := 500; C.Length := 0.05; C.RelativePermeability := 1; C.Current := 2;
  CheckNear(SolenoidField(C), 4 * Pi * 1e-7 * 500 * 2 / 0.05, 1e-12, 'solenoide: B = mu0 N I / L');
  CheckNear(SaturatedField(0.1, 1.5), 0.1, 0.002, 'nucleo linear longe da saturacao');
  Check(SaturatedField(10, 1.5) < 1.5, 'nucleo nao passa de Bsat');
end;

procedure TestCouplingAndRecorder;
var
  P: TPhysicsProject;
  R: TSimulationRuntime;
  I, K: Integer;
  Rec: TTelemetryRecorder;
  L: TStringList;
  FN: string;
begin
  Section('Acoplamento runtime -> FEM e gravador');
  P := TPhysicsProject.Create; R := TSimulationRuntime.Create; Rec := TTelemetryRecorder.Create; L := TStringList.Create;
  try
    R.Start;
    for I := 1 to 500 do
    begin
      R.Step;
      if I mod 50 = 0 then Rec.Sample(R.Snapshot);
    end;
    K := ApplyRuntimeHeat(P, 'MOTOR', R.Snapshot);
    Check((K >= 0) and (P.BC(K).Kind = bkHeatPower) and SameValue(P.BC(K).Value, R.Snapshot.Thermal.HeatPower),
      Format('perdas I2R do motor viram potencia dissipada (%.3f W)', [P.BC(K).Value]));
    Check(ApplyRuntimeHeat(P, 'MOTOR', R.Snapshot) = K, 'reaplicar atualiza a mesma condicao');
    FN := GetTempDir + 'mp_telemetria.csv';
    Rec.SaveCSV(FN);
    L.LoadFromFile(FN);
    Check((L.Count = 11) and (Pos('time_s', L[0]) = 1), 'CSV com cabecalho e 10 amostras');
    DeleteFile(FN);
  finally
    L.Free; Rec.Free; R.Free; P.Free;
  end;
end;

begin
  TestOpenLoop;
  TestClosedLoop;
  TestMachine;
  TestFaults;
  TestMNA;
  TestElectronics;
  TestCouplingAndRecorder;
  Finish('modelos de sistema');
end.
