unit laserart_imagefx;
{$mode objfpc}{$H+}
interface
uses Graphics,Math;
type TLaserImageFX=class
 public class procedure Grayscale(B:TBitmap);class procedure Threshold(B:TBitmap;Level:Byte;Invert:Boolean);class procedure FloydSteinberg(B:TBitmap;Invert:Boolean);
 end;
implementation
function Gray(C:TColor):Integer;begin C:=ColorToRGB(C);Result:=Round(0.299*(C and $FF)+0.587*((C shr 8)and $FF)+0.114*((C shr 16)and $FF));end;
function Clamp(V:Integer):Integer;begin Result:=Max(0,Min(255,V));end;
class procedure TLaserImageFX.Grayscale(B:TBitmap);var X,Y,G:Integer;begin for Y:=0 to B.Height-1 do for X:=0 to B.Width-1 do begin G:=Gray(B.Canvas.Pixels[X,Y]);B.Canvas.Pixels[X,Y]:=RGBToColor(G,G,G);end;end;
class procedure TLaserImageFX.Threshold(B:TBitmap;Level:Byte;Invert:Boolean);var X,Y,G,V:Integer;begin for Y:=0 to B.Height-1 do for X:=0 to B.Width-1 do begin G:=Gray(B.Canvas.Pixels[X,Y]);if G<Level then V:=0 else V:=255;if Invert then V:=255-V;B.Canvas.Pixels[X,Y]:=RGBToColor(V,V,V);end;end;
class procedure TLaserImageFX.FloydSteinberg(B:TBitmap;Invert:Boolean);var A:array of array of Double;X,Y,N,O:Integer;E:Double;begin SetLength(A,B.Height,B.Width);for Y:=0 to B.Height-1 do for X:=0 to B.Width-1 do A[Y,X]:=Gray(B.Canvas.Pixels[X,Y]);for Y:=0 to B.Height-1 do for X:=0 to B.Width-1 do begin O:=Round(A[Y,X]);if O<128 then N:=0 else N:=255;E:=O-N;if X+1<B.Width then A[Y,X+1]:=A[Y,X+1]+E*7/16;if(Y+1<B.Height)and(X>0)then A[Y+1,X-1]:=A[Y+1,X-1]+E*3/16;if Y+1<B.Height then A[Y+1,X]:=A[Y+1,X]+E*5/16;if(Y+1<B.Height)and(X+1<B.Width)then A[Y+1,X+1]:=A[Y+1,X+1]+E/16;if Invert then N:=255-N;N:=Clamp(N);B.Canvas.Pixels[X,Y]:=RGBToColor(N,N,N);end;end;
end.
