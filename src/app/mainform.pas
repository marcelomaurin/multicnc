unit mainform;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,ComCtrls,
 multicnc_types,multicnc_interfaces,multicnc_machine,multicnc_simulator,multicnc_grbl;
type TMainForm=class(TForm)
 private
  FTransport:IMultiCNCTransport;FProtocol:IMultiCNCProtocol;FMachine:IMultiCNCMachine;
  TopPanel:TPanel;MachineType:TComboBox;BtnConnect,BtnHome,BtnPause,BtnResume,BtnStop:TButton;
  JogPanel:TPanel;BtnXm,BtnXp,BtnYm,BtnYp,BtnZm,BtnZp:TButton;
  MemoLog:TMemo;EditCommand:TEdit;BtnSend:TButton;Status:TStatusBar;
  procedure ConnectClick(Sender:TObject);procedure CommandClick(Sender:TObject);procedure JogClick(Sender:TObject);
  procedure Log(const S:string);
 public constructor Create(AOwner:TComponent);override;
 end;
implementation
constructor TMainForm.Create(AOwner:TComponent);
 procedure B(var X:TButton;const C:string;L:Integer;E:TNotifyEvent);
 begin X:=TButton.Create(Self);X.Parent:=TopPanel;X.Caption:=C;X.Left:=L;X.Top:=8;X.OnClick:=E;end;
begin inherited Create(AOwner);Caption:='MultiCNC - Router / Laser / 3D Printer';Width:=900;Height:=600;
 TopPanel:=TPanel.Create(Self);TopPanel.Parent:=Self;TopPanel.Align:=alTop;TopPanel.Height:=50;
 MachineType:=TComboBox.Create(Self);MachineType.Parent:=TopPanel;MachineType.Items.Add('Router');MachineType.Items.Add('Laser');MachineType.Items.Add('3D Printer');MachineType.ItemIndex:=0;MachineType.Left:=8;MachineType.Top:=10;MachineType.Width:=120;
 B(BtnConnect,'Conectar SIM',140,@ConnectClick);B(BtnHome,'Home',250,@CommandClick);B(BtnPause,'Pause',330,@CommandClick);B(BtnResume,'Resume',410,@CommandClick);B(BtnStop,'STOP',500,@CommandClick);
 JogPanel:=TPanel.Create(Self);JogPanel.Parent:=Self;JogPanel.Align:=alTop;JogPanel.Height:=50;TopPanel:=JogPanel;
 B(BtnXm,'X-',8,@JogClick);B(BtnXp,'X+',80,@JogClick);B(BtnYm,'Y-',152,@JogClick);B(BtnYp,'Y+',224,@JogClick);B(BtnZm,'Z-',296,@JogClick);B(BtnZp,'Z+',368,@JogClick);
 MemoLog:=TMemo.Create(Self);MemoLog.Parent:=Self;MemoLog.Align:=alClient;MemoLog.ScrollBars:=ssAutoBoth;
 EditCommand:=TEdit.Create(Self);EditCommand.Parent:=Self;EditCommand.Align:=alBottom;EditCommand.Text:='G0 X10 Y10';
 BtnSend:=TButton.Create(Self);BtnSend.Parent:=Self;BtnSend.Align:=alBottom;BtnSend.Caption:='Enviar G-code';BtnSend.OnClick:=@CommandClick;
 Status:=TStatusBar.Create(Self);Status.Parent:=Self;Status.Align:=alBottom;
end;
procedure TMainForm.Log(const S:string);begin MemoLog.Lines.Add(S);Status.SimpleText:=S;end;
procedure TMainForm.ConnectClick(Sender:TObject);
var MT:TMachineType;
begin case MachineType.ItemIndex of 1:MT:=mtLaser;2:MT:=mtPrinter3D;else MT:=mtRouter;end;
 FTransport:=TSimulatorTransport.Create;FProtocol:=TGRBLProtocol.Create;FMachine:=TMultiCNCMachine.Create(MT,FTransport,FProtocol);
 if FMachine.Connect then Log('Simulador conectado: '+MachineType.Text) else Log('Falha na conexao');end;
procedure TMainForm.CommandClick(Sender:TObject);
begin if not Assigned(FMachine)then begin Log('Conecte primeiro');Exit;end;
 if Sender=BtnHome then FMachine.Home else if Sender=BtnPause then FMachine.Pause else if Sender=BtnResume then FMachine.Resume else if Sender=BtnStop then FMachine.Stop else if Sender=BtnSend then FMachine.SendGCode(EditCommand.Text);end;
procedure TMainForm.JogClick(Sender:TObject);
var A:TAxis;D:Double;
begin if not Assigned(FMachine)then Exit;D:=1;if(Sender=BtnXm)or(Sender=BtnYm)or(Sender=BtnZm)then D:=-1;
 if(Sender=BtnXm)or(Sender=BtnXp)then A:=axX else if(Sender=BtnYm)or(Sender=BtnYp)then A:=axY else A:=axZ;
 if not FMachine.Jog(A,D,500)then Log('Jog bloqueado/nao suportado');end;
end.
