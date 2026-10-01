unit laserart_raster;
{$mode objfpc}{$H+}
{ Adaptador LCL: converte TBitmap para TGrayImage e delega ao rasterizador
  independente (laserart_rasterizer), que gera runs de potencia em vez de
  um ponto por pixel. }
interface
uses Classes,SysUtils,Graphics,Math,laserart_types,laserart_rasterizer,laserpcb_job;
type TLaserRaster=class
 public
  class function BitmapToGray(B:TBitmap):TGrayImage;
  class procedure BitmapToJob(B:TBitmap;J:TLaserPCBJob;X0,Y0,WidthMM:Double;Threshold:Byte;Invert:Boolean);
  class procedure BitmapToJobEx(B:TBitmap;J:TLaserPCBJob;X0,Y0,WidthMM:Double;const S:TRasterSettings);
 end;
implementation
class function TLaserRaster.BitmapToGray(B:TBitmap):TGrayImage;
var X,Y:Integer;C:TColor;
begin
 Result:=NewGrayImage(B.Width,B.Height);
 for Y:=0 to B.Height-1 do for X:=0 to B.Width-1 do begin
  C:=ColorToRGB(B.Canvas.Pixels[X,Y]);
  SetGrayPixel(Result,X,Y,Round(0.299*(C and $FF)+0.587*((C shr 8)and $FF)+0.114*((C shr 16)and $FF)));
 end;
end;
class procedure TLaserRaster.BitmapToJobEx(B:TBitmap;J:TLaserPCBJob;X0,Y0,WidthMM:Double;const S:TRasterSettings);
var G:TGrayImage;
begin
 if(B.Width=0)or(B.Height=0)then Exit;
 G:=BitmapToGray(B);PrepareImage(G,S);RasterToJob(G,J,X0,Y0,WidthMM,S);
end;
class procedure TLaserRaster.BitmapToJob(B:TBitmap;J:TLaserPCBJob;X0,Y0,WidthMM:Double;Threshold:Byte;Invert:Boolean);
var S:TRasterSettings;
begin
 S:=DefaultRasterSettings;S.Dither:=ldThreshold;S.Threshold:=Threshold;S.Invert:=Invert;
 S.PowerMin:=0;S.PowerMax:=1;S.Feed:=0;S.OverscanMM:=0; { Feed=0: potencia/feed do perfil do job }
 BitmapToJobEx(B,J,X0,Y0,WidthMM,S);
end;
end.
