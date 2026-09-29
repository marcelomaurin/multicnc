unit laserart_jobbuilder;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Graphics,laserart_types,laserart_document,laserart_vector,laserart_raster,laserpcb_job;
type TLaserArtJobBuilder=class
 public class procedure Build(D:TLaserArtDocument;J:TLaserPCBJob);
 end;
implementation
class procedure TLaserArtJobBuilder.Build(D:TLaserArtDocument;J:TLaserPCBJob);var I:Integer;A:TLaserArtItem;B:TBitmap;begin J.Clear;J.Name:=D.Name;J.Width:=D.BedWidth;J.Height:=D.BedHeight;for I:=0 to D.Count-1 do begin A:=D.Item(I);if not A.Visible then Continue;case A.Kind of
lakRectangle:TLaserVectorBuilder.Rectangle(J,A.X,A.Y,A.Width,A.Height);
lakEllipse:TLaserVectorBuilder.Ellipse(J,A.X+A.Width/2,A.Y+A.Height/2,A.Width/2,A.Height/2);
lakImage:if FileExists(A.SourceFile)then begin B:=TBitmap.Create;try B.LoadFromFile(A.SourceFile);TLaserRaster.BitmapToJob(B,J,A.X,A.Y,A.Width,A.Threshold,False);finally B.Free;end;end;
end;end;end;
end.
