unit multicam_electronics_faults;
{$mode objfpc}{$H+}
interface
uses multicam_electronics_types;
type TFaultKind=(fkNone,fkEStop,fkLimitX,fkLimitY,fkLimitZ,fkDriverX,fkDriverY,fkDriverZ,fkSpindle);
 TElectronicFaults=class public class procedure Inject(var S:TElectronicsState;F:TFaultKind);static;end;
implementation
class procedure TElectronicFaults.Inject(var S:TElectronicsState;F:TFaultKind);
begin case F of fkEStop:S.EStop:=True;fkLimitX:S.LimitX:=True;fkLimitY:S.LimitY:=True;fkLimitZ:S.LimitZ:=True;fkDriverX:S.X.DriverFault:=True;fkDriverY:S.Y.DriverFault:=True;fkDriverZ:S.Z.DriverFault:=True;fkSpindle:S.Spindle.Fault:=True;end;end;
end.
