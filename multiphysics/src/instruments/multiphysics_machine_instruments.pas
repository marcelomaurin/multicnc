unit multiphysics_machine_instruments;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multiphysics_machine_runtime;
procedure SampleMachine(M:TMachineRuntime;Lines:TStrings);
implementation
procedure SampleMachine(M:TMachineRuntime;Lines:TStrings);var I:Integer;A:TAxisRuntime;begin Lines.Add('EIXO;POS_MM;CORRENTE_A;TEMP_C;PASSOS_PERDIDOS');for I:=0 to M.AxisCount-1 do begin A:=M.Axis(I);Lines.Add(Format('%s;%.4f;%.3f;%.2f;%d',[A.Name,A.State.PositionMM,A.Current,A.Temperature,A.Motor.LostSteps]));end;Lines.Add(Format('SPINDLE;%.1f RPM',[M.SpindleRPM]));end;
end.
