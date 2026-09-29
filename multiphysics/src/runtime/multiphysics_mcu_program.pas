unit multiphysics_mcu_program;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multiphysics_mcu;
type TMCUOp=(moPinModeOut,moDigitalHigh,moDigitalLow,moPWM,moDelay,moStepPulse,moDirHigh,moDirLow);
 TMCUInstruction=record Op:TMCUOp;Pin:Integer;Value:Double;end;
 TMCUProgram=class
 private FCode:array of TMCUInstruction;FPC:Integer;FWait:Double;
 public procedure Add(Op:TMCUOp;Pin:Integer;Value:Double=0);procedure Reset;procedure Step(M:TMCU;Dt:Double);function Count:Integer;
 end;
implementation
procedure TMCUProgram.Add(Op:TMCUOp;Pin:Integer;Value:Double);var N:Integer;begin N:=Length(FCode);SetLength(FCode,N+1);FCode[N].Op:=Op;FCode[N].Pin:=Pin;FCode[N].Value:=Value;end;
procedure TMCUProgram.Reset;begin FPC:=0;FWait:=0;end;
procedure TMCUProgram.Step(M:TMCU;Dt:Double);var I:TMCUInstruction;begin M.Step(Dt);if FWait>0 then begin FWait:=FWait-Dt;Exit;end;if Length(FCode)=0 then Exit;if FPC>=Length(FCode)then FPC:=0;I:=FCode[FPC];case I.Op of moPinModeOut:M.PinMode(I.Pin,True);moDigitalHigh,moDirHigh:M.DigitalWrite(I.Pin,True);moDigitalLow,moDirLow:M.DigitalWrite(I.Pin,False);moPWM:M.PWMWrite(I.Pin,I.Value);moDelay:FWait:=I.Value;moStepPulse:begin M.DigitalWrite(I.Pin,True);end;end;Inc(FPC);end;
function TMCUProgram.Count:Integer;begin Result:=Length(FCode);end;
end.
