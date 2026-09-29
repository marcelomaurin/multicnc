unit laserart_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,ComCtrls,Dialogs,laserart_types,laserart_document,laserart_canvas,laserart_jobbuilder,laserpcb_job,laserpcb_gcode;
type TLaserArtForm=class(TForm)
 private Doc:TLaserArtDocument;View:TLaserArtCanvas;Tree:TTreeView;Props:TMemo;Bar:TPanel;function Btn(const S:string;H:TNotifyEvent):TButton;procedure Refresh;procedure AddText(Sender:TObject);procedure AddImage(Sender:TObject);procedure AddRect(Sender:TObject);procedure AddEllipse(Sender:TObject);procedure ExportClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TLaserArtForm.Btn(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=Bar;Result.Align:=alLeft;Result.Width:=100;Result.Caption:=S;Result.OnClick:=H;end;
constructor TLaserArtForm.Create(AOwner:TComponent);begin inherited;Caption:='LaserArt - Logos, Imagens e Arte para Laser';Width:=1280;Height:=760;Doc:=TLaserArtDocument.Create;Bar:=TPanel.Create(Self);Bar.Parent:=Self;Bar.Align:=alTop;Bar.Height:=38;Btn('Texto',@AddText);Btn('Imagem',@AddImage);Btn('Retangulo',@AddRect);Btn('Elipse',@AddEllipse);Btn('Gerar G-code',@ExportClick);Tree:=TTreeView.Create(Self);Tree.Parent:=Self;Tree.Align:=alLeft;Tree.Width:=220;Props:=TMemo.Create(Self);Props.Parent:=Self;Props.Align:=alRight;Props.Width:=240;Props.Lines.Text:='Processo: Gravar / Cortar / Marcar'+LineEnding+'Potencia e velocidade devem usar perfil calibrado.';View:=TLaserArtCanvas.Create(Self);View.Parent:=Self;View.Align:=alClient;View.Document:=Doc;Refresh;end;
destructor TLaserArtForm.Destroy;begin Doc.Free;inherited;end;
procedure TLaserArtForm.Refresh;var I:Integer;begin Tree.Items.Clear;Tree.Items.Add(nil,Doc.Name);for I:=0 to Doc.Count-1 do Tree.Items.AddChild(Tree.Items[0],Doc.Item(I).Name);Tree.FullExpand;View.Invalidate;end;
procedure TLaserArtForm.AddText(Sender:TObject);var A:TLaserArtItem;begin A:=Doc.Add(lakText,'Texto '+IntToStr(Doc.Count+1));A.Text:='MultiCNC';A.FontName:='Arial';A.X:=20;A.Y:=20;A.Width:=50;A.Height:=12;Refresh;end;
procedure TLaserArtForm.AddImage(Sender:TObject);var D:TOpenDialog;A:TLaserArtItem;begin D:=TOpenDialog.Create(Self);try D.Filter:='Imagens|*.bmp;*.png;*.jpg;*.jpeg';if D.Execute then begin A:=Doc.Add(lakImage,ExtractFileName(D.FileName));A.SourceFile:=D.FileName;A.X:=20;A.Y:=40;A.Width:=60;A.Height:=40;Refresh;end;finally D.Free;end;end;
procedure TLaserArtForm.AddRect(Sender:TObject);var A:TLaserArtItem;begin A:=Doc.Add(lakRectangle,'Retangulo '+IntToStr(Doc.Count+1));A.X:=20;A.Y:=20;A.Width:=50;A.Height:=30;A.Mode:=lamCut;Refresh;end;
procedure TLaserArtForm.AddEllipse(Sender:TObject);var A:TLaserArtItem;begin A:=Doc.Add(lakEllipse,'Elipse '+IntToStr(Doc.Count+1));A.X:=20;A.Y:=20;A.Width:=40;A.Height:=40;A.Mode:=lamCut;Refresh;end;
procedure TLaserArtForm.ExportClick(Sender:TObject);var J:TLaserPCBJob;D:TSaveDialog;begin J:=TLaserPCBJob.Create;try TLaserArtJobBuilder.Build(Doc,J);if J.Count=0 then begin Props.Lines.Add('Nada para exportar.');Exit;end;J.Profile.Power:=0;J.Profile.Feed:=0;J.Profile.Passes:=1;Props.Lines.Add('Job preparado: '+IntToStr(J.Count)+' pontos.');Props.Lines.Add('Defina perfil calibrado antes de gerar G-code.');if(J.Profile.Power<=0)or(J.Profile.Feed<=0)then Exit;D:=TSaveDialog.Create(Self);try D.Filter:='G-code|*.gcode';if D.Execute then TLaserGCodeExporter.ExportJob(J,D.FileName);finally D.Free;end;finally J.Free;end;end;
end.
