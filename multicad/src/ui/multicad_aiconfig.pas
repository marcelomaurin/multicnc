unit multicad_aiconfig;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes;

type
  TCadAIConfig = record
    Model, Key: string;
    RigEndpoint, RigModel, RigKey: string;
  end;

function LoadCadAIConfig: TCadAIConfig;
function EditCadAIConfig(Owner: TComponent; var Config: TCadAIConfig): Boolean;

implementation

uses
  {$IFDEF WINDOWS}Windows, Base64,{$ELSE}BaseUnix,{$ENDIF}
  SysUtils, IniFiles, LazFileUtils, LazUTF8, Forms, Controls, StdCtrls,
  multicad_text3d;

const
  MeshyModels: array[0..5] of string = ('meshy-7.1', 'meshy-6',
    'meshy-6-lite', 'meshy-t2.5', 'meshy-t2', 'meshy-7');

{$IFDEF WINDOWS}
type
  TDataBlob = record
    Size: DWORD;
    Data: PByte;
  end;

function CryptProtectData(var Input: TDataBlob; Description: PWideChar;
  Entropy, Reserved, Prompt: Pointer; Flags: DWORD; var Output: TDataBlob): BOOL;
  stdcall; external 'crypt32.dll';
function CryptUnprotectData(var Input: TDataBlob; Description, Entropy,
  Reserved, Prompt: Pointer; Flags: DWORD; var Output: TDataBlob): BOOL;
  stdcall; external 'crypt32.dll';

function ConvertKey(const Key: string; Protect: Boolean): string;
var
  Input, Output: TDataBlob;
  Data: RawByteString;
  OK: BOOL;
begin
  if Key = '' then Exit('');
  if Protect then Data := Key else Data := DecodeStringBase64(Key, True);
  Input.Size := Length(Data);
  Input.Data := PByte(Pointer(Data));
  Output := Default(TDataBlob);
  if Protect then
    OK := CryptProtectData(Input, 'MultiCAD', nil, nil, nil, 1, Output)
  else
    OK := CryptUnprotectData(Input, nil, nil, nil, nil, 1, Output);
  if not OK then raise Exception.Create('Não foi possível acessar a chave protegida no Windows.');
  try
    SetString(Result, PChar(Output.Data), Output.Size);
    if Protect then Result := EncodeStringBase64(Result);
  finally
    if not Protect and (Output.Size > 0) then FillChar(Output.Data^, Output.Size, 0);
    LocalFree(HLOCAL(Output.Data));
  end;
end;
{$ENDIF}

function ConfigPath: string;
var Dir: string;
begin
  {$IFDEF WINDOWS}
  Dir := GetEnvironmentVariableUTF8('LOCALAPPDATA');
  if Dir = '' then raise Exception.Create('O Windows não informou a pasta LocalAppData.');
  {$ELSE}
  Dir := GetEnvironmentVariableUTF8('XDG_CONFIG_HOME');
  if Dir = '' then Dir := IncludeTrailingPathDelimiter(GetUserDir) + '.config';
  {$ENDIF}
  Result := IncludeTrailingPathDelimiter(Dir) + 'MultiCAD' + PathDelim +
    'privado' + PathDelim + 'configuracao-ia.ini';
end;

function LoadCadAIConfig: TCadAIConfig;
var
  Ini: TMemIniFile;
  FileName: string;
begin
  Result := Default(TCadAIConfig);
  Result.Model := Trim(GetEnvironmentVariableUTF8('MESHY_3D_MODEL'));
  Result.RigEndpoint:=GetEnvironmentVariableUTF8('MULTICAD_RIG_ENDPOINT');
  if Result.RigEndpoint='' then Result.RigEndpoint:='http://127.0.0.1:8095/v1/chat/completions';
  Result.RigModel:=GetEnvironmentVariableUTF8('MULTICAD_RIG_MODEL');
  Result.RigKey:=GetEnvironmentVariableUTF8('MULTICAD_RIG_KEY');
  if Result.Model = '' then Result.Model := MeshyDefaultModel;
  FileName := ConfigPath;
  if not FileExistsUTF8(FileName) then Exit;
  Ini := TMemIniFile.Create(FileName);
  try
    Result.Model := Ini.ReadString('STL.Meshy', 'modelo', Result.Model);
    Result.RigEndpoint:=Ini.ReadString('Esqueleto.IA','endpoint',Result.RigEndpoint);
    Result.RigModel:=Ini.ReadString('Esqueleto.IA','modelo',Result.RigModel);
    {$IFDEF WINDOWS}
    try
      Result.Key := ConvertKey(Ini.ReadString('STL.Meshy', 'chave_dpapi', ''), False);
      if Ini.ReadString('Esqueleto.IA','chave_dpapi','')<>'' then
        Result.RigKey:=ConvertKey(Ini.ReadString('Esqueleto.IA','chave_dpapi',''),False);
    except
      // Uma chave de outro perfil pode ser substituída pelo editor.
      Result.Key := '';
    end;
    {$ENDIF}
  finally
    Ini.Free;
  end;
end;

procedure SaveCadAIConfig(const Config: TCadAIConfig);
var
  Ini: TMemIniFile;
  Lines: TStringList;
  FileName, Temp: string;
  ID: TGUID;
