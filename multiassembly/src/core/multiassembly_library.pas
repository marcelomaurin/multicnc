unit multiassembly_library;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, multiassembly_types;

type
  TStringArray = array of string;

  TAssemblyLibrary = class
  private
    class var FLibraryFolder: string;
    class function ResolveDefaultFolder: string; static;
  public
    class function GetLibraryFolder: string; static;
    class procedure SetLibraryFolder(const APath: string); static;

    class function MakeComponent(const ID, Name: string; Kind: TAssemblyComponentKind;
      X, Y, Z, SX, SY, SZ: Double): TAssemblyComponent; static;
    class procedure AddPort(var C: TAssemblyComponent; const Name: string;
      Kind: TAssemblyPortKind; Voltage: Double = 0); static;

    // Fixadores
    class function MakeScrew(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeNut(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeWasher(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeRivet(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeSpacer(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;

    // Rolamentos
    class function MakeBearing(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;

    // Motores
    class function MakeDCMotor(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeACMotor(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeStepperMotor(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;

    // Eletronica e Controle
    class function MakeDriver(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeController(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakePowerSupply(const ID, Spec: string; Voltage: Double; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeEndstop(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeEStop(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeSpindle(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent; static;

    // Estrutura e Transmissao
    class function MakeProfile(const ID, Spec: string; LengthMM: Double; X, Y, Z: Double): TAssemblyComponent; static;
    class function MakeLeadScrew(const ID, Spec: string; LengthMM, PitchMM: Double; X, Y, Z: Double): TAssemblyComponent; static;

    // Catalogo baseado em pastas e arquivos
    class function GetCategories: TStringArray; static;
    class function GetCatalogItems(const Category: string): TStringArray; static;
    class function CreateFromCatalog(const Category, Item, ID: string; X, Y, Z: Double): TAssemblyComponent; static;

    // Carregamento e salvamento direto de arquivos de componentes (.json)
    class function LoadComponentFromFile(const Filename, ID: string; X, Y, Z: Double): TAssemblyComponent; static;
    class procedure SaveComponentToFile(const Filename: string; const C: TAssemblyComponent); static;
  end;

function StrToComponentKind(const S: string; DefaultKind: TAssemblyComponentKind = ackMechanicalPart): TAssemblyComponentKind;
function ComponentKindToStr(Kind: TAssemblyComponentKind): string;
function StrToPortKind(const S: string; DefaultKind: TAssemblyPortKind = apkMechanical): TAssemblyPortKind;
function PortKindToStr(Kind: TAssemblyPortKind): string;

implementation

function StrToComponentKind(const S: string; DefaultKind: TAssemblyComponentKind): TAssemblyComponentKind;
var
  V: Integer;
begin
  if TryStrToInt(S, V) and (V >= 0) and (V <= Ord(High(TAssemblyComponentKind))) then
    Exit(TAssemblyComponentKind(V));

  if SameText(S, 'ackMechanicalPart') or SameText(S, 'Mecanico') or SameText(S, 'Estrutura') then Exit(ackMechanicalPart);
  if SameText(S, 'ackMotor') or SameText(S, 'Motor') then Exit(ackMotor);
  if SameText(S, 'ackSpindle') or SameText(S, 'Spindle') then Exit(ackSpindle);
  if SameText(S, 'ackLeadScrew') or SameText(S, 'Fuso') then Exit(ackLeadScrew);
  if SameText(S, 'ackLinearGuide') or SameText(S, 'GuiaLinear') or SameText(S, 'Guia') then Exit(ackLinearGuide);
  if SameText(S, 'ackBearing') or SameText(S, 'Rolamento') or SameText(S, 'Mancal') then Exit(ackBearing);
  if SameText(S, 'ackPulley') or SameText(S, 'Polia') then Exit(ackPulley);
  if SameText(S, 'ackBelt') or SameText(S, 'Correia') then Exit(ackBelt);
  if SameText(S, 'ackController') or SameText(S, 'Controladora') then Exit(ackController);
  if SameText(S, 'ackDriver') or SameText(S, 'Driver') then Exit(ackDriver);
  if SameText(S, 'ackPowerSupply') or SameText(S, 'Fonte') then Exit(ackPowerSupply);
  if SameText(S, 'ackVFD') or SameText(S, 'Inversor') then Exit(ackVFD);
  if SameText(S, 'ackRelay') or SameText(S, 'Rele') then Exit(ackRelay);
  if SameText(S, 'ackSensor') or SameText(S, 'Sensor') then Exit(ackSensor);
  if SameText(S, 'ackEndStop') or SameText(S, 'EndStop') or SameText(S, 'FimDeCurso') then Exit(ackEndStop);
  if SameText(S, 'ackEStop') or SameText(S, 'EStop') or SameText(S, 'Emergencia') then Exit(ackEStop);
  if SameText(S, 'ackConnector') or SameText(S, 'Conector') then Exit(ackConnector);
  if SameText(S, 'ackPCB') or SameText(S, 'Placa') then Exit(ackPCB);
  if SameText(S, 'ackFastenerScrew') or SameText(S, 'Parafuso') then Exit(ackFastenerScrew);
  if SameText(S, 'ackFastenerNut') or SameText(S, 'Porca') then Exit(ackFastenerNut);
  if SameText(S, 'ackFastenerWasher') or SameText(S, 'Arruela') then Exit(ackFastenerWasher);
  if SameText(S, 'ackFastenerRivet') or SameText(S, 'Rebite') then Exit(ackFastenerRivet);
  if SameText(S, 'ackPinSpacer') or SameText(S, 'Espacador') then Exit(ackPinSpacer);
  Result := DefaultKind;
end;

function ComponentKindToStr(Kind: TAssemblyComponentKind): string;
begin
  case Kind of
    ackMechanicalPart: Result := 'ackMechanicalPart';
    ackMotor:          Result := 'ackMotor';
    ackSpindle:        Result := 'ackSpindle';
    ackLeadScrew:      Result := 'ackLeadScrew';
    ackLinearGuide:    Result := 'ackLinearGuide';
    ackBearing:        Result := 'ackBearing';
    ackPulley:         Result := 'ackPulley';
    ackBelt:           Result := 'ackBelt';
    ackController:     Result := 'ackController';
    ackDriver:         Result := 'ackDriver';
    ackPowerSupply:    Result := 'ackPowerSupply';
    ackVFD:            Result := 'ackVFD';
    ackRelay:          Result := 'ackRelay';
    ackSensor:         Result := 'ackSensor';
    ackEndStop:        Result := 'ackEndStop';
    ackEStop:          Result := 'ackEStop';
    ackConnector:      Result := 'ackConnector';
    ackPCB:            Result := 'ackPCB';
    ackFastenerScrew:  Result := 'ackFastenerScrew';
    ackFastenerNut:    Result := 'ackFastenerNut';
    ackFastenerWasher: Result := 'ackFastenerWasher';
    ackFastenerRivet:  Result := 'ackFastenerRivet';
    ackPinSpacer:      Result := 'ackPinSpacer';
    ackOther:          Result := 'ackOther';
  end;
end;

function StrToPortKind(const S: string; DefaultKind: TAssemblyPortKind): TAssemblyPortKind;
var
  V: Integer;
begin
  if TryStrToInt(S, V) and (V >= 0) and (V <= Ord(High(TAssemblyPortKind))) then
    Exit(TAssemblyPortKind(V));

  if SameText(S, 'apkMechanical') or SameText(S, 'Mecanico') then Exit(apkMechanical);
  if SameText(S, 'apkPower') or SameText(S, 'Power') or SameText(S, 'VCC') then Exit(apkPower);
  if SameText(S, 'apkGround') or SameText(S, 'GND') or SameText(S, 'Terra') then Exit(apkGround);
  if SameText(S, 'apkDigitalInput') or SameText(S, 'DIN') then Exit(apkDigitalInput);
  if SameText(S, 'apkDigitalOutput') or SameText(S, 'DOUT') then Exit(apkDigitalOutput);
  if SameText(S, 'apkAnalogInput') or SameText(S, 'AIN') then Exit(apkAnalogInput);
  if SameText(S, 'apkAnalogOutput') or SameText(S, 'AOUT') then Exit(apkAnalogOutput);
  if SameText(S, 'apkStep') or SameText(S, 'Passo') or SameText(S, 'PUL') then Exit(apkStep);
  if SameText(S, 'apkDir') or SameText(S, 'Direcao') then Exit(apkDir);
  if SameText(S, 'apkEnable') or SameText(S, 'ENA') then Exit(apkEnable);
  if SameText(S, 'apkPWM') then Exit(apkPWM);
  if SameText(S, 'apkCommunication') or SameText(S, 'COM') then Exit(apkCommunication);
  Result := DefaultKind;
end;

function PortKindToStr(Kind: TAssemblyPortKind): string;
begin
  case Kind of
    apkMechanical:    Result := 'apkMechanical';
    apkPower:         Result := 'apkPower';
    apkGround:        Result := 'apkGround';
    apkDigitalInput:  Result := 'apkDigitalInput';
    apkDigitalOutput: Result := 'apkDigitalOutput';
    apkAnalogInput:   Result := 'apkAnalogInput';
    apkAnalogOutput:  Result := 'apkAnalogOutput';
    apkStep:          Result := 'apkStep';
    apkDir:           Result := 'apkDir';
    apkEnable:        Result := 'apkEnable';
    apkPWM:           Result := 'apkPWM';
    apkCommunication: Result := 'apkCommunication';
  end;
end;

class function TAssemblyLibrary.ResolveDefaultFolder: string;
var
  Cand: string;
begin
  Cand := 'D:\projetos\maurinsoft\multicnc\models\components\mec';
  if DirectoryExists(Cand) then Exit(Cand);

  Cand := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\models\components\mec');
  if DirectoryExists(Cand) then Exit(Cand);

  Cand := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\..\models\components\mec');
  if DirectoryExists(Cand) then Exit(Cand);

  Cand := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\..\..\models\components\mec');
  if DirectoryExists(Cand) then Exit(Cand);

  Result := 'D:\projetos\maurinsoft\multicnc\models\components\mec';
end;

class function TAssemblyLibrary.GetLibraryFolder: string;
begin
  if FLibraryFolder = '' then
    FLibraryFolder := ResolveDefaultFolder;
  Result := FLibraryFolder;
end;

class procedure TAssemblyLibrary.SetLibraryFolder(const APath: string);
begin
  FLibraryFolder := Trim(APath);
end;

class function TAssemblyLibrary.MakeComponent(const ID, Name: string; Kind: TAssemblyComponentKind;
  X, Y, Z, SX, SY, SZ: Double): TAssemblyComponent;
begin
  Result.ID := ID;
  Result.Name := Name;
  Result.Model := '';
  Result.SourceRef := '';
  Result.Category := 'Geral';
  Result.Material := 'Aco';
  Result.Fixed := False;
  Result.Color := 0;
  SetLength(Result.Ports, 0);
  Result.Position.X := X; Result.Position.Y := Y; Result.Position.Z := Z;
  Result.Rotation.X := 0; Result.Rotation.Y := 0; Result.Rotation.Z := 0;
  Result.Size.X := SX; Result.Size.Y := SY; Result.Size.Z := SZ;
  Result.Kind := Kind;
end;

class procedure TAssemblyLibrary.AddPort(var C: TAssemblyComponent; const Name: string;
  Kind: TAssemblyPortKind; Voltage: Double);
var
  N: Integer;
begin
  N := Length(C.Ports);
  SetLength(C.Ports, N + 1);
  C.Ports[N].Name := Name;
  C.Ports[N].Kind := Kind;
  C.Ports[N].Voltage := Voltage;
end;

class function TAssemblyLibrary.MakeScrew(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
var
  Dia, Len: Double;
begin
  Dia := 4; Len := 16;
  if Pos('M3', Spec) > 0 then Dia := 3
  else if Pos('M4', Spec) > 0 then Dia := 4
  else if Pos('M5', Spec) > 0 then Dia := 5;

  if Pos('10', Spec) > 0 then Len := 10
  else if Pos('16', Spec) > 0 then Len := 16
  else if Pos('20', Spec) > 0 then Len := 20
  else if Pos('25', Spec) > 0 then Len := 25
  else if Pos('30', Spec) > 0 then Len := 30;

  Result := MakeComponent(ID, 'Parafuso ' + Spec, ackFastenerScrew, X, Y, Z, Dia * 1.8, Dia * 1.8, Len);
  Result.Category := 'Fixadores';
  Result.Model := Spec;
  Result.Material := 'Aco Inox 304';
  AddPort(Result, 'ROSCA', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeNut(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
var
  Dia, H: Double;
begin
  Dia := 4; H := 3.2;
  if Pos('M3', Spec) > 0 then begin Dia := 3; H := 2.4; end
  else if Pos('M4', Spec) > 0 then begin Dia := 4; H := 3.2; end
  else if Pos('M5', Spec) > 0 then begin Dia := 5; H := 4.0; end;

  Result := MakeComponent(ID, 'Porca ' + Spec, ackFastenerNut, X, Y, Z, Dia * 2.0, Dia * 2.0, H);
  Result.Category := 'Fixadores';
  Result.Model := Spec;
  Result.Material := 'Aco Carbono';
  AddPort(Result, 'ROSCA', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeWasher(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
var
  Dia, T: Double;
begin
  Dia := 4; T := 0.8;
  if Pos('M3', Spec) > 0 then begin Dia := 3; T := 0.5; end
  else if Pos('M4', Spec) > 0 then begin Dia := 4; T := 0.8; end
  else if Pos('M5', Spec) > 0 then begin Dia := 5; T := 1.0; end;

  Result := MakeComponent(ID, 'Arruela ' + Spec, ackFastenerWasher, X, Y, Z, Dia * 2.2, Dia * 2.2, T);
  Result.Category := 'Fixadores';
  Result.Model := Spec;
  Result.Material := 'Aco Zincado';
  AddPort(Result, 'FACE', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeRivet(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  Result := MakeComponent(ID, 'Rebite ' + Spec, ackFastenerRivet, X, Y, Z, 8, 8, 12);
  Result.Category := 'Fixadores';
  Result.Model := Spec;
  Result.Material := 'Aluminio';
  AddPort(Result, 'MECH', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeSpacer(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  Result := MakeComponent(ID, 'Espacador ' + Spec, ackPinSpacer, X, Y, Z, 7, 7, 15);
  Result.Category := 'Fixadores';
  Result.Model := Spec;
  Result.Material := 'Latao';
  AddPort(Result, 'MECH', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeBearing(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  if Pos('608', Spec) > 0 then
    Result := MakeComponent(ID, 'Rolamento 608ZZ', ackBearing, X, Y, Z, 22, 22, 7)
  else if Pos('6205', Spec) > 0 then
    Result := MakeComponent(ID, 'Rolamento 6205', ackBearing, X, Y, Z, 52, 52, 15)
  else if Pos('LM8UU', Spec) > 0 then
    Result := MakeComponent(ID, 'Rolamento Linear LM8UU', ackBearing, X, Y, Z, 15, 15, 24)
  else if Pos('KP08', Spec) > 0 then
    Result := MakeComponent(ID, 'Mancal KP08', ackBearing, X, Y, Z, 55, 13, 29)
  else
    Result := MakeComponent(ID, 'Rolamento ' + Spec, ackBearing, X, Y, Z, 22, 22, 7);

  Result.Category := 'Rolamentos';
  Result.Model := Spec;
  Result.Material := 'Aco Cromo 52100';
  AddPort(Result, 'EIXO', apkMechanical, 0);
  AddPort(Result, 'ALOJAMENTO', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeDCMotor(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  if Pos('775', Spec) > 0 then
    Result := MakeComponent(ID, 'Motor DC 775 12-24V', ackMotor, X, Y, Z, 42, 42, 67)
  else
    Result := MakeComponent(ID, 'Motor DC com Redutor 12V', ackMotor, X, Y, Z, 37, 37, 50);

  Result.Category := 'Motores';
  Result.Model := Spec;
  Result.Material := 'Aco / Cobre';
  AddPort(Result, 'V+', apkPower, 24);
  AddPort(Result, 'V-', apkGround, 0);
  AddPort(Result, 'EIXO', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeACMotor(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  if Pos('Spindle', Spec) > 0 then
  begin
    Result := MakeComponent(ID, 'Spindle AC 1.5kW', ackSpindle, X, Y, Z, 65, 65, 200);
    AddPort(Result, 'U', apkPower, 220);
    AddPort(Result, 'V', apkPower, 220);
    AddPort(Result, 'W', apkPower, 220);
    AddPort(Result, 'PE', apkGround, 0);
  end
  else
  begin
    Result := MakeComponent(ID, 'Motor AC Monofasico 1/2 CV', ackMotor, X, Y, Z, 140, 140, 220);
    AddPort(Result, 'L', apkPower, 220);
    AddPort(Result, 'N', apkGround, 0);
    AddPort(Result, 'PE', apkGround, 0);
  end;
  Result.Category := 'Motores';
  Result.Model := Spec;
  Result.Material := 'Aluminio / Ferro Fundido';
  AddPort(Result, 'EIXO', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeStepperMotor(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  if Pos('NEMA 23', Spec) > 0 then
    Result := MakeComponent(ID, 'Motor de Passo NEMA 23', ackMotor, X, Y, Z, 57, 57, 56)
  else if Pos('NEMA 34', Spec) > 0 then
    Result := MakeComponent(ID, 'Motor de Passo NEMA 34', ackMotor, X, Y, Z, 86, 86, 80)
  else
    Result := MakeComponent(ID, 'Motor de Passo NEMA 17', ackMotor, X, Y, Z, 42, 42, 40);

  Result.Category := 'Motores';
  Result.Model := Spec;
  Result.Material := 'Aco Eletrico / Cobre';
  AddPort(Result, 'COIL', apkPower, 24);
  AddPort(Result, 'A+', apkPower, 24);
  AddPort(Result, 'A-', apkGround, 0);
  AddPort(Result, 'B+', apkPower, 24);
  AddPort(Result, 'B-', apkGround, 0);
  AddPort(Result, 'EIXO', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeDriver(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  if Pos('TB6600', Spec) > 0 then
    Result := MakeComponent(ID, 'Driver TB6600 4A', ackDriver, X, Y, Z, 96, 71, 37)
  else if Pos('DM542', Spec) > 0 then
    Result := MakeComponent(ID, 'Driver Digital DM542', ackDriver, X, Y, Z, 118, 76, 33)
  else
    Result := MakeComponent(ID, 'Driver A4988', ackDriver, X, Y, Z, 20, 15, 11);

  Result.Category := 'Eletronica';
  Result.Model := Spec;
  Result.Material := 'PCB / Aluminio';
  AddPort(Result, 'STEP', apkStep, 5);
  AddPort(Result, 'DIR', apkDir, 5);
  AddPort(Result, 'EN', apkEnable, 5);
  AddPort(Result, 'VMOT', apkPower, 24);
  AddPort(Result, 'GND', apkGround, 0);
  AddPort(Result, 'MOTOR', apkPower, 24);
end;

class function TAssemblyLibrary.MakeController(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  if Pos('GrblHAL', Spec) > 0 then
    Result := MakeComponent(ID, 'Controladora GrblHAL 32-bit', ackController, X, Y, Z, 100, 80, 15)
  else if Pos('FluidNC', Spec) > 0 then
    Result := MakeComponent(ID, 'Controladora FluidNC ESP32', ackController, X, Y, Z, 120, 90, 20)
  else
    Result := MakeComponent(ID, 'Arduino CNC Shield V3', ackController, X, Y, Z, 75, 55, 18);

  Result.Category := 'Eletronica';
  Result.Model := Spec;
  Result.Material := 'FR4';
  AddPort(Result, 'STEP_X', apkStep, 5);
  AddPort(Result, 'DIR_X', apkDir, 5);
  AddPort(Result, 'STEP_Y', apkStep, 5);
  AddPort(Result, 'DIR_Y', apkDir, 5);
  AddPort(Result, 'STEP_Z', apkStep, 5);
  AddPort(Result, 'DIR_Z', apkDir, 5);
  AddPort(Result, 'SPINDLE_PWM', apkPWM, 5);
  AddPort(Result, 'ESTOP', apkDigitalInput, 5);
  AddPort(Result, '5V', apkPower, 5);
  AddPort(Result, 'GND', apkGround, 0);
end;

class function TAssemblyLibrary.MakePowerSupply(const ID, Spec: string; Voltage: Double; X, Y, Z: Double): TAssemblyComponent;
begin
  Result := MakeComponent(ID, 'Fonte Chaveada ' + Spec, ackPowerSupply, X, Y, Z, 200, 100, 50);
  Result.Category := 'Eletronica';
  Result.Model := Spec;
  Result.Material := 'Chapa Aco Perfurada';
  AddPort(Result, '24V', apkPower, Voltage);
  AddPort(Result, 'V+', apkPower, Voltage);
  AddPort(Result, 'GND', apkGround, 0);
  AddPort(Result, 'L', apkPower, 220);
  AddPort(Result, 'N', apkGround, 0);
  AddPort(Result, 'PE', apkGround, 0);
end;

class function TAssemblyLibrary.MakeEndstop(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  Result := MakeComponent(ID, 'Fim de Curso ' + Spec, ackEndStop, X, Y, Z, 20, 10, 8);
  Result.Category := 'Sensores';
  Result.Model := Spec;
  Result.Material := 'Plastico';
  AddPort(Result, 'SIG', apkDigitalInput, 5);
  AddPort(Result, 'GND', apkGround, 0);
  AddPort(Result, 'VCC', apkPower, 5);
end;

class function TAssemblyLibrary.MakeEStop(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  Result := MakeComponent(ID, 'Botao E-Stop ' + Spec, ackEStop, X, Y, Z, 40, 40, 70);
  Result.Category := 'Seguranca';
  Result.Model := Spec;
  Result.Material := 'Plastico / Metal';
  AddPort(Result, 'NC', apkDigitalInput, 5);
  AddPort(Result, 'COM', apkGround, 0);
end;

class function TAssemblyLibrary.MakeSpindle(const ID, Spec: string; X, Y, Z: Double): TAssemblyComponent;
begin
  Result := MakeComponent(ID, 'Spindle ' + Spec, ackSpindle, X, Y, Z, 52, 52, 180);
  Result.Category := 'Usinagem';
  Result.Model := Spec;
  Result.Material := 'Aluminio';
  AddPort(Result, 'MOTOR', apkPower, 24);
  AddPort(Result, 'PWM', apkPWM, 5);
  AddPort(Result, 'MECH', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeProfile(const ID, Spec: string; LengthMM: Double; X, Y, Z: Double): TAssemblyComponent;
var
  W, H: Double;
begin
  W := 20; H := 20;
  if Pos('2040', Spec) > 0 then H := 40;
  Result := MakeComponent(ID, 'Perfil ' + Spec + ' ' + FloatToStr(LengthMM) + 'mm', ackMechanicalPart, X, Y, Z, W, H, LengthMM);
  Result.Category := 'Estrutura';
  Result.Model := Spec;
  Result.Material := 'Aluminio Anodizado 6063';
  AddPort(Result, 'SLOT', apkMechanical, 0);
end;

class function TAssemblyLibrary.MakeLeadScrew(const ID, Spec: string; LengthMM, PitchMM: Double; X, Y, Z: Double): TAssemblyComponent;
begin
  Result := MakeComponent(ID, 'Fuso T8 ' + FloatToStr(LengthMM) + 'mm', ackLeadScrew, X, Y, Z, 8, 8, LengthMM);
  Result.Category := 'Estrutura';
  Result.Model := Spec;
  Result.Material := 'Aco Inox';
  AddPort(Result, 'FUSO', apkMechanical, 0);
end;

class function TAssemblyLibrary.GetCategories: TStringArray;
var
  BaseDir: string;
  SR: TSearchRec;
  Cats: TStringList;
  I: Integer;
begin
  BaseDir := GetLibraryFolder;
  Cats := TStringList.Create;
  try
    if DirectoryExists(BaseDir) then
    begin
      if FindFirst(IncludeTrailingPathDelimiter(BaseDir) + '*', faDirectory, SR) = 0 then
      begin
        repeat
          if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') and (SR.Name[1] <> '.') then
            Cats.Add(SR.Name);
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
    end;

    if Cats.Count > 0 then
    begin
      Cats.Sort;
      SetLength(Result, Cats.Count);
      for I := 0 to Cats.Count - 1 do
        Result[I] := Cats[I];
      Exit;
    end;

    // Fallback se pasta ainda não tiver sido inicializada
    SetLength(Result, 9);
    Result[0] := 'perfis';
    Result[1] := 'guias_fusos';
    Result[2] := 'motores';
    Result[3] := 'fixadores';
    Result[4] := 'rolamentos_mancais';
    Result[5] := 'transmissao';
    Result[6] := 'placas_suportes';
    Result[7] := 'mesas_bases';
    Result[8] := 'eletronica';
  finally
    Cats.Free;
  end;
end;

class function TAssemblyLibrary.GetCatalogItems(const Category: string): TStringArray;
var
  BaseDir, CatDir, FilePath: string;
  SR: TSearchRec;
  Items: TStringList;
  I: Integer;
  JSONText: string;
  Data: TJSONData;
  Obj: TJSONObject;
  NameStr: string;
  F: TFileStream;
begin
  BaseDir := GetLibraryFolder;
  CatDir := IncludeTrailingPathDelimiter(BaseDir) + Category;
  Items := TStringList.Create;
  try
    if not DirectoryExists(CatDir) then
    begin
      if FindFirst(IncludeTrailingPathDelimiter(BaseDir) + '*', faDirectory, SR) = 0 then
      begin
        repeat
          if ((SR.Attr and faDirectory) <> 0) and SameText(SR.Name, Category) then
          begin
            CatDir := IncludeTrailingPathDelimiter(BaseDir) + SR.Name;
            Break;
          end;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
    end;

    if DirectoryExists(CatDir) then
    begin
      if FindFirst(IncludeTrailingPathDelimiter(CatDir) + '*.json', faAnyFile, SR) = 0 then
      begin
        repeat
          FilePath := IncludeTrailingPathDelimiter(CatDir) + SR.Name;
          NameStr := '';
          try
            F := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyNone);
            try
              SetLength(JSONText, F.Size);
              if F.Size > 0 then
                F.ReadBuffer(JSONText[1], F.Size);
            finally
              F.Free;
            end;
            if JSONText <> '' then
            begin
              Data := GetJSON(JSONText);
              try
                if Data is TJSONObject then
                begin
                  Obj := TJSONObject(Data);
                  NameStr := Obj.Get('name', '');
                end;
              finally
                Data.Free;
              end;
            end;
          except
            NameStr := '';
          end;

          if NameStr = '' then
            NameStr := ChangeFileExt(SR.Name, '');

          Items.Add(NameStr);
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
    end;

    if Items.Count > 0 then
    begin
      Items.Sort;
      SetLength(Result, Items.Count);
      for I := 0 to Items.Count - 1 do
        Result[I] := Items[I];
      Exit;
    end;

    // Fallbacks para compatibilidade com testes legados
    if SameText(Category, 'Fixadores') or SameText(Category, 'fixadores') then
    begin
      SetLength(Result, 9);
      Result[0] := 'Parafuso M3x10 Allen';
      Result[1] := 'Parafuso M3x16 Allen';
      Result[2] := 'Parafuso M4x16 Allen';
      Result[3] := 'Parafuso M4x25 Allen';
      Result[4] := 'Parafuso M5x20 Sextavado';
      Result[5] := 'Porca M3 Travante';
      Result[6] := 'Porca M4 Travante';
      Result[7] := 'Arruela M4 Lisa';
      Result[8] := 'Espacador M3x10';
    end
    else if SameText(Category, 'Rolamentos') or SameText(Category, 'rolamentos_mancais') then
    begin
      SetLength(Result, 4);
      Result[0] := 'Rolamento 608ZZ';
      Result[1] := 'Rolamento 6205';
      Result[2] := 'Rolamento Linear LM8UU';
      Result[3] := 'Mancal KP08';
    end
    else if SameText(Category, 'Motores') or SameText(Category, 'motores') then
    begin
      SetLength(Result, 6);
      Result[0] := 'Motor de Passo NEMA 17';
      Result[1] := 'Motor de Passo NEMA 23';
      Result[2] := 'Motor de Passo NEMA 34';
      Result[3] := 'Motor DC 775 24V';
      Result[4] := 'Motor DC Redutor 12V';
      Result[5] := 'Spindle AC 1.5kW 220V';
    end
    else if SameText(Category, 'Eletronica') or SameText(Category, 'eletronica') then
    begin
      SetLength(Result, 6);
      Result[0] := 'Driver A4988';
      Result[1] := 'Driver TB6600 4A';
      Result[2] := 'Driver Digital DM542';
      Result[3] := 'Arduino CNC Shield V3';
      Result[4] := 'Controladora GrblHAL 32-bit';
      Result[5] := 'Fonte Chaveada 24V 15A';
    end
    else if SameText(Category, 'Sensores') then
    begin
      SetLength(Result, 3);
      Result[0] := 'Fim de Curso Microswitch';
      Result[1] := 'Fim de Curso Optico';
      Result[2] := 'Botao E-Stop Emergencia';
    end
    else
    begin
      SetLength(Result, 3);
      Result[0] := 'Perfil Aluminio 2020 300mm';
      Result[1] := 'Perfil Aluminio 2040 400mm';
      Result[2] := 'Fuso Trapezoidal T8 300mm';
    end;
  finally
    Items.Free;
  end;
end;

class function TAssemblyLibrary.LoadComponentFromFile(const Filename, ID: string; X, Y, Z: Double): TAssemblyComponent;
var
  JSONText: string;
  Data, PortsData: TJSONData;
  Obj, VecObj, PortObj: TJSONObject;
  PortsArr: TJSONArray;
  F: TFileStream;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.ID := ID;
  Result.Position := Vec3(X, Y, Z);
  Result.Rotation := Vec3(0, 0, 0);
  Result.Size := Vec3(20, 20, 20);
  Result.Kind := ackMechanicalPart;
  Result.Category := 'Geral';
  Result.Material := 'Aco';
  Result.Color := 0;
  SetLength(Result.Ports, 0);

  if not FileExists(Filename) then Exit;

  F := TFileStream.Create(Filename, fmOpenRead or fmShareDenyNone);
  try
    SetLength(JSONText, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(JSONText[1], F.Size);
  finally
    F.Free;
  end;

  if JSONText = '' then Exit;
  Data := GetJSON(JSONText);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);

    Result.Name := Obj.Get('name', ChangeFileExt(ExtractFileName(Filename), ''));
    Result.Model := Obj.Get('model', '');
    Result.Category := Obj.Get('category', ExtractFileName(ExtractFileDir(Filename)));
    Result.Material := Obj.Get('material', 'Aco');
    Result.SourceRef := ExtractFileName(Filename);
    Result.Color := Obj.Get('color', 0);

    if Obj.Find('kind') <> nil then
    begin
      if Obj.Find('kind').JSONType = jtNumber then
        Result.Kind := TAssemblyComponentKind(Obj.Get('kind', 0))
      else
        Result.Kind := StrToComponentKind(Obj.Get('kind', ''));
    end;

    VecObj := Obj.Get('size', TJSONObject(nil));
    if VecObj <> nil then
    begin
      Result.Size.X := VecObj.Get('x', 20.0);
      Result.Size.Y := VecObj.Get('y', 20.0);
      Result.Size.Z := VecObj.Get('z', 20.0);
    end;

    PortsData := Obj.Find('ports');
    if (PortsData <> nil) and (PortsData is TJSONArray) then
    begin
      PortsArr := TJSONArray(PortsData);
      SetLength(Result.Ports, PortsArr.Count);
      for I := 0 to PortsArr.Count - 1 do
      begin
        PortObj := PortsArr.Objects[I];
        Result.Ports[I].Name := PortObj.Get('name', 'P' + IntToStr(I + 1));
        if PortObj.Find('kind') <> nil then
        begin
          if PortObj.Find('kind').JSONType = jtNumber then
            Result.Ports[I].Kind := TAssemblyPortKind(PortObj.Get('kind', 0))
          else
            Result.Ports[I].Kind := StrToPortKind(PortObj.Get('kind', ''));
        end
        else
          Result.Ports[I].Kind := apkMechanical;
        Result.Ports[I].Voltage := PortObj.Get('voltage', 0.0);
      end;
    end;
  finally
    Data.Free;
  end;
end;

class procedure TAssemblyLibrary.SaveComponentToFile(const Filename: string; const C: TAssemblyComponent);
var
  Root, VecObj, PortObj: TJSONObject;
  PortsArr: TJSONArray;
  I: Integer;
  S: string;
  F: TFileStream;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('name', C.Name);
    Root.Add('model', C.Model);
    Root.Add('category', C.Category);
    Root.Add('kind', ComponentKindToStr(C.Kind));
    Root.Add('material', C.Material);
    Root.Add('color', C.Color);

    VecObj := TJSONObject.Create;
    VecObj.Add('x', C.Size.X);
    VecObj.Add('y', C.Size.Y);
    VecObj.Add('z', C.Size.Z);
    Root.Add('size', VecObj);

    PortsArr := TJSONArray.Create;
    for I := 0 to High(C.Ports) do
    begin
      PortObj := TJSONObject.Create;
      PortObj.Add('name', C.Ports[I].Name);
      PortObj.Add('kind', PortKindToStr(C.Ports[I].Kind));
      PortObj.Add('voltage', C.Ports[I].Voltage);
      PortsArr.Add(PortObj);
    end;
    Root.Add('ports', PortsArr);
    Root.Add('description', C.Name + ' (' + C.Model + ')');

    S := Root.FormatJSON;
    ForceDirectories(ExtractFileDir(Filename));
    F := TFileStream.Create(Filename, fmCreate);
    try
      if Length(S) > 0 then
        F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
  finally
    Root.Free;
  end;
end;

class function TAssemblyLibrary.CreateFromCatalog(const Category, Item, ID: string; X, Y, Z: Double): TAssemblyComponent;
var
  BaseDir, CatDir, FilePath: string;
  SR: TSearchRec;
  MatchedFile: string;
  JSONText: string;
  Data: TJSONData;
  Obj: TJSONObject;
  NameStr: string;
  F: TFileStream;
begin
  BaseDir := GetLibraryFolder;
  CatDir := IncludeTrailingPathDelimiter(BaseDir) + Category;
  MatchedFile := '';

  if not DirectoryExists(CatDir) then
  begin
    if FindFirst(IncludeTrailingPathDelimiter(BaseDir) + '*', faDirectory, SR) = 0 then
    begin
      repeat
        if ((SR.Attr and faDirectory) <> 0) and SameText(SR.Name, Category) then
        begin
          CatDir := IncludeTrailingPathDelimiter(BaseDir) + SR.Name;
          Break;
        end;
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
  end;

  if DirectoryExists(CatDir) then
  begin
    FilePath := IncludeTrailingPathDelimiter(CatDir) + Item + '.json';
    if FileExists(FilePath) then
      MatchedFile := FilePath
    else
    begin
      if FindFirst(IncludeTrailingPathDelimiter(CatDir) + '*.json', faAnyFile, SR) = 0 then
      begin
        repeat
          FilePath := IncludeTrailingPathDelimiter(CatDir) + SR.Name;
          if SameText(ChangeFileExt(SR.Name, ''), Item) then
          begin
            MatchedFile := FilePath;
            Break;
          end;

          NameStr := '';
          try
            F := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyNone);
            try
              SetLength(JSONText, F.Size);
              if F.Size > 0 then
                F.ReadBuffer(JSONText[1], F.Size);
            finally
              F.Free;
            end;
            if JSONText <> '' then
            begin
              Data := GetJSON(JSONText);
              try
                if Data is TJSONObject then
                begin
                  Obj := TJSONObject(Data);
                  NameStr := Obj.Get('name', '');
                end;
              finally
                Data.Free;
              end;
            end;
          except
            NameStr := '';
          end;

          if SameText(NameStr, Item) then
          begin
            MatchedFile := FilePath;
            Break;
          end;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
    end;
  end;

  if MatchedFile <> '' then
  begin
    Result := LoadComponentFromFile(MatchedFile, ID, X, Y, Z);
    Exit;
  end;

  // Fallback programático (se o arquivo não estiver presente no disco)
  if SameText(Category, 'Fixadores') or SameText(Category, 'fixadores') then
  begin
    if Pos('Porca', Item) > 0 then
      Result := MakeNut(ID, Item, X, Y, Z)
    else if Pos('Arruela', Item) > 0 then
      Result := MakeWasher(ID, Item, X, Y, Z)
    else if Pos('Espacador', Item) > 0 then
      Result := MakeSpacer(ID, Item, X, Y, Z)
    else
      Result := MakeScrew(ID, Item, X, Y, Z);
  end
  else if SameText(Category, 'Rolamentos') or SameText(Category, 'rolamentos_mancais') then
    Result := MakeBearing(ID, Item, X, Y, Z)
  else if SameText(Category, 'Motores') or SameText(Category, 'motores') then
  begin
    if Pos('NEMA', Item) > 0 then
      Result := MakeStepperMotor(ID, Item, X, Y, Z)
    else if Pos('Spindle', Item) > 0 then
      Result := MakeACMotor(ID, Item, X, Y, Z)
    else
      Result := MakeDCMotor(ID, Item, X, Y, Z);
  end
  else if SameText(Category, 'Eletronica') or SameText(Category, 'eletronica') then
  begin
    if Pos('Driver', Item) > 0 then
      Result := MakeDriver(ID, Item, X, Y, Z)
    else if Pos('Fonte', Item) > 0 then
      Result := MakePowerSupply(ID, Item, 24, X, Y, Z)
    else
      Result := MakeController(ID, Item, X, Y, Z);
  end
  else if SameText(Category, 'Sensores') then
  begin
    if Pos('E-Stop', Item) > 0 then
      Result := MakeEStop(ID, Item, X, Y, Z)
    else
      Result := MakeEndstop(ID, Item, X, Y, Z);
  end
  else
  begin
    if Pos('Fuso', Item) > 0 then
      Result := MakeLeadScrew(ID, Item, 300, 2, X, Y, Z)
    else
      Result := MakeProfile(ID, Item, 300, X, Y, Z);
  end;
end;

end.
