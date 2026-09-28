unit uWorker;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Math, StrUtils, uDomain, uProtocol, uSerialTransport;
type
  TMachineWorker=class(TThread)
  private
    FConfig:TDeviceConfig;
    FLock:TRTLCriticalSection;
    FCommands, FProgram, FLogs:TStringList;
    FSnapshot,FPublic:TSnapshot;
    FSerial:TSerialTransport;
    FFramer:TLineFramer;
    FPending,FIdentified,FProbeSent:Boolean;
    FPendingKind:string;
    FStartTick,FLastPoll,FSentTick,FDrainTick,FLastSim:QWord;
    FNext,FSimPoint:Integer;
    FPoints:TVectors;
    procedure Publish;
    procedure Log(const S:string);
    procedure Send(const S:string);
    procedure ProcessLine(const S:string);
    procedure Position(const P:TVector;const FrameName,Quality:string);
    procedure Action(const S:string);
    procedure Tick;
  protected procedure Execute;override;
  public
    constructor Create(const Config:TDeviceConfig;Transport:TSerialTransport=nil);
    destructor Destroy;override;
    procedure Request(const Command:string);
    function Snapshot:TSnapshot;
    property Config:TDeviceConfig read FConfig;
  end;
implementation
constructor TMachineWorker.Create(const Config:TDeviceConfig;Transport:TSerialTransport);
begin
  inherited Create(True);FreeOnTerminate:=False;FConfig:=Config;FSerial:=Transport;InitCriticalSection(FLock);
  FCommands:=TStringList.Create;FProgram:=TStringList.Create;FLogs:=TStringList.Create;FFramer:=TLineFramer.Create;
  FSnapshot.State:='Conectando';Publish;
end;
destructor TMachineWorker.Destroy;
begin Terminate;WaitFor;FCommands.Free;FProgram.Free;FLogs.Free;FFramer.Free;DoneCriticalSection(FLock);inherited Destroy;end;
procedure TMachineWorker.Request(const Command:string);
begin
  if Length(Command)>1048580 then raise Exception.Create('Solicitação muito grande.');
  EnterCriticalSection(FLock);try
    if FCommands.Count>=8 then raise Exception.Create('Aguarde o processamento da solicitação anterior.');
    FCommands.Add(Command);
  finally LeaveCriticalSection(FLock);end;
end;
function TMachineWorker.Snapshot:TSnapshot;
begin EnterCriticalSection(FLock);try Result:=FPublic;Result.Trail:=Copy(FPublic.Trail);finally LeaveCriticalSection(FLock);end;end;
procedure TMachineWorker.Publish;
begin
  FSnapshot.LogText:=FLogs.Text;
  EnterCriticalSection(FLock);try FPublic:=FSnapshot;FPublic.Trail:=Copy(FSnapshot.Trail);finally LeaveCriticalSection(FLock);end;
