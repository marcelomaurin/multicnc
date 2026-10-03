unit simuform;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  aimarlinserialdevice, aimarlinsimulator, multicnc_print3d_view;
type
  TMainForm = class(TForm)
  private
    DeviceEdit, BaudEdit: TEdit;
    ConnectButton, ClearButton, ResetButton: TButton;
    View: TPrint3DView; LogMemo: TMemo; Timer: TTimer; Status: TStatusBar;
    Device: TAIMarlinSerialDevice;
    procedure ConnectClick(Sender: TObject); procedure ClearClick(Sender: TObject);
    procedure ResetClick(Sender: TObject); procedure Tick(Sender: TObject);
    procedure Traffic(Sender: TObject; const AText: string);
    procedure Motion(Sender: TObject; const A, B: TAIMarlinPosition; Material: Double);
    procedure Log(const S: string);
  public constructor Create(AOwner: TComponent); override; destructor Destroy; override;
  end;
implementation
constructor TMainForm.Create(AOwner: TComponent);
var P: TPanel; L: TLabel;
begin
  inherited CreateNew(AOwner); Caption:='SimuCNC - Equipamento Marlin virtual'; Position:=poScreenCenter; SetBounds(0,0,1100,760);
  P:=TPanel.Create(Self); P.Parent:=Self; P.Align:=alTop; P.Height:=70; P.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Porta serial virtual'; L.SetBounds(12,8,130,22);
  DeviceEdit:=TEdit.Create(Self); DeviceEdit.Parent:=P; DeviceEdit.SetBounds(12,32,130,28); DeviceEdit.Text:='COM4';
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Baud'; L.SetBounds(155,8,70,22);
  BaudEdit:=TEdit.Create(Self); BaudEdit.Parent:=P; BaudEdit.SetBounds(155,32,90,28); BaudEdit.Text:='115200';
  ConnectButton:=TButton.Create(Self); ConnectButton.Parent:=P; ConnectButton.Caption:='Iniciar porta'; ConnectButton.SetBounds(260,28,130,34); ConnectButton.OnClick:=@ConnectClick;
  ResetButton:=TButton.Create(Self); ResetButton.Parent:=P; ResetButton.Caption:='Limpar peça'; ResetButton.SetBounds(400,28,110,34); ResetButton.OnClick:=@ResetClick;
  ClearButton:=TButton.Create(Self); ClearButton.Parent:=P; ClearButton.Caption:='Limpar log'; ClearButton.SetBounds(520,28,110,34); ClearButton.OnClick:=@ClearClick;
  View:=TPrint3DView.Create(Self); View.Parent:=Self; View.Align:=alClient;
  LogMemo:=TMemo.Create(Self); LogMemo.Parent:=Self; LogMemo.Align:=alRight; LogMemo.Width:=330; LogMemo.ReadOnly:=True; LogMemo.ScrollBars:=ssAutoBoth;
  Status:=TStatusBar.Create(Self); Status.Parent:=Self; Status.Align:=alBottom; Status.SimplePanel:=True; Status.SimpleText:='Porta virtual desligada';
  Device:=TAIMarlinSerialDevice.Create(Self); Device.OnTraffic:=@Traffic; Device.Simulator.OnMotion:=@Motion;
  Timer:=TTimer.Create(Self); Timer.Interval:=100; Timer.OnTimer:=@Tick; Timer.Enabled:=True;
end;
destructor TMainForm.Destroy; begin Timer.Enabled:=False; Device.Close; inherited Destroy; end;
procedure TMainForm.Log(const S:string); begin LogMemo.Lines.Add(FormatDateTime('hh:nn:ss',Now)+'  '+S); end;
procedure TMainForm.Traffic(Sender:TObject; const AText:string); begin Log(AText); end;
procedure TMainForm.Motion(Sender:TObject; const A,B:TAIMarlinPosition; Material:Double); begin View.AddMotion(Sender,A,B,Material); end;
procedure TMainForm.ConnectClick(Sender:TObject); begin
  if Device.Serial.Active then begin Device.Close; ConnectButton.Caption:='Iniciar porta'; Status.SimpleText:='Porta virtual desligada'; Log('Porta fechada.'); end
  else if Device.Open(Trim(DeviceEdit.Text),StrToIntDef(BaudEdit.Text,115200)) then begin ConnectButton.Caption:='Parar porta'; Status.SimpleText:='Marlin virtual ativo em '+DeviceEdit.Text; Log('Marlin virtual pronto.'); end
  else Log('Falha ao abrir porta: '+Device.LastError);
end;
procedure TMainForm.ResetClick(Sender:TObject); begin View.ClearPrint; Device.Simulator.Reset; Log('Simulador reiniciado.'); end;
procedure TMainForm.ClearClick(Sender:TObject); begin LogMemo.Clear; end;
procedure TMainForm.Tick(Sender:TObject); begin Device.Poll(0.1); end;
end.


