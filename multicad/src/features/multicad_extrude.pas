unit multicad_extrude;
{$mode objfpc}{$H+}
interface
uses multicad_types,multicad_feature;
type TCadExtrude=class(TCadFeature)
 public SketchID:string;Depth:Double;Symmetric,Reverse:Boolean;
  constructor Create(const AName,ASketchID:string;ADepth:Double;IsCut:Boolean);
 end;
implementation
constructor TCadExtrude.Create(const AName,ASketchID:string;ADepth:Double;IsCut:Boolean);
begin if IsCut then inherited Create(cfCut,AName) else inherited Create(cfExtrude,AName);SketchID:=ASketchID;Depth:=ADepth;end;
end.
