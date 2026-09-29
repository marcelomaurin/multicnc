unit multicam_machine_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multicam_types,multicam_job,multicam_setup,multicam_machine_model,multicam_machine_kinematics;
type TMachineCanvas=class(TCustomControl)
 private FSetup:TMechanicalSetup;FMachine:TMachineModel;FPose:TMachinePose;
 protected procedure Paint;override;
 public procedure SetPose(const P:TMachinePose);property Setup:TMechanicalSetup read FSetup write FSetup;property Machine:TMachineModel read FMachine write FMachine;
 end;
implementation
procedure TMachineCanvas.SetPose(const P:TMachinePose);begin FPose:=P;Invalidate;end;
procedure TMachineCanvas.Paint;var SX,SY:Double;OX,OY,X,Y:Integer;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if not Assigned(FSetup)then Exit;OX:=40;OY:=40;SX:=(ClientWidth-80)/Max(1,FSetup.Stock.Width);SY:=(ClientHeight-80)/Max(1,FSetup.Stock.Height);Canvas.Brush.Style:=bsClear;Canvas.Pen.Color:=clGray;Canvas.Rectangle(OX,OY,OX+Round(FSetup.Stock.Width*SX),OY+Round(FSetup.Stock.Height*SY));X:=OX+Round((FPose.X-FSetup.Stock.OriginX)*SX);Y:=OY+Round((FPose.Y-FSetup.Stock.OriginY)*SY);Canvas.Pen.Color:=clBlack;Canvas.Line(X-12,Y,X+12,Y);Canvas.Line(X,Y-12,X,Y+12);Canvas.Ellipse(X-6,Y-6,X+6,Y+6);Canvas.TextOut(5,5,Format('X %.2f  Y %.2f  Z %.2f',[FPose.X,FPose.Y,FPose.Z]));end;
end.
