program makerouter;

{ MakeRouter - projeto e usinagem de madeira na CNC Router (em desenvolvimento).
  Versao provisoria: so a tela da suite, sem percursos nem G-code.
  Plano em makerouter/docs/TAREFA.md. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, SysUtils, Forms, makerouter_main, multisuite_context;

{$R *.res}

var
  F: TMakeRouterForm;
  C: TSuiteContext;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'MakeRouter';
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TMakeRouterForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  F.Show;
  Application.Run;
end.
