unit multisuite_zcompensation;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multisuite_heightmap;
type
 TCompensatedPoint=record X,Y,NominalZ,SurfaceZ,CorrectedZ:Double;end;
 TZCompensator=class
 private FMap:THeightMap;FReferenceZ,FMaxCorrection:Double;
 public constructor Create(AMap:THeightMap);function Correct(X,Y,NominalZ:Double;out P:TCompensatedPoint):Boolean;
  property ReferenceZ:Double read FReferenceZ write FReferenceZ;
  property MaxCorrection:Double read FMaxCorrection write FMaxCorrection;
 end;
implementation
constructor TZCompensator.Create(AMap:THeightMap);begin FMap:=AMap;FReferenceZ:=0;FMaxCorrection:=1.0;end;
function TZCompensator.Correct(X,Y,NominalZ:Double;out P:TCompensatedPoint):Boolean;
var Surface,Delta:Double;
begin FillChar(P,SizeOf(P),0);P.X:=X;P.Y:=Y;P.NominalZ:=NominalZ;Result:=Assigned(FMap)and FMap.Interpolate(X,Y,Surface);if not Result then Exit;Delta:=Surface-FReferenceZ;if Abs(Delta)>FMaxCorrection then Exit(False);P.SurfaceZ:=Surface;P.CorrectedZ:=NominalZ+Delta;end;
end.
