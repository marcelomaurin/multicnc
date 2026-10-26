unit multiproject_estimates;

{ Estimativa automatica da duracao da fabricacao (fase 7.6, PJ-L08).

  - G-code do MultiSlicer: o cabecalho "; MS-PRINT: TIME=.. FILAMENT_G=.."
    (lido por SuiteParseHeader) da o tempo e a massa de filamento; o
    "; MS-MATERIAL:" diz o filamento.
  - Outro G-code (router, laser, placa): o planejador do Grbl de
    multicnc_gcode_preflight calcula o tempo com o volume de trabalho da
    maquina atribuida (cadastro do MultiCNC, somente leitura). Sem maquina,
    usa um envelope generico e avisa.
  - Documento da ferramenta (.mslice, .lart, .mrouter): procura o G-code de
    mesmo nome na mesma pasta.

  O resultado e uma SUGESTAO com origem e data (TPJEstimate). Nada muda no
  plano ate o usuario aceitar (TPJProject.AcceptEstimate). O MultiProject
  nunca envia nada a maquina. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, multiproject_types, multiproject_document;

type
  TPJEstimateResult = record
    Ok: Boolean;
    Estimate: TPJEstimate;
    Message: string;
  end;

{ G-code que acompanha o arquivo (o proprio, ou o de mesmo nome) }
function PJFindGCodeFor(const FileName: string): string;

{ estima um G-code; WorkX/Y/Z = volume da maquina (0 = generico) }
function PJEstimateGCode(K: TPJTaskKind; const FileName: string;
  WorkX, WorkY, WorkZ: Double; const AMachine: string): TPJEstimateResult;

{ estima a tarefa pelo arquivo vinculado; nao altera o documento.
  AEquipmentFile = '' usa o multicnc.json padrao. }
function PJEstimateTask(P: TPJProject; const ATaskId, AProjectFile: string;
  const AEquipmentFile: string = ''): TPJEstimateResult;

function PJEstimateCaption(const E: TPJEstimate): string;

implementation

uses
  Math, multisuite_gcode_writer, multicnc_gcode_preflight, multicnc_types,
  multicnc_equipment, multiproject_kinds;

const
  GENERIC_SIZE_XY = 1000;     // mm, so para o tempo (o MultiCNC confere os limites)
  GENERIC_SIZE_Z = 300;

function NowISO: string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now);
end;

function PJFindGCodeFor(const FileName: string): string;
var Base: string; E: string;
begin
  Result := '';
  if FileName = '' then Exit;
  if PJIsGCode(FileName) then
  begin
    if FileExists(FileName) then Result := FileName;
    Exit;
  end;
  Base := ChangeFileExt(FileName, '');
  for E in ['.gcode', '.nc', '.tap'] do
    if FileExists(Base + E) then Exit(Base + E);
end;

function Minutes(Seconds: Double): Int64;
begin
  if Seconds <= 0 then Exit(0);
  Result := Max(Int64(1), Ceil(Seconds / 60));
end;

function PJEstimateGCode(K: TPJTaskKind; const FileName: string;
  WorkX, WorkY, WorkZ: Double; const AMachine: string): TPJEstimateResult;
var
  L, Warn: TStringList;
  H: TSuiteGCodeHeader;
  B: TSuiteBounds;
  HasHeader: Boolean;
  Env: TMachineEnvelope;
  Rep: TGCodeReport;
begin
  Result.Ok := False;
  Result.Estimate := Default(TPJEstimate);
  Result.Message := '';
  if not FileExists(FileName) then
  begin
    Result.Message := 'G-code nao encontrado: ' + ExtractFileName(FileName);
    Exit;
  end;
  Result.Estimate.Date := NowISO;
  Result.Estimate.Machine := AMachine;
  L := TStringList.Create;
  Warn := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
      if L.Count = 0 then begin Result.Message := 'G-code vazio'; Exit; end;
      H := Default(TSuiteGCodeHeader);
      HasHeader := SuiteParseHeader(L, H, B);
      { impressao: o MultiSlicer ja calculou tempo e filamento }
      if HasHeader and (H.Machine = 'printer3d') and (H.PrintSeconds > 0) then
      begin
        Result.Estimate.Minutes := Minutes(H.PrintSeconds);
        Result.Estimate.MassG := Max(0, H.FilamentG);
        Result.Estimate.Material := H.Material;
        Result.Estimate.Source := 'multislicer';
        if H.Printer <> '' then Result.Estimate.Machine := H.Printer;
        Result.Estimate.Note := Format('%d camadas', [Round(H.Layers)]);
        Result.Ok := True;
        Result.Message := Format('MultiSlicer: %s e %.0f g de filamento',
          [FormatDuration(H.PrintSeconds), Result.Estimate.MassG]);
        Exit;
      end;
      if K = tkPrint3D then
        Result.Estimate.Note := 'sem MS-PRINT do MultiSlicer: tempo pelo planejador do Grbl';
      { router, laser e placa: planejador do Grbl }
      if (WorkX <= 0) or (WorkY <= 0) then
      begin
        Env := DefaultEnvelope(GENERIC_SIZE_XY, GENERIC_SIZE_XY, GENERIC_SIZE_Z);
        if Result.Estimate.Note = '' then
          Result.Estimate.Note := 'sem maquina atribuida: aceleracao e avanco genericos';
      end
      else
        Env := DefaultEnvelope(WorkX, WorkY, Max(WorkZ, 1));
      Env.RequireSpindleForCut := False;     // so o tempo interessa aqui
      Rep := TGCodeAnalyzer.Analyze(L, Env, Warn);
      if Rep.Motions = 0 then
      begin
        Result.Message := 'G-code sem movimentos';
        Exit;
      end;
      Result.Estimate.Minutes := Minutes(Rep.EstimatedSeconds);
      if Result.Estimate.Minutes = 0 then
      begin
        Result.Message := 'G-code sem tempo de execucao';
        Exit;
      end;
      Result.Estimate.Source := 'gcode';
      if Rep.Incomplete or Rep.LimitReached then
        Result.Estimate.Note := Trim(Result.Estimate.Note + ' analise parcial');
      Result.Ok := True;
      Result.Message := Format('G-code: %s (%d movimentos, corte de %.0f mm)',
        [FormatDuration(Rep.EstimatedSeconds), Rep.Motions, Rep.CutLength]);
    except
      on E: Exception do
      begin
        Result.Ok := False;
        Result.Message := 'Nao foi possivel estimar: ' + E.Message;
      end;
    end;
  finally
    Warn.Free;
    L.Free;
  end;
