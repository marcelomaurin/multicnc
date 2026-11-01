program test_bed_calibration;
{$mode objfpc}{$H+}
{$interfaces corba}
uses Classes, SysUtils, multisuite_numfmt, multicnc_interfaces, multicnc_protocol_base, multicnc_types, multicnc_session, multicnc_bed_calibration;
type
  TPositionSimulator = class(TInterfacedObject,IMultiCNCTransport)
    Connected: Boolean;
    Data: TTransportDataEvent;
    State: TTransportStateEvent;
    P: TMachinePosition;
    MinTravelZ: Double;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure Poll;
    procedure SetOnData(E: TTransportDataEvent);
    procedure SetOnState(E: TTransportStateEvent);
    function GetName: string;
  end;
function TPositionSimulator.Connect: Boolean;
begin Connected:=True; if Assigned(State) then State(True); if Assigned(Data) then Data('Grbl 1.1h'+LineEnding); Result:=True; end;
procedure TPositionSimulator.Disconnect;
begin Connected:=False; end;
function TPositionSimulator.IsConnected: Boolean;
begin Result:=Connected; end;
procedure TPositionSimulator.Poll;
begin end;
procedure TPositionSimulator.SetOnData(E: TTransportDataEvent);
begin Data:=E; end;
procedure TPositionSimulator.SetOnState(E: TTransportStateEvent);
begin State:=E; end;
function TPositionSimulator.GetName: string;
begin Result:='Position simulator'; end;
function TPositionSimulator.Send(const AData: string): Boolean;
var Lines: TStringList; Line: string; V: Double;
begin
  Result:=Connected; if not Result or not Assigned(Data) then Exit;
  if AData='?' then begin Data(Format('<Idle|WPos:%.3f,%.3f,%.3f|FS:0,0>',[P.X,P.Y,P.Z],InvariantFS)+LineEnding); Exit; end;
  if Pos(#24,AData)>0 then begin Data('Grbl 1.1h'+LineEnding); Exit; end;
  Lines:=TStringList.Create;
  try
    Lines.Text:=AData;
    for Line in Lines do if Trim(Line)<>'' then begin
      if (Copy(Line,1,2)='G1') or (Copy(Line,1,2)='G0') then begin
        if ValueAfter(Line,'X',V) and (Abs(V-P.X)>0.001) and (P.Z<MinTravelZ-0.001) then raise Exception.Create('X moved below travel height');
        if ValueAfter(Line,'Y',V) and (Abs(V-P.Y)>0.001) and (P.Z<MinTravelZ-0.001) then raise Exception.Create('Y moved below travel height');
        if ValueAfter(Line,'X',V) then P.X:=V;
        if ValueAfter(Line,'Y',V) then P.Y:=V;
        if ValueAfter(Line,'Z',V) then P.Z:=V;
      end;
      if SameText(Trim(Line),'M114') then
        Data(Format('X:%.3f Y:%.3f Z:%.3f E:0.00',[P.X,P.Y,P.Z],InvariantFS)+LineEnding);
      Data('ok'+LineEnding);
    end;
  finally Lines.Free; end;
end;
var S: TSimulationSession; C: TBedCalibration; T: TPositionSimulator; I: Integer;
procedure Check(B: Boolean; const Msg: string);
begin if not B then raise Exception.Create(Msg+' / '+C.MessageText); end;
procedure Arrive(X,Y: Double);
var J: Integer;
begin
  for J:=1 to 150 do begin S.Poll; S.Tick; C.Tick; if C.Stage=0 then Break; Sleep(20); end;
  if C.Stage<>0 then WriteLn('DEBUG stage=',C.Stage,' machine=',Ord(S.MachineState),' session=',Ord(S.State),' wait=',S.WaitingForReply,' pos=',S.Position.X:0:3,',',S.Position.Y:0:3,',',S.Position.Z:0:3);
  Check(C.Active and (C.Stage=0),'Arrival');
  Check((Abs(S.Position.X-X)<0.02) and (Abs(S.Position.Y-Y)<0.02) and (Abs(S.Position.Z-2)<0.02),'Coordinates');
end;
begin
  S:=TSimulationSession.Create; C:=TBedCalibration.Create(S);
  try
    Check(not C.Start(5,5,2,300),'Disconnected guard');
    T:=TPositionSimulator.Create;
    T.MinTravelZ:=10;
    Check(S.ConnectTransport(mtRouter,pkGRBL,T,T),'Connect');
    for I:=1 to 5 do begin S.Poll; S.Tick; end;
    Check(not C.Start(5,5,2,300),'Unknown envelope');
    S.SetWorkEnvelope(200,150,50);
    Check(not C.Start(100,5,2,300),'Invalid margin');
    Check(not C.Start(5,5,48,300),'Clearance validation');
    Check(not C.Start(5,5,2,300,9),'Minimum travel height');
    Check(C.Start(5,5,2,300),'Start');
    Check(not C.Navigate(1),'No navigation during motion');
    Arrive(5,5);
    for I:=1 to 10 do C.Tick;
    Check(C.Corner=0,'Wait for operator');
    Check(not C.Navigate(-1),'First corner bound');
    Check(C.Navigate(1),'Next'); Arrive(195,5);
    Check(C.Navigate(1),'Next'); Arrive(195,145);
    Check(C.Navigate(-1),'Previous'); Arrive(195,5);
    Check(C.Navigate(1),'Next'); Arrive(195,145);
    Check(C.Navigate(1),'Next'); Arrive(5,145);
    Check(not C.Navigate(1),'Last corner bound');
    C.Finish; Check(not C.Active,'Finish');
    T.MinTravelZ:=20;
    Check(C.Start(5,5,2,300,20),'Custom travel height'); Arrive(5,5);
    Check(C.Navigate(1),'Custom height next'); Arrive(195,5); C.Finish;
    Check(C.Start(5,5,2,300),'Restart');
    C.Finish; Check(not C.Active,'Finish during motion');
    for I:=1 to 5 do begin S.Poll; S.Tick; end;
    S.Disconnect;
    T:=TPositionSimulator.Create;
    Check(S.ConnectTransport(mtLaser,pkGRBL,T,T),'Connect laser');
    Check(not C.Start(5,5,2,300),'Reject without Z');
    S.Disconnect;
    T:=TPositionSimulator.Create; T.P.X:=-3; T.P.Y:=-10; T.MinTravelZ:=10;
    Check(S.ConnectTransport(mtPrinter3D,pkMarlin,T,T),'Connect Marlin negative home');
    T.Data('start'+LineEnding); Sleep(2600);
    S.SetWorkEnvelope(220,220,250); Check(S.Status,'Get negative home position');
    Check((S.Position.X=-3) and (S.Position.Y=-10),'Marlin negative home reported');
    Check(not S.MoveTo(-3,-10,10,300,True),'Keep full move limits');
    Check(not S.LiftTo(251,300),'Reject Z beyond travel');
    Check(not S.LiftTo(-1,300),'Reject lowering Z');
    Check(C.Start(5,5,2,300),'Calibration from negative Marlin home');
    Check((T.P.X=-3) and (T.P.Y=-10) and (T.P.Z=10),'First motion lifts Z only');
    Arrive(5,5);
    Check(C.Navigate(1),'Marlin next'); Arrive(215,5);
    C.Finish;

    WriteLn('Bed calibration: OK');
  finally C.Free; S.Free; end;
end.
