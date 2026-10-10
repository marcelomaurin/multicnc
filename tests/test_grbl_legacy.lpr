program test_grbl_legacy;
{$mode objfpc}{$H+}
uses SysUtils, multicnc_realtime, multicnc_types, multicnc_grbl, multicnc_grbl_status;
procedure Check(Value:Boolean; const Msg:string);
begin if not Value then raise Exception.Create(Msg); end;
var P:TGRBLProtocol; S:TMachineState; Position:TMachinePosition;
begin
 P:=TGRBLProtocol.Create;
 try
  Check(P.BuildJogCommand(axX,1,500)='','No jog before identification');
  P.ProcessIncoming('Grbl 0.9j [''$'' for help]'#13#10);
  P.ProcessIncoming('<Idle,MPos:0.000,0.000,0.000,WPos:-3.056,');
  P.ProcessIncoming('-5.238,26.256>'#13#10);
  Check(P.ReportedState(S) and (S=msIdle),'Legacy Idle');
  Check(P.CurrentState=msIdle,'Parser legacy state');
  Check(P.ReportedPosition(Position),'Legacy reported position');
  Check((Abs(Position.X+3.056)<0.001) and (Abs(Position.Y+5.238)<0.001) and
    (Abs(Position.Z-26.256)<0.001),'Legacy coordinates including negative values');
  Check(P.Parser.Status.HasMPos and P.Parser.Status.HasWPos,'Both legacy coordinates');
  Check((P.Parser.Version='0.9j') and (P.Parser.Compatibility=gcLegacy),'Legacy version detection');
  Check(P.BuildFeedOverride(110)='','No modern feed override on legacy');
  Check(P.BuildSpindleOverride(110)='','No modern spindle override on legacy');
  Check(P.BuildJogCancel='','No modern jog cancel on legacy');
  Check(P.BuildRealtime(rtFeedHold)='!','Legacy hold available');
  P.ProcessIncoming('$13=0 (report inches, bool)'#10);
  P.ProcessIncoming('[G0 G54 G17 G21 G91 G94 M5 M9 T0 F0.0 S0.0]'#10);
  Check(P.BuildJogCommand(axX,1.5,500)='G91 G21 G94 G1 X1.500 F500'+LineEnding+
    'G21 G91 G94 G0 F0.0'+LineEnding,'Legacy jog restores original distance, motion and feed');
  P.ProcessIncoming('$13=1'#10);
  Check(P.BuildJogCommand(axX,1,500)='','Legacy inch reports block manual movement');
  P.ProcessIncoming('$13=0'#10);
  P.ProcessIncoming('[G2 G54 G17 G21 G90 G94 M5 M9 T0 F100 S0]'#10);
  Check(P.BuildJogCommand(axX,1,500)='','No jog with unrestorable arc mode');
  P.ProcessIncoming('error:Setting disabled'#10);
  Check(P.Parser.LastError=0,'Legacy textual error handled');
  P.ProcessIncoming('<Run,MPos:1,2,3,WPos:4,5,6,Buf:15,RX:0>'#10);
  Check(P.ReportedState(S) and (S=msRunning) and (P.CurrentState=msRunning),'Legacy Run');
  P.ProcessIncoming('<Hold,MPos:1,2,3,WPos:4,5,6>'#10);
  Check(P.ReportedState(S) and (S=msPaused) and (P.CurrentState=msPaused),'Legacy Hold');
  P.ProcessIncoming('<Alarm,MPos:1,2,3,WPos:4,5,6>'#10);
  Check(P.ReportedState(S) and (S=msAlarm) and (P.CurrentState=msAlarm),'Legacy Alarm');
  P.ProcessIncoming('<Idle|MPos:10,20,30|WCO:1,2,3|FS:100,200>'#10);
  Check(P.ReportedPosition(Position) and (Position.X=9) and (Position.Y=18) and (Position.Z=27),'GRBL 1.1 retained');
  Check((P.Parser.Status.Feed=100) and (P.Parser.Status.Spindle=200),'GRBL 1.1 fields');
  P.ProcessIncoming('Grbl 1.1h'#10);
  Check((P.Parser.Version='1.1h') and (P.Parser.Compatibility=gcModern),'Modern version detection');
  Check(Pos('$J=',P.BuildJogCommand(axX,1,500))=1,'Modern native jog');
  Check(P.BuildFeedOverride(110)=#$91,'Modern feed override');
  P.ProcessIncoming('Grbl 1.0c'#10);
  Check(P.Parser.Compatibility=gcLegacy,'1.0 is earlier than native jog');
  P.Reset;
  Check((P.Parser.Version='') and (P.Parser.Compatibility=gcUnknown),'Reconnect discards old version');
  P.ProcessIncoming('[0.9j.20160726:]'#10);
  Check((P.Parser.Version='0.9j') and (P.Parser.Compatibility=gcLegacy),'Legacy build info fallback');
  P.Reset; P.ProcessIncoming('[VER:1.1h.20190825:]'#10);
  Check(P.Parser.Compatibility=gcModern,'Modern build info fallback');
  P.ProcessIncoming('GrblHAL 1.1f'#10);
  Check((P.Parser.Firmware=gfGrblHAL) and (P.Parser.Compatibility=gcModern),'grblHAL detection');
  P.ProcessIncoming('[MSG:INFO: FluidNC v3.9.1]'#10);
  Check((P.Parser.Firmware=gfFluidNC) and (P.Parser.Compatibility=gcModern),'FluidNC detection');
  Writeln('GRBL versions and capabilities: OK');
 finally P.Free; end;
end.