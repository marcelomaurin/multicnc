unit multiphysics_component_library;
{$mode objfpc}{$H+}
interface
uses multiphysics_graph;
function NewPowerSupply(const ID:string;Voltage,MaxCurrent:Double):TSimComponent;
function NewPWMDriver(const ID:string):TSimComponent;
function NewDCMotor(const ID:string):TSimComponent;
function NewAxisLoad(const ID:string):TSimComponent;
function NewSpeedSensor(const ID:string):TSimComponent;
function NewController(const ID:string):TSimComponent;
function NewResistor(const ID:string;Ohms:Double):TSimComponent;
function NewCapacitor(const ID:string;Farads:Double):TSimComponent;
function NewInductor(const ID:string;Henries:Double):TSimComponent;
function NewRelay(const ID:string):TSimComponent;
function NewStepper(const ID:string):TSimComponent;
function NewServo(const ID:string):TSimComponent;
function NewBLDC(const ID:string):TSimComponent;
function NewGear(const ID:string;Ratio:Double):TSimComponent;
function NewLeadScrew(const ID:string;PitchMM:Double):TSimComponent;
function NewEndStop(const ID:string):TSimComponent;
implementation
function NewPowerSupply(const ID:string;Voltage,MaxCurrent:Double):TSimComponent;begin Result:=TSimComponent.Create(ID,'Fonte',ckPowerSupply,cdElectrical);Result.AddPort('V+',ptElectrical);Result.AddPort('GND',ptElectrical);Result.Parameters.Values['voltage']:=FloatToStr(Voltage);Result.Parameters.Values['max_current']:=FloatToStr(MaxCurrent);end;
function NewPWMDriver(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Driver PWM',ckPWMDriver,cdElectronic);Result.AddPort('VIN',ptElectrical);Result.AddPort('VOUT',ptElectrical);Result.AddPort('CMD',ptSignal);end;
function NewDCMotor(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Motor DC',ckDCMotor,cdElectrical);Result.AddPort('PWR',ptElectrical);Result.AddPort('SHAFT',ptMechanicalRotary);Result.AddPort('TEMP',ptThermal);end;
function NewAxisLoad(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Carga de eixo',ckAxisLoad,cdMechanical);Result.AddPort('SHAFT',ptMechanicalRotary);end;
function NewSpeedSensor(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Sensor velocidade',ckSpeedSensor,cdSensor);Result.AddPort('SHAFT',ptMechanicalRotary);Result.AddPort('OUT',ptSignal);end;
function NewController(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Controlador',ckController,cdController);Result.AddPort('SENSOR',ptSignal);Result.AddPort('PWM',ptSignal);end;
function NewResistor(const ID:string;Ohms:Double):TSimComponent;begin Result:=TSimComponent.Create(ID,'Resistor',ckResistor,cdElectrical);Result.AddPort('A',ptElectrical);Result.AddPort('B',ptElectrical);Result.Parameters.Values['resistance']:=FloatToStr(Ohms);end;
function NewCapacitor(const ID:string;Farads:Double):TSimComponent;begin Result:=TSimComponent.Create(ID,'Capacitor',ckCapacitor,cdElectrical);Result.AddPort('A',ptElectrical);Result.AddPort('B',ptElectrical);Result.Parameters.Values['capacitance']:=FloatToStr(Farads);end;
function NewInductor(const ID:string;Henries:Double):TSimComponent;begin Result:=TSimComponent.Create(ID,'Indutor',ckInductor,cdElectrical);Result.AddPort('A',ptElectrical);Result.AddPort('B',ptElectrical);Result.Parameters.Values['inductance']:=FloatToStr(Henries);end;
function NewRelay(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Rele',ckRelay,cdElectronic);Result.AddPort('COIL+',ptElectrical);Result.AddPort('COIL-',ptElectrical);Result.AddPort('COM',ptElectrical);Result.AddPort('NO',ptElectrical);Result.AddPort('NC',ptElectrical);end;
function NewStepper(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Motor de passo',ckStepperMotor,cdElectrical);Result.AddPort('PWR',ptElectrical);Result.AddPort('STEP',ptSignal);Result.AddPort('DIR',ptSignal);Result.AddPort('SHAFT',ptMechanicalRotary);end;
function NewServo(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Servo',ckServoMotor,cdElectrical);Result.AddPort('PWR',ptElectrical);Result.AddPort('CMD',ptSignal);Result.AddPort('SHAFT',ptMechanicalRotary);end;
function NewBLDC(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Motor BLDC',ckBLDCMotor,cdElectrical);Result.AddPort('PWR',ptElectrical);Result.AddPort('CMD',ptSignal);Result.AddPort('SHAFT',ptMechanicalRotary);end;
function NewGear(const ID:string;Ratio:Double):TSimComponent;begin Result:=TSimComponent.Create(ID,'Engrenagem',ckGear,cdMechanical);Result.AddPort('IN',ptMechanicalRotary);Result.AddPort('OUT',ptMechanicalRotary);Result.Parameters.Values['ratio']:=FloatToStr(Ratio);end;
function NewLeadScrew(const ID:string;PitchMM:Double):TSimComponent;begin Result:=TSimComponent.Create(ID,'Fuso',ckLeadScrew,cdMechanical);Result.AddPort('SHAFT',ptMechanicalRotary);Result.AddPort('LINEAR',ptMechanicalRotary);Result.Parameters.Values['pitch_mm']:=FloatToStr(PitchMM);end;
function NewEndStop(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Fim de curso',ckEndStop,cdSensor);Result.AddPort('OUT',ptSignal);Result.Parameters.Values['position']:=FloatToStr(0);end;
end.
