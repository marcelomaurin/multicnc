unit multiproject_taskctx;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpjson, multiproject_document;
function PJTaskContext(P: TPJProject; T: TPJTask; const ProjectFile, ArtifactFile: string): TJSONObject;
procedure PJWriteTaskContext(P: TPJProject; T: TPJTask; const ProjectFile, ArtifactFile: string);
implementation
uses multiproject_artifacts, multiproject_types;
function PJTaskContext(P: TPJProject; T: TPJTask; const ProjectFile, ArtifactFile: string): TJSONObject;
var A, Inputs, Criteria: TJSONArray; Spec, O: TJSONObject; I: Integer; Pred: TPJTask; Base: string;
begin
  Base := ExtractFilePath(ExpandFileName(ArtifactFile));
  Result := TJSONObject.Create;
  Result.Add('format', 'MultiProject.Task'); Result.Add('schema_version', 1);
  Result.Add('project', ExtractRelativePath(Base, ExpandFileName(ProjectFile)));
  Result.Add('task', T.Id); Result.Add('name', T.Name);
  Result.Add('short', T.ShortDesc); Result.Add('long', T.LongDesc);
  Spec := TJSONObject.Create; A := TJSONArray.Create;
  for I := 0 to High(T.TechItems) do
    A.Add(TJSONObject.Create(['key', T.TechItems[I].Key, 'value', T.TechItems[I].Value, 'unit', T.TechItems[I].UnitName]));
  Spec.Add('items', A); Spec.Add('text', T.TechText); Result.Add('tech_spec', Spec);
  Criteria := TJSONArray.Create;
  for I := 0 to High(T.FuncSpec) do
  begin
    O := TJSONObject.Create(['id', T.FuncSpec[I].Id, 'text', T.FuncSpec[I].Text,
      'state', CriterionStateName(T.FuncSpec[I].State), 'evidence', T.FuncSpec[I].Evidence]);
    Criteria.Add(O);
  end;
  Result.Add('func_spec', Criteria); Inputs := TJSONArray.Create;
  for I := 0 to P.LinkCount-1 do
    if P.Links[I].Artifact and (P.Links[I].ToId = T.Id) then
    begin
      Pred := P.FindTask(P.Links[I].FromId);
      if (Pred <> nil) and (Pred.Artifact.Path <> '') then
        Inputs.Add(ExtractRelativePath(Base, PJArtifactFile(Pred, ProjectFile)));
    end;
  Result.Add('inputs', Inputs);
end;
procedure PJWriteTaskContext(P: TPJProject; T: TPJTask; const ProjectFile, ArtifactFile: string);
var O: TJSONObject; L: TStringList;
begin
  O := PJTaskContext(P, T, ProjectFile, ArtifactFile); L := TStringList.Create;
  try L.Text := O.FormatJSON([], 2); L.SaveToFile(ArtifactFile + '.task.json');
  finally L.Free; O.Free; end;
end;
end.
