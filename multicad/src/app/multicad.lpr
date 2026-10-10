program multicad;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, multicad_main, multisuite_context;

{$R *.res}

var
  F: TMainForm;
  C: TSuiteContext;
begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Initialize;
  C := ReadSuiteContext;
  F := TMainForm.Create(Application);
  F.Hint := 'Projeto: ' + C.ProjectRoot;
  F.Show;
  Application.ProcessMessages;
  if (C.FileName <> '') and FileExists(C.FileName) and
    SameText(ExtractFileExt(C.FileName), '.mcad') then
    F.OpenFile(C.FileName);
  Application.Run;
end.
