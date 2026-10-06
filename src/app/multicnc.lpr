program multicnc;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, mainform, multisuite_context;

{$R *.res}

var F: TMainForm; C: TSuiteContext;
begin
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TMainForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  F.Hint := 'Projeto: ' + C.ProjectRoot + ' | Arquivo: ' + C.FileName;
  F.ShowHint := True;
  { --file vindo da suite (ex.: LaserArt "Enviar ao MultiCNC") }
  if (C.FileName <> '') and FileExists(C.FileName) then
    F.OpenProgramFile(C.FileName)
  else if (ParamCount >= 1) and (Copy(ParamStr(1), 1, 1) <> '-') and FileExists(ParamStr(1)) then
    F.OpenProgramFile(ParamStr(1));
  Application.Run;
end.
