unit multicnc_bed_calibration;
{$mode objfpc}{$H+}
interface
uses SysUtils, Math, multicnc_types, multicnc_session;
type
  TBedCalibration = class
  private
    FSession: TSimulationSession;
    FActive: Boolean;
    FStage, FCorner: Integer;
    FX, FY, FZ, FSafeZ, FFeed: Double;
    FTarget: TMachinePosition;
    FDeadline: QWord;
    FMessage: string;
    function Ready: Boolean;
    function Move(X,Y,Z: Double; LiftOnly: Boolean = False): Boolean;
    function GoCorner(Index: Integer): Boolean;
  public
    constructor Create(ASession: TSimulationSession);
    function Start(MarginX,MarginY,Distance,Feed: Double; TravelHeight: Double = 10): Boolean;
    function Navigate(Delta: Integer): Boolean;
    procedure Tick;
    procedure Finish;
    property Active: Boolean read FActive;
    property Stage: Integer read FStage;
    property Corner: Integer read FCorner;
    property MessageText: string read FMessage;
  end;
implementation
constructor TBedCalibration.Create(ASession: TSimulationSession);
begin inherited Create; FSession:=ASession; FMessage:='Defina o zero Z na base e inicie a calibracao.'; end;
function TBedCalibration.Ready: Boolean;
begin
  Result:=FSession.Connected and FSession.ControllerReady and
    (FSession.MachineState=msIdle) and not FSession.WaitingForReply and
    not (FSession.State in [ssRunning,ssPaused,ssError]);
end;
function TBedCalibration.Move(X,Y,Z: Double; LiftOnly: Boolean): Boolean;
begin
  FTarget:=EmptyPosition; FTarget.X:=X; FTarget.Y:=Y; FTarget.Z:=Z;
  if LiftOnly then Result:=FSession.LiftTo(Z,FFeed)
  else Result:=FSession.MoveTo(X,Y,Z,FFeed,True);
  if Result then FDeadline:=GetTickCount64+300000
  else begin FMessage:=FSession.LastError; FActive:=False; FStage:=0; end;
end;
function TBedCalibration.Start(MarginX,MarginY,Distance,Feed: Double; TravelHeight: Double): Boolean;
begin
  Result:=False;
  if FActive then Exit;
  if not Ready then begin FMessage:='Conecte a maquina e aguarde ficar ociosa.'; Exit; end;
  if not FSession.SupportsAxis(axZ) then begin FMessage:='A calibracao requer eixos X, Y e Z.'; Exit; end;
  if not ((MarginX>0) and (MarginY>0) and (Distance>0) and
    (FSession.EnvelopeX>2*MarginX) and (FSession.EnvelopeY>2*MarginY) and
    (TravelHeight>=10) and (TravelHeight>Distance) and
    (FSession.EnvelopeZ>=TravelHeight) and (Feed>=1) and (Feed<=10000)) then
  begin FMessage:='Confira margens e curso útil X/Y/Z. A altura de movimentação deve ser pelo menos 10 mm e maior que a distância da base.'; Exit; end;
  FX:=MarginX; FY:=MarginY; FZ:=Distance; FFeed:=Feed;
  FSafeZ:=Max(TravelHeight,FSession.Position.Z);
  if FSafeZ>FSession.EnvelopeZ then begin FMessage:='Z atual fora do curso util.'; Exit; end;
  FActive:=True;
  Result:=GoCorner(0);
end;
function TBedCalibration.GoCorner(Index: Integer): Boolean;
var P: TMachinePosition;
begin
  FCorner:=Index; FStage:=1; P:=FSession.Position;
  FMessage:=Format('Posicionando no canto %d de 4...',[FCorner+1]);
  Result:=Move(P.X,P.Y,FSafeZ,True);
end;
function TBedCalibration.Navigate(Delta: Integer): Boolean;
begin
  Result:=False;
  if not FActive or (FStage<>0) or not Ready then Exit;
  if (Delta<>-1) and (Delta<>1) then Exit;
  if (FCorner+Delta<0) or (FCorner+Delta>3) then Exit;
  Result:=GoCorner(FCorner+Delta);
end;
procedure TBedCalibration.Tick;
var P: TMachinePosition; X,Y: Double;
begin
  if not FActive then Exit;
  if not FSession.Connected or (FSession.MachineState in [msAlarm,msError]) or
    (FSession.State in [ssError,ssRunning,ssPaused]) then
  begin FActive:=False; FStage:=0; FMessage:='Calibracao interrompida.'; Exit; end;
  if FStage=0 then Exit;
  if GetTickCount64>FDeadline then
  begin FSession.Stop; FActive:=False; FStage:=0; FMessage:='Calibracao interrompida: tempo de movimento excedido.'; Exit; end;
  P:=FSession.Position;
  if not Ready or (Abs(P.X-FTarget.X)>0.02) or
    (Abs(P.Y-FTarget.Y)>0.02) or (Abs(P.Z-FTarget.Z)>0.02) then Exit;
  case FStage of
    1: begin
      X:=FX; Y:=FY;
      if FCorner in [1,2] then X:=FSession.EnvelopeX-FX;
      if FCorner in [2,3] then Y:=FSession.EnvelopeY-FY;
      FStage:=2; Move(X,Y,FSafeZ);
    end;
    2: begin FStage:=3; Move(P.X,P.Y,FZ); end;
    3: begin FStage:=0; FMessage:=Format('Canto %d de 4: X %.2f / Y %.2f / Z %.2f mm. Ajuste a mesa e escolha o proximo canto.',[FCorner+1,P.X,P.Y,P.Z]); end;
  end;
end;
procedure TBedCalibration.Finish;
begin
  if not FActive then Exit;
  if FStage<>0 then FSession.Stop;
  FActive:=False; FStage:=0;
  FMessage:='Calibracao finalizada. A maquina permanece na posicao atual.';
end;
end.
