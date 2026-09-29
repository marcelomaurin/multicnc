unit multipcb_cnc_positionform;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,multipcb_cnc_position,multipcb_probeplan,multipcb_cnc_canvas;
type TPCBCNCPositionForm=class(TForm)
 private P:TPCBPlacement;Plan:TProbePlan;FView:TPCBCNCCanvas;FTopBar:TPanel;Log:TMemo;
  procedure ToggleFace(Sender:TObject);procedure BuildProbe(Sender:TObject);procedure ZoomIn(Sender:TObject);procedure ZoomOut(Sender:TObject);function Btn(const S:string;H:TNotifyEvent):TButton;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TPCBCNCPositionForm.Btn(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=FTopBar;Result.Align:=alLeft;Result.Width:=130;Result.Caption:=S;Result.OnClick:=H;end;
constructor TPCBCNCPositionForm.Create(AOwner:TComponent);
begin inherited;Caption:='MultiPCB - Posicionamento CNC';Width:=1000;Height:=700;P:=TPCBPlacement.Create;P.BoardWidth:=100;P.BoardHeight:=70;P.OriginX:=20;P.OriginY:=20;Plan:=TProbePlan.Create;
 FTopBar:=TPanel.Create(Self);FTopBar.Parent:=Self;FTopBar.Align:=alTop;FTopBar.Height:=36;Btn('TOP / BOTTOM',@ToggleFace);Btn('Grade Probe 5x5',@BuildProbe);Btn('Zoom +',@ZoomIn);Btn('Zoom -',@ZoomOut);
 Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alBottom;Log.Height:=90;Log.Lines.Add('Defina o posicionamento e valide antes do probe fisico.');
 FView:=TPCBCNCCanvas.Create(Self);FView.Parent:=Self;FView.Align:=alClient;FView.Placement:=P;FView.ProbePlan:=Plan;end;
destructor TPCBCNCPositionForm.Destroy;begin Plan.Free;P.Free;inherited;end;
procedure TPCBCNCPositionForm.ToggleFace(Sender:TObject);begin if P.Face=pfTop then P.Face:=pfBottom else P.Face:=pfTop;FView.Invalidate;end;
procedure TPCBCNCPositionForm.BuildProbe(Sender:TObject);begin Plan.BuildGrid(P,5,5,3);FView.ShowProbe:=True;FView.Invalidate;Log.Lines.Add(Format('Grade criada: %d pontos',[Plan.Count]));end;
procedure TPCBCNCPositionForm.ZoomIn(Sender:TObject);begin FView.ZoomIn;end;
procedure TPCBCNCPositionForm.ZoomOut(Sender:TObject);begin FView.ZoomOut;end;
end.
