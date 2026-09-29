program test_physics_export;
{$mode objfpc}{$H+}
uses multipcb_model,multipcb_physics_export,multisuite_component_contract;
var P:TPCBProject;U:TUnifiedMachine;N:TNet;
begin P:=TPCBProject.Create;U:=TUnifiedMachine.Create;try P.AddComponent('PSU1','24V Supply','power','psu');P.AddComponent('MOTOR_X','DC Motor','motor.dc','motor');P.AddComponent('CTRL1','Controller MCU','controller.mcu','qfp');N:=P.AddNet('24V');N.Nodes.Add('PSU1.V+');N.Nodes.Add('MOTOR_X.PWR');N:=P.AddNet('CTRL');N.Nodes.Add('CTRL1.PWM');N.Nodes.Add('MOTOR_X.CMD');ExportPCBToUnified(P,U,False);if U.Count<>3 then Halt(1);if U.Find('MOTOR_X')=nil then Halt(2);if U.Find('MOTOR_X').Parameters.Values['net.PWR']<>'24V' then Halt(3);if U.LinkCount<>2 then Halt(4);Writeln('PASS MultiPCB physics export');finally U.Free;P.Free;end;end.
