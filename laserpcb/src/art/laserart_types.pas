unit laserart_types;
{$mode objfpc}{$H+}
interface
type TLaserArtKind=(lakText,lakVector,lakImage,lakRectangle,lakEllipse);
 TLaserArtMode=(lamEngrave,lamCut,lamScore);
 TLaserDither=(ldNone,ldThreshold,ldFloydSteinberg);
 TLaserArtItem=class
 public Name,SourceFile,Text,FontName:string;Kind:TLaserArtKind;Mode:TLaserArtMode;X,Y,Width,Height,Rotation,Scale:Double;Power,Feed:Double;Passes:Integer;Threshold:Byte;Dither:TLaserDither;Visible,Locked:Boolean;
 constructor Create;
 end;
implementation
constructor TLaserArtItem.Create;begin Visible:=True;Scale:=1;Power:=0;Feed:=0;Passes:=1;Threshold:=128;Dither:=ldThreshold;end;
end.
