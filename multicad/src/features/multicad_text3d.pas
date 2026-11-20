unit multicad_text3d;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, SysUtils, multicad_generatedmesh;

const
  MeshyDefaultModel = 'meshy-7.1';

type
  { Adaptado de StarIndustry/tools/visualizador/ugeracao3d.pas.
    Para o CAD, a etapa preview já entrega a geometria e dispensa a texturização. }
  TCadText3DJob = class(TThread)
  private
    FPrompt, FKey, FModel, FError: string;
    FSizeMM: Double;
    FStage: LongInt;
    FWake: PRTLEvent;
    FFeature: TCadGeneratedMesh;
    function Request(const URL, Payload: string; Download: Boolean): RawByteString;
  protected
    procedure Execute; override;
  public
    constructor Create(const APrompt, AKey, AModel: string; ASizeMM: Double);
    destructor Destroy; override;
    procedure Cancel;
    function Stage: Integer;
    { Ler somente depois de WaitFor. }
    function TakeFeature: TCadGeneratedMesh;
    property ErrorMessage: string read FError;
  end;

implementation

uses
  {$IFDEF WINDOWS}Windows, WinHttp,{$ELSE}ctypes, libcurl,{$ENDIF}
  URIParser, fpjson, jsonparser, multicad_mesh;

const
  MeshyURL = 'https://api.meshy.ai/openapi/v2/text-to-3d';
  JSONLimit = 1024 * 1024;

function ResponseObject(const Data: RawByteString): TJSONObject;
var Value: TJSONData;
begin
  Value := GetJSON(Data, True);
  if Value is TJSONObject then Exit(TJSONObject(Value));
  Value.Free;
  raise Exception.Create('A Meshy retornou uma resposta inesperada.');
end;

function ValidTaskID(const ID: string): Boolean;
var C: Char;
begin
  Result := False;
  if (ID = '') or (Length(ID) > 80) then Exit;
  for C in ID do
    if not (C in ['a'..'z','A'..'Z','0'..'9','-','_']) then Exit;
  Result := True;
end;

procedure CheckHTTP(Code: Integer);
begin
  case Code of
    200..299: Exit;
    401,403: raise Exception.Create('A Meshy recusou o acesso. Confira a chave e as permissões.');
    402: raise Exception.Create('A Meshy informa que não há créditos suficientes.');
    429: raise Exception.Create('A Meshy atingiu o limite de requisições.');
  else
    raise Exception.CreateFmt('A requisição 3D falhou (HTTP %d).', [Code]);
  end;
end;

constructor TCadText3DJob.Create(const APrompt, AKey, AModel: string; ASizeMM: Double);
begin
  inherited Create(True);
  FPrompt := APrompt;
  FKey := AKey;
  FModel := AModel;
  FSizeMM := ASizeMM;
  FWake := RTLEventCreate;
end;

destructor TCadText3DJob.Destroy;
begin
  Cancel;
  inherited Destroy;
  RTLEventDestroy(FWake);
  FFeature.Free;
end;

procedure TCadText3DJob.Cancel;
begin
  Terminate;
  if FWake <> nil then RTLEventSetEvent(FWake);
end;

function TCadText3DJob.Stage: Integer;
begin
  Result := InterlockedCompareExchange(FStage, 0, 0);
end;

function TCadText3DJob.TakeFeature: TCadGeneratedMesh;
begin
  Result := FFeature;
  FFeature := nil;
end;

procedure TCadText3DJob.Execute;
var
  Body, Reply, Files: TJSONObject;
  ID, Status, DownloadURL: string;
  Mesh: TCadMesh;
  Deadline: QWord;