begin
  FileName := ConfigPath;
  if not ForceDirectoriesUTF8(ExtractFileDir(FileName)) then
    raise Exception.Create('Não foi possível criar a pasta privada do MultiCAD.');
  if CreateGUID(ID) <> 0 then raise Exception.Create('Falha ao criar o arquivo temporário.');
  Temp := FileName + GUIDToString(ID) + '.tmp';
  Ini := TMemIniFile.Create('');
  Lines := TStringList.Create;
  try
    Ini.WriteString('Geral', 'stl', 'Meshy');
    Ini.WriteString('STL.Meshy', 'modelo', Config.Model);
    Ini.WriteString('Esqueleto.IA','endpoint',Config.RigEndpoint);
    Ini.WriteString('Esqueleto.IA','modelo',Config.RigModel);
    {$IFDEF WINDOWS}
    Ini.WriteString('STL.Meshy', 'chave_dpapi', ConvertKey(Config.Key, True));
    Ini.WriteString('Esqueleto.IA','chave_dpapi',ConvertKey(Config.RigKey,True));
    {$ENDIF}
    Ini.GetStrings(Lines);
    Lines.SaveToFile(Temp);
    {$IFDEF WINDOWS}
    if not MoveFileExW(PWideChar(UTF8Decode(Temp)), PWideChar(UTF8Decode(FileName)),
      MOVEFILE_REPLACE_EXISTING) then RaiseLastOSError;
    {$ELSE}
    if FpChmod(Temp, &600) <> 0 then RaiseLastOSError;
    if not RenameFileUTF8(Temp, FileName) then RaiseLastOSError;
    {$ENDIF}
  finally
    Lines.Free;
    Ini.Free;
    if FileExistsUTF8(Temp) then DeleteFileUTF8(Temp);
  end;
end;

function EditCadAIConfig(Owner: TComponent; var Config: TCadAIConfig): Boolean;
var
  Dialog: TForm;
  Model: TComboBox;
  Key: TEdit;
  RigEndpoint, RigModel, RigKey: TEdit;
  Button: TButton;
  ID: string;
  Edited: TCadAIConfig;
  Status: TLabel;

  function PutLabel(const Text: string; Y: Integer): TLabel;
  begin
    Result := TLabel.Create(Dialog);
    Result.Parent := Dialog;
    Result.Left := 16;
    Result.Top := Y;
    Result.Caption := Text;
  end;

  function PutButton(const Text: string; X, Value: Integer): TButton;
  begin
    Result := TButton.Create(Dialog);
    Result.Parent := Dialog;
    Result.SetBounds(X, 440, 100, 28);
    Result.Caption := Text;
    Result.ModalResult := Value;
  end;

begin
  Result := False;
  Dialog := TForm.CreateNew(Owner);
  try
    Dialog.Caption := 'MultiCAD · Configuração da IA';
    Dialog.BorderStyle := bsDialog;
    Dialog.Position := poOwnerFormCenter;
    Dialog.ClientWidth := 456;
    Dialog.ClientHeight := 484;
    PutLabel('Provedor para malhas 3D   Meshy', 14);
    PutLabel('Modelo 3D', 48);
    Model := TComboBox.Create(Dialog);
    Model.Parent := Dialog;
    Model.SetBounds(16, 68, 424, 26);
    Model.Style := csDropDown;
    for ID in MeshyModels do Model.Items.Add(ID);
    Model.Text := Config.Model;

    PutLabel('Chave API Meshy', 104);
    Key := TEdit.Create(Dialog);
    Key.Parent := Dialog;
    Key.SetBounds(16, 124, 424, 26);
    Key.PasswordChar := '*';
    Key.Text := Config.Key;
    Key.TextHint := 'MESHY_API_KEY';
    {$IFDEF WINDOWS}
    PutLabel('A chave fica protegida no perfil do Windows.', 158);
    {$ELSE}
    PutLabel('A chave digitada vale para esta sessão.', 158);
    {$ENDIF}
    PutLabel('IA do esqueleto · API compatível com OpenAI / Ollama',188);
    PutLabel('Endpoint de chat',214);
    RigEndpoint:=TEdit.Create(Dialog); RigEndpoint.Parent:=Dialog;
    RigEndpoint.SetBounds(16,234,424,26); RigEndpoint.Text:=Config.RigEndpoint;
    PutLabel('Modelo de linguagem',266);
    RigModel:=TEdit.Create(Dialog); RigModel.Parent:=Dialog;
    RigModel.SetBounds(16,286,424,26); RigModel.Text:=Config.RigModel;
    RigModel.TextHint:='Nome exato do modelo no servidor';
    PutLabel('Chave da IA do esqueleto (opcional para servidor local)',318);
    RigKey:=TEdit.Create(Dialog); RigKey.Parent:=Dialog;
    RigKey.SetBounds(16,338,424,26); RigKey.PasswordChar:='*'; RigKey.Text:=Config.RigKey;
    Status := PutLabel('', 386);
    Status.Width := 424;
    Status.AutoSize := False;
    Status.Height := 30;
    Status.WordWrap := True;
    Button := PutButton('Cancelar', 234, mrCancel);
    Button.Cancel := True;
    Button := PutButton('Salvar', 340, mrOk);
    Button.Default := True;
    while Dialog.ShowModal = mrOk do
    begin
      Edited.Model := Trim(Model.Text);
      Edited.Key := Trim(Key.Text);
      Edited.RigEndpoint:=Trim(RigEndpoint.Text); Edited.RigModel:=Trim(RigModel.Text);
      Edited.RigKey:=Trim(RigKey.Text);
      if (Edited.Model = '') or (Pos(#10, Edited.Key) > 0) or
         (Pos(#13, Edited.Key) > 0) or (Pos(#0, Edited.Key) > 0) or
         (Pos(#13,Edited.RigKey)>0) or (Pos(#10,Edited.RigKey)>0) or (Pos(#0,Edited.RigKey)>0) then
      begin
        Status.Caption := 'Informe um modelo e uma chave válida.';
        Continue;
      end;
      try
        SaveCadAIConfig(Edited);
        Config := Edited;
        Exit(True);
      except
        on E: Exception do Status.Caption := E.Message;
      end;
    end;
  finally
    Dialog.Free;
  end;
end;

end.
