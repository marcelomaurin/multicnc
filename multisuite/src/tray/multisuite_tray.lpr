program multisuite_tray;

{ MultiSuite Bandeja - icone ao lado do relogio que abre o painel vertical
  de ferramentas da suite. Ver multisuite_tray_form.pas. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Interfaces, Forms, multisuite_tray_form;

{$R *.res}

begin
  {$IFDEF WINDOWS}
  { Uma unica instancia na bandeja }
  CreateMutex(nil, True, 'Maurinsoft.MultiSuite.Tray');
  if GetLastError = ERROR_ALREADY_EXISTS then
    Halt(0);
  {$ENDIF}
  RequireDerivedFormResource := False;
  Application.Title := 'MultiSuite';
  Application.Initialize;
  Application.ShowMainForm := False;
  Application.CreateForm(TTrayForm, TrayForm);
  Application.Run;
end.
