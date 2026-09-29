program test_degradation_faults;
{$mode objfpc}{$H+}
uses multiphysics_types,multiphysics_materials,multiphysics_degradation,multiphysics_electrical_faults;
var D:TDegradationState;E:TCorrosionEnvironment;C:TCorrosionModel;M:TMaterial;S:TShortCircuitState;P:TProtectionModel;I:Integer;
begin M:=Steel;InitDegradation(D,1);E.TemperatureC:=30;E.RelativeHumidity:=0.9;E.ChlorideFactor:=1;E.AcidityFactor:=0;E.OxygenFactor:=1;C.BaseRateMMPerYear:=0.2;C.ActivationPer10C:=2;C.HumidityThreshold:=0.6;CorrosionStep(D,M,E,C,365.25*24*3600);if(D.Thickness>=1)or(D.Integrity>=1)or(D.ResistanceMultiplier<=1)then Halt(1);OxidationStep(D,100,1,0.1,3600);if D.OxideThickness<=0 then Halt(2);InitShort(S,0.05,25);P.CurrentLimit:=10;P.TripDelay:=0.05;P.FuseI2t:=1000;for I:=1 to 20 do ShortCircuitStep(S,P,24,0.01,50,1,25);if not S.Tripped then Halt(3);Writeln('PASS degradation corrosion oxidation short circuit');end.
