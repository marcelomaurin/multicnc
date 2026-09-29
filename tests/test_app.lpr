program test_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, SysUtils, mainform;
var F: TMainForm; I: Integer; ConnectButton, StartButton, JogZ: TButton;
begin
  Application.Initialize;
  F := TMainForm.Create(nil);
  try
    ConnectButton := nil; StartButton := nil; JogZ := nil;
    for I := 0 to F.ComponentCount - 1 do
      if F.Components[I] is TButton then
        with TButton(F.Components[I]) do begin
          if Caption = 'Conectar simulador' then ConnectButton := TButton(F.Components[I]);
          if Caption = 'Iniciar' then StartButton := TButton(F.Components[I]);
          if Caption = 'Z +' then JogZ := TButton(F.Components[I]);
        end;
    if not Assigned(ConnectButton) or not Assigned(StartButton) or not Assigned(JogZ) then Halt(1);
    if StartButton.Enabled or JogZ.Enabled then Halt(2);
    ConnectButton.Click;
    if not JogZ.Enabled or StartButton.Enabled then Halt(3);
    ConnectButton.Click;
    if JogZ.Enabled then Halt(4);
    WriteLn('MultiCNC GUI: OK (creation, connection, control availability)');
  finally
    F.Free;
  end;
end.
