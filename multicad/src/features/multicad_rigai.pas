unit multicad_rigai;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, SysUtils, fpjson, multicad_mesh, multicad_rig;

function CadRigGeometryContext(const Meshes: array of TCadMesh): string;
function ParseCadRigAIResponse(const Response: string): TCadRig;

type
  TCadRigAIJob = class(TThread)
  private
    FContext, FPrompt, FEndpoint, FKey, FModel, FError: string;
    FRig: TCadRig;
    procedure ReadProgress(Sender: TObject; const ContentLength, CurrentPos: Int64);
  protected
    procedure Execute; override;
  public
    constructor Create(const Context, Prompt, Endpoint, Key, Model: string);
    destructor Destroy; override;
    function TakeRig: TCadRig; { after Finished + WaitFor }
    function IsCancelled: Boolean;
    property ErrorMessage: string read FError;
  end;

implementation

uses Math, jsonparser, URIParser, multicad_types,
  {$IFDEF WINDOWS}Windows, WinHttp{$ELSE}fphttpclient, opensslsockets{$ENDIF};

type
  TLimitedReply = class(TMemoryStream)
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

function TLimitedReply.Write(const Buffer; Count: LongInt): LongInt;
begin
  if (Count<0) or (Size+Int64(Count)>1024*1024) then
    raise Exception.Create('Resposta da IA maior que 1 MB.');
  Result:=inherited Write(Buffer,Count);
end;

function CadRigGeometryContext(const Meshes: array of TCadMesh): string;
var Root,O: TJSONObject; Bodies,Points: TJSONArray; I,J,Step: Integer; B: TCadBox3;
begin
  Root:=TJSONObject.Create;
  try
    Root.Add('units','mm'); Root.Add('up_axis','y'); Root.Add('front_axis','z');
    Bodies:=TJSONArray.Create; Root.Add('bodies',Bodies);
    if Length(Meshes)>64 then raise Exception.Create('Selecione um modelo com até 64 corpos.');
    for I:=0 to High(Meshes) do
    begin
      B:=Meshes[I].Bounds;
      if B.Empty then Continue;
      O:=TJSONObject.Create; Bodies.Add(O);
      O.Add('min',CadRigVectorJSON(B.Min)); O.Add('max',CadRigVectorJSON(B.Max));
      O.Add('triangle_count',Meshes[I].TriCount);
      Points:=TJSONArray.Create; O.Add('sampled_vertices',Points);
      Step:=Max(1,(Meshes[I].VertCount+255) div 256); J:=0;
      while J<Meshes[I].VertCount do
      begin Points.Add(CadRigVectorJSON(Meshes[I].Verts[J])); Inc(J,Step); end;
    end;
    if Bodies.Count=0 then raise Exception.Create('Não há malha para analisar.');
    Result:=Root.AsJSON;
  finally Root.Free; end;
end;

