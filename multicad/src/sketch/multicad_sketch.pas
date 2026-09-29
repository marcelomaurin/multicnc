unit multicad_sketch;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multicad_types,multicad_feature;
type
 TSketchEntity=record Kind:TSketchEntityKind;P1,P2:TCadVec2;Radius:Double;Construction:Boolean;end;
 TSketchConstraint=record Kind:TConstraintKind;EntityA,EntityB:Integer;Value:Double;Driving:Boolean;end;
 TCadSketch=class(TCadFeature)
 private FEntities:array of TSketchEntity;FConstraints:array of TSketchConstraint;
 public Plane:string;constructor Create(const AName:string);
  function AddLine(X1,Y1,X2,Y2:Double):Integer;function AddCircle(X,Y,R:Double):Integer;function AddRectangle(X1,Y1,X2,Y2:Double):Integer;
  function AddConstraint(AKind:TConstraintKind;A,B:Integer;Value:Double):Integer;
  function EntityCount:Integer;function ConstraintCount:Integer;function Entity(I:Integer):TSketchEntity;
 end;
implementation
constructor TCadSketch.Create(const AName:string);begin inherited Create(cfSketch,AName);Plane:='XY';end;
function TCadSketch.AddLine(X1,Y1,X2,Y2:Double):Integer;var E:TSketchEntity;begin E.Kind:=seLine;E.P1.X:=X1;E.P1.Y:=Y1;E.P2.X:=X2;E.P2.Y:=Y2;Result:=Length(FEntities);SetLength(FEntities,Result+1);FEntities[Result]:=E;end;
function TCadSketch.AddCircle(X,Y,R:Double):Integer;var E:TSketchEntity;begin E.Kind:=seCircle;E.P1.X:=X;E.P1.Y:=Y;E.Radius:=R;Result:=Length(FEntities);SetLength(FEntities,Result+1);FEntities[Result]:=E;end;
function TCadSketch.AddRectangle(X1,Y1,X2,Y2:Double):Integer;begin Result:=AddLine(X1,Y1,X2,Y1);AddLine(X2,Y1,X2,Y2);AddLine(X2,Y2,X1,Y2);AddLine(X1,Y2,X1,Y1);end;
function TCadSketch.AddConstraint(AKind:TConstraintKind;A,B:Integer;Value:Double):Integer;var C:TSketchConstraint;begin C.Kind:=AKind;C.EntityA:=A;C.EntityB:=B;C.Value:=Value;C.Driving:=True;Result:=Length(FConstraints);SetLength(FConstraints,Result+1);FConstraints[Result]:=C;end;
function TCadSketch.EntityCount:Integer;begin Result:=Length(FEntities);end;
function TCadSketch.ConstraintCount:Integer;begin Result:=Length(FConstraints);end;
function TCadSketch.Entity(I:Integer):TSketchEntity;begin Result:=FEntities[I];end;
end.
