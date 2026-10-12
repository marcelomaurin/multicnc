unit multislicer_userdata;

{ MultiSlicer - pasta de dados do usuario (perfis de impressora e material).

  Os perfis prontos ficam no codigo (multislicer_printers/materials); os
  perfis criados pelo usuario ficam em JSON, um arquivo por perfil:
    <pasta>/printers/<nome>.json
    <pasta>/materials/<nome>.json
    <pasta>/multislicer.json      (ultima impressora e material escolhidos)

  <pasta> = GetAppConfigDir(False) (no Windows, %LOCALAPPDATA%\multislicer).
  A variavel de ambiente MULTISLICER_PROFILE_DIR troca a pasta (testes,
  instalacao portatil). }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, fpjson, jsonparser;

var
  { quando preenchida, substitui a pasta (testes) }
  SlicerDataDirOverride: string = '';

function SlicerDataDir: string;
function SlicerDataSubDir(const Sub: string): string;
function SafeProfileFileName(const AName: string): string;
function LoadJSONObject(const FN: string): TJSONObject;
procedure SaveJSONObject(const FN: string; O: TJSONObject);
function JStr(O: TJSONObject; const Key, Def: string): string;
function JFloat(O: TJSONObject; const Key: string; Def: Double): Double;
function JInt(O: TJSONObject; const Key: string; Def: Integer): Integer;
function JBool(O: TJSONObject; const Key: string; Def: Boolean): Boolean;
function ReadLastChoice(const Key: string): string;
procedure WriteLastChoice(const Key, Value: string);

implementation

function SlicerDataDir: string;
begin
  Result := SlicerDataDirOverride;
  if Result = '' then Result := GetEnvironmentVariable('MULTISLICER_PROFILE_DIR');
  if Result = '' then Result := GetAppConfigDir(False);
  Result := IncludeTrailingPathDelimiter(Result);
end;

function SlicerDataSubDir(const Sub: string): string;
begin
  Result := IncludeTrailingPathDelimiter(SlicerDataDir + Sub);
end;

function SafeProfileFileName(const AName: string): string;
var I: Integer; C: Char;
begin
  Result := '';
  for I := 1 to Length(AName) do
  begin
    C := AName[I];
    if C in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', ' '] then Result := Result + C
    else Result := Result + '_';
  end;
  Result := Trim(Result);
  if Result = '' then Result := 'perfil';
  Result := Result + '.json';
end;

function LoadJSONObject(const FN: string): TJSONObject;
var S: TStringList; D: TJSONData;
begin
  Result := nil;
  if not FileExists(FN) then Exit;
  S := TStringList.Create;
  try
    S.LoadFromFile(FN);
    try
      D := GetJSON(S.Text);
    except
      Exit;
    end;
    if D is TJSONObject then Result := TJSONObject(D)
    else D.Free;
  finally
    S.Free;
  end;
end;

procedure SaveJSONObject(const FN: string; O: TJSONObject);
var S: TStringList;
begin
  ForceDirectories(ExtractFileDir(FN));
  S := TStringList.Create;
  try
    S.Text := O.FormatJSON;
    S.SaveToFile(FN);
  finally
    S.Free;
  end;
end;

function JStr(O: TJSONObject; const Key, Def: string): string;
var D: TJSONData;
begin
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType = jtString) then Result := D.AsString else Result := Def;
end;

function JFloat(O: TJSONObject; const Key: string; Def: Double): Double;
var D: TJSONData;
begin
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType = jtNumber) then Result := D.AsFloat else Result := Def;
end;

function JInt(O: TJSONObject; const Key: string; Def: Integer): Integer;
var D: TJSONData;
begin
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType = jtNumber) then Result := Round(D.AsFloat) else Result := Def;
end;

function JBool(O: TJSONObject; const Key: string; Def: Boolean): Boolean;
var D: TJSONData;
begin
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType = jtBoolean) then Result := D.AsBoolean else Result := Def;
end;

function ReadLastChoice(const Key: string): string;
var O: TJSONObject;
begin
  Result := '';
  O := LoadJSONObject(SlicerDataDir + 'multislicer.json');
  if O = nil then Exit;
  try
    Result := JStr(O, Key, '');
  finally
    O.Free;
  end;
end;

procedure WriteLastChoice(const Key, Value: string);
var O: TJSONObject;
begin
  O := LoadJSONObject(SlicerDataDir + 'multislicer.json');
  if O = nil then O := TJSONObject.Create;
  try
    O.Strings[Key] := Value;
    try
      SaveJSONObject(SlicerDataDir + 'multislicer.json', O);
    except
      { pasta sem permissao: a escolha apenas nao e lembrada }
    end;
  finally
    O.Free;
  end;
end;

end.
