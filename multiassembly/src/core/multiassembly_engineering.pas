unit multiassembly_engineering;

{$mode objfpc}{$H+}

{ Engenharia do projeto eletromecanico (MultiAssembly).

  - ERC eletromecanico: verifica ligacoes contra o papel de cada porta e de
    cada componente - drivers sem STEP/DIR/alimentacao/motor, motores sem
    driver, tensoes incompativeis, sinais ligados a portas erradas, E-stop
    ausente, componentes soltos e ligacoes para IDs inexistentes. Quando o
    componente nao declara portas, o tipo e inferido pelo nome (STEP_X, DIR,
    VMOT, 24V, GND, EN, PWM, COIL...).
  - Lista de materiais (BOM) agrupada, em CSV e JSON.
  - Configuracao de firmware a partir da cinematica: passos/mm de cada eixo
    (fuso, correia, cremalheira ou relacao direta), velocidade maxima pelo
    limite do motor, curso pela estrutura; gera os parametros $100..$132 do
    Grbl/grblHAL e o bloco axes do YAML do FluidNC - pronto para o MultiCNC
    enviar a maquina. }

interface

uses Classes, SysUtils, Math, fpjson, multiassembly_types, multiassembly_project;

type
  TIssueSeverity = (isError, isWarning, isInfo);

  TAssemblyComponentKinds = set of TAssemblyComponentKind;

  TAssemblyIssue = record
    Severity: TIssueSeverity;
    ComponentID: string;
    Message: string;
  end;
  TAssemblyIssues = array of TAssemblyIssue;

  TAssemblyERC = class
  public
    class function InferPortKind(const PortName: string; out Voltage: Double): TAssemblyPortKind;
    class function Check(P: TAssemblyProject): TAssemblyIssues;
    class function ErrorCount(const Issues: TAssemblyIssues): Integer;
    class procedure ToText(const Issues: TAssemblyIssues; Output: TStrings);
  end;

  TBOMLine = record
    Kind: TAssemblyComponentKind;
    Description, Model: string;
    Quantity: Integer;
    IDs: string;
  end;
  TBOMLines = array of TBOMLine;

  TAssemblyBOM = class
  public
    class function Build(P: TAssemblyProject): TBOMLines;
    class procedure ToCSV(const B: TBOMLines; Output: TStrings);
    class function ToJSON(const B: TBOMLines): string;
  end;

  TDriveKind = (dkLeadScrew, dkBelt, dkRackPinion, dkDirect);

  TAxisConfig = record
    Axis: Char;               // X, Y, Z
    MotorID: string;
    Drive: TDriveKind;
    MMPerRev: Double;         // deslocamento por volta do motor (apos reducao)
    StepsPerMM: Double;
    MaxRateMMMin: Double;
    AccelMMS2: Double;
    MaxTravelMM: Double;
    Assumed: Boolean;         // valores padrao usados por falta de dados
  end;

  TMotionOptions = record
    StepsPerRev: Integer;     // 200 = 1,8 graus
    Microsteps: Integer;
    MotorMaxRPM: Double;      // limite pratico do motor de passo
    Acceleration: Double;     // mm/s^2
    DefaultLeadMM: Double;    // fuso padrao quando o passo nao foi informado
  end;

  TMachineConfig = record
    Axes: array of TAxisConfig;
    Warnings: string;
  end;

  TMachineConfigurator = class
  public
    class function DefaultOptions: TMotionOptions;
    class function FromAssembly(P: TAssemblyProject; const Opt: TMotionOptions): TMachineConfig;
    class procedure ToGrblSettings(const C: TMachineConfig; Output: TStrings);
    class procedure ToFluidNCYaml(const C: TMachineConfig; const Opt: TMotionOptions; Output: TStrings);
  end;

function ComponentKindName(K: TAssemblyComponentKind): string;
function PortKindName(K: TAssemblyPortKind): string;

implementation

