program test_routerpcb_ui;

{ Teste da interface nativa do RouterPCB: abre a pasta do MakePCB, gera,
  valida, exporta, recusa parametro invalido e faz o fluxo de nivelamento
  (so a sondagem sem mapa; com mapa, todos os programas).

  test_routerpcb_ui [--shots <pasta>]  grava capturas de cada etapa (PNG). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Classes, SysUtils, Forms, Controls, StdCtrls, Graphics,
  laserpcb_roles, routerpcb_types, routerpcb_project, routerpcb_heightmap,
  routerpcb_gcode, routerpcb_main, multisuite_numfmt;

var
  Checks, Failures: Integer;
  F: TRouterPCBForm;
  ShotDir: string;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Cond then
  begin
    Inc(Failures);
    Writeln('FALHA: ', Msg);
  end;
end;

function FixtureDir: string;
var C: array[0..2] of string; I: Integer;
begin
  C[0] := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'astable_gerber';
  C[1] := 'fixtures' + PathDelim + 'astable_gerber';
  C[2] := 'routerpcb' + PathDelim + 'tests' + PathDelim + 'fixtures' + PathDelim + 'astable_gerber';
  for I := 0 to 2 do
    if DirectoryExists(C[I]) then Exit(ExpandFileName(C[I]));
  raise Exception.Create('fixture nao encontrado');
end;

procedure Pump;
var I: Integer;
begin
  for I := 0 to 20 do
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

function FindEdit(const Value: string): TEdit;
var I: Integer;
begin
  for I := 0 to F.ComponentCount - 1 do
    if (F.Components[I] is TEdit) and (TEdit(F.Components[I]).Text = Value) then
      Exit(TEdit(F.Components[I]));
  Result := nil;
end;

function FindCheck(const ACaption: string): TCheckBox;
var I: Integer;
begin
  for I := 0 to F.ComponentCount - 1 do
    if (F.Components[I] is TCheckBox) and (TCheckBox(F.Components[I]).Caption = ACaption) then
      Exit(TCheckBox(F.Components[I]));
  Result := nil;
end;

procedure Run;
var Dir: string; Files, Log: TStringList; E: TEdit; C: TCheckBox; I, K, J: Integer;
  HM: TRPHeightMap;
begin
  F := TRouterPCBForm.Create(Application);
  F.Show;
  Pump;
  Shot('routerpcb_00_vazio');
  F.OpenFile(FixtureDir);
  Pump;
  Check(F.Project.LayerCount = 4, 'quatro camadas importadas');
  Check(F.Project.DrillFiles.Count = 2, 'PTH e NPTH');
  Check(F.Project.Side = rsBottom, 'abre em Bottom');
  Check(F.Project.BoardMask <> nil, 'mascaras para a previa');
  Check(F.Preview.Zoom > 1, 'previa ajustada a placa');
  Shot('routerpcb_01_importar');
  Check(F.Prepare, 'gera e valida o exemplo: ' + F.Log.Lines.Text);
  Check(Length(F.Project.IsolationPaths) > 10, 'isolacao gerada');
  for I := 1 to 5 do
  begin
    F.FocusPage(I);
    Shot(Format('routerpcb_%.2d_etapa', [I + 1]));
  end;
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'routerpcb_ui_' + IntToStr(GetProcessID);
  Files := F.ExportTo(Dir);
  try
    Check(Files.Count = 4, 'quatro programas: ' + IntToStr(Files.Count));
    for I := 0 to Files.Count - 1 do Check(FileExists(Files[I]), 'arquivo gravado');
    Log := TStringList.Create;
    try
      Log.LoadFromFile(Files[0]);
      Check(Pos(RP_HEADER, Log[0]) = 1, 'cabecalho no arquivo');
    finally
      Log.Free;
    end;
    for I := 0 to Files.Count - 1 do DeleteFile(Files[I]);
  finally
    Files.Free;
  end;
  { parametro invalido: nada e gravado }
  E := FindEdit('-0.08');
  Check(E <> nil, 'campo da profundidade');
  if E <> nil then
  begin
    E.Text := '0.3';
    Pump;
    Check(not F.Prepare, 'profundidade positiva recusada');
    Files := nil;
    try
      Files := F.ExportTo(Dir);
      Check(False, 'exportou com erro');
    except
      Check(True, 'exportar com erro levanta excecao');
    end;
    Files.Free;
    E.Text := '-0.08';
  end;
  { nivelamento }
  C := FindCheck('Nivelar pela sondagem (autolevel)');
  Check(C <> nil, 'opcao de nivelamento');
  if C <> nil then
  begin
    C.Checked := True;
    Pump;
    Check(F.Prepare, 'valido com nivelamento ligado');
    Check(F.HeightMap.Ready, 'grade de sondagem criada');
    Files := F.ExportTo(Dir);
    try
      Check((Files.Count = 1) and (Pos('_0_sondagem', Files[0]) > 0), 'sem mapa so a sondagem');
      for I := 0 to Files.Count - 1 do DeleteFile(Files[I]);
    finally
      Files.Free;
    end;
    HM := F.HeightMap;
    Log := TStringList.Create;
    try
      for K := 0 to HM.Count - 1 do
      begin
        HM.ProbeOrder(K, I, J);
        Log.Add(Format('[PRB:%.3f,%.3f,%.4f:1]', [HM.PointX(I) - 10, HM.PointY(J) - 10,
          -3 + 0.002 * HM.PointY(J)], InvariantFS));
      end;
      Check(HM.LoadProbeLog(Log, F.Log.Lines) = HM.Count, 'mapa importado');
    finally
      Log.Free;
    end;
    F.FocusPage(4);
    Files := F.ExportTo(Dir);
    try
      Check(Files.Count = 5, 'com mapa: 5 programas');
      Shot('routerpcb_07_nivelamento');
      for I := 0 to Files.Count - 1 do DeleteFile(Files[I]);
    finally
      Files.Free;
    end;
  end;
  RemoveDir(Dir);
  F.Close;
  Pump;
end;

begin
  Checks := 0; Failures := 0;
  ShotDir := '';
  if (ParamCount >= 2) and (ParamStr(1) = '--shots') then
  begin
    ShotDir := ParamStr(2);
    ForceDirectories(ShotDir);
  end;
  RequireDerivedFormResource := False;
  Application.Initialize;
  try
    Run;
  except
    on Ex: Exception do
    begin
      Inc(Failures);
      Writeln('EXCECAO: ', Ex.ClassName, ': ', Ex.Message);
    end;
  end;
  if Failures = 0 then
    Writeln('PASS: ', Checks, ' checks (interface: importar, gerar, validar, exportar, erro, nivelamento)')
  else
  begin
    Writeln('FAIL: ', Failures, ' de ', Checks);
    Halt(1);
  end;
end.
