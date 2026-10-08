program test_makerouter_ui;

{ Teste da interface nativa do MakeRouter: exemplo, calculo, simulacao,
  validacao, exportacao e recusa de parametro invalido.

  test_makerouter_ui [--shots <pasta>]  grava capturas de cada etapa (PNG). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Classes, SysUtils, Forms, Graphics, makerouter_types, makerouter_project,
  makerouter_main, makerouter_view;

var
  Checks, Failures: Integer;
  F: TMakeRouterForm;
  ShotDir, Dir: string;
  Files, L: TStringList;
  I: Integer;
  Vol, Keep: Double;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Cond then
  begin
    Inc(Failures);
    Writeln('FALHA: ', Msg);
  end;
end;

procedure Pump;
var K: Integer;
begin
  for K := 0 to 20 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
end;

procedure Shot(const Name: string);
var B: TBitmap; P: TPortableNetworkGraphic;
begin
  if ShotDir = '' then Exit;
  Pump;
  B := F.GetFormImage;
  P := TPortableNetworkGraphic.Create;
  try
    P.Assign(B);
    P.SaveToFile(IncludeTrailingPathDelimiter(ShotDir) + Name + '.png');
  finally
    P.Free;
    B.Free;
  end;
end;

begin
  Checks := 0; Failures := 0; ShotDir := '';
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = '--shots' then ShotDir := ParamStr(I + 1);
  if ShotDir <> '' then ForceDirectories(ShotDir);
  RequireDerivedFormResource := False;
  Application.Initialize;
  Application.CreateForm(TMakeRouterForm, F);
  F.Show;
  Pump;
  Check(F.Project.ShapeCount = 0, 'comeca vazio');
  Shot('01_material_vazio');
  F.LoadExample;
  Check((F.Project.ShapeCount = 7) and (F.Project.ToolpathCount = 4), 'exemplo carregado');
  Check(F.CalculateAll = 0, 'percursos calculados');
  for I := 0 to F.Project.ToolpathCount - 1 do
    Check(not F.Project.Toolpaths[I].Dirty and (Length(F.Project.Toolpaths[I].Moves) > 0),
      'percurso calculado: ' + F.Project.Toolpaths[I].Name);
  F.ViewControl.FitMaterial;
  F.ShowStep(0); Shot('02_material');
  F.ViewControl.SelectOnly(F.Project.Shapes[1].Id);
  F.ShowStep(1); Shot('03_desenho');
  F.ShowStep(3); Shot('04_percursos');
  Vol := F.Simulate;
  Check(Vol > 50000, Format('simulacao removeu %.0f mm3', [Vol]));
  Check(F.ViewControl.Mode = vmSim, 'vista em modo simulacao');
  F.ShowStep(4); Shot('05_simulacao');
  Check(F.ValidateJob, 'trabalho valido');
  F.ShowStep(5); Shot('06_saida');
  Dir := GetTempDir + 'mr_ui_' + IntToStr(GetProcessID);
  Files := F.ExportTo(Dir);
  try
    Check(Files.Count = 4, 'exporta 4 programas');
    L := TStringList.Create;
    try
      for I := 0 to Files.Count - 1 do
      begin
        Check(FileExists(Files[I]), 'arquivo existe ' + ExtractFileName(Files[I]));
        L.LoadFromFile(Files[I]);
        Check((L.Count > 10) and (L[0] = '; MakeRouter -> MultiCNC (CNC Router)'), 'cabecalho ' + ExtractFileName(Files[I]));
        DeleteFile(Files[I]);
      end;
    finally
      L.Free;
    end;
  finally
    Files.Free;
    RemoveDir(Dir);
  end;
  { parametro invalido: profundidade muito alem da espessura }
  Keep := F.Project.Toolpaths[1].Depth;
  F.Project.Toolpaths[1].Depth := 99; F.Project.Toolpaths[1].Dirty := True;
  Check(not F.ValidateJob, 'profundidade invalida recusa');
  F.Project.Toolpaths[1].Depth := Keep; F.Project.Toolpaths[1].Dirty := True;
  Check(F.ValidateJob, 'volta a validar');
  F.Close;
  Pump;
  if Failures = 0 then
    Writeln(Format('PASS: %d checks (MakeRouter UI)', [Checks]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failures, Checks]));
    Halt(1);
  end;
end.
