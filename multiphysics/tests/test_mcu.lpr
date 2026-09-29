program test_mcu;
{$mode objfpc}{$H+}
uses Math,multiphysics_mcu,multiphysics_mcu_program;
var M:TMCU;P:TMCUProgram;I:Integer;
begin M:=TMCU.Create(mfATmega328P);P:=TMCUProgram.Create;try if M.Profile.GPIOCount<>20 then Halt(1);M.PinMode(13,True);M.DigitalWrite(13,True);if not M.DigitalRead(13)then Halt(2);M.AnalogInput(0,2.5);I:=M.AnalogRead(0,5);if Abs(I-512)>1 then Halt(3);M.PWMWrite(3,0.5);if Abs(M.PWMRead(3)-0.5)>1e-6 then Halt(4);P.Add(moPinModeOut,2);P.Add(moDirHigh,2);P.Add(moPinModeOut,3);P.Add(moStepPulse,3);for I:=1 to 4 do P.Step(M,0.001);if not M.DigitalRead(2)then Halt(5);if not M.DigitalRead(3)then Halt(6);Writeln('PASS MCU peripherals and program');finally P.Free;M.Free;end;end.
