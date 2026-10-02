program test_workspace_validation;
{$mode objfpc}{$H+}
uses Classes, SysUtils, multisuite_types, multisuite_workspace;
var W, R: TWorkspace; A: TProjectArtifact; Lines: TStringList;
  Base, First, Moved, FN: string; Rejected: Boolean;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
procedure Reject(const Text: string);
begin
  Lines.Text := Text; Lines.SaveToFile(Base + '/invalid.msuite'); Rejected := False;
  try R.Load(Base + '/invalid.msuite'); except on E: EWorkspaceFormat do Rejected := True; end;
  Check(Rejected and (R.Project.Name = 'Projeto | 100%') and (R.ArtifactCount = 1),
    'invalid document preserves active project');
end;
begin
  Base := GetTempFileName(GetTempDir, 'msu'); DeleteFile(Base); ForceDirectories(Base);
  First := Base + '/first'; Moved := Base + '/moved'; ForceDirectories(First + '/cad');
  W := TWorkspace.Create; R := TWorkspace.Create; Lines := TStringList.Create;
  try
    W.NewProject('Projeto | 100%', First);
    A.Name := 'Peca | revisao'#10'2'; A.FileName := First + '/cad/peca.mcad';
    A.Kind := akCAD; A.Tool := stiMultiCAD;
    Lines.Text := 'fixture'; Lines.SaveToFile(A.FileName);
    W.AddArtifact(A); W.SetStage(wsAssembly, ssDone); FN := First + '/projeto.msuite'; W.Save(FN);
    Check(not W.Modified, 'save clears dirty state');
    R.Load(FN); Check((R.Project.Name = W.Project.Name) and (R.Artifact(0).Name = A.Name), 'escaped text roundtrip');
    Check(R.Artifact(0).FileName = 'cad' + DirectorySeparator + 'peca.mcad', 'internal file is relative');
    W.SetStage(wsExecution, ssBlocked); W.Save(FN); R.Load(FN);
    Check(R.Stage(wsExecution) = ssBlocked, 'save replaces an existing manifest');
    Check(RenameFile(First, Moved), 'move project directory');
    R.Load(Moved + '/projeto.msuite');
    Check((R.Project.RootPath = ExpandFileName(Moved)) and FileExists(R.ArtifactPath(0)), 'portable project resolves moved files');
    Reject('[project]'#10'name=invalid'#10'[workflow]'#10'999=0');
    Reject('[project]'#10'name=invalid'#10'[workflow]'#10'0=999');
    Reject('[project]'#10'name=invalid'#10'[artifacts]'#10'0|99|bad|file');
    Reject('[project]'#10'version=2'#10'name=bad%XX');
    Reject('[project]'#10'version=3'#10'name=future');
    Reject('[project]'#10'name=invalid'#10'[artifacts]'#10'broken');
    Lines.Text := '[project]'#10'name=Legacy 100%'#10'root=.'#10'[workflow]'#10'0=2'#10'[artifacts]'#10'0|0|old|cad/old.mcad';
    Lines.SaveToFile(Base + '/legacy.msuite'); R.Load(Base + '/legacy.msuite');
    Check((R.Project.Name = 'Legacy 100%') and (R.Stage(wsDesign) = ssDone) and
      (R.Stage(wsExecution) = ssPending), 'legacy load resets absent workflow stages');
    R.RemoveArtifact(0); Check(R.Modified and (R.ArtifactCount = 0), 'remove updates dirty state');
    Writeln('Workspace validation: OK (portable paths, escaped text, legacy, transactional load)');
  finally
    Lines.Free; R.Free; W.Free;
    DeleteFile(Moved + '/cad/peca.mcad'); RemoveDir(Moved + '/cad');
    DeleteFile(Moved + '/projeto.msuite'); RemoveDir(Moved);
    DeleteFile(Base + '/invalid.msuite'); DeleteFile(Base + '/legacy.msuite'); RemoveDir(Base);
  end;
end.
