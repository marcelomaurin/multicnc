unit multicad_aiconfig;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, multicad_text3d;

type
  TCadAIConfig = record
    Provider: TCadAIProvider;
    Models, Keys: array[TCadAIProvider] of string;
  end;

function LoadCadAIConfig: TCadAIConfig;
function EditCadAIConfig(Owner: TComponent; var Config: TCadAIConfig): Boolean;

implementation

uses
  {$IFDEF WINDOWS}Windows, Base64,{$ELSE}BaseUnix,{$ENDIF}
  SysUtils, IniFiles, LazFileUtils, LazUTF8, Forms, Controls, StdCtrls,
  multicad_log;

const
  ModelVariables: array[TCadAIProvider] of string = ('MESHY_3D_MODEL', 'TRIPO3D_MODEL');

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
  FileName, Section: string;
  Provider: TCadAIProvider;
begin
  Result := Default(TCadAIConfig);
  for Provider := Low(TCadAIProvider) to High(TCadAIProvider) do
  begin
    Result.Models[Provider] := CadAINormalizeModel(Provider,
      GetEnvironmentVariableUTF8(ModelVariables[Provider]));
  end;
  FileName := ConfigPath;
  if not FileExistsUTF8(FileName) then Exit;
  Ini := TMemIniFile.Create(FileName);
  try
    if SameText(Ini.ReadString('Geral', 'stl', 'Meshy'), 'Tripo') then
      Result.Provider := capTripo;
    for Provider := Low(TCadAIProvider) to High(TCadAIProvider) do
    begin
      Section := 'STL.' + CadAIProviderNames[Provider];
      Result.Models[Provider] := CadAINormalizeModel(Provider,
        Ini.ReadString(Section, 'modelo', Result.Models[Provider]));
      {$IFDEF WINDOWS}
      try
        Result.Keys[Provider] := ConvertKey(Ini.ReadString(Section, 'chave_dpapi', ''), False);
        while (Pos('AQAA', Result.Keys[Provider]) = 1) and (Length(Result.Keys[Provider]) > 64) do
          Result.Keys[Provider] := ConvertKey(Result.Keys[Provider], False);
      except
        on E: Exception do
        begin
          Result.Keys[Provider] := '';
          CadLog('AI.CONFIG.KEY_ERR', CadAIProviderNames[Provider] + ': ' + E.Message);
        end;
      end;
      {$ENDIF}
    end;
    CadLog('AI.CONFIG.LOAD', Format('provider=%s meshy_model=%s meshy_key_len=%d tripo_model=%s tripo_key_len=%d',
      [CadAIProviderNames[Result.Provider], Result.Models[capMeshy], Length(Result.Keys[capMeshy]),
       Result.Models[capTripo], Length(Result.Keys[capTripo])]));
  finally
    Ini.Free;
  end;
end;

procedure SaveCadAIConfig(const Config: TCadAIConfig);
var
  Ini: TMemIniFile;
  Lines: TStringList;
  FileName, Temp, Section: string;
  Provider: TCadAIProvider;
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
    Ini.WriteString('Geral', 'stl', CadAIProviderNames[Config.Provider]);
    for Provider := Low(TCadAIProvider) to High(TCadAIProvider) do
    begin
      Section := 'STL.' + CadAIProviderNames[Provider];
      Ini.WriteString(Section, 'modelo', Config.Models[Provider]);
      {$IFDEF WINDOWS}
      Ini.WriteString(Section, 'chave_dpapi', ConvertKey(Config.Keys[Provider], True));
      {$ENDIF}
    end;
    Ini.GetStrings(Lines);
    Lines.SaveToFile(Temp);
    {$IFDEF WINDOWS}
    if not MoveFileExW(PWideChar(UTF8Decode(Temp)), PWideChar(UTF8Decode(FileName)),
      MOVEFILE_REPLACE_EXISTING) then RaiseLastOSError;
    {$ELSE}
    if FpChmod(Temp, &600) <> 0 then RaiseLastOSError;
    if not RenameFileUTF8(Temp, FileName) then RaiseLastOSError;
    {$ENDIF}
    CadLog('AI.CONFIG.SAVE', Format('provider=%s meshy_model=%s meshy_key_len=%d tripo_model=%s tripo_key_len=%d',
      [CadAIProviderNames[Config.Provider], Config.Models[capMeshy], Length(Config.Keys[capMeshy]),
       Config.Models[capTripo], Length(Config.Keys[capTripo])]));
  finally
    Lines.Free;
    Ini.Free;
    if FileExistsUTF8(Temp) then DeleteFileUTF8(Temp);
  end;
end;

type
  TCadAIConfigDialog = class(TForm)
  private
    FProviders, FModel: TComboBox;
    FKey: TEdit;
    FModelLabel, FKeyLabel, FStatus: TLabel;
    FDraft: TCadAIConfig;
    procedure RememberProviderFields;
    procedure ShowProviderFields;
    procedure ProviderChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; const Config: TCadAIConfig); reintroduce;
    function Edit(var Config: TCadAIConfig): Boolean;
  end;

