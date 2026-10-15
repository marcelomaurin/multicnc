program multiassembly;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, SysUtils, Forms, multiassembly_main, multisuite_context;

{$R *.res}

var
  F: TMultiAssemblyForm;
  C: TSuiteContext;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'MultiAssembly';
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TMultiAssemblyForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  F.Hint := 'Projeto: ' + C.ProjectRoot + ' | Arquivo: ' + C.FileName;
  F.ShowHint := True;
  F.Show;
  Application.Run;
end.
