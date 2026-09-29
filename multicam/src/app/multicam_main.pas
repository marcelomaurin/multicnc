unit multicam_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,Dialogs,multicam_types,multicam_job,multicam_profile,multicam_engine,multicam_validator,multicam_gcode;
type TMultiCAMForm=class(TForm)
 private J:TCamJob;Log:TMemo;W,H,Depth,Diameter,StepDown,SafeZ,Feed,Plunge,RPM:TEdit;BuildBtn,ExportBtn:TButton;
  procedure BuildClick(Sender:TObject);procedure ExportClick(Sender:TObject);function E(const Caption,Value:string):TEdit;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TMultiCAMForm.E(const Caption,Value:string):TEdit;begin Result:=TEdit.Create(Self);Result.Parent:=Self;Result.Align:=alTop;Result.Text:=Value;Result.TextHint:=Caption;end;
constructor TMultiCAMForm.Create(AOwner:TComponent);
begin inherited Create(AOwner);Caption:='MultiCAM - CNC Router';Width:=900;Height:=650;J:=TCamJob.Create;J.Tool:=DefaultRouterTool;J.Settings:=DefaultCamSettings;
 W:=E('Largura (mm)','50');H:=E('Altura (mm)','30');Depth:=E('Profundidade final negativa','-2');Diameter:=E('Diametro ferramenta','3.175');StepDown:=E('Step-down','0.5');SafeZ:=E('Safe Z','5');Feed:=E('Feed - configurar','0');Plunge:=E('Plunge - configurar','0');RPM:=E('Spindle RPM - configurar','0');
 BuildBtn:=TButton.Create(Self);BuildBtn.Parent:=Self;BuildBtn.Align:=alTop;BuildBtn.Caption:='Gerar perfil retangular';BuildBtn.OnClick:=@BuildClick;
 ExportBtn:=TButton.Create(Self);ExportBtn.Parent:=Self;ExportBtn.Align:=alTop;ExportBtn.Caption:='Validar e exportar G-code';ExportBtn.OnClick:=@ExportClick;
 Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.Lines.Add('Configure ferramenta e corte antes de exportar.');end;
destructor TMultiCAMForm.Destroy;begin J.Free;inherited;end;
procedure TMultiCAMForm.BuildClick(Sender:TObject);
begin J.Tool.Diameter:=StrToFloatDef(Diameter.Text,0);J.Settings.StepDown:=StrToFloatDef(StepDown.Text,0);J.Settings.SafeZ:=StrToFloatDef(SafeZ.Text,0);TCamEngine.RectangleProfile(J,0,0,StrToFloatDef(W.Text,0),StrToFloatDef(H.Text,0),StrToFloatDef(Depth.Text,-1),True);Log.Lines.Add(Format('Toolpath: %d movimentos',[J.Count]));end;
procedure TMultiCAMForm.ExportClick(Sender:TObject);var D:TSaveDialog;begin J.Tool.Feed:=StrToFloatDef(Feed.Text,0);J.Tool.Plunge:=StrToFloatDef(Plunge.Text,0);J.Tool.SpindleRPM:=StrToIntDef(RPM.Text,0);if not TCamValidator.Validate(J,Log.Lines)then Exit;D:=TSaveDialog.Create(Self);try D.Filter:='G-code|*.gcode';if D.Execute then begin TCamGCode.ExportJob(J,D.FileName);Log.Lines.Add('Gerado: '+D.FileName);end;finally D.Free;end;end;
end.
