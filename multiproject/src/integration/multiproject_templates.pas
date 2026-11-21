unit multiproject_templates;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, multiproject_document;
procedure PJCreateFromTemplate(P, Template: TPJProject);
implementation
uses fpjson, Math, multiproject_types, multiproject_json;
procedure PJCreateFromTemplate(P, Template: TPJProject);
var Q: TPJProject; OldIDs, NewIDs: TStringList; I,J,N: Integer; T: TPJTask; O: TJSONObject; G: TGUID;
  function Remap(const Id: string): string;
  var K: Integer;
  begin K:=OldIDs.IndexOf(Id); if K<0 then Result:=Id else Result:=NewIDs[K]; end;
begin
  Q:=TPJProject.Create; OldIDs:=TStringList.Create; NewIDs:=TStringList.Create;
  try
    ProjectFromJSONText(Q,ProjectToJSONText(Template));
    Q.NextNumber:=Max(P.NextNumber,Q.NextNumber);
    for I:=0 to Q.Count-1 do
    begin OldIDs.Add(Q[I].Id); NewIDs.Add(Q.NewTaskId(Q[I].Kind)); end;
    for I:=0 to Q.Count-1 do
    begin
      T:=Q[I]; T.Id:=NewIDs[I]; T.State:=tsPlanned;
      T.Artifact:=Default(TPJArtifact); T.Artifact.Status:='none'; T.Artifact.Size:=-1; T.Artifact.MTime:=-1;
      T.LevelStart:=0; T.ManualStart:=0; T.ManualFinish:=0;
      T.Origin.Scope:=Remap(T.Origin.Scope);
      for J:=0 to High(T.Origin.Sources) do T.Origin.Sources[J]:=Remap(T.Origin.Sources[J]);
      for J:=0 to High(T.FuncSpec) do
      begin T.FuncSpec[J].State:=csPending; T.FuncSpec[J].Evidence:=''; end;
      if T.Raw<>nil then
      begin N:=T.Raw.IndexOfName('progress'); if N>=0 then T.Raw.Delete(N); end;
    end;
    for I:=0 to Q.LinkCount-1 do
    begin Q.Links[I].FromId:=Remap(Q.Links[I].FromId); Q.Links[I].ToId:=Remap(Q.Links[I].ToId); end;
    for I:=0 to Q.AssignmentCount-1 do Q.Assignments[I].TaskId:=Remap(Q.Assignments[I].TaskId);
    for I:=0 to High(Q.ObjectiveSuccess) do
    begin Q.ObjectiveSuccess[I].State:=csPending; Q.ObjectiveSuccess[I].Evidence:=''; end;
    CreateGUID(G); Q.Id:='P-'+GUIDToString(G); Q.Revision:='A'; Q.StatusDate:=0;
    Q.StartDate:=Date+EncodeTime(8,0,0,0);
    O:=ProjectToJSON(Q);
    try
      P.BeginChange('Criar de modelo');
      try ProjectFromJSON(P,O); finally P.EndChange; end;
    finally O.Free; end;
  finally NewIDs.Free; OldIDs.Free; Q.Free; end;
end;
end.
