program test_mcu_stepper;
{$mode objfpc}{$H+}
uses multiphysics_mcu,multiphysics_digital_power;
var M:TMCU;D:TStepperDriverState;I:Integer;
begin M:=TMCU.Create(mfESP32);try M.PinMode(18,True);M.PinMode(19,True);M.DigitalWrite(19,True);for I:=1 to 200 do begin M.DigitalWrite(18,True);StepperDriverStep(D,M.DigitalRead(18),M.DigitalRead(19),True);M.DigitalWrite(18,False);StepperDriverStep(D,M.DigitalRead(18),M.DigitalRead(19),True);M.Step(0.0001);end;if D.StepCount<>200 then Halt(1);Writeln('PASS ESP32 -> STEP/DIR = ',D.StepCount);finally M.Free;end;end.
