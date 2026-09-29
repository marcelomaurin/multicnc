unit laserpcb_types;
{$mode objfpc}{$H+}
interface
type TPCBLayerSide=(lsTop,lsBottom);TLaserProcess=(lpMaskResist,lpDirectAblation,lpMarking);
 TLaserProfile=record Name:string;SpotMM,Power,Feed:Double;Passes:Integer;Process:TLaserProcess;end;
 TPathPoint=record X,Y:Double;LaserOn:Boolean;Power,Feed:Double;end;
implementation
end.