unit multicam_types;
{$mode objfpc}{$H+}
interface
type
 TCamPoint=record X,Y,Z:Double;end;
 TToolType=(ttFlatEndMill,ttBallNose,ttVBit,ttDrill);
 TCamOperation=(coProfileOutside,coProfileInside,coPocket,coDrill,coFacing,coEngrave,coRelief3D);
 TTool=record Name:string;ToolType:TToolType;Diameter,FluteLength:Double;SpindleRPM:Integer;Feed,Plunge:Double;end;
 TStock=record Width,Height,Thickness,OriginX,OriginY,TopZ:Double;end;
 TCamSettings=record SafeZ,StepDown,StepOver:Double;end;
 TPathMove=record P:TCamPoint;Rapid,SpindleOn:Boolean;end;
implementation
end.