function ComponentKindName(K: TAssemblyComponentKind): string;
begin
  case K of
    ackMechanicalPart: Result := 'Peca mecanica';
    ackMotor: Result := 'Motor';
    ackSpindle: Result := 'Spindle';
    ackLeadScrew: Result := 'Fuso';
    ackLinearGuide: Result := 'Guia linear';
    ackBearing: Result := 'Rolamento';
    ackPulley: Result := 'Polia';
    ackBelt: Result := 'Correia';
    ackController: Result := 'Controladora';
    ackDriver: Result := 'Driver de motor';
    ackPowerSupply: Result := 'Fonte';
    ackVFD: Result := 'Inversor (VFD)';
    ackRelay: Result := 'Rele';
    ackSensor: Result := 'Sensor';
    ackEndStop: Result := 'Fim de curso';
    ackEStop: Result := 'Parada de emergencia';
    ackConnector: Result := 'Conector';
    ackPCB: Result := 'Placa (PCB)';
  else
    Result := 'Outro';
  end;
end;

function PortKindName(K: TAssemblyPortKind): string;
begin
  WriteStr(Result, K);
  Delete(Result, 1, 3);
end;

function StartsWithAny(const S: string; const P: array of string): Boolean;
var I: Integer;
begin
  for I := 0 to High(P) do
    if Copy(S, 1, Length(P[I])) = P[I] then Exit(True);
  Result := False;
end;

class function TAssemblyERC.InferPortKind(const PortName: string; out Voltage: Double): TAssemblyPortKind;
var U, Num: string; I: Integer;
begin
  U := UpperCase(Trim(PortName));
  Voltage := 0;
  // tensao explicita no nome: 24V, 12V, 5V, 3V3
  if (Length(U) >= 2) and (U[Length(U)] = 'V') and (U[1] in ['0'..'9']) then begin
    Num := Copy(U, 1, Length(U) - 1);
    Voltage := StrToFloatDef(Num, 0);
    Exit(apkPower);
  end;
  if (Pos('V', U) > 1) and (U[1] in ['0'..'9']) then begin
    I := Pos('V', U);
    Voltage := StrToFloatDef(Copy(U, 1, I - 1), 0) + StrToFloatDef(Copy(U, I + 1, MaxInt), 0) / 10;
    Exit(apkPower);
  end;
  if StartsWithAny(U, ['STEP', 'STP', 'PUL']) then Result := apkStep
  else if StartsWithAny(U, ['DIR']) then Result := apkDir
  else if StartsWithAny(U, ['EN', 'ENA']) then Result := apkEnable
  else if StartsWithAny(U, ['GND', 'COM', '0V']) then Result := apkGround
  else if StartsWithAny(U, ['VMOT', 'VCC', 'VIN', 'V+', 'POWER', 'PWR']) then Result := apkPower
  else if StartsWithAny(U, ['PWM', 'SPINDLE_PWM']) then Result := apkPWM
  else if StartsWithAny(U, ['COIL', 'MOTOR', 'PHASE', 'A+', 'A-', 'B+', 'B-']) then Result := apkPower
  else if StartsWithAny(U, ['TX', 'RX', 'SDA', 'SCL', 'MOSI', 'MISO', 'SCK', 'CAN', 'RS485', 'USB']) then Result := apkCommunication
  else if StartsWithAny(U, ['ADC', 'AIN', 'ANALOG']) then Result := apkAnalogInput
  else if StartsWithAny(U, ['NC', 'NO', 'ESTOP', 'LIMIT', 'PROBE', 'DOOR', 'IN']) then Result := apkDigitalInput
  else if StartsWithAny(U, ['OUT', 'RELAY']) then Result := apkDigitalOutput
  else if StartsWithAny(U, ['SHAFT', 'AXIS', 'MECH']) then Result := apkMechanical
  else Result := apkDigitalOutput;
end;

function PortInfo(const C: TAssemblyComponent; const PortName: string; out Kind: TAssemblyPortKind;
  out Voltage: Double; out Declared: Boolean): Boolean;
var I: Integer;
begin
  Declared := Length(C.Ports) > 0;
  for I := 0 to High(C.Ports) do
    if SameText(C.Ports[I].Name, PortName) then begin
      Kind := C.Ports[I].Kind;
      Voltage := C.Ports[I].Voltage;
      Exit(True);
    end;
  Kind := TAssemblyERC.InferPortKind(PortName, Voltage);
  Result := not Declared; // porta inexistente quando o componente declara portas
end;

procedure AddIssue(var L: TAssemblyIssues; Sev: TIssueSeverity; const ID, Msg: string);
var N: Integer;
begin
  N := Length(L);
  SetLength(L, N + 1);
  L[N].Severity := Sev;
  L[N].ComponentID := ID;
  L[N].Message := Msg;
