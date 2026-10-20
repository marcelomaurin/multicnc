program multiproject;

{ MultiProject - gestao de projetos mecanicos e eletronicos da MultiSuite:
  objetivo, tarefas em grafo, cronograma (caminho critico) e vinculo de cada
  tarefa com a ferramenta da suite. Referencia funcional: Microsoft Project.

  Uso: multiproject [--project <pasta>] [--file <projeto.mproj>] | multiproject <projeto.mproj> }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, SysUtils, Forms, multiproject_main, multisuite_context;

{$R *.res}

var
  C: TSuiteContext;
  FN: string;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'MultiProject';
  Application.Initialize;
  C := ReadSuiteContext;
  FN := C.FileName;
  if (FN = '') and (ParamCount >= 1) and (Copy(ParamStr(1), 1, 2) <> '--') then
    FN := ExpandFileName(ParamStr(1));
  { CreateForm define Application.MainForm: fechar a janela encerra o processo }
  Application.CreateForm(TMultiProjectForm, MultiProjectForm);
  if (FN <> '') and FileExists(FN) then MultiProjectForm.OpenFile(FN);
  MultiProjectForm.Show;
  Application.Run;
end.
