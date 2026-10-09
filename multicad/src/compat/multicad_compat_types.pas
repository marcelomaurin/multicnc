unit multicad_compat_types;
{$mode objfpc}{$H+}
interface
type
 TCadVec2=record X,Y:Double;end;
 TCadVec3=record X,Y,Z:Double;end;
 TCadFeatureKind=(cfSketch,cfExtrude,cfCut,cfHole,cfFillet,cfChamfer,cfPattern,cfBody);
 TSketchEntityKind=(seLine,seCircle,seArc,seRectangle);
 { ckFixed: fixa o ponto P1 (ou centro) da entidade na posicao atual -
   ancora o sketch no plano (remove translacao). }
 TConstraintKind=(ckHorizontal,ckVertical,ckCoincident,ckParallel,ckPerpendicular,ckEqual,ckDistance,ckRadius,ckAngle,ckFixed);
implementation
end.
