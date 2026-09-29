unit laserpcb_camera_intf;
{$mode objfpc}{$H+}
interface
uses Graphics;
type
 ILaserCamera=interface
  function Open:Boolean;
  procedure Close;
  function IsOpen:Boolean;
  function CaptureFrame(out Frame:TBitmap):Boolean;
  function DeviceName:string;
 end;
implementation
end.
