program test_blend_sequence;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Math, multicad_document, multicad_feature, multicad_blend,
  multicad_rebuild, multicad_mesh, multicad_csg, multicad_types;
var
  D, Reloaded: TCadDocument;
  RB, RR: TCadRebuilder;
  F: TCadFillet3D;
  Edges: TCadStrArray;
  E, Filename: string;
  V0, V2, V4, Expected: Double;
  I, Checks, Face: Integer;
  OpenMesh, ResultMesh: TCadMesh;
  Ops: TCadBoolOperands;
  T: TCadTri;
procedure Check(OK: Boolean; const Msg: string);
begin Inc(Checks); if not OK then raise Exception.Create(Msg); end;
procedure Solid(const Msg: string);
begin
  Check(RB.BodyCount=1,Msg+': one body');
  Check(RB.Body(0).Mesh.CheckClosed(E),Msg+': closed, oriented manifold: '+E);
  Check(CadMeshComponents(RB.Body(0).Mesh)=1,Msg+': connected solid');
end;
begin
  Checks:=0;
  D:=TCadDocument.Create;Reloaded:=TCadDocument.Create;RB:=nil;RR:=nil;
  try
    Check(D.LoadFromFile(ExtractFilePath(ParamStr(0))+'fixtures'+DirectorySeparator+'fillet-crossing-cuts.mcad',E),'Load regression fixture: '+E);
    F:=TCadFillet3D(D.Feature(D.Count-1));Edges:=Copy(F.Edges);
    Check(Length(Edges)=12,'Twelve selected edges from the 008 failure');
    RB:=TCadRebuilder.Create(D);F.Suppressed:=True;
    Check(RB.Rebuild=0,'Original two cuts rebuild');Solid('Before fillet');V0:=RB.TotalVolume;
    F.Suppressed:=False;
    Check(RB.Rebuild=0,'Twelve-edge R2 fillet rebuild: '+F.Message);Solid('Twelve-edge R2');V2:=RB.TotalVolume;
    Check((V2<V0-200) and (V2>V0-1000),'All fillets remove material while preserving the body');
    for I:=1 to 12 do begin
      Face:=RB.Body(0).Mesh.FaceIndex(F.Name+'/'+IntToStr(I));
      Check((Face>=0) and (RB.Body(0).Mesh.FaceTriCount(Face)>0) and
        (RB.Body(0).Mesh.FaceArea(Face)>0.01),'Persistent curved surface for fillet '+IntToStr(I));
    end;
    Check(RB.Rebuild=0,'Cached rebuild');
    Check(Abs(RB.TotalVolume-V2)<1E-7,'Cached volume unchanged');
    F.Edges:=Copy(Edges,0,4);
    Check(RB.Rebuild=0,'Four vertical fillets');Solid('Four vertical R2');V4:=RB.TotalVolume;
    Expected:=V0-4*26.9*4*(1-Pi/4);
    Check(Abs(V4-Expected)<0.01,'Four disjoint fillets match analytic removed volume');
    F.Edges:=Copy(Edges);
    for I:=0 to High(Edges) do F.Edges[I]:=Edges[High(Edges)-I];
    Check(RB.Rebuild=0,'Reverse edge order: '+F.Message);Solid('Reversed order');
    Check(Abs(RB.TotalVolume-V2)<0.05,'Volume independent of selected edge order');
    F.Edges:=Copy(Edges);F.Radius:=1;
    Check(RB.Rebuild=0,'R1 fillets');Solid('Twelve-edge R1');
    Check((RB.TotalVolume>V2) and (RB.TotalVolume<V0),'Smaller radius removes less material');
    F.Radius:=2;Check(RB.Rebuild=0,'Restore R2');
    Filename:=GetTempFileName(GetTempDir,'cad');
    try
      Check(D.SaveToFile(Filename,E),'Save fillet part: '+E);
      Check(Reloaded.LoadFromFile(Filename,E),'Reload fillet part: '+E);
      RR:=TCadRebuilder.Create(Reloaded);
      Check(RR.Rebuild=0,'Rebuild saved fillets');
      Check((RR.BodyCount=1) and RR.Body(0).Mesh.CheckClosed(E),'Saved part remains closed');
      Check(Abs(RR.TotalVolume-V2)<0.05,'Saved part preserves geometry');
    finally DeleteFile(Filename);end;
    F.Edges:=['edge:missing/a|missing/b'];
    Check((RB.Rebuild=1) and (F.State=fsError),'Missing edge still rejected');Solid('Failed operation retains original body');
    Check(Abs(RB.TotalVolume-V0)<0.01,'Failure does not partially modify the solid');
    OpenMesh:=TCadMesh.Create;
    try
      for I:=0 to RB.Body(0).Mesh.FaceCount-1 do OpenMesh.AddFace(RB.Body(0).Mesh.Faces[I]);
      for I:=0 to RB.Body(0).Mesh.VertCount-1 do OpenMesh.AddVertexRaw(RB.Body(0).Mesh.Verts[I]);
      for I:=1 to RB.Body(0).Mesh.TriCount-1 do begin T:=RB.Body(0).Mesh.Tris[I];OpenMesh.AddTri(T.A,T.B,T.C,T.Face);end;
      Ops:=nil;ResultMesh:=CadBooleanBlendSequence(OpenMesh,Ops,E);
      try Check((ResultMesh=nil) and (E<>''),'Open input cannot be accepted or silently patched');finally ResultMesh.Free;end;
      ResultMesh:=CadBooleanBlendSequence(RB.Body(0).Mesh,Ops,E);
      try Check((ResultMesh<>nil) and ResultMesh.CheckClosed(E),'Empty sequence preserves a valid body');finally ResultMesh.Free;end;
    finally OpenMesh.Free;end;
    Writeln('PASS: ',Checks,' checks; crossing cuts, twelve fillets, analytic volume, edge order, radius, persistence and invalid input');
  finally RR.Free;RB.Free;Reloaded.Free;D.Free;end;
end.
