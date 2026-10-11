program test_outline;
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multicnc_outline, multicnc_gcode_analyzer,
  multicnc_session, multicnc_types, multicnc_simulator;
procedure Check(OK:Boolean; const Msg:string);
begin if not OK then raise Exception.Create(Msg); end;
var Source, Path:TStringList; B:TGCodeBounds; I,N:Integer; S:TSimulationSession;
    T:TSimulatorTransport; FN:string; Rejected:Boolean;
begin
 Source:=TStringList.Create; S:=TSimulationSession.Create; Path:=nil;
 FN:=GetTempFileName(GetTempDir,'out');
 try
  Source.Text:='; header'#10'$H'#10'G21 G90'#10'G92 X0 Y0 Z0'#10'M3 S8000'#10'G0 Z5'#10+
    'G0 X20 Y20'#10'G1 Z-1 F300'#10'G1 X80 Y20 F900'#10'G1 X80 Y80'#10'G1 X20 Y80'#10'G1 X20 Y20'#10'M5';
  Path:=BuildOutline(Source,500,B);
  Check((B.MinX=20) and (B.MinY=20) and (B.MaxX=80) and (B.MaxY=80),'Actual XY extents exclude initial Z at origin');
  Check(OutlineFeed(B,20,20)=1800,'60x60 perimeter in 8 seconds independent from engraving feed');
  Check(OutlineFeed(B,0,0)>1800,'Approach included in time budget');
  Check((Path[0]='M5') and (Path[1]='G21 G90 G94') and (Path[Path.Count-1]='M5'),'Units, feed mode, absolute and power off');
  Check((Path[2]='G1 X20.000 Y20.000 F500.000') and (Path[6]='G1 X20.000 Y20.000'),'Approach and closed rectangle');
  for I:=0 to Path.Count-1 do
    Check((Pos('Z',Path[I])=0) and (Pos('M3',Path[I])=0) and (Pos('$H',Path[I])=0),'No Z, spindle or homing commands');
  FreeAndNil(Path);
  Source.Text:='G20 G90'#10'G0 X1 Y1'#10'G91 G1 X1 Y2 F10';
  Path:=BuildOutline(Source,500,B);
  Check((Abs(B.MinX-25.4)<0.0001) and (Abs(B.MaxX-50.8)<0.0001) and
    (Abs(B.MaxY-76.2)<0.0001),'Relative inches converted to millimetres');
  FreeAndNil(Path);
  Source.Text:='G21 G90'#10'G0 X60 Y50'#10'G2 I-10 J0 F500';
  Path:=BuildOutline(Source,500,B);
  Check((Abs(B.MinX-40)<0.01) and (Abs(B.MaxX-60)<0.01) and
    (Abs(B.MinY-40)<0.01) and (Abs(B.MaxY-60)<0.01),'Full circle includes arc extremes');
  FreeAndNil(Path);
  Source.Text:='G0 X-20 Y-30'#10'G1 X-10 Y-5 F500';
  Path:=BuildOutline(Source,500,B);
  Check((B.MinX=-20) and (B.MaxX=-10) and (B.MinY=-30) and (B.MaxY=-5),'Negative coordinates');
  FreeAndNil(Path);
  Source.Text:='G21 G90'#10'G0 X20 Y20'#10'G1 X80 Y20 F500'#10'G1 X80 Y80'#10'G1 X20 Y80'#10'G1 X20 Y20';
  Source.SaveToFile(FN); S.LoadFile(FN);
  Check(not S.RunOutline,'Disconnected outline rejected');
  T:=TSimulatorTransport.Create; T.DeferredReplies:=True;
  Check(S.ConnectTransport(mtLaser,pkGRBL,T,T),'Connect local simulator');
  N:=S.Count; Check(S.RunOutline,'Run outline');
  Check(not S.RunOutline,'Reject overlapping outline');
  for I:=1 to 100 do begin S.Poll; S.Tick; if not S.FramingActive then Break; end;
  Check((S.State=ssIdle) and (S.Count=N) and not S.FramingActive,'Original program restored after outline');
  Check(S.Start,'Original program still starts after outline');
  S.Stop; S.Disconnect;
  Source.Text:='G53 G0 X0'#10'G0 X10 Y10';
  Rejected:=False; try Path:=BuildOutline(Source,500,B); except Rejected:=True; end;
  Check(Rejected,'Uncertain machine coordinates rejected');
  Source.Text:='G0 Z5';
  Rejected:=False; try Path:=BuildOutline(Source,500,B); except Rejected:=True; end;
  Check(Rejected,'Z-only program rejected');
  Writeln('PASS: Outline geometry, units, arcs, no spindle/Z/homing, session guards and program preservation');
 finally Path.Free; S.Free; Source.Free; DeleteFile(FN); end;
end.
