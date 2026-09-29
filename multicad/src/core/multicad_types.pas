unit multicad_types;
{$mode objfpc}{$H+}
interface
type
 TCadVec2=record X,Y:Double;end;
 TCadVec3=record X,Y,Z:Double;end;
 TCadFeatureKind=(cfSketch,cfExtrude,cfCut,cfHole,cfFillet,cfChamfer,cfPattern,cfBody);
 TSketchEntityKind=(seLine,seCircle,seArc,seRectangle);
 TConstraintKind=(ckHorizontal,ckVertical,ckCoincident,ckParallel,ckPerpendicular,ckEqual,ckDistance,ckRadius,ckAngle);
implementation
end.
