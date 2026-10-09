program test_core;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes, SysUtils, Math, uDomain, uProtocol, uWorker, uSerialTransport;
type
  TFakeSerial=class(TSerialTransport)
  private FBuffer,FMachineState,FFirmware:string;FFail:Boolean;
  public
    constructor Create(FailProgram:Boolean;const Firmware:string='grbl');
    procedure Open(const Config:TDeviceConfig);override;
    procedure Write(const S:RawByteString);override;
    function ReadAvailable:RawByteString;override;
  end;
var Checks:Integer=0;
procedure Check(Condition:Boolean;const MessageText:string);
begin Inc(Checks);if not Condition then raise Exception.Create('FAIL: '+MessageText);end;
constructor TFakeSerial.Create(FailProgram:Boolean;const Firmware:string);
begin inherited Create;FFail:=FailProgram;FMachineState:='Idle';FFirmware:=Firmware;end;
procedure TFakeSerial.Open(const Config:TDeviceConfig);
begin if FFirmware='grbl' then FBuffer:='Grbl 1.1h [test]'+#13#10 else FBuffer:='start'+#10;end;
procedure TFakeSerial.Write(const S:RawByteString);
begin
  if S='M115'+#10 then FBuffer:=FBuffer+'FIRMWARE_NAME:'+FFirmware+#10+'ok'+#10
  else if (S='M114'+#10) or (S='M114 R'+#10) then FBuffer:=FBuffer+'X:10 Y:20 Z:30 E:0 Count X:100 Y:200 Z:300'+#10+'ok'+#10
  else if S='$I'+#10 then FBuffer:=FBuffer+'[VER:1.1h:test]'+#10+'ok'+#10
  else if S='?' then FBuffer:=FBuffer+'<'+FMachineState+'|WPos:10.000,20.000,3.000|FS:0,0>'+#10
  else if S='!' then FMachineState:='Hold:0'
  else if S='~' then FMachineState:='Idle'
  else if S=#24 then FMachineState:='Alarm'
  else if FFail then FBuffer:=FBuffer+'error:20'+#10
  else FBuffer:=FBuffer+'ok'+#10;
end;
function TFakeSerial.ReadAvailable:RawByteString;
begin Result:=Copy(FBuffer,1,7);Delete(FBuffer,1,7);end;
function SimConfig:TDeviceConfig;
begin Result:=Default(TDeviceConfig);Result.ID:='test';Result.Name:='Teste';Result.Kind:='laser';Result.Brand:='MultiCNC';Result.Model:='Sim';Result.Port:='SIM';Result.Protocol:='simulator';Result.Baud:=115200;end;
procedure WaitReady(W:TMachineWorker);
var Deadline:QWord;
begin Deadline:=GetTickCount64+5000;while not W.Snapshot.Ready and (GetTickCount64<Deadline) do Sleep(15);Check(W.Snapshot.Ready,'worker identificada: '+W.Snapshot.LastError);end;
procedure ProtocolTests;
var P:TVector;State,FrameName:string;F:TLineFramer;L:TStringList;Pts:TVectors;Failed:Boolean;
begin
  Check(ParseGrbl('<Run|FS:10,2|MPos:-1.200,3.400,5.000>',State,FrameName,P),'GRBL campos fora de ordem');
  Check((State='Run') and (FrameName='Máquina') and (Abs(P.X+1.2)<0.001),'GRBL coordenada');
  Check(ParseGrbl('<Idle|WPos:1,2,3>',State,FrameName,P) and (FrameName='Trabalho'),'WPos');
  Check(not ParseGrbl('<Idle|MPos:bad,2,3>',State,FrameName,P),'posição malformada');
  Check(not ParseGrbl('ok',State,FrameName,P),'ok não é posição');
  Check(ParseMarlin('X:1.25 Y:-2.5 Z:3.0 E:4 Count X:100 Y:200 Z:300',P),'Marlin');
  Check(Abs(P.X-1.25)<0.0001,'ignorar Count Marlin');
  Check(not ParseMarlin('X:NaN Y:2 Z:3',P),'NaN rejeitado');
  F:=TLineFramer.Create;L:=TStringList.Create;
  try F.Feed('<Id',L);Check(L.Count=0,'fragmento');F.Feed('le|WPos:1,2,3>'+#13#10+'ok'+#10,L);Check(L.Count=2,'CRLF e linhas agrupadas');
    PrepareProgram('G21'+#10+'G90'+#10+'G0 X0 Y0 Z5'+#10+'G1 X10 Y20 F300'+#10+'M5',L,Pts);
    Check((Length(Pts)=2) and (Pts[1].Y=20),'prévia linear');
    Failed:=False;try PrepareProgram('G21'+#10+'G90'+#10+'G2 X2 Y2'+#10+'M5',L,Pts);except Failed:=True;end;Check(Failed,'arcos rejeitados');
    Failed:=False;try PrepareProgram('G1 X2 Y2 Z2'+#10+'M5',L,Pts);except Failed:=True;end;Check(Failed,'modos obrigatórios');
    Failed:=False;try PrepareProgram('G21'+#10+'G90'+#10+'G0 X2 Y2'+#10+'M5',L,Pts);except Failed:=True;end;Check(Failed,'origem inicial incompleta');
    Failed:=False;try F.Feed(StringOfChar('a',8193),L);except Failed:=True;end;Check(Failed,'limite de linha recebida');
  finally F.Free;L.Free;end;
end;
procedure PersistenceTests;
var C:TDeviceConfigs;D:TDeviceConfigs;FN:string;Failed:Boolean;
begin
  FN:=GetTempDir(False)+'multicnc-test-'+IntToStr(GetProcessID)+'.ini';SetLength(C,1);C[0]:=SimConfig;
  try SaveConfigs(FN,C);D:=LoadConfigs(FN);Check((Length(D)=1) and (D[0].Brand=C[0].Brand),'persistência');C[0].Model:='Alterado';SaveConfigs(FN,C);D:=LoadConfigs(FN);Check(D[0].Model='Alterado','atualização');Check(FileExists(FN+'.bak'),'backup');
    C[0].Protocol:='grbl';C[0].Port:='COM0';Failed:=False;try ValidateConfig(C[0]);except Failed:=True;end;Check(Failed,'porta inválida');
  finally DeleteFile(FN);DeleteFile(FN+'.bak');DeleteFile(FN+'.tmp');end;
end;
procedure WorkerTests;
var A,B:TMachineWorker;C:TDeviceConfig;S:TSnapshot;CountBefore:Integer;Deadline:QWord;
const Job='G21'+#10+'G90'+#10+'G0X0Y0Z5'+#10+'G1X10Y10F300'+#10+'M5';
begin
  C:=SimConfig;A:=TMachineWorker.Create(C);C.ID:='second';B:=TMachineWorker.Create(C);
  try A.Start;B.Start;WaitReady(A);WaitReady(B);Sleep(350);Check(A.Snapshot.HasPosition and B.Snapshot.HasPosition,'duas threads com posições');
    A.Request('hold');Sleep(150);CountBefore:=Length(A.Snapshot.Trail);Sleep(250);Check(Length(A.Snapshot.Trail)=CountBefore,'pausa isolada');Check(Length(B.Snapshot.Trail)>CountBefore,'segunda thread continua');
    A.Request('resume');Sleep(150);Check(Length(A.Snapshot.Trail)>CountBefore,'retomada');
    S:=A.Snapshot;S.Trail[0].X:=99999;Check(A.Snapshot.Trail[0].X<>99999,'snapshot sem referência mutável');
    A.Request('run:'+Job);Sleep(500);Check(A.Snapshot.Accepted=A.Snapshot.Total,'simulação de programa');
  finally A.Free;B.Free;end;
  C.Protocol:='grbl';C.Port:='COM999';A:=TMachineWorker.Create(C,TFakeSerial.Create(False));B:=TMachineWorker.Create(C,TFakeSerial.Create(True));
  try
    A.Start;B.Start;WaitReady(A);WaitReady(B);Sleep(500);Check(A.Snapshot.Position.Y=20,'telemetria serial fragmentada');
    A.Request('run:'+Job);B.Request('run:'+Job);Deadline:=GetTickCount64+4500;
    repeat Sleep(50);S:=A.Snapshot;until ((S.Accepted=S.Total) and (S.Total>0) and not S.Running) or (GetTickCount64>Deadline);
    Check((S.Accepted=5) and not S.Running and S.Ready,'stream confirma ack e Idle');
    Check(B.Snapshot.LastError<>'','erro de protocolo isolado');Check(A.Snapshot.Ready,'outro equipamento preservado');
    A.Request('hold');Sleep(500);Check(A.Snapshot.MachineState='Hold:0','hold confirmado');A.Request('resume');Sleep(500);Check(A.Snapshot.MachineState='Idle','resume confirmado');
  finally A.Free;B.Free;end;
  C.Protocol:='marlin';A:=TMachineWorker.Create(C,TFakeSerial.Create(False,'Marlin test'));B:=TMachineWorker.Create(C,TFakeSerial.Create(False,'Unknown test'));
  try
    A.Start;B.Start;WaitReady(A);Sleep(1500);Check(A.Snapshot.HasPosition,'posição Marlin');Check(Pos('Projetada',A.Snapshot.Quality)>0,'qualidade Marlin explícita');
    A.Request('run:'+Job);Sleep(100);Check(not A.Snapshot.Running,'Marlin recusa envio não implementado');Check(B.Snapshot.LastError<>'','firmware desconhecido recusado');
  finally A.Free;B.Free;end;
end;
begin
  try ProtocolTests;PersistenceTests;WorkerTests;WriteLn('PASS: ',Checks,' verificações.');
  except on E:Exception do begin WriteLn(E.Message);Halt(1);end;end;
end.
