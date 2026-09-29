unit laserpcb_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,Dialogs,laserpcb_job,laserpcb_types,laserpcb_svg,laserpcb_gcode;
type TLaserPCBForm=class(TForm)
 private J:TLaserPCBJob;Memo:TMemo;Power,Feed,Passes:TEdit;Mirror:TCheckBox;BtnOpen,BtnExport:TButton;
  procedure OpenClick(Sender:TObject);procedure ExportClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;procedure OpenFile(const FN:string);
 end;
implementation
constructor TLaserPCBForm.Create(AOwner:TComponent);
begin inherited Create(AOwner);Caption:='LaserPCB - Preparacao de PCB para Laser';Width:=900;Height:=600;J:=TLaserPCBJob.Create;
 BtnOpen:=TButton.Create(Self);BtnOpen.Parent:=Self;BtnOpen.Align:=alTop;BtnOpen.Caption:='Abrir SVG';BtnOpen.OnClick:=@OpenClick;
 Mirror:=TCheckBox.Create(Self);Mirror.Parent:=Self;Mirror.Align:=alTop;Mirror.Caption:='Espelhar camada Bottom';
 Power:=TEdit.Create(Self);Power.Parent:=Self;Power.Align:=alTop;Power.Text:='0';Power.TextHint:='Potencia calibrada';
 Feed:=TEdit.Create(Self);Feed.Parent:=Self;Feed.Align:=alTop;Feed.Text:='0';Feed.TextHint:='Velocidade calibrada';
 Passes:=TEdit.Create(Self);Passes.Parent:=Self;Passes.Align:=alTop;Passes.Text:='1';
 BtnExport:=TButton.Create(Self);BtnExport.Parent:=Self;BtnExport.Align:=alTop;BtnExport.Caption:='Gerar G-code';BtnExport.OnClick:=@ExportClick;
 Memo:=TMemo.Create(Self);Memo.Parent:=Self;Memo.Align:=alClient;Memo.Lines.Add('LaserPCB: abra um SVG com elementos line.');end;
destructor TLaserPCBForm.Destroy;begin J.Free;inherited;end;
procedure TLaserPCBForm.OpenFile(const FN:string);begin if(FN='')or(not FileExists(FN))then Exit;if TSVGImporter.ImportFile(FN,J)then Memo.Lines.Add(Format('Aberto pelo MultiSuite: %s | %d pontos',[FN,J.Count]))else Memo.Lines.Add('Arquivo recebido pelo MultiSuite nao contem linhas SVG reconhecidas: '+FN);end;
procedure TLaserPCBForm.OpenClick(Sender:TObject);var D:TOpenDialog;begin D:=TOpenDialog.Create(Self);try D.Filter:='SVG|*.svg';if D.Execute then OpenFile(D.FileName);finally D.Free;end;end;
procedure TLaserPCBForm.ExportClick(Sender:TObject);var D:TSaveDialog;begin if J.Count=0 then begin Memo.Lines.Add('Abra um trabalho primeiro');Exit;end;J.Profile.Power:=StrToFloatDef(Power.Text,0);J.Profile.Feed:=StrToFloatDef(Feed.Text,0);J.Profile.Passes:=StrToIntDef(Passes.Text,1);if(J.Profile.Power<=0)or(J.Profile.Feed<=0)then begin Memo.Lines.Add('Defina potencia e velocidade calibradas');Exit;end;J.Mirror:=Mirror.Checked;if J.Mirror then J.ApplyBottomMirror;D:=TSaveDialog.Create(Self);try D.Filter:='G-code|*.gcode';if D.Execute then begin TLaserGCodeExporter.ExportJob(J,D.FileName);Memo.Lines.Add('G-code gerado: '+D.FileName);end;finally D.Free;end;end;
end.
