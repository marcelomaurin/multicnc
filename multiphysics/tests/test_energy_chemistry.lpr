program test_energy_chemistry;
{$mode objfpc}{$H+}
uses Math,multiphysics_energy_chemistry;
var B:TBatteryModel;P:TSolarPanel;V,S:Double;
begin B:=LeadAcid12V(10);V:=BatteryTerminalVoltage(B,5);if(V<=0)or(V>=13)then Halt(1);BatteryStep(B,5,3600);if Abs(B.SOC-0.5)>0.01 then Halt(2);P.RatedPower:=100;P.TemperatureCoefficient:=-0.004;S:=SolarPower(P,1000,25);if Abs(S-100)>0.01 then Halt(3);if Gasoline.LowerHeatingValue<=EthanolFuel.LowerHeatingValue then Halt(4);if Water.SpecificHeat<4000 then Halt(5);Writeln('PASS energy and chemistry');end.
