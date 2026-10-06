program test_simu_temperature_control;
{$mode objfpc}{$H+}
uses
  Classes, SysUtils, aimarlinsimulator;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then raise Exception.Create('TEST FAILED: ' + Msg);
end;

type
  TTestListener = class
  public
    LastResp: string;
    procedure HandleResponse(Sender: TObject; const Text: string);
  end;

procedure TTestListener.HandleResponse(Sender: TObject; const Text: string);
begin
  LastResp := Text;
end;

var
  Sim: TAIMarlinSimulator;
  Listener: TTestListener;
begin
  WriteLn('Testing TAIMarlinSimulator Temperature Controls...');
  Sim := TAIMarlinSimulator.Create(nil);
  Listener := TTestListener.Create;
  try
    Sim.OnResponse := @Listener.HandleResponse;

    // Initial state
    Check(Sim.State.Hotend = 25.0, 'Initial hotend is 25 C');
    Check(Sim.State.Bed = 25.0, 'Initial bed is 25 C');
    Check(Sim.State.HotendTarget = 0.0, 'Initial hotend target is 0');
    Check(Sim.State.BedTarget = 0.0, 'Initial bed target is 0');

    // Test SetHotendTarget & SetBedTarget
    Sim.SetHotendTarget(210.0);
    Sim.SetBedTarget(60.0);
    Check(Sim.State.HotendTarget = 210.0, 'Hotend target set to 210');
    Check(Sim.State.BedTarget = 60.0, 'Bed target set to 60');

    // Test Advance / Heating step
    Sim.Advance(5.0); // 5 seconds of heating (3 C/s hotend, 0.8 C/s bed)
    Check(Sim.State.Hotend > 25.0, 'Hotend heated up after 5 seconds');
    Check(Sim.State.Bed > 25.0, 'Bed heated up after 5 seconds');

    // Test SetHotendActual & SetBedActual (instant heat test)
    Sim.SetHotendActual(210.0);
    Sim.SetBedActual(60.0);
    Check(Sim.State.Hotend = 210.0, 'Instant hotend actual reached 210');
    Check(Sim.State.Bed = 60.0, 'Instant bed actual reached 60');

    // Test M105 temperature query
    Sim.Receive('M105'#10);
    Check(Pos('T:210', Listener.LastResp) > 0, 'M105 reports hotend temperature');
    Check(Pos('B:60', Listener.LastResp) > 0, 'M105 reports bed temperature');

    // Test cooldown
    Sim.SetHotendTarget(0);
    Sim.SetBedTarget(0);
    Check(Sim.State.HotendTarget = 0, 'Hotend target cooled to 0');
    Check(Sim.State.BedTarget = 0, 'Bed target cooled to 0');
  finally
    Sim.Free;
    Listener.Free;
  end;
  WriteLn('ALL SIMULATOR TEMPERATURE CONTROL TESTS PASSED!');
end.