constructor TCadAIConfigDialog.Create(AOwner: TComponent; const Config: TCadAIConfig);
var
  Provider: TCadAIProvider;
  Button: TButton;

  function PutLabel(const Text: string; Y: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.Left := 16;
    Result.Top := Y;
    Result.Caption := Text;
  end;

  function PutButton(const Text: string; X, Value: Integer): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(X, 225, 100, 28);
    Result.Caption := Text;
    Result.ModalResult := Value;
  end;

begin
  inherited CreateNew(AOwner);
  FDraft := Config;
  Caption := 'MultiCAD · Configuração da IA';
  BorderStyle := bsDialog;
  Position := poOwnerFormCenter;
  ClientWidth := 456;
  ClientHeight := 269;

  PutLabel('Provedor padrão', 14);
  FProviders := TComboBox.Create(Self);
  FProviders.Name := 'AIProvider';
  FProviders.Parent := Self;
  FProviders.SetBounds(16, 34, 424, 26);
  FProviders.Style := csDropDownList;
  for Provider := Low(TCadAIProvider) to High(TCadAIProvider) do
    FProviders.Items.Add(CadAIProviderNames[Provider]);
  FProviders.ItemIndex := Ord(FDraft.Provider);

  FModelLabel := PutLabel('', 72);
  FModel := TComboBox.Create(Self);
  FModel.Name := 'AIModel';
  FModel.Parent := Self;
  FModel.SetBounds(16, 92, 424, 26);
  FModel.Style := csDropDownList;

  FKeyLabel := PutLabel('', 126);
  FKey := TEdit.Create(Self);
  FKey.Name := 'AIKey';
  FKey.Parent := Self;
  FKey.SetBounds(16, 146, 424, 26);
  FKey.PasswordChar := '*';

  {$IFDEF WINDOWS}
  PutLabel('A chave fica protegida no perfil do Windows.', 181);
  {$ELSE}
  PutLabel('A chave digitada vale para esta sessão.', 181);
  {$ENDIF}
  FStatus := PutLabel('', 201);
  FStatus.AutoSize := False;
  FStatus.Width := 424;
  FStatus.Height := 24;
  FStatus.WordWrap := True;
  Button := PutButton('Cancelar', 234, mrCancel);
  Button.Cancel := True;
  Button := PutButton('Salvar', 340, mrOk);
  Button.Default := True;

  ShowProviderFields;
  FProviders.OnChange := @ProviderChanged;
  ActiveControl := FProviders;
end;

procedure TCadAIConfigDialog.RememberProviderFields;
begin
  FDraft.Models[FDraft.Provider] := CadAINormalizeModel(FDraft.Provider, FModel.Text);
  FDraft.Keys[FDraft.Provider] := Trim(FKey.Text);
end;

procedure TCadAIConfigDialog.ShowProviderFields;
var
  I: Integer;
  ProviderName, SelectedModel: string;
begin
  ProviderName := CadAIProviderNames[FDraft.Provider];
  SelectedModel := CadAINormalizeModel(FDraft.Provider, FDraft.Models[FDraft.Provider]);
  FDraft.Models[FDraft.Provider] := SelectedModel;
  FModelLabel.Caption := 'Modelo ' + ProviderName;
  FModel.Items.BeginUpdate;
  try
    FModel.Items.Clear;
    for I := 0 to CadAIModelCount(FDraft.Provider) - 1 do
      FModel.Items.Add(CadAIModelAt(FDraft.Provider, I));
    FModel.ItemIndex := FModel.Items.IndexOf(SelectedModel);
    if (FModel.ItemIndex < 0) and (FModel.Items.Count > 0) then
      FModel.ItemIndex := 0;
  finally
    FModel.Items.EndUpdate;
  end;

  FKeyLabel.Caption := 'Chave API ' + ProviderName;
  FKey.Text := FDraft.Keys[FDraft.Provider];
  FKey.TextHint := CadAIKeyVariables[FDraft.Provider];
end;

procedure TCadAIConfigDialog.ProviderChanged(Sender: TObject);
begin
  if FProviders.ItemIndex < 0 then Exit;
  RememberProviderFields;
  FDraft.Provider := TCadAIProvider(FProviders.ItemIndex);
  ShowProviderFields;
  FStatus.Caption := '';
end;

function TCadAIConfigDialog.Edit(var Config: TCadAIConfig): Boolean;
var
  Provider: TCadAIProvider;
  Model, Key: string;
begin
  Result := False;
  while ShowModal = mrOk do
  begin
    RememberProviderFields;
    FStatus.Caption := '';
    for Provider := Low(TCadAIProvider) to High(TCadAIProvider) do
    begin
      Model := FDraft.Models[Provider];
      Key := FDraft.Keys[Provider];
      if not CadAIModelCompatible(Provider, Model) then
      begin
        FStatus.Caption := 'O modelo "' + Model + '" não é compatível com ' +
          CadAIProviderNames[Provider] + '.';
        Break;
      end;
      if (Pos(#10, Key) > 0) or (Pos(#13, Key) > 0) or (Pos(#0, Key) > 0) then
      begin
        FStatus.Caption := 'Confira a chave de ' + CadAIProviderNames[Provider] + '.';
        Break;
      end;
      if (Pos('AQAA', Key) = 1) and (Length(Key) > 64) then
      begin
        FStatus.Caption := 'Cole a chave API original de ' + CadAIProviderNames[Provider] +
          ', não o bloco criptografado (AQAA...).';
        Break;
      end;
      if (Provider = capTripo) and (Pos('tcli_', Key) = 1) then
      begin
        FStatus.Caption := 'Na Tripo, use a chave secreta (tsk_...), não o client_id (tcli_...).';
        Break;
      end;
    end;
    if FStatus.Caption <> '' then Continue;
    try
      SaveCadAIConfig(FDraft);
      Config := FDraft;
      Exit(True);
    except
      on E: Exception do FStatus.Caption := E.Message;
    end;
  end;
end;

function EditCadAIConfig(Owner: TComponent; var Config: TCadAIConfig): Boolean;
var Dialog: TCadAIConfigDialog;
begin
  Dialog := TCadAIConfigDialog.Create(Owner, Config);
  try
    Result := Dialog.Edit(Config);
  finally
    Dialog.Free;
  end;
end;

end.
