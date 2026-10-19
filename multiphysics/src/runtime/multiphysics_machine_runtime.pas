unit multiphysics_machine_runtime;

{ Maquina CNC virtual: eixos com motor de passo, spindle e protecoes.

  Cada eixo segue um perfil trapezoidal (aceleracao Accel ate MaxSpeed e
  desaceleracao para parar no alvo, v <= sqrt(2 a d)). O motor de passo tem
  curva de torque disponivel que cai com a velocidade (pull-out linear ate
  NoLoadSpeed); quando o torque de carga passa do disponivel o passo e perdido
  e o eixo para (estol). Passos fracionarios se acumulam (sem erro de
  arredondamento na posicao final). Fim de curso, homing, aquecimento I2R e
  desarme por sobrecorrente/sobretemperatura. Modelo reduzido: ESTIMATIVA. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, multiphysics_graph, multiphysics_axis_control, multiphysics_stepper_physics;

type
  TAxisRuntime = class
  public
    Name: string;
    Command: TAxisCommand;
    State: TAxisState;
    Motor: TStepperPhysical;
    MinMM, MaxMM, Temperature, Current: Double;
    Accel: Double;              { mm/s2; 0 = sem rampa }
    NoLoadSpeed: Double;        { mm/s em que o torque disponivel chega a zero; 0 = constante }
    StepFrac: Double;           { passos fracionarios acumulados }
    { falhas }
    ExtraCurrent: Double;       { A somados (curto, sobrecorrente) }
    ResistanceFactor: Double;   { aquecimento I2R x fator (corrosao, oxidacao) }
    Locked: Boolean;            { eixo travado mecanicamente }
    SensorOffsetMM: Double;     { leitura de posicao com erro (sensor falhou) }
    LimitStuck: Boolean;        { fim de curso minimo preso acionado }
    Homed: Boolean;
    constructor Create;
    function AvailableTorque: Double;
    function ReadPositionMM: Double;   { o que o controlador "ve" }
  end;

  TMachineRuntime = class
  private
    FAxes: TList;
    FSpindleRPM, FSpindleTarget, FTime, FDT: Double;
    FEnabled: Boolean;
    FTripReason: string;
    function AxisByName(const N: string): TAxisRuntime;
    procedure StepAxis(A: TAxisRuntime);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function AddAxis(const N: string; MinMM, MaxMM, StepsPerMM, Torque: Double): TAxisRuntime;
    procedure CommandAxis(const N: string; TargetMM, SpeedMMs: Double);
    procedure SetSpindle(RPM: Double);
    procedure Start;
    procedure Stop;
    procedure Step;
    { roda ate todos os eixos pararem no alvo (ou desarme); devolve o tempo simulado }
    function RunUntilIdle(MaxTime: Double): Double;
    { homing: anda para o fim de curso minimo e zera a posicao; False se nao achou }
    function HomeAxis(const N: string; SpeedMMs: Double): Boolean;
    function AxisCount: Integer;
    function Axis(I: Integer): TAxisRuntime;
    function FindAxis(const N: string): TAxisRuntime;
    property SpindleRPM: Double read FSpindleRPM;
    property Enabled: Boolean read FEnabled;
    property TripReason: string read FTripReason;
    property Time: Double read FTime;
    property Dt: Double read FDT write FDT;
  end;

implementation

constructor TAxisRuntime.Create;
begin
  inherited Create;
  ResistanceFactor := 1;
  Temperature := 25;
end;

function TAxisRuntime.AvailableTorque: Double;
var
  T: Double;
begin
  T := Motor.RunningTorque;
  if T <= 0 then T := Motor.HoldingTorque;
  if NoLoadSpeed > 0 then T := T * Max(0.0, 1 - Abs(State.VelocityMMs) / NoLoadSpeed);
  Result := T;
end;

function TAxisRuntime.ReadPositionMM: Double;
begin
  Result := State.PositionMM + SensorOffsetMM;
end;

constructor TMachineRuntime.Create;
begin
  inherited Create;
  FAxes := TList.Create;
  FDT := 0.001;
end;

destructor TMachineRuntime.Destroy;
begin
  Clear;
  FAxes.Free;
  inherited Destroy;
end;

procedure TMachineRuntime.Clear;
var
  I: Integer;
begin
  for I := 0 to FAxes.Count - 1 do TObject(FAxes[I]).Free;
  FAxes.Clear;
  FTime := 0;
  FTripReason := '';
end;

function TMachineRuntime.AddAxis(const N: string; MinMM, MaxMM, StepsPerMM, Torque: Double): TAxisRuntime;
begin
  Result := TAxisRuntime.Create;
  Result.Name := N;
  Result.MinMM := MinMM;
  Result.MaxMM := MaxMM;
  Result.Motor.StepsPerMM := StepsPerMM;
  Result.Motor.RunningTorque := Torque;
  Result.Command.MaxSpeedMMs := 50;
  FAxes.Add(Result);
end;

function TMachineRuntime.AxisByName(const N: string): TAxisRuntime;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FAxes.Count - 1 do
    if SameText(TAxisRuntime(FAxes[I]).Name, N) then Exit(TAxisRuntime(FAxes[I]));
end;

function TMachineRuntime.FindAxis(const N: string): TAxisRuntime;
begin
  Result := AxisByName(N);
end;

procedure TMachineRuntime.CommandAxis(const N: string; TargetMM, SpeedMMs: Double);
var
  A: TAxisRuntime;
begin
  A := AxisByName(N);
  if A = nil then Exit;
  A.Command.TargetMM := TargetMM;
  A.Command.MaxSpeedMMs := SpeedMMs;
  A.Command.Enabled := True;
end;

procedure TMachineRuntime.SetSpindle(RPM: Double);
begin
  FSpindleTarget := Max(0.0, RPM);
end;

procedure TMachineRuntime.Start;
begin
  FEnabled := True;
  FTripReason := '';
end;

procedure TMachineRuntime.Stop;
begin
  FEnabled := False;
  FSpindleTarget := 0;
end;

procedure TMachineRuntime.StepAxis(A: TAxisRuntime);
var
  E, Dist, VTarget, Dir, StepsF: Double;
  Demand, Done: Integer;
  P: TProtectionState;
begin
  Demand := 0;
  if A.Command.Enabled and (A.Motor.StepsPerMM > 0) then
  begin
    { o controlador ve a posicao do sensor (com o erro de uma falha) }
    E := A.Command.TargetMM - A.ReadPositionMM;
    Dist := Abs(E);
    if Dist < 0.5 / A.Motor.StepsPerMM then
    begin
      A.State.VelocityMMs := 0;
      A.StepFrac := 0;
    end
    else
    begin
      Dir := Sign(E);
      if A.Accel > 0 then
      begin
        { trapezio: acelera ate a velocidade maxima e freia para parar no alvo }
        VTarget := Min(A.Command.MaxSpeedMMs, Sqrt(2 * A.Accel * Dist));
        if Abs(A.State.VelocityMMs) < VTarget then
          A.State.VelocityMMs := Dir * Min(VTarget, Abs(A.State.VelocityMMs) + A.Accel * FDT)
        else
          A.State.VelocityMMs := Dir * VTarget;
      end
      else
        A.State.VelocityMMs := Dir * A.Command.MaxSpeedMMs;
      StepsF := A.StepFrac + A.State.VelocityMMs * FDT * A.Motor.StepsPerMM;
      Demand := Trunc(StepsF);
      { nao passa do alvo }
      if Abs(Demand) > Round(Dist * A.Motor.StepsPerMM) then Demand := Round(E * A.Motor.StepsPerMM);
      if (Demand = 0) and (A.Accel <= 0) then Demand := Round(Dir);
      A.StepFrac := StepsF - Demand;
    end;
  end;
  { torque: travado ou carga acima do disponivel na velocidade atual -> passo perdido }
  if A.Locked then A.Motor.LoadTorque := Max(A.Motor.LoadTorque, 1e9);
  if (Demand <> 0) and (Abs(A.Motor.LoadTorque) > A.AvailableTorque) then
  begin
    Inc(A.Motor.CommandedSteps, Demand);
    Inc(A.Motor.LostSteps, Abs(Demand));
    Inc(A.State.LostSteps, Abs(Demand));
    Done := 0;
    A.State.VelocityMMs := 0;
    A.StepFrac := 0;
  end
  else
  begin
    Inc(A.Motor.CommandedSteps, Demand);
    Inc(A.Motor.ActualSteps, Demand);
    Done := Demand;
  end;
  A.State.PositionMM := A.State.PositionMM + Done / A.Motor.StepsPerMM;
  A.Current := 0.5 + Abs(Demand) * 0.002 + A.ExtraCurrent;
  A.Temperature := A.Temperature + (Sqr(A.Current) * 0.02 * A.ResistanceFactor - (A.Temperature - 25) * 0.01) * FDT;
  UpdateLimits(A.State, A.MinMM, A.MaxMM);
  if A.LimitStuck then A.State.AtMin := True;
  P.MaxCurrent := 5;
  P.MaxTemperature := 90;
  CheckProtection(A.Current, A.Temperature, P);
  if P.Tripped then
  begin
    FTripReason := A.Name + ': ' + P.Reason;
    FEnabled := False;
  end;
end;

procedure TMachineRuntime.Step;
var
  I: Integer;
begin
  if not FEnabled then Exit;
  for I := 0 to FAxes.Count - 1 do
  begin
    StepAxis(TAxisRuntime(FAxes[I]));
    if not FEnabled then Exit;
  end;
  FSpindleRPM := FSpindleRPM + (FSpindleTarget - FSpindleRPM) * Min(1.0, 5 * FDT);
  FTime := FTime + FDT;
end;

function TMachineRuntime.RunUntilIdle(MaxTime: Double): Double;
var
  T0: Double;
  I: Integer;
  Busy: Boolean;
begin
  T0 := FTime;
  repeat
    Step;
    Busy := False;
    for I := 0 to FAxes.Count - 1 do
      with TAxisRuntime(FAxes[I]) do
        if Command.Enabled and (Abs(Command.TargetMM - ReadPositionMM) >= 0.5 / Max(Motor.StepsPerMM, 1e-9)) and
          not Locked and not (Abs(Motor.LoadTorque) > AvailableTorque) then Busy := True;
  until not FEnabled or not Busy or (FTime - T0 >= MaxTime);
  Result := FTime - T0;
end;

function TMachineRuntime.HomeAxis(const N: string; SpeedMMs: Double): Boolean;
var
  A: TAxisRuntime;
  T0: Double;
begin
  Result := False;
  A := AxisByName(N);
  if A = nil then Exit;
  A.Homed := False;
  A.Command.TargetMM := A.MinMM - (A.MaxMM - A.MinMM) - 1;
  A.Command.MaxSpeedMMs := SpeedMMs;
  A.Command.Enabled := True;
  T0 := FTime;
  while FEnabled and not A.State.AtMin and (FTime - T0 < 600) do Step;
  if not A.State.AtMin then Exit;
  { zera: o controlador passa a considerar o fim de curso como MinMM. Com o
    fim de curso preso o zero fica errado: a posicao real nao muda, so a lida }
  A.Command.Enabled := False;
  A.SensorOffsetMM := A.MinMM - A.State.PositionMM;
  A.Command.TargetMM := A.MinMM;
  A.State.VelocityMMs := 0;
  A.StepFrac := 0;
  A.Homed := True;
  Result := True;
end;

function TMachineRuntime.AxisCount: Integer;
begin
  Result := FAxes.Count;
end;

function TMachineRuntime.Axis(I: Integer): TAxisRuntime;
begin
  Result := TAxisRuntime(FAxes[I]);
end;

end.