end;
procedure TMachineWorker.Log(const S:string);
begin FLogs.Add(FormatDateTime('hh:nn:ss',Now)+' '+S);while FLogs.Count>100 do FLogs.Delete(0);end;
procedure TMachineWorker.Send(const S:string);
begin FSerial.Write(RawByteString(S));if S<>'?' then Log('TX '+StringReplace(S,#10,'',[rfReplaceAll]));end;
procedure TMachineWorker.Position(const P:TVector;const FrameName,Quality:string);
var N:Integer;
begin
  if (FSnapshot.FrameName<>'') and (FSnapshot.FrameName<>FrameName) then FSnapshot.Trail:=nil;
  FSnapshot.FrameName:=FrameName;FSnapshot.Quality:=Quality;FSnapshot.Position:=P;FSnapshot.HasPosition:=True;FSnapshot.LastPositionTick:=GetTickCount64;
  N:=Length(FSnapshot.Trail);
  if N>0 then if (Abs(FSnapshot.Trail[N-1].X-P.X)<0.00001) and (Abs(FSnapshot.Trail[N-1].Y-P.Y)<0.00001) and (Abs(FSnapshot.Trail[N-1].Z-P.Z)<0.00001) then Exit;
  if N>=10000 then begin Move(FSnapshot.Trail[1000],FSnapshot.Trail[0],9000*SizeOf(TVector));N:=9000;end;
  SetLength(FSnapshot.Trail,N+1);FSnapshot.Trail[N]:=P;
end;
procedure TMachineWorker.ProcessLine(const S:string);
var State,FrameName,Q:string;P:TVector;
begin
  if (S='') then Exit;
  if S[1]<>'<' then Log('RX '+S);
  if StartsStr('error:',LowerCase(S)) or StartsStr('alarm:',LowerCase(S)) or StartsStr('resend:',LowerCase(S)) or StartsStr('!!',S) then raise Exception.Create('Controlador: '+S);
  if FConfig.Protocol='grbl' then begin
    if StartsStr('Grbl 1.1',S) or StartsStr('[VER:1.1',S) then begin
      if FSnapshot.Ready then raise Exception.Create('Reset inesperado do firmware. Reconecte e revise a máquina.');
      FIdentified:=True;
    end;
    if ParseGrbl(S,State,FrameName,P) then begin
      FSnapshot.MachineState:=State;
      if FConfig.StatusInches then begin P.X:=P.X*25.4;P.Y:=P.Y*25.4;P.Z:=P.Z*25.4;end;
      Position(P,FrameName,'Reportada pelo GRBL; sem encoder');
      if StartsStr('Alarm',State) or StartsStr('Door',State) then begin
        if FSnapshot.Running then raise Exception.Create('Execução interrompida: '+State);
      end;
      if FSnapshot.Running and (FDrainTick>0) and (GetTickCount64-FDrainTick>1000) and (State='Idle') and not FSnapshot.Paused then begin
        FSnapshot.Running:=False;FSnapshot.State:='Concluído (GRBL Idle)';Log(FSnapshot.State);
      end;
    end else if State<>'' then FSnapshot.MachineState:=State;
    if FSnapshot.Running and (StartsStr('Alarm',State) or StartsStr('Door',State)) then raise Exception.Create('Execução interrompida: '+State);
  end else begin
    if (LowerCase(S)='start') and FSnapshot.Ready then raise Exception.Create('Reset inesperado do firmware.');
    if (Pos('FIRMWARE_NAME:',S)>0) and ((Pos('Marlin',S)>0) or (Pos('Prusa',S)>0)) then FIdentified:=True;
    if ParseMarlin(S,P) then begin
      Q:='Projetada pelo firmware (M114)';if FConfig.RealtimeMarlin then Q:='Reportada por M114 R; recurso confirmado pelo operador';
      Position(P,'Trabalho',Q);
    end;
  end;
  if (S='ok') or StartsStr('ok ',S) then begin
    if FPending then begin
      if FPendingKind='identify' then begin
        if not FIdentified then raise Exception.Create('Firmware não identificado como o protocolo selecionado.');
        FSnapshot.Ready:=True;FSnapshot.State:='Monitorando';Log('Protocolo identificado. Perfil comercial ainda exige homologação.');
      end else if FPendingKind='program' then begin
        Inc(FSnapshot.Accepted);if FNext>=FProgram.Count then begin FDrainTick:=GetTickCount64;FSnapshot.State:='Aguardando máquina ficar Idle';end;
      end;
      FPending:=False;
    end;
  end;
end;
procedure TMachineWorker.Action(const S:string);
var Temp:TStringList;Pts:TVectors;
begin
  if S='clear' then begin FSnapshot.Trail:=nil;Exit;end;
  if not FSnapshot.Ready then begin Log('Ação recusada: protocolo ainda não está pronto.');Exit;end;
  if S='hold' then begin
    if FConfig.Protocol='marlin' then begin Log('Pausa Marlin não implementada.');Exit;end;
    if FConfig.Protocol='grbl' then Send('!');FSnapshot.Paused:=True;FSnapshot.State:='Pausa solicitada';Exit;
  end;
  if S='resume' then begin
    if FConfig.Protocol='marlin' then Exit;
    if (FConfig.Protocol='grbl') and (FSnapshot.MachineState<>'Hold:0') then begin Log('Aguarde Hold:0 antes de retomar.');Exit;end;
    if FConfig.Protocol='grbl' then Send('~');FSnapshot.Paused:=False;FSnapshot.State:='Retomada solicitada';Exit;
  end;
  if S='reset' then begin
    if FConfig.Protocol='grbl' then Send(#24);
    FSnapshot.State:='Cancelado/reset solicitado; revise a máquina';FSnapshot.Running:=False;FSnapshot.Ready:=False;Terminate;Exit;
  end;
  if StartsStr('run:',S) then begin
    if FConfig.Protocol='marlin' then begin Log('Envio de impressão ainda não implementado.');Exit;end;
    if FSnapshot.Running or FPending then begin Log('Ação recusada: trabalho ou consulta em andamento.');Exit;end;
    if (FConfig.Protocol='grbl') and ((FSnapshot.MachineState<>'Idle') or (GetTickCount64-FSnapshot.LastPositionTick>1500)) then begin Log('É necessário GRBL Idle com telemetria recente.');Exit;end;
    Temp:=TStringList.Create;
    try
      try PrepareProgram(Copy(S,5,Length(S)),Temp,Pts);
      except on E:Exception do begin Log('Programa recusado: '+E.Message);Exit;end;end;
      FProgram.Assign(Temp);FPoints:=Pts;FNext:=0;FSimPoint:=0;FDrainTick:=0;FSnapshot.Accepted:=0;FSnapshot.Total:=FProgram.Count;
      FSnapshot.Paused:=False;FSnapshot.Running:=True;FSnapshot.State:='Executando';Log('Programa iniciado explicitamente pelo operador.');
    finally Temp.Free;end;
  end;
end;
procedure TMachineWorker.Tick;
var Cmd,Chunk,S:string;Lines:TStringList;NowTick:QWord;P:TVector;T:Double;
begin
  Cmd:='';EnterCriticalSection(FLock);try if FCommands.Count>0 then begin Cmd:=FCommands[0];FCommands.Delete(0);end;finally LeaveCriticalSection(FLock);end;
  if Cmd<>'' then Action(Cmd);if Terminated then Exit;
  NowTick:=GetTickCount64;
  if FConfig.Protocol='simulator' then begin
    if NowTick-FLastSim<100 then Exit;FLastSim:=NowTick;
    if FSnapshot.Paused then begin FSnapshot.MachineState:='Hold:0';Exit;end;
    if FSnapshot.Running then begin
      if FSimPoint<Length(FPoints) then begin Position(FPoints[FSimPoint],'Trabalho','SIMULAÇÃO — não é telemetria');Inc(FSimPoint);end
      else begin FSnapshot.Running:=False;FSnapshot.Accepted:=FSnapshot.Total;FSnapshot.State:='Simulação concluída';end;
    end else begin T:=(NowTick-FStartTick)/2500;P:=Vector(50+35*Cos(T),50+35*Sin(T),5+2*Sin(T/2));Position(P,'Trabalho','SIMULAÇÃO — trajetória demonstrativa');end;
    FSnapshot.MachineState:='Idle';Exit;
  end;
  Chunk:=string(FSerial.ReadAvailable);Lines:=TStringList.Create;
  try FFramer.Feed(Chunk,Lines);for S in Lines do ProcessLine(S);finally Lines.Free;end;
  if not FProbeSent and (NowTick-FStartTick>2000) then begin
    if FConfig.Protocol='grbl' then Send('$I'+#10) else Send('M115'+#10);
    FProbeSent:=True;FPending:=True;FPendingKind:='identify';FSentTick:=NowTick;
  end;
  if not FSnapshot.Ready then begin if NowTick-FStartTick>12000 then raise Exception.Create('Identificação sem resposta. Verifique porta, baud e firmware.');Exit;end;
  if FPending and (NowTick-FSentTick>30000) then raise Exception.Create('Timeout aguardando confirmação; sem reenvio automático.');
  if FConfig.Protocol='grbl' then begin
    if NowTick-FLastPoll>=250 then begin Send('?');FLastPoll:=NowTick;end;
    if (FSnapshot.HasPosition and (NowTick-FSnapshot.LastPositionTick>5000)) or (not FSnapshot.HasPosition and (NowTick-FStartTick>15000)) then raise Exception.Create('Telemetria ausente; conexão interrompida.');
    if FSnapshot.Running and not FSnapshot.Paused and not FPending and (FNext<FProgram.Count) and ((FSnapshot.MachineState='Idle') or (FSnapshot.MachineState='Run')) then begin
      Send(FProgram[FNext]+#10);Inc(FNext);FPending:=True;FPendingKind:='program';FSentTick:=NowTick;
    end;
  end else if not FPending and (NowTick-FLastPoll>=1000) then begin
    if FConfig.RealtimeMarlin then Send('M114 R'+#10) else Send('M114'+#10);
    FPending:=True;FPendingKind:='position';FSentTick:=NowTick;FLastPoll:=NowTick;
  end;
end;
procedure TMachineWorker.Execute;
begin
  try
    FStartTick:=GetTickCount64;
    if FConfig.Protocol='simulator' then begin FSnapshot.Ready:=True;FSnapshot.Connected:=True;FSnapshot.State:='Simulador conectado';Log('Nenhuma porta física foi aberta.');end
    else begin if FSerial=nil then FSerial:=TSerialTransport.Create;FSerial.Open(FConfig);FSnapshot.Connected:=True;FSnapshot.State:='Identificando firmware';Log('Serial '+FConfig.Port+' aberta, 8N1.');end;
    while not Terminated do begin Tick;Publish;Sleep(15);end;
  except on E:Exception do begin
    FSnapshot.LastError:=E.Message;FSnapshot.State:='Falha: '+E.Message;Log(FSnapshot.State);
    if FSnapshot.Running and (FConfig.Protocol='grbl') and Assigned(FSerial) then try Send('!');except end;
  end;end;
  if FSnapshot.Running then begin FSnapshot.State:='Interrompido; estado físico não confirmado';Log(FSnapshot.State);end;
  FSnapshot.Ready:=False;FSnapshot.Connected:=False;FSnapshot.Running:=False;FreeAndNil(FSerial);Publish;
end;
end.
