unit laserart_calibrationform;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,Dialogs,laserpcb_job,laserpcb_gcode,laserart_calibration;
type TLaserCalibrationForm=class(TForm)
 private EPowerMin,EPowerMax,EFeedMin,EFeedMax,ECols,ERows:TEdit;Log:TMemo;J:TLaserPCBJob;function Field(const ACaption,Value:string):TEdit;procedure BuildClick(Sender:TObject);procedure ExportClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TLaserCalibrationForm.Field(const ACaption,Value:string):TEdit;var L:TLabel;begin L:=TLabel.Create(Self);L.Parent:=Self;L.Align:=alTop;L.Caption:=ACaption;Result:=TEdit.Create(Self);Result.Parent:=Self;Result.Align:=alTop;Result.Text:=Value;end;
constructor TLaserCalibrationForm.Create(AOwner:TComponent);var B:TButton;
begin inherited;Caption:='LaserArt - Teste de Material';Width:=520;Height:=600;J:=TLaserPCBJob.Create;EPowerMin:=Field('Potencia minima (S)','');EPowerMax:=Field('Potencia maxima (S)','');EFeedMin:=Field('Velocidade minima (mm/min)','');EFeedMax:=Field('Velocidade maxima (mm/min)','');ECols:=Field('Colunas','5');ERows:=Field('Linhas','5');B:=TButton.Create(Self);B.Parent:=Self;B.Align:=alTop;B.Caption:='Preparar matriz';B.OnClick:=@BuildClick;B:=TButton.Create(Self);B.Parent:=Self;B.Align:=alTop;B.Caption:='Exportar G-code';B.OnClick:=@ExportClick;Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.Lines.Add('Informe limites calibrados/seguros para sua maquina e material.');end;
destructor TLaserCalibrationForm.Destroy;begin J.Free;inherited;end;
procedure TLaserCalibrationForm.BuildClick(Sender:TObject);var P1,P2,F1,F2:Double;C,R:Integer;
begin P1:=StrToFloatDef(EPowerMin.Text,0);P2:=StrToFloatDef(EPowerMax.Text,0);F1:=StrToFloatDef(EFeedMin.Text,0);F2:=StrToFloatDef(EFeedMax.Text,0);C:=StrToIntDef(ECols.Text,0);R:=StrToIntDef(ERows.Text,0);if(P1<=0)or(P2<P1)or(F1<=0)or(F2<F1)or(C<2)or(R<2)then begin Log.Lines.Add('Parametros invalidos.');Exit;end;TLaserCalibration.BuildMatrix(J,10,10,12,12,P1,P2,F1,F2,C,R);Log.Lines.Add(Format('Matriz preparada: %dx%d, %d movimentos',[C,R,J.Count]));end;
procedure TLaserCalibrationForm.ExportClick(Sender:TObject);var D:TSaveDialog;begin if J.Count=0 then begin Log.Lines.Add('Prepare a matriz primeiro.');Exit;end;D:=TSaveDialog.Create(Self);try D.Filter:='G-code|*.gcode';if D.Execute then begin TLaserGCodeExporter.ExportJob(J,D.FileName);Log.Lines.Add('Arquivo gerado. Execute somente apos revisar limites e area util.');end;finally D.Free;end;end;
end.
