unit laserpcb_transform;
{$mode objfpc}{$H+}
interface
uses laserpcb_types, laserpcb_layout;
type TLaserTransform = class
  public class function Apply(const P: TPathPoint; I: TLaserLayoutItem): TPathPoint;
end;
implementation
class function TLaserTransform.Apply(const P: TPathPoint; I: TLaserLayoutItem): TPathPoint;
begin
  Result := P;
  I.LocalToWorld(P.X, P.Y, Result.X, Result.Y);
end;
end.
