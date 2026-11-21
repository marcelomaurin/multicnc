unit multicad_skin;

{$mode objfpc}{$H+}

interface

uses SysUtils, Math, Classes, multicad_types, multicad_mesh, multicad_rig;

type
  TCadVertexBinding = record
    Bone0, Bone1: Integer;
    Weight0: Double;
  end;
  { Bind in the original mesh, then deform a copy. CAD solids stay unchanged. }
  TCadSkin = class
  private
    FSource: TCadMesh;
    FBindRig: TCadRig;
    FBindings: array of TCadVertexBinding;
  public
    constructor Create(Source: TCadMesh; Rig: TCadRig);
    destructor Destroy; override;
    function Pose(Rig: TCadRig): TCadMesh;
  end;

implementation

function DistanceToBone(const P: TCadVec3; const S: TCadRigSegment): Double;
var D: TCadVec3; T: Double;
begin
  D:=VSub(S.Tip,S.Pivot);
  T:=EnsureRange(VDot(VSub(P,S.Pivot),D)/Max(CAD_EPS,VDot(D,D)),0.0,1.0);
  Result:=VDist(P,VAdd(S.Pivot,VScale(D,T)));
end;

constructor TCadSkin.Create(Source: TCadMesh; Rig: TCadRig);
var I,J,K,B0,B1: Integer; D,D0,D1: Double; Parts: TStringList;
    Pins: array of Integer; Tr: TCadTri; Face: string;
begin
  inherited Create;
  Rig.Validate;
  FSource:=Source.Clone;
  FBindRig:=Rig.Clone;
  SetLength(FBindings,Source.VertCount);
  SetLength(Pins,Source.VertCount);
  for I:=0 to High(Pins) do Pins[I]:=-1;
  Parts:=TStringList.Create;
  try
    Parts.StrictDelimiter:=True; Parts.Delimiter:=';';
    for J:=0 to Rig.Count-1 do
    begin
      Parts.DelimitedText:=Rig[J].FacePrefixes;
      for I:=0 to Source.TriCount-1 do
      begin
        Tr:=Source.Tris[I]; Face:=Source.Faces[Tr.Face].Name;
        for K:=0 to Parts.Count-1 do
          if (Trim(Parts[K])<>'') and (Pos(Trim(Parts[K]),Face)=1) then
          begin
            { Explicit bindings take precedence over automatic weights. }
            if Pins[Tr.A]<0 then Pins[Tr.A]:=J;
            if Pins[Tr.B]<0 then Pins[Tr.B]:=J;
            if Pins[Tr.C]<0 then Pins[Tr.C]:=J;
          end;
      end;
    end;
    for I:=0 to Source.VertCount-1 do
    begin
      B0:=-1; B1:=-1; D0:=1e100; D1:=1e100;
      for J:=0 to Rig.Count-1 do
      begin
        { Segments pinned to named faces must not attract unrelated geometry. }
        if Trim(Rig[J].FacePrefixes)<>'' then Continue;
        D:=DistanceToBone(Source.Verts[I],Rig[J]);
        if D<D0 then begin D1:=D0; B1:=B0; D0:=D; B0:=J; end
        else if D<D1 then begin D1:=D; B1:=J; end;
      end;
      if Pins[I]>=0 then begin B0:=Pins[I]; B1:=-1; end;
      FBindings[I].Bone0:=B0; FBindings[I].Bone1:=B1;
      FBindings[I].Weight0:=1;
      if B1>=0 then
      begin
        { Blend only along a parent/child joint; never across opposite limbs. }
        if (Rig[B0].ParentID<>Rig[B1].ID) and (Rig[B1].ParentID<>Rig[B0].ID) then
          FBindings[I].Bone1:=-1
        else FBindings[I].Weight0:=Sqr(Max(D1,CAD_TOL))/(Sqr(Max(D0,CAD_TOL))+Sqr(Max(D1,CAD_TOL)));
      end;
    end;
  finally Parts.Free; end;
end;

destructor TCadSkin.Destroy;
begin FSource.Free; FBindRig.Free; inherited Destroy; end;

function TCadSkin.Pose(Rig: TCadRig): TCadMesh;
var I: Integer; M: TCadRigMatrices; B: TCadVertexBinding; P: TCadVec3;
begin
  if Rig.Count<>FBindRig.Count then raise Exception.Create('Reconstrua os vínculos após alterar o esqueleto.');
  for I:=0 to Rig.Count-1 do
    if (Rig[I].ID<>FBindRig[I].ID) or (Rig[I].ParentID<>FBindRig[I].ParentID) or
       (Rig[I].Axis<>FBindRig[I].Axis) or not VSame(Rig[I].Pivot,FBindRig[I].Pivot) or
       not VSame(Rig[I].Tip,FBindRig[I].Tip) or (Rig[I].FacePrefixes<>FBindRig[I].FacePrefixes) then
      raise Exception.Create('Reconstrua os vínculos após alterar o esqueleto.');
  M:=Rig.Matrices;
  Result:=FSource.Clone;
  try
    for I:=0 to FSource.VertCount-1 do
    begin
      B:=FBindings[I]; P:=FSource.Verts[I];
      if B.Bone0>=Length(M) then raise Exception.Create('Reconstrua os vínculos após alterar o esqueleto.');
      if B.Bone0>=0 then
      begin
        P:=MatPoint(M[B.Bone0],P);
        if B.Bone1>=0 then P:=VLerp(MatPoint(M[B.Bone1],FSource.Verts[I]),P,B.Weight0);
      end;
      Result.SetVert(I,P);
    end;
    Result.RefreshPlaneNormals;
  except Result.Free; raise; end;
end;

end.
