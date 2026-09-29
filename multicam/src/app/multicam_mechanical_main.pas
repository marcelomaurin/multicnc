unit multicam_mechanical_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,Dialogs,multicam_types,multicam_job,multicam_profile,multicam_mechanical,multicam_engine,multicam_validator,multicam_gcode;
type TMechanicalCAMForm=class(TForm)
 private J:TCamJob;Log:TMemo;W,H,Depth,Diameter,StepDown,StepOver,SafeZ,Feed,Plunge,RPM:TEdit;function E(const Hint,Value:string):TEdit;function B(const S:string;Hnd:TNotifyEvent):TButton;procedure LoadParams;procedure FaceClick(Sender:TObject);procedure PocketClick(Sender:TObject);procedure DrillClick(Sender:TObject);procedure ProfileClick(Sender:TObject);procedure ExportClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TMechanicalCAMForm.E(const Hint,Value:string):TEdit;begin Result:=TEdit.Create(Self);Result.Parent:=Self;Result.Align:=alTop;Result.TextHint:=Hint;Result.Text:=Value;end;
function TMechanicalCAMForm.B(const S:string;Hnd:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=Self;Result.Align:=alTop;Result.Caption:=S;Result.OnClick:=Hnd;end;
constructor TMechanicalCAMForm.Create(AOwner:TComponent);
begin inherited;Caption:='MultiCAM Mecanica - CNC Router';Width:=980;Height:=720;J:=TCamJob.Create;J.Tool:=DefaultRouterTool;J.Settings:=DefaultCamSettings;W:=E('Largura da operacao mm','50');H:=E('Altura da operacao mm','30');Depth:=E('Profundidade final negativa','-2');Diameter:=E('Diametro da ferramenta mm','');StepDown:=E('Step-down mm','');StepOver:=E('Step-over 0..1','');SafeZ:=E('Z seguro mm','5');Feed:=E('Avanco XY calibrado','');Plunge:=E('Avanco Z calibrado','');RPM:=E('RPM calibrado','');B('Faceamento',@FaceClick);B('Pocket',@PocketClick);B('Furacao 3x2',@DrillClick);B('Contorno externo',@ProfileClick);B('Validar e exportar G-code',@ExportClick);Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.Lines.Add('Defina ferramenta, material, profundidade e parametros de corte antes de gerar a usinagem.');end;
destructor TMechanicalCAMForm.Destroy;begin J.Free;inherited;end;
procedure TMechanicalCAMForm.LoadParams;begin J.Tool.Diameter:=StrToFloatDef(Diameter.Text,0);J.Tool.Feed:=StrToFloatDef(Feed.Text,0);J.Tool.Plunge:=StrToFloatDef(Plunge.Text,0);J.Tool.SpindleRPM:=StrToIntDef(RPM.Text,0);J.Settings.StepDown:=StrToFloatDef(StepDown.Text,0);J.Settings.StepOver:=StrToFloatDef(StepOver.Text,0);J.Settings.SafeZ:=StrToFloatDef(SafeZ.Text,0);end;
procedure TMechanicalCAMForm.FaceClick(Sender:TObject);begin LoadParams;TMechanicalCAM.Facing(J,0,0,StrToFloatDef(W.Text,0),StrToFloatDef(H.Text,0),StrToFloatDef(Depth.Text,0));Log.Lines.Add(Format('Faceamento: %d movimentos',[J.Count]));end;
procedure TMechanicalCAMForm.PocketClick(Sender:TObject);begin LoadParams;TMechanicalCAM.Pocket(J,0,0,StrToFloatDef(W.Text,0),StrToFloatDef(H.Text,0),StrToFloatDef(Depth.Text,0));Log.Lines.Add(Format('Pocket: %d movimentos',[J.Count]));end;
procedure TMechanicalCAMForm.DrillClick(Sender:TObject);begin LoadParams;TMechanicalCAM.DrillGrid(J,5,5,10,10,3,2,StrToFloatDef(Depth.Text,0));Log.Lines.Add(Format('Furacao: %d movimentos',[J.Count]));end;
procedure TMechanicalCAMForm.ProfileClick(Sender:TObject);begin LoadParams;TCamEngine.RectangleProfile(J,0,0,StrToFloatDef(W.Text,0),StrToFloatDef(H.Text,0),StrToFloatDef(Depth.Text,0),True);Log.Lines.Add(Format('Contorno: %d movimentos',[J.Count]));end;
procedure TMechanicalCAMForm.ExportClick(Sender:TObject);var D:TSaveDialog;begin LoadParams;if not TCamValidator.Validate(J,Log.Lines)then Exit;D:=TSaveDialog.Create(Self);try D.Filter:='G-code|*.gcode';if D.Execute then begin TCamGCode.ExportJob(J,D.FileName);Log.Lines.Add('G-code preparado para execucao posterior no MultiCNC.');end;finally D.Free;end;end;
end.