end;

{ volume da primeira maquina atribuida, pelo cadastro do MultiCNC }
procedure MachineOf(P: TPJProject; const ATaskId, AEquipmentFile: string;
  out Name: string; out X, Y, Z: Double);
var
  A, I: Integer;
  R: TPJResource;
  Store: TEquipmentStore;
  FileName: string;
  E: TEquipmentProfile;
begin
  Name := ''; X := 0; Y := 0; Z := 0;
  R := nil;
  for A in P.AssignmentsOfTask(ATaskId) do
  begin
    R := P.FindResource(P.Assignments[A].ResourceId);
    if (R <> nil) and (R.RType = rtMachine) then Break;
    R := nil;
  end;
  if R = nil then Exit;
  Name := R.Name;
  if AEquipmentFile <> '' then FileName := AEquipmentFile else FileName := EquipmentFileName;
  if not FileExists(FileName) then Exit;
  Store := TEquipmentStore.Create(FileName);
  try
    try
      Store.Load;
    except
      Exit;
    end;
    for I := 0 to Store.Count - 1 do
    begin
      E := Store.Item(I);
      if SameText(E.Name, R.Equipment) or SameText(E.Name, R.Name) then
      begin
        X := E.WorkX; Y := E.WorkY; Z := E.WorkZ;
        Exit;
      end;
    end;
  finally
    Store.Free;
  end;
end;

function PJEstimateTask(P: TPJProject; const ATaskId, AProjectFile: string;
  const AEquipmentFile: string): TPJEstimateResult;
var
  T: TPJTask;
  Doc, GCode, Machine: string;
  X, Y, Z: Double;
begin
  Result.Ok := False;
  Result.Estimate := Default(TPJEstimate);
  T := P.FindTask(ATaskId);
  if T = nil then begin Result.Message := 'tarefa inexistente: ' + ATaskId; Exit; end;
  if not PJKindInfo(T.Kind).Fabrication then
  begin
    Result.Message := 'Estimativa so para impressao, router, laser e placa';
    Exit;
  end;
  if T.Artifact.Path = '' then
  begin
    Result.Message := 'Vincule o arquivo da fabricacao (G-code ou documento da ferramenta)';
    Exit;
  end;
  Doc := T.Artifact.Path;
  if (ExtractFileDrive(Doc) = '') and not (Doc[1] in ['/', '\']) then
    Doc := ExpandFileName(ExtractFilePath(ExpandFileName(AProjectFile)) + Doc);
  GCode := PJFindGCodeFor(Doc);
  if GCode = '' then
  begin
    Result.Message := 'Gere o G-code na ferramenta: nenhum .gcode junto de ' + ExtractFileName(Doc);
    Exit;
  end;
  MachineOf(P, ATaskId, AEquipmentFile, Machine, X, Y, Z);
  Result := PJEstimateGCode(T.Kind, GCode, X, Y, Z, Machine);
  if Result.Ok then
    Result.Estimate.FileName := ExtractRelativePath(
      ExtractFilePath(ExpandFileName(AProjectFile)), ExpandFileName(GCode));
end;

function HoursText(AMinutes: Int64): string;
begin
  if AMinutes < 60 then Result := IntToStr(AMinutes) + 'min'
  else if AMinutes mod 60 = 0 then Result := IntToStr(AMinutes div 60) + 'h'
  else Result := Format('%dh%.2d', [AMinutes div 60, AMinutes mod 60]);
end;

function PJEstimateCaption(const E: TPJEstimate): string;
var Src: string;
begin
  if E.Minutes <= 0 then Exit('Sem estimativa');
  if E.Source = 'multislicer' then Src := 'MultiSlicer'
  else if E.Source = 'gcode' then Src := 'G-code'
  else Src := E.Source;
  Result := Format('%s: %s', [Src, HoursText(E.Minutes)]);
  if E.MassG > 0 then Result := Result + Format(', %.0f g', [E.MassG]);
  if E.Material <> '' then Result := Result + ' ' + E.Material;
  if E.Machine <> '' then Result := Result + ' (' + E.Machine + ')';
  if E.Date <> '' then Result := Result + ' em ' + Copy(E.Date, 9, 2) + '/' + Copy(E.Date, 6, 2);
  if E.Note <> '' then Result := Result + ' - ' + E.Note;
end;

end.