end;

class function TAssemblyERC.Check(P: TAssemblyProject): TAssemblyIssues;
var
  I, K, IA, IB, N: Integer;
  W: TElectricalConnection;
  CA, CB, C: TAssemblyComponent;
  KA, KB: TAssemblyPortKind;
  VA, VB: Double;
  DA, DB, HasStep, HasDir, HasPower, HasMotor, HasDriver, HasEStop, Linked: Boolean;

  function HasPortKind(const ID: string; Kind: TAssemblyPortKind): Boolean;
  var J, Idx: Integer; WW: TElectricalConnection; Kd: TAssemblyPortKind; Vd: Double; Dd: Boolean;
    Port: string;
  begin
    Result := False;
    for J := 0 to P.WireCount - 1 do begin
      WW := P.Wire(J);
      if SameText(WW.ToComponent, ID) then Port := WW.ToPort
      else if SameText(WW.FromComponent, ID) then Port := WW.FromPort
      else Continue;
      Idx := P.FindComponent(ID);
      if Idx < 0 then Continue;
      PortInfo(P.Component(Idx), Port, Kd, Vd, Dd);
      if Kd = Kind then Exit(True);
      if (Kind = apkPower) and SameText(Port, 'VMOT') then Exit(True);
    end;
  end;

  function LinkedTo(const ID: string; Kinds: TAssemblyComponentKinds): Boolean;
  var J, Idx: Integer; WW: TElectricalConnection; Other: string;
  begin
    Result := False;
    for J := 0 to P.WireCount - 1 do begin
      WW := P.Wire(J);
      if SameText(WW.ToComponent, ID) then Other := WW.FromComponent
      else if SameText(WW.FromComponent, ID) then Other := WW.ToComponent
      else Continue;
      Idx := P.FindComponent(Other);
      if (Idx >= 0) and (P.Component(Idx).Kind in Kinds) then Exit(True);
    end;
  end;

