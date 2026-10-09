unit laserart_jobbuilder;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Graphics,laserart_types,laserart_document,laserart_vector,laserart_raster,laserart_rasterizer,laserpcb_job;
type TLaserArtJobBuilder=class public class procedure Build(D:TLaserArtDocument;J:TLaserPCBJob);end;
implementation
class procedure TLaserArtJobBuilder.Build(D:TLaserArtDocument;J:TLaserPCBJob);var I:Integer;A:TLaserArtItem;B:TBitmap;Pic:TPicture;RS:TRasterSettings;
begin J.Clear;J.Name:=D.Name;J.Width:=D.BedWidth;J.Height:=D.BedHeight;for I:=0 to D.Count-1 do begin A:=D.Item(I);if not A.Visible then Continue;case A.Kind of
lakRectangle:TLaserVectorBuilder.Rectangle(J,A.X,A.Y,A.Width,A.Height);
lakEllipse:TLaserVectorBuilder.Ellipse(J,A.X+A.Width/2,A.Y+A.Height/2,A.Width/2,A.Height/2);
lakImage:if FileExists(A.SourceFile)then begin Pic:=TPicture.Create;B:=TBitmap.Create;try Pic.LoadFromFile(A.SourceFile);B.SetSize(Pic.Width,Pic.Height);B.Canvas.Draw(0,0,Pic.Graphic);RS:=DefaultRasterSettings;RS.Dither:=A.Dither;RS.Threshold:=A.Threshold;RS.PowerMin:=0;RS.PowerMax:=A.Power;RS.Feed:=A.Feed;{ item sem calibracao: usa perfil do job (modo binario) }if(A.Power<=0)or(A.Feed<=0)then begin RS.Feed:=0;RS.PowerMax:=1;if RS.Dither=ldNone then RS.Dither:=ldThreshold;end;TLaserRaster.BitmapToJobEx(B,J,A.X,A.Y,A.Width,RS);finally B.Free;Pic.Free;end;end;
end;end;end;
end.
