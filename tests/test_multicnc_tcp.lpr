program test_multicnc_tcp;
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multicnc_session, multicnc_types,
  multislicer_mesh, multislicer_pipeline;
type
  TProbe=class
    Data:string;
    procedure Receive(const S:string);
    procedure Expect(Session:TSimulationSession; const Token:string);
  end;
procedure TProbe.Receive(const S:string);
begin Data:=Data+S;end;
procedure TProbe.Expect(Session:TSimulationSession; const Token:string);
var Deadline:QWord;
begin
  Deadline:=GetTickCount64+8000;
  repeat Session.Poll;Session.Tick;Sleep(10);until (Pos(Token,Data)>0) or (GetTickCount64>Deadline);
  if Pos(Token,Data)=0 then raise Exception.Create('Missing '+Token+': '+Data);
  Data:='';
end;
procedure Check(V:Boolean;const Msg:string);
begin if not V then raise Exception.Create(Msg);end;
var S:TSimulationSession;Probe:TProbe;I:Integer;Deadline,T0:QWord;
    G:TStringList;M:TMesh;W:TModernSlicer;Settings:TSliceSettings;
    FN,Reason:string; MaxHotend,MaxBed:Double;
begin
  S:=TSimulationSession.Create;Probe:=TProbe.Create;G:=TStringList.Create;
  M:=TMesh.Create;W:=TModernSlicer.Create;FN:=GetTempFileName(GetTempDir,'tcp');
  try
    S.OnLog:=@Probe.Receive;
    for I:=1 to 2 do begin
      Check(S.Connect(mtPrinter3D,pkMarlin,'127.0.0.1:9000',115200),'connection');
      Probe.Expect(S,'start');Deadline:=GetTickCount64+8000;
      repeat S.Poll;S.Tick;Sleep(10);until S.ControllerReady or (GetTickCount64>Deadline);
      Check(S.ControllerReady,'boot deadline');Probe.Expect(S,'FIRMWARE_NAME');
      Check(S.Send('G90'),'send G90');Probe.Expect(S,'ok');
      Check(S.Send('G1 X12 Y15 F6000'),'send move');Probe.Expect(S,'ok');
      Check(S.Send('M114'),'send position');Probe.Expect(S,'X:12.000 Y:15.000');
      S.QueryTemperatures;Deadline:=GetTickCount64+5000;
      repeat S.Poll;S.Tick;Sleep(10);until S.Temperatures.HasReadings or (GetTickCount64>Deadline);
      Check(S.Temperatures.HasReadings,'temperature readings');
      if I=1 then begin S.Disconnect;Sleep(300);end;
    end;
    AddBox(M,10,10,0,14,14,0.4);
    Settings:=DefaultSliceSettings;Settings.ArcFitting:=False;
    Settings.Adhesion:=adNone;Settings.SkirtLoops:=0;Settings.FirstLayerHeight:=0.2;
    Settings.Printer.HotendTemp:=180;Settings.Printer.BedTemp:=30;
    Settings.Printer.Name:='TCP Cartesian test (not a calibrated Ender 3 profile)';
    W.Slice(M,Settings,G);G.SaveToFile(FN);
    if ParamCount>0 then G.SaveToFile(ParamStr(1));
    S.LoadFile(FN);S.SetWorkEnvelope(220,220,250);
    Check(S.ValidateProgram(Reason),'audit: '+Reason);
    { Drain the periodic query before Start, which correctly rejects pending work. }
    Deadline:=GetTickCount64+5000;
    repeat S.Poll;Sleep(10);until (S.MachineState=msIdle) or (GetTickCount64>Deadline);
    Check(S.Start,'start: '+S.LastError);T0:=GetTickCount64;MaxHotend:=0;MaxBed:=0;
    while (S.State in [ssRunning,ssPaused]) and (GetTickCount64-T0<180000) do begin
      S.Poll;S.Tick;MaxHotend:=Max(MaxHotend,S.Temperatures.HotendActual);
      MaxBed:=Max(MaxBed,S.Temperatures.BedActual);Sleep(10);
    end;
    if ParamCount>1 then S.SaveSessionLog(ParamStr(2));
    Check(S.State=ssDone,Format('print state %d: %s (%d/%d)',[Ord(S.State),S.LastError,S.Completed,S.Count]));
    Check(S.Completed=S.Count,'all commands acknowledged');
    Check(GetTickCount64-T0>10000,'actual thermal/motion time, not an immediate-ack stub');
    Check((MaxHotend>=179) and (MaxBed>=29),'thermal targets reached in simulation');
    Check(S.Send('M114'),'final position query');Probe.Expect(S,'Z:5.400');
    if ParamCount>1 then S.SaveSessionLog(ParamStr(2));
    Writeln(Format('PASS: real TCP generated print, %d commands, %d ms; hotend %.1f, bed %.1f; final Z 5.4; reconnect and M400 completion',
      [S.Count,GetTickCount64-T0,MaxHotend,MaxBed]));
    S.Disconnect;
    Check(not S.Connect(mtPrinter3D,pkMarlin,'127.0.0.1:0',115200),'invalid port rejected');
  finally
    S.Free;Probe.Free;G.Free;M.Free;W.Free;DeleteFile(FN);
  end;
end.