begin
  SetLength(Result, 0);
  // 1. ligacoes: existencia de componentes e portas, compatibilidade
  for I := 0 to P.WireCount - 1 do begin
    W := P.Wire(I);
    IA := P.FindComponent(W.FromComponent);
    IB := P.FindComponent(W.ToComponent);
    if IA < 0 then begin AddIssue(Result, isError, W.FromComponent, 'Ligacao "' + W.Caption + '" cita componente inexistente ' + W.FromComponent); Continue; end;
    if IB < 0 then begin AddIssue(Result, isError, W.ToComponent, 'Ligacao "' + W.Caption + '" cita componente inexistente ' + W.ToComponent); Continue; end;
    CA := P.Component(IA); CB := P.Component(IB);
    if not PortInfo(CA, W.FromPort, KA, VA, DA) then
      AddIssue(Result, isError, CA.ID, CA.ID + ': porta ' + W.FromPort + ' nao existe');
    if not PortInfo(CB, W.ToPort, KB, VB, DB) then
      AddIssue(Result, isError, CB.ID, CB.ID + ': porta ' + W.ToPort + ' nao existe');
    // sinais de controle devem chegar a porta do mesmo tipo
    if (KA in [apkStep, apkDir, apkEnable]) and (KB in [apkStep, apkDir, apkEnable]) and (KA <> KB) then
      AddIssue(Result, isError, CB.ID, SysUtils.Format('%s.%s (%s) ligado a %s.%s (%s)',
        [CA.ID, W.FromPort, PortKindName(KA), CB.ID, W.ToPort, PortKindName(KB)]));
    if ((KA = apkGround) <> (KB = apkGround)) and ((KA = apkPower) or (KB = apkPower)) then
      AddIssue(Result, isError, CB.ID, SysUtils.Format('Curto: alimentacao %s.%s ligada ao terra %s.%s',
        [CA.ID, W.FromPort, CB.ID, W.ToPort]));
    if (VA > 0) and (VB > 0) and (Abs(VA - VB) > 0.05 * Max(VA, VB)) then
      AddIssue(Result, isError, CB.ID, SysUtils.Format('Tensao incompativel: %s.%s=%gV -> %s.%s=%gV',
        [CA.ID, W.FromPort, VA, CB.ID, W.ToPort, VB]));
  end;
  // 2. regras por papel de componente
  HasEStop := False;
  for I := 0 to P.ComponentCount - 1 do begin
    C := P.Component(I);
    Linked := False;
    for K := 0 to P.WireCount - 1 do
      if SameText(P.Wire(K).FromComponent, C.ID) or SameText(P.Wire(K).ToComponent, C.ID) then Linked := True;
    case C.Kind of
      ackDriver: begin
        HasStep := HasPortKind(C.ID, apkStep);
        HasDir := HasPortKind(C.ID, apkDir);
        HasPower := HasPortKind(C.ID, apkPower);
        HasMotor := LinkedTo(C.ID, [ackMotor]);
        if not HasStep then AddIssue(Result, isError, C.ID, C.Name + ': sem sinal STEP');
        if not HasDir then AddIssue(Result, isError, C.ID, C.Name + ': sem sinal DIR (motor so gira em um sentido)');
        if not HasPower then AddIssue(Result, isError, C.ID, C.Name + ': sem alimentacao de potencia (VMOT)');
        if not HasMotor then AddIssue(Result, isWarning, C.ID, C.Name + ': nenhum motor ligado');
        if not HasPortKind(C.ID, apkEnable) then
          AddIssue(Result, isInfo, C.ID, C.Name + ': ENABLE nao ligado (driver sempre habilitado)');
      end;
      ackMotor: begin
        HasDriver := LinkedTo(C.ID, [ackDriver, ackController, ackVFD, ackRelay]);
        if not HasDriver then AddIssue(Result, isError, C.ID, C.Name + ': motor sem driver/acionamento');
      end;
      ackSpindle:
        if not LinkedTo(C.ID, [ackVFD, ackRelay, ackController, ackDriver, ackPowerSupply]) then
          AddIssue(Result, isWarning, C.ID, C.Name + ': spindle sem acionamento (VFD/rele/PWM)');
      ackEStop: begin
        HasEStop := True;
        if not LinkedTo(C.ID, [ackController, ackRelay, ackPowerSupply, ackVFD]) then
          AddIssue(Result, isError, C.ID, C.Name + ': E-stop nao interrompe controladora nem potencia');
      end;
      ackController, ackPowerSupply, ackVFD, ackRelay, ackSensor, ackEndStop, ackPCB, ackConnector:
        if not Linked then AddIssue(Result, isWarning, C.ID, C.Name + ': componente eletrico sem ligacoes');
    end;
  end;
  N := 0;
  for I := 0 to P.ComponentCount - 1 do
    if P.Component(I).Kind in [ackMotor, ackSpindle] then Inc(N);
  if (N > 0) and not HasEStop then
    AddIssue(Result, isError, '', 'Maquina com motores/spindle sem parada de emergencia');
end;

class function TAssemblyERC.ErrorCount(const Issues: TAssemblyIssues): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(Issues) do if Issues[I].Severity = isError then Inc(Result);
end;

class procedure TAssemblyERC.ToText(const Issues: TAssemblyIssues; Output: TStrings);
const Tag: array[TIssueSeverity] of string = ('ERRO', 'AVISO', 'INFO');
var I: Integer;
begin
  for I := 0 to High(Issues) do Output.Add(Tag[Issues[I].Severity] + ': ' + Issues[I].Message);
end;

class function TAssemblyBOM.Build(P: TAssemblyProject): TBOMLines;
var I, K, N: Integer; C: TAssemblyComponent; Found: Boolean; Model: string;
begin
  SetLength(Result, 0);
  N := 0;
  for I := 0 to P.ComponentCount - 1 do begin
    C := P.Component(I);
    Model := C.Model;
    Found := False;
    for K := 0 to N - 1 do
      if (Result[K].Kind = C.Kind) and SameText(Result[K].Model, Model) then begin
        Inc(Result[K].Quantity);
        Result[K].IDs := Result[K].IDs + ' ' + C.ID;
        Found := True;
        Break;
      end;
    if not Found then begin
      SetLength(Result, N + 1);
      Result[N].Kind := C.Kind;
      Result[N].Model := Model;
      if Model <> '' then Result[N].Description := ComponentKindName(C.Kind) + ' ' + Model
      else Result[N].Description := ComponentKindName(C.Kind);
      Result[N].Quantity := 1;
      Result[N].IDs := C.ID;
      Inc(N);
    end;
  end;
