unit multicam_signal_trace;
{$mode objfpc}{$H+}
interface
uses multicam_electronics_types;
type TSignalSample=record TimeS:Double;XStep,XDir,YStep,YDir,ZStep,ZDir,EnableX,EnableY,EnableZ:Boolean;SpindlePWM:Double;LimitX,LimitY,LimitZ,EStop:Boolean;end;
 TSignalTrace=class
 private FSamples:array of TSignalSample;
 public procedure Clear;procedure Capture(TimeS:Double;const E:TElectronicsState);function Count:Integer;function Sample(I:Integer):TSignalSample;
 end;
implementation
procedure TSignalTrace.Clear;begin SetLength(FSamples,0);end;
procedure TSignalTrace.Capture(TimeS:Double;const E:TElectronicsState);var N:Integer;begin N:=Length(FSamples);SetLength(FSamples,N+1);FSamples[N].TimeS:=TimeS;FSamples[N].XStep:=E.X.Step=elHigh;FSamples[N].XDir:=E.X.Dir=elHigh;FSamples[N].YStep:=E.Y.Step=elHigh;FSamples[N].YDir:=E.Y.Dir=elHigh;FSamples[N].ZStep:=E.Z.Step=elHigh;FSamples[N].ZDir:=E.Z.Dir=elHigh;FSamples[N].EnableX:=E.X.Enable=elHigh;FSamples[N].EnableY:=E.Y.Enable=elHigh;FSamples[N].EnableZ:=E.Z.Enable=elHigh;FSamples[N].SpindlePWM:=E.Spindle.PWM;FSamples[N].LimitX:=E.LimitX;FSamples[N].LimitY:=E.LimitY;FSamples[N].LimitZ:=E.LimitZ;FSamples[N].EStop:=E.EStop;end;
function TSignalTrace.Count:Integer;begin Result:=Length(FSamples);end;function TSignalTrace.Sample(I:Integer):TSignalSample;begin Result:=FSamples[I];end;
end.
