unit multiphysics_mcu;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math;
type TMCUFamily=(mfGeneric,mfATmega328P,mfESP32,mfRP2040,mfSTM32);
 TMCUProfile=record Name:string;ClockHz:QWord;FlashBytes,RAMBytes,EEPROMBytes,GPIOCount,ADCChannels,ADCBits,DACChannels,PWMChannels,UARTCount,SPICount,I2CCount:Integer;end;
 TGPIOPin=record OutputMode,DigitalValue:Boolean;AnalogValue:Double;PWM:Double;end;
 TMCU=class
 private FProfile:TMCUProfile;FPins:array of TGPIOPin;FTime:Double;FReset:Boolean;
 public constructor Create(Family:TMCUFamily);procedure Reset;procedure Step(Dt:Double);procedure PinMode(Pin:Integer;OutputMode:Boolean);procedure DigitalWrite(Pin:Integer;Value:Boolean);function DigitalRead(Pin:Integer):Boolean;procedure AnalogInput(Pin:Integer;Voltage:Double);function AnalogRead(Pin:Integer;VRef:Double):Integer;procedure PWMWrite(Pin:Integer;Duty:Double);function PWMRead(Pin:Integer):Double;property Profile:TMCUProfile read FProfile;property Time:Double read FTime;
 end;
function MCUProfile(F:TMCUFamily):TMCUProfile;
implementation
function MCUProfile(F:TMCUFamily):TMCUProfile;begin FillChar(Result,SizeOf(Result),0);case F of
mfATmega328P:begin Result.Name:='ATmega328P / Arduino Uno';Result.ClockHz:=16000000;Result.FlashBytes:=32768;Result.RAMBytes:=2048;Result.EEPROMBytes:=1024;Result.GPIOCount:=20;Result.ADCChannels:=6;Result.ADCBits:=10;Result.PWMChannels:=6;Result.UARTCount:=1;Result.SPICount:=1;Result.I2CCount:=1;end;
mfESP32:begin Result.Name:='ESP32';Result.ClockHz:=240000000;Result.FlashBytes:=4194304;Result.RAMBytes:=520*1024;Result.GPIOCount:=40;Result.ADCChannels:=18;Result.ADCBits:=12;Result.DACChannels:=2;Result.PWMChannels:=16;Result.UARTCount:=3;Result.SPICount:=4;Result.I2CCount:=2;end;
mfRP2040:begin Result.Name:='RP2040';Result.ClockHz:=133000000;Result.FlashBytes:=2*1024*1024;Result.RAMBytes:=264*1024;Result.GPIOCount:=30;Result.ADCChannels:=4;Result.ADCBits:=12;Result.PWMChannels:=16;Result.UARTCount:=2;Result.SPICount:=2;Result.I2CCount:=2;end;
mfSTM32:begin Result.Name:='STM32 Generic';Result.ClockHz:=72000000;Result.FlashBytes:=128*1024;Result.RAMBytes:=20*1024;Result.GPIOCount:=37;Result.ADCChannels:=16;Result.ADCBits:=12;Result.PWMChannels:=12;Result.UARTCount:=3;Result.SPICount:=2;Result.I2CCount:=2;end;
else begin Result.Name:='MCU Generic';Result.ClockHz:=16000000;Result.FlashBytes:=64*1024;Result.RAMBytes:=8*1024;Result.GPIOCount:=32;Result.ADCChannels:=8;Result.ADCBits:=12;Result.PWMChannels:=8;Result.UARTCount:=2;Result.SPICount:=1;Result.I2CCount:=1;end;end;end;
constructor TMCU.Create(Family:TMCUFamily);begin inherited Create;FProfile:=MCUProfile(Family);SetLength(FPins,FProfile.GPIOCount);Reset;end;
procedure TMCU.Reset;begin FTime:=0;FReset:=True;end;procedure TMCU.Step(Dt:Double);begin if Dt>0 then FTime:=FTime+Dt;FReset:=False;end;
procedure TMCU.PinMode(Pin:Integer;OutputMode:Boolean);begin if(Pin>=0)and(Pin<Length(FPins))then FPins[Pin].OutputMode:=OutputMode;end;
procedure TMCU.DigitalWrite(Pin:Integer;Value:Boolean);begin if(Pin>=0)and(Pin<Length(FPins))and FPins[Pin].OutputMode then FPins[Pin].DigitalValue:=Value;end;
function TMCU.DigitalRead(Pin:Integer):Boolean;begin Result:=(Pin>=0)and(Pin<Length(FPins))and FPins[Pin].DigitalValue;end;
procedure TMCU.AnalogInput(Pin:Integer;Voltage:Double);begin if(Pin>=0)and(Pin<Length(FPins))then FPins[Pin].AnalogValue:=Voltage;end;
function TMCU.AnalogRead(Pin:Integer;VRef:Double):Integer;var M:Integer;begin Result:=0;if(Pin<0)or(Pin>=Length(FPins))or(VRef<=0)then Exit;M:=(1 shl FProfile.ADCBits)-1;Result:=Round(Max(0,Min(VRef,FPins[Pin].AnalogValue))/VRef*M);end;
procedure TMCU.PWMWrite(Pin:Integer;Duty:Double);begin if(Pin>=0)and(Pin<Length(FPins))then FPins[Pin].PWM:=Max(0,Min(1,Duty));end;
function TMCU.PWMRead(Pin:Integer):Double;begin if(Pin>=0)and(Pin<Length(FPins))then Result:=FPins[Pin].PWM else Result:=0;end;
end.