function ParseCadRigAIResponse(const Response: string): TCadRig;
var D,Content: TJSONData; S: string; P: SizeInt;
begin
  D:=GetJSON(Response,True);
  try
    Content:=D.FindPath('choices[0].message.content');
    if Content=nil then Content:=D.FindPath('message.content');
    if not (Content is TJSONString) then raise Exception.Create('A IA não retornou o JSON do esqueleto.');
    S:=Trim(Content.AsString);
    if Copy(S,1,3)='```' then
    begin
      P:=Pos(#10,S);
      if P=0 then raise Exception.Create('Bloco JSON incompleto.');
      Delete(S,1,P); S:=Trim(S);
      if Copy(S,Length(S)-2,3)<>'```' then raise Exception.Create('Bloco JSON incompleto.');
      Delete(S,Length(S)-2,3); S:=Trim(S);
    end;
    Content:=GetJSON(S,True);
    try
      Result:=TCadRig.Create;
      try
        Result.LoadJSON(Content);
        if Result.Count=0 then raise Exception.Create('A IA retornou um esqueleto vazio.');
        Result.Script:=''; Result.MotionJSON:='';
      except Result.Free; raise; end;
    finally Content.Free; end;
  finally D.Free; end;
end;

constructor TCadRigAIJob.Create(const Context, Prompt, Endpoint, Key, Model: string);
begin
  inherited Create(True);
  FContext:=Context; FPrompt:=Prompt; FEndpoint:=Endpoint; FKey:=Key; FModel:=Model;
end;

destructor TCadRigAIJob.Destroy;
begin Terminate; inherited Destroy; FRig.Free; end;

function TCadRigAIJob.TakeRig: TCadRig;
begin Result:=FRig; FRig:=nil; end;

function TCadRigAIJob.IsCancelled: Boolean;
begin Result:=Terminated; end;

procedure TCadRigAIJob.ReadProgress(Sender: TObject; const ContentLength, CurrentPos: Int64);
begin
  if Terminated then raise EAbort.Create('Geração cancelada.');
  if (ContentLength>1024*1024) or (CurrentPos>1024*1024) then
    raise Exception.Create('Resposta da IA maior que 1 MB.');
end;

{$IFDEF WINDOWS}
function RigHTTPTimeouts(Session: HINTERNET; Resolve, Connect, Send, Receive: LongInt): BOOL;
  stdcall; external 'winhttp.dll' name 'WinHttpSetTimeouts';

function RigPost(const Endpoint, Key, Payload: string; Job: TCadRigAIJob): string;
var URI: TURI; Session, Connection, Request: HINTERNET; Port: Word;
    Flags, Policy, Size, Status, ReadBytes: DWORD;
    Path, Headers: UnicodeString; Chunk: array[0..8191] of Byte; N: Integer;
begin
  Result:=''; URI:=ParseURI(Endpoint,False); Port:=URI.Port; Flags:=0;
  if URI.Protocol='https' then begin Flags:=WINHTTP_FLAG_SECURE; if Port=0 then Port:=443; end
  else if Port=0 then Port:=80;
  Path:=UTF8Decode(URI.Path+URI.Document);
  if Path='' then Path:='/';
  if URI.Params<>'' then Path:=Path+'?'+UTF8Decode(URI.Params);
  Headers:='Content-Type: application/json'+#13#10;
  if Key<>'' then Headers:=Headers+'Authorization: Bearer '+UTF8Decode(Key)+#13#10;
  Session:=WinHttpOpen('MultiCAD',WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,nil,nil,0);
  if Session=nil then RaiseLastOSError;
  try
    if not RigHTTPTimeouts(Session,10000,10000,30000,30000) then RaiseLastOSError;
    Connection:=WinHttpConnect(Session,PWideChar(UTF8Decode(URI.Host)),Port,0);
    if Connection=nil then RaiseLastOSError;
    try
      Request:=WinHttpOpenRequest(Connection,'POST',PWideChar(Path),nil,nil,nil,Flags);
      if Request=nil then RaiseLastOSError;
      try
        Policy:=WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
        if not WinHttpSetOption(Request,WINHTTP_OPTION_REDIRECT_POLICY,@Policy,SizeOf(Policy)) or
           not WinHttpSendRequest(Request,PWideChar(Headers),Length(Headers),Pointer(Payload),
             Length(Payload),Length(Payload),0) or not WinHttpReceiveResponse(Request,nil) then RaiseLastOSError;
        Size:=SizeOf(Status);
        if not WinHttpQueryHeaders(Request,WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
          nil,@Status,@Size,nil) then RaiseLastOSError;
        if (Status<200) or (Status>=300) then raise Exception.CreateFmt('IA do esqueleto: HTTP %d.',[Status]);
        repeat
          if Job.IsCancelled then Exit;
          if not WinHttpReadData(Request,@Chunk,SizeOf(Chunk),@ReadBytes) then RaiseLastOSError;
          N:=Length(Result);
          if N+Int64(ReadBytes)>1024*1024 then raise Exception.Create('Resposta da IA maior que 1 MB.');
          if ReadBytes>0 then begin SetLength(Result,N+ReadBytes); Move(Chunk,Result[N+1],ReadBytes); end;
        until ReadBytes=0;
      finally WinHttpCloseHandle(Request); end;
    finally WinHttpCloseHandle(Connection); end;
  finally WinHttpCloseHandle(Session); end;
end;
{$ENDIF}

procedure TCadRigAIJob.Execute;
const Instructions =
  'Propose an editable articulation skeleton for the supplied 3D mesh and user description. '+
  'Return only a JSON object: {"format":"multicad-rig","version":1,"segments":['+
  '{"id":"unique-id","name":"human name","parent":"parent-id or empty",'+
  '"pivot":[x,y,z],"tip":[x,y,z],"axis":"x or y or z","min_angle":-90,"max_angle":90,"angle":0}]}.'+
  ' All bind-pose pivot/tip coordinates are absolute model coordinates in millimeters, Y up, Z front. '+
  'Use the actual sampled geometry, bounds and description, not arbitrary scale. Each joint rotates '+
  'only on its stated axis; chain additional segments at the same joint for more axes. '+
  'Maximum 128 segments, no cycles, unique IDs/names, parents must exist, nonzero bone lengths, '+
  'limits within [-360,360] including 0. For humanoids prefer Assistente bone names '+
  'upperarm01.R, lowerarm01.R, wrist.R, upperarm01.L, lowerarm01.L, wrist.L, head. '+
  'Do not invent mesh face names. Do not return scripts. The user will review the proposal.';
var Body: TJSONObject; Messages: TJSONArray; Text: string; URI: TURI;
    {$IFNDEF WINDOWS}Client: TFPHTTPClient; Input: TStringStream; Reply: TLimitedReply;{$ENDIF}
begin
  Body:=nil;
  {$IFNDEF WINDOWS}Client:=nil; Input:=nil; Reply:=nil;{$ENDIF}
  try
    try
      if Terminated then Exit;
      URI:=ParseURI(FEndpoint,False);
      if ((URI.Protocol<>'https') and (URI.Protocol<>'http')) or (URI.Host='') or
         (URI.Username<>'') or (URI.Password<>'') or (FModel='') or
         (Pos(#13,FKey)>0) or (Pos(#10,FKey)>0) then
        raise Exception.Create('Configure o endpoint, modelo e chave da IA do esqueleto.');
      {$IFNDEF WINDOWS}
      Client:=TFPHTTPClient.Create(nil); Client.AllowRedirect:=False;
      Client.ConnectTimeout:=10000; Client.IOTimeout:=30000;
      Client.OnDataReceived:=@ReadProgress;
      Client.AddHeader('Content-Type','application/json');
      if FKey<>'' then Client.AddHeader('Authorization','Bearer '+FKey);
      {$ENDIF}
      Body:=TJSONObject.Create; Body.Add('model',FModel); Body.Add('stream',False);
      Messages:=TJSONArray.Create; Body.Add('messages',Messages);
      Messages.Add(TJSONObject.Create(['role','system','content',Instructions]));
      Messages.Add(TJSONObject.Create(['role','user','content',FPrompt+LineEnding+FContext]));
      {$IFDEF WINDOWS}
      Text:=RigPost(FEndpoint,FKey,Body.AsJSON,Self);
      {$ELSE}
      Input:=TStringStream.Create(Body.AsJSON); Client.RequestBody:=Input;
      Reply:=TLimitedReply.Create;
      Client.Post(FEndpoint,Reply);
      if Terminated then Exit;
      SetString(Text,PChar(Reply.Memory),Reply.Size);
      {$ENDIF}
      if Terminated then Exit;
      FRig:=ParseCadRigAIResponse(Text);
    except
      on E: Exception do
      begin
        FError:=E.Message;
        if FKey<>'' then FError:=StringReplace(FError,FKey,'[chave omitida]',[rfReplaceAll]);
      end;
    end;
  finally
    {$IFNDEF WINDOWS}Client.Free; Reply.Free; Input.Free;{$ENDIF}
    Body.Free; FKey:='';
  end;
end;

end.
