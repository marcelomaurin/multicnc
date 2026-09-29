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
implementation
function NewPowerSupply(const ID:string;Voltage,MaxCurrent:Double):TSimComponent;begin Result:=TSimComponent.Create(ID,'Fonte',ckPowerSupply,cdElectrical);Result.AddPort('V+',ptElectrical);Result.AddPort('GND',ptElectrical);Result.Parameters.Values['voltage']:=FloatToStr(Voltage);Result.Parameters.Values['max_current']:=FloatToStr(MaxCurrent);end;
function NewPWMDriver(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Driver PWM',ckPWMDriver,cdElectronic);Result.AddPort('VIN',ptElectrical);Result.AddPort('VOUT',ptElectrical);Result.AddPort('CMD',ptSignal);end;
function NewDCMotor(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Motor DC',ckDCMotor,cdElectrical);Result.AddPort('PWR',ptElectrical);Result.AddPort('SHAFT',ptMechanicalRotary);Result.AddPort('TEMP',ptThermal);end;
function NewAxisLoad(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Carga de eixo',ckAxisLoad,cdMechanical);Result.AddPort('SHAFT',ptMechanicalRotary);end;
function NewSpeedSensor(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Sensor velocidade',ckSpeedSensor,cdSensor);Result.AddPort('SHAFT',ptMechanicalRotary);Result.AddPort('OUT',ptSignal);end;
function NewController(const ID:string):TSimComponent;begin Result:=TSimComponent.Create(ID,'Controlador',ckController,cdController);Result.AddPort('SENSOR',ptSignal);Result.AddPort('PWM',ptSignal);end;
end.
