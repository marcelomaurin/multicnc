unit multicam_simulator_form;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,multicam_types,multicam_job,multicam_setup,multicam_machine_model,multicam_machine_kinematics,multicam_simulation_player,multicam_machine_canvas;
type TSimulatorForm=class(TForm)
 private J:TCamJob;SetupObj:TMechanicalSetup;Player:TSimulationPlayer;Kin:TMachineKinematics;View:TMachineCanvas;Info:TLabel;Timer:TTimer;procedure PlayClick(Sender:TObject);procedure PauseClick(Sender:TObject);procedure StopClick(Sender:TObject);procedure StepClick(Sender:TObject);procedure Tick(Sender:TObject);procedure Changed(Sender:TObject);function Btn(const S:string;H:TNotifyEvent):TButton;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TSimulatorForm.Btn(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=Self;Result.Align:=alTop;Result.Caption:=S;Result.OnClick:=H;end;
constructor TSimulatorForm.Create(AOwner:TComponent);var M:TMachineModel;
begin inherited;Caption:='MultiCAM - Simulador Fisico/Mecanico';Width:=1000;Height:=720;J:=TCamJob.Create;SetupObj:=TMechanicalSetup.Create;Player:=TSimulationPlayer.Create;Kin:=TMachineKinematics.Create;SetupObj.Stock.Width:=300;SetupObj.Stock.Height:=200;SetupObj.Stock.TopZ:=0;M.MinX:=0;M.MaxX:=500;M.MinY:=0;M.MaxY:=400;M.MinZ:=-100;M.MaxZ:=100;M.RapidMMMin:=3000;Kin.Configure(M);View:=TMachineCanvas.Create(Self);View.Parent:=Self;View.Align:=alClient;View.Setup:=SetupObj;View.Machine:=M;Info:=TLabel.Create(Self);Info.Parent:=Self;Info.Align:=alTop;Info.Caption:='Sem job carregado';Btn('Play',@PlayClick);Btn('Pause',@PauseClick);Btn('Passo',@StepClick);Btn('Stop',@StopClick);Player.OnChange:=@Changed;Player.Load(J);Timer:=TTimer.Create(Self);Timer.Interval:=50;Timer.Enabled:=True;Timer.OnTimer:=@Tick;end;
destructor TSimulatorForm.Destroy;begin Kin.Free;Player.Free;SetupObj.Free;J.Free;inherited;end;
procedure TSimulatorForm.PlayClick(Sender:TObject);begin Player.Play;end;procedure TSimulatorForm.PauseClick(Sender:TObject);begin Player.Pause;end;procedure TSimulatorForm.StopClick(Sender:TObject);begin Player.Stop;end;procedure TSimulatorForm.StepClick(Sender:TObject);begin Player.Step;end;
procedure TSimulatorForm.Tick(Sender:TObject);var I,N:Integer;begin if Player.State<>psPlaying then Exit;N:=Max(1,Round(Player.Speed));for I:=1 to N do if not Player.Step then Break;end;
procedure TSimulatorForm.Changed(Sender:TObject);var P:TCamPoint;begin if Player.Index>=0 then begin P:=Player.Position;Kin.MoveTo(P);View.SetPose(Kin.Pose);Info.Caption:=Format('Movimento %d/%d  X %.3f Y %.3f Z %.3f',[Player.Index+1,J.Count,P.X,P.Y,P.Z]);end else Info.Caption:='Pronto';end;
end.
