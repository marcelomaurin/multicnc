program test_simucnc_jog;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, StdCtrls, simuform, multicnc_print3d_view,
  multicnc_session, multicnc_types;
var F:simuform.TMainForm; S:TSimulationSession; V:TPrint3DView; C:TListBox;
procedure Pump(Milliseconds:Integer);
var Deadline:QWord;
begin
  Deadline:=GetTickCount64+QWord(Milliseconds);
  repeat Application.ProcessMessages;S.Poll;Sleep(5);until GetTickCount64>=Deadline;
end;
begin
  Application.Initialize;
  DefaultFormatSettings.DecimalSeparator:=',';
  F:=simuform.TMainForm.Create(nil);S:=TSimulationSession.Create;
  try
    V:=TPrint3DView(F.FindComponent('PrinterView'));
    C:=TListBox(F.FindComponent('ReceivedGCode'));
    if not S.Connect(mtPrinter3D,pkMarlin,'127.0.0.1:9000',115200) then raise Exception.Create('Connect failed');
    Pump(150);
    if not S.Jog(axX,10.5,600) then raise Exception.Create('Jog X failed');
    Pump(350);
    if (V.CurrentPosition.X<=0) or (V.CurrentPosition.X>=10.5) then raise Exception.Create('No intermediate nozzle movement');
    Pump(1000);
    if Abs(V.CurrentPosition.X-10.5)>0.01 then raise Exception.Create('Jog X position wrong');
    S.Jog(axY,12.5,600);Pump(1600);
    S.Jog(axZ,5.5,600);Pump(900);
    if (Abs(V.CurrentPosition.Y-12.5)>0.01) or (Abs(V.CurrentPosition.Z-5.5)>0.01) then raise Exception.Create('Jog Y/Z wrong');
    if C.Items.IndexOf('G0 X10.500 F600')<0 then raise Exception.Create('G-code panel missing jog');
    S.Home;Pump(200);
    if (V.CurrentPosition.X<>0) or (V.CurrentPosition.Y<>0) or (V.CurrentPosition.Z<>0) then raise Exception.Create('Home visual not synchronized');
    Writeln('PASS: actual SimuCNC form + MultiCNC jog XYZ, comma locale, intermediate nozzle movement, G-code panel, home');
  finally S.Free;F.Free;end;
end.