begin
  try
    try
      if Terminated then Exit;
      InterlockedExchange(FStage, 1);
      Body := TJSONObject.Create;
      try
        Body.Add('mode', 'preview');
        Body.Add('prompt', FPrompt);
        Body.Add('ai_model', FModel);
        if Pos('meshy-t', FModel) = 1 then
          Body.Add('model_type', 'smart-topology')
        else
          Body.Add('should_remesh', True);
        Body.Add('target_polycount', 10000);
        Body.Add('target_formats', TJSONArray.Create(['stl']));
        Reply := ResponseObject(Request(MeshyURL, Body.AsJSON, False));
        try
          ID := Reply.Get('result', '');
        finally
          Reply.Free;
        end;
      finally
        Body.Free;
      end;
      if not ValidTaskID(ID) then
        raise Exception.Create('A Meshy não forneceu um identificador de tarefa válido.');

      InterlockedExchange(FStage, 2);
      Deadline := GetTickCount64 + 15*60*1000;
      DownloadURL := '';
      repeat
        if Terminated then Exit;
        Reply := ResponseObject(Request(MeshyURL + '/' + ID, '', False));
        try
          Status := UpperCase(Reply.Get('status', ''));
          if Status = 'SUCCEEDED' then
          begin
            Files := Reply.Get('model_urls', TJSONObject(nil));
            if Files <> nil then DownloadURL := Files.Get('stl', '');
            if DownloadURL = '' then
              raise Exception.Create('A tarefa foi concluída sem um arquivo STL.');
            Break;
          end;
          if (Status <> 'PENDING') and (Status <> 'IN_PROGRESS') then
            raise Exception.Create('A Meshy interrompeu a geração ou retornou um estado desconhecido.');
        finally
          Reply.Free;
        end;
        RTLEventWaitFor(FWake, 3000);
      until GetTickCount64 >= Deadline;
      if Terminated then Exit;
      if DownloadURL = '' then
        raise Exception.Create('O tempo de espera pela geração foi excedido.');

      InterlockedExchange(FStage, 3);
      FFeature := TCadGeneratedMesh.Create;
      FFeature.Prompt := FPrompt;
      FFeature.Model := FModel;
      FFeature.SizeMM := FSizeMM;
      FFeature.SetSTL(Request(DownloadURL, '', True));
      Mesh := FFeature.BuildMesh;
      Mesh.Free;
    except
      on E: Exception do
      begin
        FreeAndNil(FFeature);
        FError := StringReplace(E.Message, FKey, '[chave omitida]', [rfReplaceAll]);
        FError := StringReplace(FError, FPrompt, '[descrição omitida]', [rfReplaceAll]);
      end;
    end;
  finally
    FKey := '';
  end;
end;

{$IFDEF WINDOWS}
function CadWinHttpTimeouts(Session: HINTERNET; Resolve, Connect, Send,
  Receive: LongInt): BOOL; stdcall; external 'winhttp.dll' name 'WinHttpSetTimeouts';
{$ELSE}
type
  PCadTransfer = ^TCadTransfer;
  TCadTransfer = record
    Stream: TMemoryStream;
    Limit: PtrUInt;
    TooLarge: Boolean;
  end;

function WriteResponse(Buffer: Pointer; Size, Count: csize_t; Opaque: Pointer): csize_t; cdecl;
var Transfer: PCadTransfer;
begin
  Result := 0;
  Transfer := PCadTransfer(Opaque);
  if (Size = 0) or (Count = 0) then Exit;
  if Count > (Transfer^.Limit - PtrUInt(Transfer^.Stream.Size)) div Size then
  begin
    Transfer^.TooLarge := True;
    Exit;
  end;
  try
    Result := Transfer^.Stream.Write(Buffer^, Size*Count);
  except
    Result := 0;
  end;
end;
{$ENDIF}

function TCadText3DJob.Request(const URL, Payload: string; Download: Boolean): RawByteString;
var
  URI: TURI;
  Limit: Integer;
  {$IFDEF WINDOWS}
  Session, Connection, Handle: HINTERNET;
  Method, Path, Header: UnicodeString;
  Status, HeaderSize, Policy, BytesRead: DWORD;
  Chunk: array[0..32767] of Byte;
  Total: Integer;
  {$ELSE}
  Client: PCURL;
  Headers, Updated: Pcurl_slist;
  Transfer: TCadTransfer;
  KeyHeader: string;
  Status: clong;
  {$ENDIF}
