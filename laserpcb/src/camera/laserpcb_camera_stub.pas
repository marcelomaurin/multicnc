unit laserpcb_camera_stub;
{$mode objfpc}{$H+}
interface
uses Graphics,laserpcb_camera_intf;
type TNoCamera=class(TInterfacedObject,ILaserCamera)
 public function Open:Boolean;procedure Close;function IsOpen:Boolean;function CaptureFrame(out Frame:TBitmap):Boolean;function DeviceName:string;
 end;
implementation
function TNoCamera.Open:Boolean;begin Result:=False;end;
procedure TNoCamera.Close;begin end;
function TNoCamera.IsOpen:Boolean;begin Result:=False;end;
function TNoCamera.CaptureFrame(out Frame:TBitmap):Boolean;begin Frame:=nil;Result:=False;end;
function TNoCamera.DeviceName:string;begin Result:='Camera nao configurada';end;
end.
