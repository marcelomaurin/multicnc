unit multiassembly_types;
{$mode objfpc}{$H+}
interface
type
 TAssemblyVec3=record X,Y,Z:Double;end;
 TAssemblyComponentKind=(ackMechanicalPart,ackMotor,ackSpindle,ackLeadScrew,ackLinearGuide,ackBearing,ackPulley,ackBelt,ackController,ackDriver,ackPowerSupply,ackVFD,ackRelay,ackSensor,ackEndStop,ackEStop,ackConnector,ackPCB,ackOther);
 TAssemblyPortKind=(apkMechanical,apkPower,apkGround,apkDigitalInput,apkDigitalOutput,apkAnalogInput,apkAnalogOutput,apkStep,apkDir,apkEnable,apkPWM,apkCommunication);
 TAssemblyPort=record Name:string;Kind:TAssemblyPortKind;Voltage:Double;end;
 TAssemblyComponent=record ID,Name,Model,SourceRef:string;Kind:TAssemblyComponentKind;Position,Rotation,Size:TAssemblyVec3;Ports:array of TAssemblyPort;end;
 TElectricalConnection=record FromComponent,FromPort,ToComponent,ToPort:string;Caption:string;end;
 TMechanicalRelationKind=(mrFixed,mrAxis,mrCoupled,mrBelt,mrLeadScrew);
 TMechanicalRelation=record A,B:string;Kind:TMechanicalRelationKind;Axis:TAssemblyVec3;Ratio,PitchMM:Double;end;
implementation
end.
