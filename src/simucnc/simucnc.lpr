program simucnc;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, simuform;
var F: TMainForm; T: TextFile;
begin
  try
    Application.Initialize;
    Application.CreateForm(TMainForm, F);
    F.Caption := 'SimuCNC - Simulador de Impressora 3D Marlin';
    Application.Run;
  except
    on E: Exception do begin
      AssignFile(T, ExtractFilePath(ParamStr(0)) + 'simucnc-error.log');
      Rewrite(T); WriteLn(T, E.ClassName + ': ' + E.Message); CloseFile(T);
      Halt(1);
    end;
  end;
end.
