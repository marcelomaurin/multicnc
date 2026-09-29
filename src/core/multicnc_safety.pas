unit multicnc_safety;
{$mode objfpc}{$H+}
interface
uses SysUtils,multicnc_types;
type TSafetyValidator=class
 public class function CanMove(AState:TMachineState;AAxis:TAxis;const C:TMachineCapabilities;out Reason:string):Boolean;
 end;
implementation
class function TSafetyValidator.CanMove(AState:TMachineState;AAxis:TAxis;const C:TMachineCapabilities;out Reason:string):Boolean;
begin Reason:=''; if AState in [msDisconnected,msConnecting,msAlarm,msError] then begin Reason:='Estado da maquina nao permite movimento';Exit(False);end; if not(AAxis in C.Axes) then begin Reason:='Eixo nao suportado';Exit(False);end; Result:=True; end;
end.
