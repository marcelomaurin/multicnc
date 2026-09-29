unit multicam_cut_load;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types;
type TCutLoadModel=class public class function EstimateTorque(const Tool:TTool;DepthMM,FeedMMMin:Double):Double;static;end;
implementation
class function TCutLoadModel.EstimateTorque(const Tool:TTool;DepthMM,FeedMMMin:Double):Double;
begin if(DepthMM<=0)or(Tool.Diameter<=0)or(FeedMMMin<=0)then Exit(0);Result:=0.0000025*Tool.Diameter*DepthMM*FeedMMMin;end;
end.
