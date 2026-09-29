unit laserart_raster;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Graphics,Math,laserpcb_job;
type TLaserRaster=class
 public class procedure BitmapToJob(B:TBitmap;J:TLaserPCBJob;X0,Y0,WidthMM:Double;Threshold:Byte;Invert:Boolean);
 end;
implementation
class procedure TLaserRaster.BitmapToJob(B:TBitmap;J:TLaserPCBJob;X0,Y0,WidthMM:Double;Threshold:Byte;Invert:Boolean);
var X,Y:Integer;DX,DY,G:Double;C:TColor;On:Boolean;
begin if(B.Width=0)or(B.Height=0)then Exit;DX:=WidthMM/B.Width;DY:=DX;for Y:=0 to B.Height-1 do begin if Odd(Y)then begin for X:=B.Width-1 downto 0 do begin C:=ColorToRGB(B.Canvas.Pixels[X,Y]);G:=((C and $FF)+((C shr 8)and $FF)+((C shr 16)and $FF))/3;On:=G<Threshold;if Invert then On:=not On;J.AddPoint(X0+X*DX,Y0+Y*DY,On);end;end else for X:=0 to B.Width-1 do begin C:=ColorToRGB(B.Canvas.Pixels[X,Y]);G:=((C and $FF)+((C shr 8)and $FF)+((C shr 16)and $FF))/3;On:=G<Threshold;if Invert then On:=not On;J.AddPoint(X0+X*DX,Y0+Y*DY,On);end;J.AddPoint(X0,Y0+(Y+1)*DY,False);end;end;
end.
