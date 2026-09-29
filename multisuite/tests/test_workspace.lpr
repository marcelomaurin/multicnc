program test_workspace;
{$mode objfpc}{$H+}
uses SysUtils,multisuite_types,multisuite_workspace;
var W,W2:TWorkspace;A:TProjectArtifact;FN:string;
begin W:=TWorkspace.Create;W2:=TWorkspace.Create;try W.NewProject('CNC Demo','demo_project');A.Name:='Estrutura';A.FileName:='cad/estrutura.mcad';A.Kind:=akCAD;A.Tool:=stiMultiCAD;W.AddArtifact(A);A.Name:='Montagem';A.FileName:='assembly/cnc.massembly';A.Kind:=akAssembly;A.Tool:=stiMultiAssembly;W.AddArtifact(A);W.SetStage(wsDesign,ssDone);W.SetStage(wsAssembly,ssReady);FN:='workspace_test.msuite';W.Save(FN);W2.Load(FN);if W2.ArtifactCount<>2 then Halt(1);if W2.Stage(wsDesign)<>ssDone then Halt(2);if W2.Project.Name<>'CNC Demo'then Halt(3);DeleteFile(FN);Writeln('MultiSuite workspace: OK');finally W2.Free;W.Free;end;end.
