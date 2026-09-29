unit multislicer_positionform;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,multislicer_layout3d,multislicer_arrange,multislicer_bedcanvas;
type TPosition3DForm=class(TForm)
 private L:TPrintBedLayout;C:TPrintBedCanvas;Top:TPanel;Log:TMemo;function Btn(const S:string;H:TNotifyEvent):TButton;procedure AddClick(Sender:TObject);procedure ArrangeClick(Sender:TObject);procedure RotateClick(Sender:TObject);procedure CenterClick(Sender:TObject);procedure ValidateClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TPosition3DForm.Btn(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=Top;Result.Align:=alLeft;Result.Width:=115;Result.Caption:=S;Result.OnClick:=H;end;
constructor TPosition3DForm.Create(AOwner:TComponent);begin inherited;Caption:='MultiSlicer - Posicionamento 3D';Width:=1000;Height:=700;L:=TPrintBedLayout.Create;Top:=TPanel.Create(Self);Top.Parent:=Self;Top.Align:=alTop;Top.Height:=36;Btn('Adicionar',@AddClick);Btn('Auto Arrange',@ArrangeClick);Btn('Girar Z 90',@RotateClick);Btn('Centralizar',@CenterClick);Btn('Validar',@ValidateClick);Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alBottom;Log.Height:=100;C:=TPrintBedCanvas.Create(Self);C.Parent:=Self;C.Align:=alClient;C.Layout:=L;end;
destructor TPosition3DForm.Destroy;begin L.Free;inherited;end;
procedure TPosition3DForm.AddClick(Sender:TObject);var P:TModelPlacement;begin P:=L.AddModel('Modelo '+IntToStr(L.Count+1),'',30,30,30);P.X:=L.Margin;P.Y:=L.Margin;C.Invalidate;end;
procedure TPosition3DForm.ArrangeClick(Sender:TObject);begin if not TAutoArrange3D.ArrangeRows(L)then Log.Lines.Add('Nem todos os modelos cabem na mesa');C.Invalidate;end;
procedure TPosition3DForm.RotateClick(Sender:TObject);begin C.RotateZ90;end;
procedure TPosition3DForm.CenterClick(Sender:TObject);begin C.CenterSelected;end;
procedure TPosition3DForm.ValidateClick(Sender:TObject);begin if L.Validate(Log.Lines)then Log.Lines.Add('Posicionamento valido');end;
end.
