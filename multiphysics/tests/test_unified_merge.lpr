program test_unified_merge;
{$mode objfpc}{$H+}
uses Classes, multiassembly_types, multiassembly_project, multiassembly_physics_export,
  multisuite_component_contract, multiphysics_graph, multiphysics_unified_import;
var A:TAssemblyProject; U:TUnifiedMachine; G:TSimulationGraph;
  C:TAssemblyComponent; Motor, Supply:TUnifiedComponent; Link:TUnifiedLink; Log:TStringList;
begin
  A:=TAssemblyProject.Create; U:=TUnifiedMachine.Create; Log:=TStringList.Create;
  try
    FillChar(C,SizeOf(C),0); C.ID:='MOTOR_X'; C.Name:='Motor X'; C.Kind:=ackMotor;
    A.AddComponent(C); ExportAssemblyToUnified(A,U);
    Motor:=U.Find('MOTOR_X'); if Motor=nil then Halt(1);
    { O contrato eletrico complementa a mesma montagem, sem duplicar o motor. }
    Motor.Domains:=Motor.Domains+[udElectrical,udElectronic]; Motor.Model:='motor.dc';
    Motor.Parameters.Values['net.PWR']:='24V';
    Supply:=TUnifiedComponent.Create('PSU1','24V Supply');
    Supply.Domains:=[udElectrical]; Supply.Parameters.Values['net.V+']:='24V'; U.Add(Supply);
    Link.FromID:='PSU1'; Link.FromPort:='V+'; Link.ToID:='MOTOR_X';
    Link.ToPort:='PWR'; Link.Kind:=upElectrical; U.Link(Link);
    if U.Count<>2 then Halt(2);
    if not(udMechanical in Motor.Domains)then Halt(3);
    if not(udElectrical in Motor.Domains)then Halt(4);
    G:=UnifiedToSimulation(U,Log);
    try
      if G.Find('MOTOR_X')=nil then Halt(5);
      if G.ConnectionCount<>1 then Halt(6);
    finally G.Free; end;
    Writeln('PASS Assembly + electrical unified contract');
  finally Log.Free; U.Free; A.Free; end;
end.
