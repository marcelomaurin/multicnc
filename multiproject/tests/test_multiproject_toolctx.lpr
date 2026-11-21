program test_multiproject_toolctx;
{$mode objfpc}{$H+}
uses Interfaces, Classes, SysUtils, Forms, Controls, StdCtrls, LCLType,
  multisuite_context, multisuite_taskpanel, multicad_main, makepcb_main;
var CAD: TMainForm; PCB: TMakePCBForm; Root, Target, TaskFile: string;
    L: TStringList; Key: Word; I, Passed: Integer; HasSpec: Boolean;
procedure Check(B: Boolean; const Msg: string);
begin if not B then raise Exception.Create(Msg); Inc(Passed); end;
begin
  RequireDerivedFormResource:=False; Application.Initialize;
  Root:=IncludeTrailingPathDelimiter(GetTempDir(False))+'multiproject-toolctx-'+IntToStr(GetProcessID)+DirectorySeparator;
  ForceDirectories(Root); TaskFile:=Root+'tarefa.task.json';
  L:=TStringList.Create;
  try
    L.Text:='{"format":"MultiProject.Task","schema_version":1,"task":"T-0001","name":"Peca","tech_spec":{"text":"PETG","items":[]},"func_spec":[],"inputs":[]}';
    L.SaveToFile(TaskFile);
    CAD:=TMainForm.Create(nil);
    try
      Target:=Root+'nova peca.mcad'; CAD.SetNewTarget(Target);
      ShowSuiteTaskPanel(CAD,TaskFile); HasSpec:=False;
      for I:=0 to CAD.ComponentCount-1 do
        if CAD.Components[I] is TMemo then
          HasSpec:=HasSpec or (Pos('PETG',TMemo(CAD.Components[I]).Text)>0);
      Check(HasSpec,'painel CAD mostra especificacao');
      CAD.ActiveControl:=nil; Key:=VK_S; CAD.OnKeyDown(CAD,Key,[ssCtrl]);
      Check(FileExists(Target),'Ctrl+S CAD usa o caminho --new');
      try CAD.SetNewTarget(Target); Check(False,'CAD nao deve aceitar --new existente'); except on E: Exception do Check(Pos('existe',E.Message)>0,'CAD recusa existente'); end;
    finally CAD.Free; end;
    PCB:=TMakePCBForm.Create(nil);
    try
      Target:=Root+'nova placa.mpcb'; PCB.SetNewTarget(Target);
      ShowSuiteTaskPanel(PCB,TaskFile); HasSpec:=False;
      for I:=0 to PCB.ComponentCount-1 do
        if PCB.Components[I] is TMemo then
          HasSpec:=HasSpec or (Pos('PETG',TMemo(PCB.Components[I]).Text)>0);
      Check(HasSpec,'painel PCB mostra especificacao');
      Key:=VK_S; PCB.OnKeyDown(PCB,Key,[ssCtrl]);
      Check(FileExists(Target),'Ctrl+S PCB usa o caminho --new');
      try PCB.SetNewTarget(Target); Check(False,'PCB nao deve aceitar --new existente'); except on E: Exception do Check(Pos('existe',E.Message)>0,'PCB recusa existente'); end;
    finally PCB.Free; end;
    Writeln('PASS: ',Passed,' checks (CAD/PCB --new, Ctrl+S, painel de especificacao)');
  finally
    L.Free; DeleteFile(TaskFile); DeleteFile(Root+'nova peca.mcad'); DeleteFile(Root+'nova placa.mpcb'); RemoveDir(Root);
  end;
end.
