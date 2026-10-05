unit multicam_machine_canvas;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,Controls,Graphics,Math,multicam_types,multicam_job,multicam_setup,multicam_machine_model,multicam_machine_kinematics;
type TMachineCanvas=class(TCustomControl)
 private FCollision:Boolean;FContact:TCamPoint;FSetup:TMechanicalSetup;FMachine:TMachineModel;FPose:TMachinePose;
 protected procedure Paint;override;
 public procedure ShowCollision(const P:TCamPoint);procedure ClearCollision;procedure SetPose(const P:TMachinePose);property Setup:TMechanicalSetup read FSetup write FSetup;property Machine:TMachineModel read FMachine write FMachine;
 end;
implementation
procedure TMachineCanvas.ShowCollision(const P:TCamPoint);begin FCollision:=True;FContact:=P;Invalidate;end;
procedure TMachineCanvas.ClearCollision;begin FCollision:=False;Invalidate;end;
procedure TMachineCanvas.SetPose(const P:TMachinePose);begin FPose:=P;Invalidate;end;
procedure TMachineCanvas.Paint;var SX,SY:Double;OX,OY,X,Y,I:Integer;F:TFixture;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if not Assigned(FSetup)then Exit;OX:=40;OY:=40;SX:=(ClientWidth-80)/Max(1,FSetup.Stock.Width);SY:=(ClientHeight-80)/Max(1,FSetup.Stock.Height);Canvas.Brush.Style:=bsClear;Canvas.Pen.Color:=clGray;Canvas.Rectangle(OX,OY,OX+Round(FSetup.Stock.Width*SX),OY+Round(FSetup.Stock.Height*SY));for I:=0 to FSetup.FixtureCount-1 do begin F:=FSetup.Fixture(I);Canvas.Pen.Color:=clMaroon;
 Canvas.Rectangle(OX+Round((F.X-FSetup.Stock.OriginX)*SX),OY+Round((F.Y-FSetup.Stock.OriginY)*SY),OX+Round((F.X+F.W-FSetup.Stock.OriginX)*SX),OY+Round((F.Y+F.H-FSetup.Stock.OriginY)*SY));end;
 if FCollision then begin Canvas.Pen.Color:=clRed;Canvas.Pen.Width:=3;X:=OX+Round((FContact.X-FSetup.Stock.OriginX)*SX);Y:=OY+Round((FContact.Y-FSetup.Stock.OriginY)*SY);Canvas.Ellipse(X-10,Y-10,X+10,Y+10);Canvas.Pen.Width:=1;end;
 X:=OX+Round((FPose.X-FSetup.Stock.OriginX)*SX);Y:=OY+Round((FPose.Y-FSetup.Stock.OriginY)*SY);Canvas.Pen.Color:=clBlack;Canvas.Line(X-12,Y,X+12,Y);Canvas.Line(X,Y-12,X,Y+12);Canvas.Ellipse(X-6,Y-6,X+6,Y+6);Canvas.TextOut(5,5,Format('X %.2f  Y %.2f  Z %.2f',[FPose.X,FPose.Y,FPose.Z],InvariantFS));end;
end.
