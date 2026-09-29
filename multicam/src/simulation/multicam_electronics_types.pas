unit multicam_electronics_types;
{$mode objfpc}{$H+}
interface
type TElectricalLevel=(elLow,elHigh,elFloating);
 TAxisElectricalState=record Step,Dir,Enable:TElectricalLevel;PulseCount:Int64;DriverFault:Boolean;MotorCurrentA,SupplyV,DriverTempC,CommandMM,ActualMM:Double;LostSteps:Int64;end;
 TSpindleElectricalState=record Enable:Boolean;PWM:Double;CommandRPM,FeedbackRPM:Double;Fault:Boolean;end;
 TElectronicsState=record X,Y,Z:TAxisElectricalState;LimitX,LimitY,LimitZ,EStop:Boolean;Spindle:TSpindleElectricalState;ControllerV,LogicV:Double;end;
implementation
end.
