program makepcb;

{ MakePCB - projeto de placas de circuito impresso do zero (estilo PCB
  Wizard), gerando Gerber + Excellon para o LaserPCB. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, SysUtils, Forms, makepcb_main, multisuite_context;

{$R *.res}

var
  F: TMakePCBForm;
  C: TSuiteContext;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'MakePCB';
  Application.Initialize;
  C := ReadSuiteContext;
  F := TMakePCBForm.Create(Application);
  if (C.FileName <> '') and FileExists(C.FileName) then F.OpenFile(C.FileName);
  F.Show;
  Application.Run;
end.