end;

function CSVField(const S: string): string;
begin
  if (Pos(';', S) > 0) or (Pos('"', S) > 0) or (Pos(',', S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

class procedure TAssemblyBOM.ToCSV(const B: TBOMLines; Output: TStrings);
var I: Integer;
begin
  Output.Clear;
  Output.Add('item;quantidade;descricao;modelo;referencias');
  for I := 0 to High(B) do
    Output.Add(SysUtils.Format('%d;%d;%s;%s;%s', [I + 1, B[I].Quantity, CSVField(B[I].Description),
      CSVField(B[I].Model), CSVField(B[I].IDs)]));
end;

class function TAssemblyBOM.ToJSON(const B: TBOMLines): string;
var A: TJSONArray; O: TJSONObject; I: Integer;
begin
  A := TJSONArray.Create;
  try
    for I := 0 to High(B) do begin
      O := TJSONObject.Create;
      O.Add('item', I + 1);
      O.Add('quantity', B[I].Quantity);
      O.Add('description', B[I].Description);
      O.Add('model', B[I].Model);
      O.Add('refs', B[I].IDs);
      A.Add(O);
    end;
    Result := A.FormatJSON;
  finally
    A.Free;
  end;
end;

class function TMachineConfigurator.DefaultOptions: TMotionOptions;
begin
  Result.StepsPerRev := 200;
  Result.Microsteps := 16;
  Result.MotorMaxRPM := 600;   // motor de passo NEMA17/23 com torque util
  Result.Acceleration := 300;
  Result.DefaultLeadMM := 8;   // fuso trapezoidal T8
end;

class function TMachineConfigurator.FromAssembly(P: TAssemblyProject; const Opt: TMotionOptions): TMachineConfig;
var
  I, K, N, Frame: Integer;
  R: TMechanicalRelation;
  Mot: TAssemblyComponent;
  Ax: TAxisConfig;
  Found: Boolean;
begin
  SetLength(Result.Axes, 0);
  Result.Warnings := '';
  N := 0;
  Frame := -1;
  for I := 0 to P.ComponentCount - 1 do
    if (P.Component(I).Kind = ackMechanicalPart) and (Frame < 0) then Frame := I;
  for I := 0 to P.RelationCount - 1 do begin
    R := P.Relation(I);
    K := P.FindComponent(R.A);
    if (K < 0) or (P.Component(K).Kind <> ackMotor) then Continue;
    Mot := P.Component(K);
    FillChar(Ax, SizeOf(Ax), 0);
    Ax.MotorID := Mot.ID;
    if (Abs(R.Axis.X) >= Abs(R.Axis.Y)) and (Abs(R.Axis.X) >= Abs(R.Axis.Z)) then Ax.Axis := 'X'
    else if Abs(R.Axis.Y) >= Abs(R.Axis.Z) then Ax.Axis := 'Y'
    else Ax.Axis := 'Z';
    // relacao: PitchMM = avanco por volta do elemento final; Ratio = reducao
    case R.Kind of
      mrLeadScrew: Ax.Drive := dkLeadScrew;
      mrBelt: Ax.Drive := dkBelt;
    else
      Ax.Drive := dkDirect;
    end;
    Ax.MMPerRev := R.PitchMM;
    if Ax.MMPerRev <= 0 then begin
      Ax.MMPerRev := Opt.DefaultLeadMM;
      Ax.Assumed := True;
      Ax.Drive := dkLeadScrew;
      Result.Warnings := Result.Warnings + SysUtils.Format('%s: passo/avanco nao informado, assumido fuso de %g mm/volta; ',
        [Mot.ID, Opt.DefaultLeadMM]);
    end;
    if (R.Ratio > 0) and (R.Ratio <> 1) then Ax.MMPerRev := Ax.MMPerRev / R.Ratio;
    Ax.StepsPerMM := Opt.StepsPerRev * Opt.Microsteps / Ax.MMPerRev;
    Ax.MaxRateMMMin := Opt.MotorMaxRPM * Ax.MMPerRev;
    Ax.AccelMMS2 := Opt.Acceleration;
    if Ax.Axis = 'Z' then Ax.AccelMMS2 := Opt.Acceleration / 2;
    if Frame >= 0 then
      case Ax.Axis of
        'X': Ax.MaxTravelMM := P.Component(Frame).Size.X;
        'Y': Ax.MaxTravelMM := P.Component(Frame).Size.Y;
        'Z': Ax.MaxTravelMM := P.Component(Frame).Size.Z;
      end;
    Found := False;
    for K := 0 to N - 1 do
      if Result.Axes[K].Axis = Ax.Axis then begin
        Found := True;
        Result.Warnings := Result.Warnings + SysUtils.Format('eixo %s com mais de um motor (%s e %s): use eixo duplo/escravo; ',
          [Ax.Axis, Result.Axes[K].MotorID, Ax.MotorID]);
      end;
    if not Found then begin
      SetLength(Result.Axes, N + 1);
      Result.Axes[N] := Ax;
      Inc(N);
    end;
  end;
  // ordena X, Y, Z
  for I := 1 to N - 1 do begin
    Ax := Result.Axes[I];
    K := I - 1;
    while (K >= 0) and (Result.Axes[K].Axis > Ax.Axis) do begin Result.Axes[K + 1] := Result.Axes[K]; Dec(K); end;
    Result.Axes[K + 1] := Ax;
  end;
end;

class procedure TMachineConfigurator.ToGrblSettings(const C: TMachineConfig; Output: TStrings);
var I, Base: Integer; FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Output.Clear;
  for I := 0 to High(C.Axes) do begin
    Base := Ord(C.Axes[I].Axis) - Ord('X');
    if (Base < 0) or (Base > 2) then Continue;
    Output.Add(SysUtils.Format('$%d=%.3f', [100 + Base, C.Axes[I].StepsPerMM], FS));
  end;
  for I := 0 to High(C.Axes) do begin
    Base := Ord(C.Axes[I].Axis) - Ord('X');
    if (Base < 0) or (Base > 2) then Continue;
    Output.Add(SysUtils.Format('$%d=%.3f', [110 + Base, C.Axes[I].MaxRateMMMin], FS));
  end;
  for I := 0 to High(C.Axes) do begin
    Base := Ord(C.Axes[I].Axis) - Ord('X');
    if (Base < 0) or (Base > 2) then Continue;
    Output.Add(SysUtils.Format('$%d=%.3f', [120 + Base, C.Axes[I].AccelMMS2], FS));
  end;
  for I := 0 to High(C.Axes) do begin
    Base := Ord(C.Axes[I].Axis) - Ord('X');
    if (Base < 0) or (Base > 2) or (C.Axes[I].MaxTravelMM <= 0) then Continue;
    Output.Add(SysUtils.Format('$%d=%.3f', [130 + Base, C.Axes[I].MaxTravelMM], FS));
  end;
end;

class procedure TMachineConfigurator.ToFluidNCYaml(const C: TMachineConfig; const Opt: TMotionOptions; Output: TStrings);
var I: Integer; FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Output.Clear;
  Output.Add('# gerado pelo MultiAssembly - revise pinos e drivers antes de usar');
  Output.Add('axes:');
  for I := 0 to High(C.Axes) do begin
    Output.Add('  ' + LowerCase(C.Axes[I].Axis) + ':');
    Output.Add(SysUtils.Format('    steps_per_mm: %.3f', [C.Axes[I].StepsPerMM], FS));
    Output.Add(SysUtils.Format('    max_rate_mm_per_min: %.1f', [C.Axes[I].MaxRateMMMin], FS));
    Output.Add(SysUtils.Format('    acceleration_mm_per_sec2: %.1f', [C.Axes[I].AccelMMS2], FS));
    if C.Axes[I].MaxTravelMM > 0 then
      Output.Add(SysUtils.Format('    max_travel_mm: %.1f', [C.Axes[I].MaxTravelMM], FS));
    Output.Add('    motor0:');
    Output.Add('      # ' + C.Axes[I].MotorID + SysUtils.Format(' - %d passos/volta x %d micropassos', [Opt.StepsPerRev, Opt.Microsteps]));
    Output.Add('      standard_stepper:');
    Output.Add('        step_pin: NO_PIN');
    Output.Add('        direction_pin: NO_PIN');
  end;
end;

end.
