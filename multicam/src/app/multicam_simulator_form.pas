unit multicam_simulator_form;
{$mode objfpc}{$H+}
interface
uses multicam_collision,multicam_collision_setup,multisuite_numfmt, Classes,SysUtils,Math,Forms,Controls,StdCtrls,ExtCtrls,multicam_types,multicam_job,multicam_setup,multicam_machine_model,multicam_machine_kinematics,multicam_simulation_player,multicam_machine_canvas,multicam_electronics_types,multicam_electronics_model,multicam_electronics_canvas,multicam_simulation_session,multicam_simulation_canvas,multicam_signal_canvas,multicam_demo_job,multicam_gcode;
type TSimulatorForm=class(TForm)
 private Toolbar:TFlowPanel;CollisionConfig:TCollisionConfig;MachineModel:TMachineModel;CollisionLog:TMemo;
 function BeforeMove(Index:Integer):Boolean;
 procedure SetupClick(Sender:TObject);procedure VerifyClick(Sender:TObject);procedure RestartSimulation;
 private J:TCamJob;SetupObj:TMechanicalSetup;Player:TSimulationPlayer;Kin:TMachineKinematics;Electronics:TElectronicsModel;Session:TSimulationSession;View:TMachineCanvas;ElectronicView:TElectronicsCanvas;StockView:TSimulationCanvas;SignalView:TSignalCanvas;Info:TLabel;Timer:TTimer;procedure PlayClick(Sender:TObject);procedure PauseClick(Sender:TObject);procedure StopClick(Sender:TObject);procedure StepClick(Sender:TObject);procedure EStopClick(Sender:TObject);procedure ResetElectronicClick(Sender:TObject);procedure LoadDemoClick(Sender:TObject);procedure ExportDemoClick(Sender:TObject);procedure Tick(Sender:TObject);procedure Changed(Sender:TObject);function Btn(const S:string;H:TNotifyEvent):TButton;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TSimulatorForm.Btn(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=Toolbar;Result.SetBounds(0,0,Max(90,Length(S)*7+16),30);Result.Caption:=S;Result.OnClick:=H;end;
constructor TSimulatorForm.Create(AOwner:TComponent);var M:TMachineModel;EC:TElectronicsConfig;
begin inherited;Caption:='MultiCAM - Simulador Fisico, Mecanico e Eletronico';Width:=1200;Height:=760;J:=TCamJob.Create;SetupObj:=TMechanicalSetup.Create;Player:=TSimulationPlayer.Create;Kin:=TMachineKinematics.Create;Electronics:=TElectronicsModel.Create;Session:=TSimulationSession.Create;SetupObj.Stock.Width:=300;SetupObj.Stock.Height:=200;SetupObj.Stock.Thickness:=20;SetupObj.Stock.TopZ:=0;M.MinX:=0;M.MaxX:=500;M.MinY:=0;M.MaxY:=400;M.MinZ:=-100;M.MaxZ:=100;M.RapidMMMin:=3000;Kin.Configure(M);MachineModel:=M;EC.StepsPerMMX:=80;EC.StepsPerMMY:=80;EC.StepsPerMMZ:=400;EC.MotorSupplyV:=24;EC.LogicSupplyV:=5;EC.MaxMotorCurrentA:=3;Electronics.Configure(EC);ElectronicView:=TElectronicsCanvas.Create(Self);ElectronicView.Parent:=Self;ElectronicView.Align:=alRight;ElectronicView.Width:=430;ElectronicView.SetState(Electronics.State);StockView:=TSimulationCanvas.Create(Self);StockView.Parent:=Self;StockView.Align:=alBottom;StockView.Height:=180;SignalView:=TSignalCanvas.Create(Self);SignalView.Parent:=Self;SignalView.Align:=alBottom;SignalView.Height:=150;View:=TMachineCanvas.Create(Self);View.Parent:=Self;View.Align:=alClient;View.Setup:=SetupObj;View.Machine:=M;Info:=TLabel.Create(Self);Info.Parent:=Self;Info.Align:=alTop;Info.Caption:='Sem job carregado';Toolbar:=TFlowPanel.Create(Self);Toolbar.Parent:=Self;Toolbar.Align:=alTop;Toolbar.Height:=100;Toolbar.BevelOuter:=bvNone;Btn('Carregar demo Pocket + Furos + Contorno',@LoadDemoClick);Btn('Exportar G-code demo',@ExportDemoClick);Btn('Configurar ferramenta e fixacoes',@SetupClick);Btn('Verificar colisoes',@VerifyClick);Btn('Play',@PlayClick);Btn('Pause',@PauseClick);Btn('Passo',@StepClick);Btn('Stop',@StopClick);Btn('E-STOP',@EStopClick);Btn('Reset eletronica',@ResetElectronicClick);CollisionLog:=TMemo.Create(Self);CollisionLog.Parent:=Self;CollisionLog.Align:=alBottom;CollisionLog.Height:=85;CollisionLog.ReadOnly:=True;CollisionLog.ScrollBars:=ssVertical;
 Player.BeforeMove:=@BeforeMove;Player.OnChange:=@Changed;Player.Load(J);Session.Configure(J,SetupObj.Stock,Electronics);StockView.HeightMap:=Session.HeightMap;SignalView.Trace:=Session.Trace;Timer:=TTimer.Create(Self);Timer.Interval:=50;Timer.Enabled:=True;Timer.OnTimer:=@Tick;CollisionConfig:=DefaultCollisionConfig(SetupObj.Stock,J.Tool);Session.ConfigureCollision(SetupObj,M,CollisionConfig);end;
destructor TSimulatorForm.Destroy;begin Session.Free;Electronics.Free;Kin.Free;Player.Free;SetupObj.Free;J.Free;inherited;end;
procedure TSimulatorForm.LoadDemoClick(Sender:TObject);begin Player.Stop;Electronics.Reset;TDemoJobBuilder.Build(J);SetupObj.Stock:=J.Stock;Session.Configure(J,J.Stock,Electronics);CollisionConfig:=DefaultCollisionConfig(J.Stock,J.Tool);CollisionConfig.HolderDiameter:=20;CollisionConfig.HolderLength:=35;SetupObj.ClearFixtures;Session.ConfigureCollision(SetupObj,MachineModel,CollisionConfig);View.ClearCollision;Kin.MoveTo(CollisionConfig.InitialPosition);View.SetPose(Kin.Pose);CollisionLog.Clear;StockView.HeightMap:=Session.HeightMap;SignalView.Trace:=Session.Trace;Player.Load(J);Info.Caption:=Format('Demo: %d movimentos. Porta-ferramenta exemplo 20 x 35 mm; confira a montagem.',[J.Count]);StockView.Invalidate;SignalView.Invalidate;end;
procedure TSimulatorForm.ExportDemoClick(Sender:TObject);var FN:string;begin if J.Count=0 then TDemoJobBuilder.Build(J);FN:=ExtractFilePath(ParamStr(0))+'multicam_demo.nc';TCamGCode.ExportJob(J,FN);Info.Caption:='G-code exportado: '+FN;end;
procedure TSimulatorForm.PlayClick(Sender:TObject);begin if Player.State=psFinished then RestartSimulation;if Electronics.HasFault then begin Info.Caption:='Execucao bloqueada: falha eletronica ativa';Exit;end;Player.Play;end;
procedure TSimulatorForm.PauseClick(Sender:TObject);begin Player.Pause;end;
procedure TSimulatorForm.StopClick(Sender:TObject);begin RestartSimulation;end;
procedure TSimulatorForm.StepClick(Sender:TObject);begin if not Electronics.HasFault then Player.Step;end;
procedure TSimulatorForm.EStopClick(Sender:TObject);begin Electronics.SetEStop(True);Player.Pause;ElectronicView.SetState(Electronics.State);Info.Caption:='E-STOP ativo - movimento e spindle bloqueados';end;
procedure TSimulatorForm.ResetElectronicClick(Sender:TObject);begin RestartSimulation;Info.Caption:='Simulacao reiniciada; material restaurado';end;
procedure TSimulatorForm.Tick(Sender:TObject);var I,N:Integer;begin if Electronics.HasFault then begin Player.Pause;Exit;end;if Player.State<>psPlaying then Exit;N:=Max(1,Round(Player.Speed));for I:=1 to N do begin if Player.State<>psPlaying then Break;if not Player.Step then Break;end;end;
procedure TSimulatorForm.RestartSimulation;
begin
 Electronics.Reset;Session.Reset;Player.Stop;CollisionLog.Clear;View.ClearCollision;
 Kin.MoveTo(CollisionConfig.InitialPosition);View.SetPose(Kin.Pose);
 StockView.Invalidate;SignalView.Invalidate;ElectronicView.SetState(Electronics.State);
end;
function TSimulatorForm.BeforeMove(Index:Integer):Boolean;
var H:TCollisionHit;MessageText:string;
begin
 Result:=Session.TryMove(Index,0.05);
 if not Result and Session.Blocked then begin
 H:=Session.Collision;
 MessageText:=Format('Movimento %d: %s - %s (X %.3f Y %.3f Z %.3f)',[H.MoveIndex+1,H.ObjectName,H.Detail,H.Position.X,H.Position.Y,H.Position.Z],InvariantFS);
 CollisionLog.Lines.Add(MessageText);Info.Caption:=MessageText;View.ShowCollision(H.Position);
 ElectronicView.SetState(Electronics.State);
 end;
end;
procedure TSimulatorForm.SetupClick(Sender:TObject);
begin
 Player.Pause;
 if EditCollisionSetup(CollisionConfig,J.Tool,SetupObj) then begin
 Session.Configure(J,SetupObj.Stock,Electronics);
 Session.ConfigureCollision(SetupObj,MachineModel,CollisionConfig);RestartSimulation;
 end;
end;
procedure TSimulatorForm.VerifyClick(Sender:TObject);
var CheckSession:TSimulationSession;I:Integer;H:TCollisionHit;
begin
 Player.Pause;CollisionLog.Clear;
 if J.Count=0 then begin Info.Caption:='Carregue um programa';Exit;end;
 CheckSession:=TSimulationSession.Create;
 try
 CheckSession.Configure(J,SetupObj.Stock,nil);
 CheckSession.ConfigureCollision(SetupObj,MachineModel,CollisionConfig);
 for I:=0 to J.Count-1 do if not CheckSession.TryMove(I,0.05)then Break;
 if CheckSession.Blocked then begin
 H:=CheckSession.Collision;View.ShowCollision(H.Position);
 CollisionLog.Lines.Add(Format('Movimento %d: %s - %s; X %.3f Y %.3f Z %.3f',[H.MoveIndex+1,H.ObjectName,H.Detail,H.Position.X,H.Position.Y,H.Position.Z],InvariantFS));
 Info.Caption:='Verificacao interrompida: '+H.Detail;
 end else begin View.ClearCollision;Info.Caption:='Sem colisao no modelo conservador configurado (XYZ, mapa de alturas)';end;
 finally CheckSession.Free;end;
end;
procedure TSimulatorForm.Changed(Sender:TObject);
begin
 if Session.Blocked then Exit;
 if Player.Index>=0 then begin
 Kin.MoveTo(Player.Position);View.SetPose(Kin.Pose);
 StockView.Invalidate;SignalView.Invalidate;ElectronicView.SetState(Electronics.State);
 Info.Caption:=Format('Movimento %d/%d  X %.3f Y %.3f Z %.3f',[Player.Index+1,J.Count,Player.Position.X,Player.Position.Y,Player.Position.Z],InvariantFS);
 end else Info.Caption:='Pronto';
end;
end.