begin
  URI := ParseURI(URL, False);
  if not SameText(URI.Protocol, 'https') or (URI.Host = '') or
     (URI.Username <> '') or (URI.Password <> '') or
     ((URI.Port <> 0) and (URI.Port <> 443)) then
    raise Exception.Create('A Meshy forneceu um endereço HTTPS inválido.');
  Limit := JSONLimit;
  if Download then Limit := CadGeneratedMaxBytes;

  {$IFDEF WINDOWS}
  Path := UTF8Decode(URI.Path + URI.Document);
  if (Path = '') or (Path[1] <> '/') then Path := '/' + Path;
  if URI.Params <> '' then Path := Path + '?' + UTF8Decode(URI.Params);
  Method := 'GET';
  Header := '';
  if not Download then Header := 'Authorization: Bearer ' + UTF8Decode(FKey) + #13#10;
  if Payload <> '' then
  begin
    Method := 'POST';
    Header := Header + 'Content-Type: application/json' + #13#10;
  end;
  Session := WinHttpOpen('MultiCAD', WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  if Session = nil then RaiseLastOSError;
  try
    if not CadWinHttpTimeouts(Session, 10000, 10000, 15000, 15000) then RaiseLastOSError;
    Connection := WinHttpConnect(Session, PWideChar(UTF8Decode(URI.Host)), 443, 0);
    if Connection = nil then RaiseLastOSError;
    try
      Handle := WinHttpOpenRequest(Connection, PWideChar(Method), PWideChar(Path),
        nil, nil, nil, WINHTTP_FLAG_SECURE or WINHTTP_FLAG_ESCAPE_DISABLE_QUERY);
      if Handle = nil then RaiseLastOSError;
      try
        Policy := WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
        if not WinHttpSetOption(Handle, WINHTTP_OPTION_REDIRECT_POLICY, @Policy, SizeOf(Policy)) or
           not WinHttpSendRequest(Handle, PWideChar(Header), Length(Header),
             Pointer(Payload), Length(Payload), Length(Payload), 0) or
           not WinHttpReceiveResponse(Handle, nil) then
          RaiseLastOSError;
        HeaderSize := SizeOf(Status);
        if not WinHttpQueryHeaders(Handle, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
          nil, @Status, @HeaderSize, nil) then RaiseLastOSError;
        CheckHTTP(Status);
        Result := '';
        repeat
          if Terminated then Exit;
          if not WinHttpReadData(Handle, @Chunk, SizeOf(Chunk), @BytesRead) then RaiseLastOSError;
          Total := Length(Result);
          if Total + BytesRead > Limit then
            raise Exception.Create('A resposta excede o tamanho suportado.');
          if BytesRead > 0 then
          begin
            SetLength(Result, Total + BytesRead);
            Move(Chunk, Result[Total+1], BytesRead);
          end;
        until BytesRead = 0;
      finally
        WinHttpCloseHandle(Handle);
      end;
    finally
      WinHttpCloseHandle(Connection);
    end;
  finally
    WinHttpCloseHandle(Session);
  end;
  {$ELSE}
  Headers := nil;
  Transfer := Default(TCadTransfer);
  Transfer.Limit := Limit;
  Transfer.Stream := TMemoryStream.Create;
  Client := curl_easy_init;
  try
    if Client = nil then raise Exception.Create('Não foi possível iniciar a conexão HTTPS.');
    if not Download then
    begin
      KeyHeader := 'Authorization: Bearer ' + FKey;
      Headers := curl_slist_append(nil, PChar(KeyHeader));
      if Headers = nil then raise Exception.Create('Falha ao preparar a requisição HTTPS.');
    end;
    if Payload <> '' then
    begin
      Updated := curl_slist_append(Headers, 'Content-Type: application/json');
      if Updated = nil then raise Exception.Create('Falha ao preparar a requisição HTTPS.');
      Headers := Updated;
    end;
    if (curl_easy_setopt(Client, CURLOPT_URL, [PChar(URL)]) <> CURLE_OK) or
       (curl_easy_setopt(Client, CURLOPT_PROTOCOLS, [clong(CURLPROTO_HTTPS)]) <> CURLE_OK) or
       (curl_easy_setopt(Client, CURLOPT_CONNECTTIMEOUT, [clong(10)]) <> CURLE_OK) or
       (curl_easy_setopt(Client, CURLOPT_TIMEOUT, [clong(30)]) <> CURLE_OK) or
       (curl_easy_setopt(Client, CURLOPT_NOSIGNAL, [clong(1)]) <> CURLE_OK) or
       (curl_easy_setopt(Client, CURLOPT_WRITEFUNCTION, [Pointer(@WriteResponse)]) <> CURLE_OK) or
       (curl_easy_setopt(Client, CURLOPT_WRITEDATA, [Pointer(@Transfer)]) <> CURLE_OK) or
       (curl_easy_setopt(Client, CURLOPT_HTTPHEADER, [Pointer(Headers)]) <> CURLE_OK) then
      raise Exception.Create('Falha ao preparar a requisição HTTPS.');
    if (Payload <> '') and
       (curl_easy_setopt(Client, CURLOPT_POSTFIELDS, [PChar(Payload)]) <> CURLE_OK) then
      raise Exception.Create('Falha ao preparar a requisição de geração.');
    if curl_easy_perform(Client) <> CURLE_OK then
    begin
      if Transfer.TooLarge then raise Exception.Create('A resposta excede o tamanho suportado.');
      raise Exception.Create('Não foi possível concluir a conexão HTTPS com a Meshy.');
    end;
    Status := 0;
    if curl_easy_getinfo(Client, CURLINFO_RESPONSE_CODE, [Pointer(@Status)]) <> CURLE_OK then
      raise Exception.Create('Não foi possível ler o status da requisição HTTPS.');
    CheckHTTP(Status);
    SetString(Result, PChar(Transfer.Stream.Memory), Transfer.Stream.Size);
  finally
    if Client <> nil then curl_easy_cleanup(Client);
    curl_slist_free_all(Headers);
    Transfer.Stream.Free;
  end;
  {$ENDIF}
end;

{$IFNDEF WINDOWS}
initialization
  curl_global_init(CURL_GLOBAL_DEFAULT);
finalization
  curl_global_cleanup;
{$ENDIF}
end.
