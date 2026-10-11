unit multicad_import;

{ MultiCAD - solido importado de arquivo STEP (fase 8, precisa do OpenCascade).

  Guarda o caminho do arquivo (relativo a pasta do .mcad quando possivel). O
  solido entra como corpo novo; as faces recebem "<nome>/f1", "<nome>/f2"...
  na ordem do arquivo e podem receber esbocos, cortes, filetes etc. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multicad_types, multicad_feature;

type
  TCadImportStep = class(TCadFeature)
  public
    FileName: string;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    { Caminho completo (relativo a ADocFile). }
    function ResolvedPath(const ADocFile: string): string;
  end;

implementation

constructor TCadImportStep.Create;
begin
  inherited Create;
  SetKind(cfImport);
end;

procedure TCadImportStep.SaveParams(O: TJSONObject);
begin
  O.Add('file', FileName);
end;

procedure TCadImportStep.LoadParams(O: TJSONObject);
begin
  FileName := JStr(O, 'file', '');
end;

function TCadImportStep.Validate: string;
begin
  if Trim(FileName) = '' then
    Result := 'Escolha o arquivo STEP'
  else
    Result := '';
end;

function TCadImportStep.ResolvedPath(const ADocFile: string): string;
begin
  Result := FileName;
  if (Result <> '') and (ExtractFileDrive(Result) = '') and (Copy(Result, 1, 1) <> PathDelim) and (ADocFile <> '') then
    Result := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(ADocFile)) + Result);
end;

initialization
  RegisterCadFeature(cfImport, TCadImportStep);

end.
