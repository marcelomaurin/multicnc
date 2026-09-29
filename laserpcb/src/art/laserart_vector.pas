unit laserart_vector;
{$mode objfpc}{$H+}
interface
uses Math,laserpcb_job;
type TLaserVectorBuilder=class
 public class procedure Rectangle(J:TLaserPCBJob;X,Y,W,H:Double);class procedure Ellipse(J:TLaserPCBJob;CX,CY,RX,RY:Double;Segments:Integer=64);
 end;
implementation
class procedure TLaserVectorBuilder.Rectangle(J:TLaserPCBJob;X,Y,W,H:Double);begin J.AddPoint(X,Y,False);J.AddPoint(X+W,Y,True);J.AddPoint(X+W,Y+H,True);J.AddPoint(X,Y+H,True);J.AddPoint(X,Y,True);J.AddPoint(X,Y,False);end;
class procedure TLaserVectorBuilder.Ellipse(J:TLaserPCBJob;CX,CY,RX,RY:Double;Segments:Integer);var I:Integer;A:Double;begin if Segments<12 then Segments:=12;for I:=0 to Segments do begin A:=2*Pi*I/Segments;J.AddPoint(CX+Cos(A)*RX,CY+Sin(A)*RY,I>0);end;J.AddPoint(CX+RX,CY,False);end;
end.
