unit multicam_mechanical_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multicam_types,multicam_job,multicam_setup;
type TMechanicalCanvas=class(TCustomControl)
 private FJob:TCamJob;FSetup:TMechanicalSetup;FScale:Double;
 protected procedure Paint;override;
 public constructor Create(AOwner:TComponent);override;property Job:TCamJob read FJob write FJob;property Setup:TMechanicalSetup read FSetup write FSetup;
 end;
implementation
constructor TMechanicalCanvas.Create(AOwner:TComponent);begin inherited;FScale:=3;Color:=clWhite;end;
procedure TMechanicalCanvas.Paint;var I:Integer;M:TPathMove;F:TFixture;X0,Y0:Integer;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);X0:=30;Y0:=30;if Assigned(FSetup)then begin Canvas.Pen.Color:=clBlack;Canvas.Brush.Style:=bsClear;Canvas.Rectangle(X0,Y0,X0+Round(FSetup.Stock.Width*FScale),Y0+Round(FSetup.Stock.Height*FScale));for I:=0 to FSetup.FixtureCount-1 do begin F:=FSetup.Fixture(I);Canvas.Pen.Color:=clRed;Canvas.Rectangle(X0+Round((F.X-FSetup.Stock.OriginX)*FScale),Y0+Round((F.Y-FSetup.Stock.OriginY)*FScale),X0+Round((F.X+F.W-FSetup.Stock.OriginX)*FScale),Y0+Round((F.Y+F.H-FSetup.Stock.OriginY)*FScale));end;end;if Assigned(FJob)and(FJob.Count>0)then begin Canvas.Pen.Color:=clBlue;M:=FJob.Move(0);Canvas.MoveTo(X0+Round(M.P.X*FScale),Y0+Round(M.P.Y*FScale));for I:=1 to FJob.Count-1 do begin M:=FJob.Move(I);if M.Rapid then Canvas.Pen.Style:=psDot else Canvas.Pen.Style:=psSolid;Canvas.LineTo(X0+Round(M.P.X*FScale),Y0+Round(M.P.Y*FScale));end;Canvas.Pen.Style:=psSolid;end;end;
end.
