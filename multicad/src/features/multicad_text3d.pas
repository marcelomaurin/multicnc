unit multicad_text3d;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, SysUtils, fpjson, multicad_generatedmesh;

type
  TCadAIProvider = (capMeshy, capTripo);

const
  CadAIProviderNames: array[TCadAIProvider] of string = ('Meshy', 'Tripo');
  CadAIKeyVariables: array[TCadAIProvider] of string = ('MESHY_API_KEY', 'TRIPO3D_API_KEY');
  CadAIDefaultModels: array[TCadAIProvider] of string = ('meshy-7.1', 'v3.1-20260211');

function CadAIModelCount(Provider: TCadAIProvider): Integer;
function CadAIModelAt(Provider: TCadAIProvider; Index: Integer): string;
function CadAIModelCompatible(Provider: TCadAIProvider; const Model: string): Boolean;
function CadAINormalizeModel(Provider: TCadAIProvider; const Model: string): string;

type
  { Adaptado de StarIndustry/tools/visualizador/ugeracao3d.pas.
    Para o CAD, a etapa preview já entrega a geometria e dispensa a texturização. }
  TCadText3DJob = class(TThread)
  private
    FPrompt, FKey, FModel, FError, FImageFile: string;
    FProvider: TCadAIProvider;
    FSizeMM: Double;
    FStage: LongInt;
    FWake: PRTLEvent;
    FFeature: TCadGeneratedMesh;
    function GenerateMeshy: string;
    function GenerateTripo: string;
    function TripoData(const Path: string; const Payload: RawByteString = '';
      const ContentType: string = 'application/json'): TJSONObject;
    function TripoSubmit(const Path: string; Body: TJSONObject): string;
    function TripoUploadImage: string;
    function TripoWait(const ID: string; NeedDownload: Boolean): string;
  protected
    function Request(const URL: string; const Payload: RawByteString;
      Download: Boolean; const ContentType: string = 'application/json'): RawByteString; virtual;
    procedure Execute; override;
  public
    constructor Create(const APrompt, AKey, AModel: string; ASizeMM: Double;
      AProvider: TCadAIProvider = capMeshy; const AImageFile: string = '');
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
  URIParser, jsonparser, multicad_mesh, multicad_log;

const
  MeshyURL = 'https://api.meshy.ai/openapi/v2/text-to-3d';
  TripoURL = 'https://openapi.tripo3d.ai/v3';
  JSONLimit = 1024 * 1024;
  TripoImageLimit = 20000000;
  MeshyModels: array[0..5] of string = ('meshy-7.1', 'meshy-6',
    'meshy-6-lite', 'meshy-t2.5', 'meshy-t2', 'meshy-7');
  TripoModels: array[0..4] of string = ('v3.1-20260211', 'v3.0-20250812',
    'v2.5-20250123', 'P2-20260801', 'P1-20260311');

function CadAIModelCount(Provider: TCadAIProvider): Integer;
begin
  case Provider of
    capMeshy: Result := Length(MeshyModels);
    capTripo: Result := Length(TripoModels);
  else
    Result := 0;
  end;
end;

function CadAIModelAt(Provider: TCadAIProvider; Index: Integer): string;
begin
  case Provider of
    capMeshy:
      if (Index >= 0) and (Index < Length(MeshyModels)) then Exit(MeshyModels[Index]);
    capTripo:
      if (Index >= 0) and (Index < Length(TripoModels)) then Exit(TripoModels[Index]);
  end;
  Result := '';
end;

function CadAIModelCompatible(Provider: TCadAIProvider; const Model: string): Boolean;
var I: Integer; Trimmed: string;
begin
  Trimmed := Trim(Model);
  if Trimmed = '' then Exit(False);
  for I := 0 to CadAIModelCount(Provider) - 1 do
    if SameText(Trimmed, CadAIModelAt(Provider, I)) then Exit(True);
  Result := False;
end;

function CadAINormalizeModel(Provider: TCadAIProvider; const Model: string): string;
var I: Integer; Trimmed: string;
begin
  Trimmed := Trim(Model);
  for I := 0 to CadAIModelCount(Provider) - 1 do
    if SameText(Trimmed, CadAIModelAt(Provider, I)) then
      Exit(CadAIModelAt(Provider, I));
  Result := CadAIDefaultModels[Provider];
