unit laserart_calibration;
{$mode objfpc}{$H+}
interface
uses SysUtils,laserpcb_job;
type TLaserCalibration=class
 public class procedure BuildMatrix(J:TLaserPCBJob;X0,Y0,CellW,CellH,PowerMin,PowerMax,FeedMin,FeedMax:Double;Cols,Rows:Integer);
 end;
implementation
class procedure TLaserCalibration.BuildMatrix(J:TLaserPCBJob;X0,Y0,CellW,CellH,PowerMin,PowerMax,FeedMin,FeedMax:Double;Cols,Rows:Integer);
var C,R:Integer;X,Y,P,F:Double;
begin if(Cols<2)or(Rows<2)or(PowerMin<=0)or(PowerMax<PowerMin)or(FeedMin<=0)or(FeedMax<FeedMin)then Exit;J.Clear;for R:=0 to Rows-1 do begin F:=FeedMin+(FeedMax-FeedMin)*R/(Rows-1);for C:=0 to Cols-1 do begin P:=PowerMin+(PowerMax-PowerMin)*C/(Cols-1);X:=X0+C*CellW;Y:=Y0+R*CellH;J.AddPoint(X,Y,False);J.AddPoint(X+CellW*.8,Y,True);J.AddPoint(X+CellW*.8,Y+CellH*.8,True);J.AddPoint(X,Y+CellH*.8,True);J.AddPoint(X,Y,True);J.AddPoint(X,Y,False);end;end;J.Profile.Power:=PowerMax;J.Profile.Feed:=FeedMin;J.Profile.Passes:=1;end;
end.
