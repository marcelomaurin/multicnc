unit laserpcb_layoutform;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,laserpcb_layout,laserpcb_nesting,laserpcb_bedcanvas;
type TLaserLayoutForm=class(TForm)
 private L:TLaserBedLayout;FView:TLaserBedCanvas;Log:TMemo;FTopBar:TPanel;
  procedure AddClick(Sender:TObject);procedure NestClick(Sender:TObject);procedure RotateClick(Sender:TObject);procedure ValidateClick(Sender:TObject);procedure ZoomInClick(Sender:TObject);procedure ZoomOutClick(Sender:TObject);function Btn(const S:string;H:TNotifyEvent):TButton;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TLaserLayoutForm.Btn(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=FTopBar;Result.Align:=alLeft;Result.Width:=105;Result.Caption:=S;Result.OnClick:=H;end;
constructor TLaserLayoutForm.Create(AOwner:TComponent);
begin inherited;Caption:='LaserPCB - Posicionamento';Width:=1000;Height:=700;L:=TLaserBedLayout.Create;FTopBar:=TPanel.Create(Self);FTopBar.Parent:=Self;FTopBar.Align:=alTop;FTopBar.Height:=35;Btn('Adicionar',@AddClick);Btn('Nesting',@NestClick);Btn('Girar 90',@RotateClick);Btn('Validar',@ValidateClick);Btn('Zoom +',@ZoomInClick);Btn('Zoom -',@ZoomOutClick);Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alBottom;Log.Height:=100;FView:=TLaserBedCanvas.Create(Self);FView.Parent:=Self;FView.Align:=alClient;FView.Layout:=L;FView.SnapMM:=1;end;
destructor TLaserLayoutForm.Destroy;begin L.Free;inherited;end;
procedure TLaserLayoutForm.AddClick(Sender:TObject);var P:TLaserLayoutItem;begin P:=L.AddItem('Peca '+IntToStr(L.Count+1),50,30);P.X:=L.Margin;P.Y:=L.Margin;FView.Invalidate;end;
procedure TLaserLayoutForm.NestClick(Sender:TObject);begin if not TLaserNesting.ArrangeRows(L)then Log.Lines.Add('Nem todas as pecas cabem na mesa');FView.Invalidate;end;
procedure TLaserLayoutForm.RotateClick(Sender:TObject);begin FView.RotateSelected90;end;
procedure TLaserLayoutForm.ValidateClick(Sender:TObject);begin if L.Validate(Log.Lines)then Log.Lines.Add('Layout valido');end;
procedure TLaserLayoutForm.ZoomInClick(Sender:TObject);begin FView.ZoomIn;end;
procedure TLaserLayoutForm.ZoomOutClick(Sender:TObject);begin FView.ZoomOut;end;
end.
