unit multicam_engine;
{$mode objfpc}{$H+}
interface
uses SysUtils,Math,multicam_types,multicam_job;
type TCamEngine=class
 public class procedure RectangleProfile(J:TCamJob;X,Y,W,H,FinalDepth:Double;Outside:Boolean);
 end;
implementation
class procedure TCamEngine.RectangleProfile(J:TCamJob;X,Y,W,H,FinalDepth:Double;Outside:Boolean);
var Z,Off:Double;
begin J.Clear;if(J.Settings.StepDown<=0)or(J.Tool.Diameter<=0)then Exit;Off:=J.Tool.Diameter/2;if Outside then begin X:=X-Off;Y:=Y-Off;W:=W+2*Off;H:=H+2*Off;end else begin X:=X+Off;Y:=Y+Off;W:=W-2*Off;H:=H-2*Off;end;
 J.AddMove(X,Y,J.Settings.SafeZ,True);Z:=-J.Settings.StepDown;while Z>FinalDepth do begin J.AddMove(X,Y,Z,False);J.AddMove(X+W,Y,Z,False);J.AddMove(X+W,Y+H,Z,False);J.AddMove(X,Y+H,Z,False);J.AddMove(X,Y,Z,False);Z:=Z-J.Settings.StepDown;end;Z:=FinalDepth;J.AddMove(X,Y,Z,False);J.AddMove(X+W,Y,Z,False);J.AddMove(X+W,Y+H,Z,False);J.AddMove(X,Y+H,Z,False);J.AddMove(X,Y,Z,False);J.AddMove(X,Y,J.Settings.SafeZ,True);end;
end.
