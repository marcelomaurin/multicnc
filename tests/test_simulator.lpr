program test_simulator;

{$mode objfpc}{$H+}

uses
  SysUtils, multicnc_types, multicnc_interfaces, multicnc_machine,
  multicnc_simulator;

var
  Transport: IMultiCNCTransport;
  Protocol: IMultiCNCProtocol;
  Machine: IMultiCNCMachine;
begin
  Transport := TSimulatorTransport.Create;
  Protocol := TSimulatorProtocol.Create;
  Machine := TMultiCNCMachine.Create(mtRouter, Transport, Protocol);

  if not Machine.Connect then Halt(1);
  if Machine.GetState <> msIdle then Halt(2);
  if not Machine.Home then Halt(3);
  if not Machine.Jog(axX, 10, 1000) then Halt(4);
  if Machine.Jog(axE, 10, 1000) then Halt(5); // Router nao possui E.
  if not Machine.SendGCode('G0 X20 Y20') then Halt(6);
  if not Machine.Pause then Halt(7);
  if not Machine.Resume then Halt(8);
  if not Machine.Stop then Halt(9);
  Machine.Disconnect;
  if Machine.GetState <> msDisconnected then Halt(10);

  WriteLn('MultiCNC simulator: OK');
end.
