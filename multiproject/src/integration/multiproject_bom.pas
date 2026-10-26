unit multiproject_bom;

{ Material automatico pela lista de materiais do MultiAssembly (fase 7.5, PJ-$03).

  Le a montagem (.massembly) com TAssemblyProject e agrupa os componentes com
  TAssemblyBOM, o mesmo agrupamento do manual do MultiAssembly. Os
  componentes comprados viram recursos do tipo material (unidade "un", grupo
  "Compras") e entram na tarefa de compra com a quantidade da lista e a
  origem "bom". Pecas mecanicas e placas ficam de fora: sao fabricadas pela
  propria suite (MultiCAD e MakePCB).

  - So le o arquivo da montagem; nunca o altera.
  - Recurso ja cadastrado com o mesmo nome e reaproveitado e mantem o custo
    unitario; a quantidade e atualizada.
  - Tudo num unico passo de desfazer. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, multiproject_types, multiproject_document;

type
  TPJBOMResult = record
    Ok: Boolean;
    Added, Updated, Skipped: Integer;   // recursos novos, quantidades atualizadas, itens fabricados
    AssemblyFile: string;
    Message: string;
  end;

{ montagem (.massembly) vinculada a uma tarefa de montagem; '' = nenhuma }
function PJFindAssemblyFile(P: TPJProject; const AProjectFile: string): string;

{ lanca a lista de materiais na tarefa de compra }
function PJImportBOM(P: TPJProject; const APurchaseTaskId, AAssemblyFile: string): TPJBOMResult;

implementation

uses
  multiassembly_types, multiassembly_project, multiassembly_engineering;

function PJFindAssemblyFile(P: TPJProject; const AProjectFile: string): string;
var I: Integer; A: TPJTask; FN: string;
begin
  Result := '';
  for I := 0 to P.Count - 1 do
  begin
    A := P[I];
    if (A.Kind <> tkAssembly) or (A.State = tsCancelled) or (A.Artifact.Path = '') then Continue;
    FN := A.Artifact.Path;
    if (ExtractFileDrive(FN) = '') and not (FN[1] in ['/', '\']) then
    begin
      if AProjectFile = '' then Continue;
      FN := ExpandFileName(ExtractFilePath(ExpandFileName(AProjectFile)) + FN);
    end;
    if FileExists(FN) and SameText(ExtractFileExt(FN), '.massembly') then Exit(FN);
  end;
end;

function PJImportBOM(P: TPJProject; const APurchaseTaskId, AAssemblyFile: string): TPJBOMResult;
var
  T: TPJTask;
  Asm_: TAssemblyProject;
  Lines: TBOMLines;
  I: Integer;
  R: TPJResource;
  Err: string;
begin
  Result := Default(TPJBOMResult);
  Result.AssemblyFile := AAssemblyFile;
  T := P.FindTask(APurchaseTaskId);
  if T = nil then begin Result.Message := 'tarefa inexistente: ' + APurchaseTaskId; Exit; end;
  if T.Kind <> tkPurchase then
  begin
    Result.Message := T.Id + ' nao e uma tarefa de compra';
    Exit;
  end;
  if (AAssemblyFile = '') or not FileExists(AAssemblyFile) then
  begin
    Result.Message := 'Vincule a montagem do MultiAssembly (.massembly) para ler a lista de materiais';
    Exit;
  end;
  Asm_ := TAssemblyProject.Create;
  try
    try
      Asm_.LoadFromFile(AAssemblyFile);
      Lines := TAssemblyBOM.Build(Asm_);
    except
      on E: Exception do
      begin
        Result.Message := 'Nao foi possivel ler a montagem: ' + E.Message;
        Exit;
      end;
    end;
  finally
    Asm_.Free;
  end;
  if Length(Lines) = 0 then
  begin
    Result.Message := 'A montagem nao tem componentes';
    Exit;
  end;
  P.BeginChange('Lista de materiais do MultiAssembly');
  try
    for I := 0 to High(Lines) do
    begin
      if Lines[I].Kind in [ackMechanicalPart, ackPCB] then
      begin
        Inc(Result.Skipped);
        Continue;
      end;
      R := P.FindResource(Lines[I].Description);
      if (R <> nil) and (R.RType <> rtMaterial) then
      begin
        Result.Message := Format('"%s" ja existe como %s', [R.Name, ResourceTypeCaption(R.RType)]);
        Exit;
      end;
      if R = nil then
      begin
        R := P.AddResource(Lines[I].Description, rtMaterial);
        R.MaterialUnit := 'un';
        R.Group := 'Compras';
        Inc(Result.Added);
      end
      else
        Inc(Result.Updated);
      if not P.SetMaterialQuantity(T.Id, R.Id, Lines[I].Quantity, 'bom', Err) then
      begin
        Result.Message := Err;
        Exit;
      end;
    end;
    Result.Ok := True;
  finally
    P.EndChange;
    if not Result.Ok and (Result.Added + Result.Updated > 0) then P.Undo;
  end;
  if Result.Added + Result.Updated = 0 then
    Result.Message := 'Lista sem componentes comprados (so pecas e placas da suite)'
  else
    Result.Message := Format('%d itens da lista de materiais em %s (%d novos)',
      [Result.Added + Result.Updated, T.Id, Result.Added]);
  if Result.Skipped > 0 then
    Result.Message := Result.Message + Format('; %d fabricados pela suite ficaram de fora', [Result.Skipped]);
end;

end.
