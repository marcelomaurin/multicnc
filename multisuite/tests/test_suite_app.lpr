program test_suite_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, ComCtrls,
  multisuite_main, multisuite_types;
var F: TMultiSuiteForm; Lines: TStringList; Base, FN: string; Raised: Boolean;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
  Application.Initialize;
  Base := GetTempFileName(GetTempDir, 'msu'); DeleteFile(Base); ForceDirectories(Base);
  FN := Base + '/projeto.msuite'; Lines := TStringList.Create; F := TMultiSuiteForm.Create(nil);
  try
    Check(not TButton(F.FindComponent('SaveProject')).Enabled, 'empty project controls');
    F.NewProject('Projeto integrado', Base);
    Lines.Text := 'G0 X10'; Lines.SaveToFile(Base + '/job.nc');
    F.AddArtifactFile(Base + '/job.nc', stiMultiCNC);
    Check((F.ProjectWorkspace.ArtifactCount = 1) and F.ProjectWorkspace.Modified, 'add real file');
    F.SaveProject(FN);
    Check(not F.ProjectWorkspace.Modified, 'saved project is clean');
    F.NewProject('Outro', Base); F.OpenProject(FN);
    Check((F.ProjectWorkspace.Project.Name = 'Projeto integrado') and
      (F.ProjectWorkspace.Artifact(0).Tool = stiMultiCNC), 'open restores artifact and responsible tool');
    Lines.Text := '[project]'#10'name=Broken'#10'[workflow]'#10'99=0';
    Lines.SaveToFile(Base + '/bad.msuite'); Raised := False;
    try F.OpenProject(Base + '/bad.msuite'); except on E: Exception do Raised := True; end;
    Check(Raised and (F.ProjectWorkspace.Project.Name = 'Projeto integrado'), 'invalid open preserves UI project');
    Check(TListBox(F.FindComponent('Tools')).Items.IndexOf('MultiPhysics') >= 0, 'MultiPhysics remains available');
    Check(TComboBox(F.FindComponent('RecentProjects')).Items.IndexOf(ExpandFileName(FN)) >= 0, 'recent projects reflect successful saves');
    F.Show; Application.ProcessMessages;
    Writeln('MultiSuite GUI: OK (new, save, open, artifacts, recent, Physics, invalid-file guard)');
  finally
    F.Free; Lines.Free; DeleteFile(FN); DeleteFile(Base + '/job.nc'); DeleteFile(Base + '/bad.msuite'); RemoveDir(Base);
  end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