end;

function MaskKeyInfo(const Key: string): string;
begin
  if Key = '' then Exit('len=0');
  if Length(Key) >= 8 then
    Result := Format('len=%d prefix=%s...', [Length(Key), Copy(Key, 1, 4)])
  else
    Result := Format('len=%d', [Length(Key)]);
end;

function SanitizeBodyForLog(const Body, Key: string): string;
begin
  Result := Copy(Body, 1, 500);
  if Key <> '' then
    Result := StringReplace(Result, Key, '[chave omitida]', [rfReplaceAll]);
end;

function ResponseObject(const Data: RawByteString): TJSONObject;
var Value: TJSONData;
begin
  Value := GetJSON(Data, True);
  if Value is TJSONObject then Exit(TJSONObject(Value));
  Value.Free;
  raise Exception.Create('O serviço retornou uma resposta inesperada.');
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

procedure CheckHTTP(Code: Integer; const Provider, URL, Body, Key: string);
var
  SafeBody, APIMsg, Detail: string;
  Parsed: TJSONData;
  Obj, ErrObj: TJSONObject;
  APICode: Integer;
begin
  if (Code >= 200) and (Code <= 299) then Exit;
  SafeBody := SanitizeBodyForLog(Body, Key);
  CadLog('AI.HTTP.ERROR', Format('provider=%s status=%d url=%s body=%s',
    [Provider, Code, URL, SafeBody]));
  APICode := 0;
  APIMsg := '';
  if Body <> '' then
  begin
    try
      Parsed := GetJSON(Body, True);
      try
        if Parsed is TJSONObject then
        begin
          Obj := TJSONObject(Parsed);
          ErrObj := Obj.Get('error', TJSONObject(nil));
          if ErrObj <> nil then Obj := ErrObj;
          APICode := Obj.Get('code', 0);
          APIMsg := Obj.Get('message', '');
        end;
      finally
        Parsed.Free;
      end;
    except
      // Resposta não-JSON (proxy/CDN)
    end;
  end;
  if Key <> '' then
    APIMsg := StringReplace(APIMsg, Key, '[chave omitida]', [rfReplaceAll]);
  APIMsg := Trim(StringReplace(StringReplace(APIMsg, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  Detail := Format('HTTP %d', [Code]);
  if APICode <> 0 then Detail := Detail + Format(' / API %d', [APICode]);
  if APIMsg <> '' then Detail := Detail + ' - ' + Copy(APIMsg, 1, 200);
  if (APICode = 2010) and SameText(Provider, 'Tripo') then
    raise Exception.CreateFmt('%s informa que não há créditos suficientes (%s).', [Provider, Detail]);
  case Code of
    401,403: raise Exception.CreateFmt('%s recusou o acesso (%s). Confira a chave e as permissões.', [Provider, Detail]);
    402: raise Exception.CreateFmt('%s informa que não há créditos suficientes (%s).', [Provider, Detail]);
    429: raise Exception.CreateFmt('%s atingiu o limite de requisições (%s).', [Provider, Detail]);
  else
    raise Exception.CreateFmt('A requisição 3D falhou (%s).', [Detail]);
  end;
end;

constructor TCadText3DJob.Create(const APrompt, AKey, AModel: string;
  ASizeMM: Double; AProvider: TCadAIProvider; const AImageFile: string);
begin
  inherited Create(True);
  FPrompt := APrompt;
  FKey := AKey;
  FModel := AModel;
  FSizeMM := ASizeMM;
  FProvider := AProvider;
  FImageFile := AImageFile;
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

function TCadText3DJob.GenerateMeshy: string;
var
  Body, Reply, Files: TJSONObject;
  ID, Status, DownloadURL: string;
  Deadline: QWord;
begin
  Result := '';
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

  Result := DownloadURL;
end;

function TCadText3DJob.TripoData(const Path: string; const Payload: RawByteString;
  const ContentType: string): TJSONObject;
var Reply, Data: TJSONObject; Code: Integer;
begin
  Reply := ResponseObject(Request(TripoURL + Path, Payload, False, ContentType));
  try
    Code := Reply.Get('code', -1);
    if Code <> 0 then
      raise Exception.CreateFmt('A Tripo recusou a etapa %s (código %d).', [Path, Code]);
    Data := Reply.Get('data', TJSONObject(nil));
    if Data = nil then raise Exception.Create('A Tripo não retornou os dados da tarefa.');
    Result := TJSONObject(Data.Clone);
  finally
    Reply.Free;
  end;
end;

function TCadText3DJob.TripoSubmit(const Path: string; Body: TJSONObject): string;
var Data: TJSONObject;
begin
  Data := TripoData(Path, Body.AsJSON);
  try
    Result := Data.Get('task_id', '');
    if not ValidTaskID(Result) then
      raise Exception.Create('A Tripo não forneceu um identificador de tarefa válido.');
  finally
    Data.Free;
  end;
end;

function TCadText3DJob.TripoUploadImage: string;
const
  PNGSignature = #$89'PNG'#$0D#$0A#$1A#$0A;
  JPEGSignature = #$FF#$D8#$FF;
  CRLF = #13#10;
var
  Image: THandleStream;
  ImageHandle: THandle;
  ImageData, Payload: RawByteString;
  Boundary, Mime, FileName: string;
  ID: TGUID;
  Data: TJSONObject;
begin
  ImageHandle := FileOpen(FImageFile, fmOpenRead or fmShareDenyWrite);
  if ImageHandle = THandle(-1) then
    raise Exception.Create('Não foi possível abrir a imagem de referência.');
  try
    Image := THandleStream.Create(ImageHandle);
    try
      if (Image.Size < 8) or (Image.Size > TripoImageLimit) then
        raise Exception.Create('Use uma imagem PNG ou JPEG de até 20 MB.');
      SetLength(ImageData, Image.Size);
      Image.ReadBuffer(ImageData[1], Length(ImageData));
    finally
      Image.Free;
    end;
  finally
    FileClose(ImageHandle);
  end;
  if Copy(ImageData, 1, 8) = PNGSignature then
  begin
    Mime := 'image/png';
    FileName := 'reference.png';
  end
  else if Copy(ImageData, 1, 3) = JPEGSignature then
  begin
    Mime := 'image/jpeg';
    FileName := 'reference.jpg';
  end
  else
    raise Exception.Create('O arquivo não contém uma imagem PNG ou JPEG.');
  if CreateGUID(ID) <> 0 then raise Exception.Create('Falha ao preparar o envio da imagem.');
  Boundary := 'MultiCAD-' + Copy(GUIDToString(ID), 2, 36);
  Payload := '--' + Boundary + CRLF +
    'Content-Disposition: form-data; name="file"; filename="' + FileName + '"' + CRLF +
    'Content-Type: ' + Mime + CRLF + CRLF + ImageData + CRLF + '--' + Boundary + '--' + CRLF;
  if Terminated then Exit('');
  Data := TripoData('/files', Payload, 'multipart/form-data; boundary=' + Boundary);
  try
    Result := Data.Get('file_token', '');
    if (Copy(Result, 1, 5) <> 'file_') or not ValidTaskID(Result) then
      raise Exception.Create('A Tripo não retornou uma referência de imagem válida.');
  finally
    Data.Free;
  end;
end;

function TCadText3DJob.TripoWait(const ID: string; NeedDownload: Boolean): string;
var Data, Output: TJSONObject; Status: string; Deadline: QWord;
begin
  Result := '';
  Deadline := GetTickCount64 + 15*60*1000;
  repeat
    if Terminated then Exit;
    Data := TripoData('/tasks/' + ID);
    try
      Status := LowerCase(Data.Get('status', ''));
      if Status = 'success' then
      begin
        if not NeedDownload then Exit;
        Output := Data.Get('output', TJSONObject(nil));
        if Output <> nil then Result := Output.Get('model_url', '');
        if Result = '' then raise Exception.Create('A Tripo não retornou o STL convertido.');
        Exit;
      end;
      if (Status = 'failed') or (Status = 'cancelled') or
         (Status = 'banned') or (Status = 'expired') then
        raise Exception.CreateFmt('Tarefa Tripo %s encerrada sem malha (código %d).',
          [ID, Data.Get('error_code', 0)]);
    finally
      Data.Free;
    end;
    RTLEventWaitFor(FWake, 3000);
  until GetTickCount64 >= Deadline;
  if not Terminated then
    raise Exception.CreateFmt('Tempo de espera excedido para a tarefa Tripo %s.', [ID]);
end;

function TCadText3DJob.GenerateTripo: string;
var Body: TJSONObject; ID, Path, Input: string;
begin
  Result := '';
  Body := TJSONObject.Create;
  try
    if FImageFile <> '' then
    begin
      InterlockedExchange(FStage, 4);
      Input := TripoUploadImage;
      if Terminated then Exit;
      Path := '/generation/image-to-model';
      Body.Add('input', Input);
    end
    else
    begin
      Path := '/generation/text-to-model';
      Body.Add('prompt', FPrompt);
    end;
    InterlockedExchange(FStage, 1);
    Body.Add('model', FModel);
    Body.Add('texture', False);
    Body.Add('pbr', False);
    Body.Add('face_limit', 10000);
    if SameText(FModel, 'P2-20260801') then Body.Add('quad', False);
    ID := TripoSubmit(Path, Body);
    InterlockedExchange(FStage, 2);
    TripoWait(ID, False);
    if Terminated then Exit;

    InterlockedExchange(FStage, 5);
    Body.Clear;
    Body.Add('input', ID);
    Body.Add('format', 'STL');
    ID := TripoSubmit('/models/convert', Body);
    Result := TripoWait(ID, True);
  finally
    Body.Free;
  end;
end;

procedure TCadText3DJob.Execute;
var DownloadURL: string; Mesh: TCadMesh;
begin
  try
    try
      if Terminated then Exit;
      CadLog('AI.JOB.START', Format('provider=%s model=%s size_mm=%.2f image=%s key=%s',
        [CadAIProviderNames[FProvider], FModel, FSizeMM, BoolToStr(FImageFile <> '', True),
         MaskKeyInfo(FKey)]));
      if not CadAIModelCompatible(FProvider, FModel) then
        raise Exception.CreateFmt('O modelo "%s" não é compatível com o provedor %s.',
          [FModel, CadAIProviderNames[FProvider]]);
      InterlockedExchange(FStage, 1);
      if FProvider = capTripo then DownloadURL := GenerateTripo
      else DownloadURL := GenerateMeshy;
      if Terminated then Exit;
      InterlockedExchange(FStage, 3);
      FFeature := TCadGeneratedMesh.Create;
      FFeature.Provider := CadAIProviderNames[FProvider];
      FFeature.FromImage := FImageFile <> '';
      FFeature.Prompt := FPrompt;
      FFeature.Model := FModel;
      FFeature.SizeMM := FSizeMM;
      FFeature.SetSTL(Request(DownloadURL, '', True));
      Mesh := FFeature.BuildMesh;
      Mesh.Free;
      CadLog('AI.JOB.OK', Format('provider=%s model=%s', [CadAIProviderNames[FProvider], FModel]));
    except
      on E: Exception do
      begin
        FreeAndNil(FFeature);
        FError := E.Message;
        if FKey <> '' then
          FError := StringReplace(FError, FKey, '[chave omitida]', [rfReplaceAll]);
        if FPrompt <> '' then
          FError := StringReplace(FError, FPrompt, '[descrição omitida]', [rfReplaceAll]);
        CadLog('AI.JOB.ERROR', FError);
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

function TCadText3DJob.Request(const URL: string; const Payload: RawByteString;
  Download: Boolean; const ContentType: string): RawByteString;
var
  URI: TURI;
  Limit: Integer;
  {$IFDEF WINDOWS}
  Session, Connection, RequestHandle: HINTERNET;
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
  if Terminated then Exit('');
  URI := ParseURI(URL, False);
  if not SameText(URI.Protocol, 'https') or (URI.Host = '') or
     (URI.Username <> '') or (URI.Password <> '') or
     ((URI.Port <> 0) and (URI.Port <> 443)) then
    raise Exception.Create('O serviço forneceu um endereço HTTPS inválido.');
  if not Download and not
     (((FProvider = capMeshy) and SameText(URI.Host, 'api.meshy.ai')) or
      ((FProvider = capTripo) and SameText(URI.Host, 'openapi.tripo3d.ai'))) then
    raise Exception.Create('O endereço não pertence ao provedor configurado.');
  Limit := JSONLimit;
  if Download then Limit := CadGeneratedMaxBytes;
  CadLog('AI.HTTP.REQ', Format('provider=%s url=%s download=%s payload_len=%d',
    [CadAIProviderNames[FProvider], URL, BoolToStr(Download, True), Length(Payload)]));

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
    Header := Header + 'Content-Type: ' + UTF8Decode(ContentType) + #13#10;
  end;
  Session := WinHttpOpen('MultiCAD', WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  if Session = nil then RaiseLastOSError;
  try
    if not CadWinHttpTimeouts(Session, 10000, 10000, 15000, 15000) then RaiseLastOSError;
    Connection := WinHttpConnect(Session, PWideChar(UTF8Decode(URI.Host)), 443, 0);
    if Connection = nil then RaiseLastOSError;
    try
      RequestHandle := WinHttpOpenRequest(Connection, PWideChar(Method), PWideChar(Path),
        nil, nil, nil, WINHTTP_FLAG_SECURE or WINHTTP_FLAG_ESCAPE_DISABLE_QUERY);
      if RequestHandle = nil then RaiseLastOSError;
      try
        Policy := WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
        if not WinHttpSetOption(RequestHandle, WINHTTP_OPTION_REDIRECT_POLICY, @Policy, SizeOf(Policy)) or
           not WinHttpSendRequest(RequestHandle, PWideChar(Header), Length(Header),
             Pointer(Payload), Length(Payload), Length(Payload), 0) or
           not WinHttpReceiveResponse(RequestHandle, nil) then
          RaiseLastOSError;
        HeaderSize := SizeOf(Status);
        if not WinHttpQueryHeaders(RequestHandle, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
          nil, @Status, @HeaderSize, nil) then RaiseLastOSError;
        Result := '';
        repeat
          if Terminated then Exit;
          if not WinHttpReadData(RequestHandle, @Chunk, SizeOf(Chunk), @BytesRead) then RaiseLastOSError;
          Total := Length(Result);
          if Total + BytesRead > Limit then
            raise Exception.Create('A resposta excede o tamanho suportado.');
          if BytesRead > 0 then
          begin
            SetLength(Result, Total + BytesRead);
            Move(Chunk, Result[Total+1], BytesRead);
          end;
        until BytesRead = 0;
        CadLog('AI.HTTP.RESP', Format('provider=%s status=%d url=%s bytes=%d',
          [CadAIProviderNames[FProvider], Status, URL, Length(Result)]));
        CheckHTTP(Status, CadAIProviderNames[FProvider], URL, Result, FKey);
      finally
        WinHttpCloseHandle(RequestHandle);
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
      Updated := curl_slist_append(Headers, PChar('Content-Type: ' + ContentType));
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
       ((curl_easy_setopt(Client, CURLOPT_POSTFIELDS, [PChar(Payload)]) <> CURLE_OK) or
        (curl_easy_setopt(Client, CURLOPT_POSTFIELDSIZE, [clong(Length(Payload))]) <> CURLE_OK)) then
      raise Exception.Create('Falha ao preparar a requisição de geração.');
    if curl_easy_perform(Client) <> CURLE_OK then
    begin
      if Transfer.TooLarge then raise Exception.Create('A resposta excede o tamanho suportado.');
      raise Exception.Create('Não foi possível concluir a conexão HTTPS com o provedor.');
    end;
    Status := 0;
    if curl_easy_getinfo(Client, CURLINFO_RESPONSE_CODE, [Pointer(@Status)]) <> CURLE_OK then
      raise Exception.Create('Não foi possível ler o status da requisição HTTPS.');
    SetString(Result, PChar(Transfer.Stream.Memory), Transfer.Stream.Size);
    CadLog('AI.HTTP.RESP', Format('provider=%s status=%d url=%s bytes=%d',
      [CadAIProviderNames[FProvider], Status, URL, Length(Result)]));
    CheckHTTP(Status, CadAIProviderNames[FProvider], URL, Result, FKey);
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
