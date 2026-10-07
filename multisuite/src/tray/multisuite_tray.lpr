program multisuite_tray;

{ MultiSuite Bandeja - icone ao lado do relogio que abre o painel vertical
  de ferramentas da suite. Ver multisuite_tray_form.pas. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Interfaces, Forms, multisuite_tray_form;

{$IFDEF WINDOWS}
var
  ShowEvent: THandle;
{$ENDIF}

{$R *.res}

begin
  {$IFDEF WINDOWS}
  { Uma unica instancia na bandeja. Se ja estiver rodando, pede para a
    instancia aberta mostrar o painel (antes saia calada e parecia travada). }
  CreateMutex(nil, True, TRAY_MUTEX_NAME);
  if GetLastError = ERROR_ALREADY_EXISTS then
  begin
    ShowEvent := OpenEvent(EVENT_MODIFY_STATE, False, TRAY_SHOW_EVENT_NAME);
    if ShowEvent <> 0 then
    begin
      SetEvent(ShowEvent);
      CloseHandle(ShowEvent);
    end;
    Halt(0);
  end;
  {$ENDIF}
  RequireDerivedFormResource := False;
  Application.Title := 'MultiSuite';
  Application.Initialize;
  Application.ShowMainForm := False;
  Application.CreateForm(TTrayForm, TrayForm);
  Application.Run;
end.
