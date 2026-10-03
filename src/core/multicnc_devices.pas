unit multicnc_devices;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, SysUtils,multicnc_interfaces;
type
 TRouterController=class
 public class function Spindle(const M:IMultiCNCMachine;OnOff:Boolean;RPM:Integer):Boolean; end;
 TLaserController=class
 public class function Power(const M:IMultiCNCMachine;OnOff:Boolean;P:Integer):Boolean; class function Frame(const M:IMultiCNCMachine;X,Y:Double):Boolean; end;
 TPrinter3DController=class
 public class function Hotend(const M:IMultiCNCMachine;T:Integer):Boolean; class function Bed(const M:IMultiCNCMachine;T:Integer):Boolean; class function Fan(const M:IMultiCNCMachine;P:Integer):Boolean; end;
implementation
class function TRouterController.Spindle(const M:IMultiCNCMachine;OnOff:Boolean;RPM:Integer):Boolean;begin if OnOff then Result:=M.SendGCode(Format('M3 S%d',[RPM])) else Result:=M.SendGCode('M5');end;
class function TLaserController.Power(const M:IMultiCNCMachine;OnOff:Boolean;P:Integer):Boolean;begin if OnOff then Result:=M.SendGCode(Format('M4 S%d',[P])) else Result:=M.SendGCode('M5');end;
class function TLaserController.Frame(const M:IMultiCNCMachine;X,Y:Double):Boolean;begin Result:=M.SendGCode(Format('G0 X%.3f Y%.3f',[X,Y],InvariantFS));end;
class function TPrinter3DController.Hotend(const M:IMultiCNCMachine;T:Integer):Boolean;begin Result:=M.SendGCode(Format('M104 S%d',[T]));end;
class function TPrinter3DController.Bed(const M:IMultiCNCMachine;T:Integer):Boolean;begin Result:=M.SendGCode(Format('M140 S%d',[T]));end;
class function TPrinter3DController.Fan(const M:IMultiCNCMachine;P:Integer):Boolean;begin Result:=M.SendGCode(Format('M106 S%d',[P]));end;
end.
