unit multiproject_pg_store;

{ Optional PostgreSQL project document repository.
  Legacy JSON files are independent and always supported.
  PostgreSQL access is intended for trusted local networks.
  Remote web/desktop access over the Internet must use the future HTTPS API. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TPJStoredProject = record
    Id, Name, Code: string;
    Revision: Int64;
  end;
  TPJStoredProjects = array of TPJStoredProject;

function PJPGEnabled: Boolean;
procedure PJPGList(out AProjects: TPJStoredProjects);
procedure PJPGCreate(const AName, ADocument: string;
  out AId: string; out ARevision: Int64);
procedure PJPGRead(const AId: string; out AName, ADocument: string;
  out ARevision: Int64);
procedure PJPGUpdate(const AId, AName, ADocument: string;
  AExpectedRevision: Int64; out ANewRevision: Int64);
procedure PJPGDelete(const AId: string; AExpectedRevision: Int64);

implementation

uses
  Classes, IniFiles, SQLDB, PQConnection;

const
  DEFAULT_ORG = '00000000-0000-4000-8000-000000000001';

function ConfigName: string;
begin
  Result := Trim(GetEnvironmentVariable('MULTIPROJECT_DB_CONFIG'));
  if Result = '' then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
      'config' + DirectorySeparator + 'postgres.ini';
end;

function PJPGEnabled: Boolean;
var Ini: TIniFile;
begin
  Result := False;
  if not FileExists(ConfigName) then Exit;
  Ini := TIniFile.Create(ConfigName);
  try
    Result := Ini.ReadBool('postgres', 'enabled', False);
  finally
    Ini.Free;
  end;
end;

function SafeIdentifier(const S: string): string;
var I: Integer;
begin
  if (Length(S) < 1) or (Length(S) > 63) then
    raise Exception.Create('Schema PostgreSQL invalido');
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', 'A'..'Z', '_', '0'..'9']) or
      ((I = 1) and (S[I] in ['0'..'9'])) then
      raise Exception.Create('Schema PostgreSQL invalido');
  Result := '"' + S + '"';
end;

procedure Connect(out C: TPQConnection; out Tx: TSQLTransaction;
  out ASchema, AOrg: string);
var
  Ini: TIniFile;
  Host, DBName, Username, PassVar, SSLMode: string;
  Port: Integer;
begin
  C := nil; Tx := nil;
  if not PJPGEnabled then
    raise Exception.Create('PostgreSQL opcional desabilitado. Copie config/postgres.example.ini para config/postgres.ini e habilite enabled=true.');
  Ini := TIniFile.Create(ConfigName);
  try
    Host := Trim(Ini.ReadString('postgres', 'host', '127.0.0.1'));
    DBName := Trim(Ini.ReadString('postgres', 'database', ''));
    Username := Trim(Ini.ReadString('postgres', 'user', ''));
    Port := Ini.ReadInteger('postgres', 'port', 5432);
    ASchema := SafeIdentifier(Trim(Ini.ReadString('postgres', 'schema', 'multiproject')));
    AOrg := Trim(Ini.ReadString('postgres', 'organization_id', DEFAULT_ORG));
    PassVar := Trim(Ini.ReadString('postgres', 'password_env', 'MULTIPROJECT_DB_PASSWORD'));
    SSLMode := Trim(Ini.ReadString('postgres', 'sslmode', 'prefer'));
  finally
    Ini.Free;
  end;
  if (Length(AOrg) <> 36) or (Host = '') or (DBName = '') or (Username = '') or
     (Port < 1) or (Port > 65535) then
    raise Exception.Create('Configuracao PostgreSQL incompleta ou invalida');
  if not ((SSLMode = 'disable') or (SSLMode = 'allow') or
    (SSLMode = 'prefer') or (SSLMode = 'require') or
    (SSLMode = 'verify-ca') or (SSLMode = 'verify-full')) then
    raise Exception.Create('sslmode PostgreSQL invalido');
  C := TPQConnection.Create(nil);
  Tx := TSQLTransaction.Create(nil);
  try
    C.HostName := Host;
    C.DatabaseName := DBName;
    C.UserName := Username;
    C.Password := GetEnvironmentVariable(PassVar);
    C.CharSet := 'UTF8';
    C.LoginPrompt := False;
    C.Params.Values['port'] := IntToStr(Port);
    C.Params.Values['sslmode'] := SSLMode;
    C.Transaction := Tx;
    Tx.Database := C;
    C.Connected := True;
    Tx.StartTransaction;
  except
    C.Free; C := nil;
    Tx.Free; Tx := nil;
    raise;
  end;
end;

procedure Disconnect(var C: TPQConnection; var Tx: TSQLTransaction);
begin
  if Tx <> nil then
  begin
    if Tx.Active then Tx.Rollback;
    Tx.Free; Tx := nil;
  end;
  if C <> nil then
  begin
    C.Free; C := nil;
  end;
end;

function QueryFor(C: TPQConnection; Tx: TSQLTransaction): TSQLQuery;
begin
  Result := TSQLQuery.Create(nil);
  Result.Database := C;
  Result.Transaction := Tx;
end;

procedure PJPGList(out AProjects: TPJStoredProjects);
var C: TPQConnection; Tx: TSQLTransaction; Q: TSQLQuery;
    Schema, Org: string; N: Integer;
begin
  SetLength(AProjects, 0);
  Connect(C, Tx, Schema, Org);
  try
    Q := QueryFor(C, Tx);
    try
      Q.SQL.Text := 'SELECT CAST(id AS text) AS id, name, code, revision FROM ' +
        Schema + '.projects WHERE organization_id = CAST(:org AS uuid) ' +
        'ORDER BY updated_at DESC, name';
      Q.Params.ParamByName('org').AsString := Org;
      Q.Open;
      while not Q.EOF do
      begin
        N := Length(AProjects);
        SetLength(AProjects, N + 1);
        AProjects[N].Id := Q.FieldByName('id').AsString;
        AProjects[N].Name := Q.FieldByName('name').AsString;
        AProjects[N].Code := Q.FieldByName('code').AsString;
        AProjects[N].Revision := Q.FieldByName('revision').AsLargeInt;
        Q.Next;
      end;
      Q.Close;
      Tx.Commit;
    finally
      Q.Free;
    end;
  finally
    Disconnect(C, Tx);
  end;
end;

procedure PJPGCreate(const AName, ADocument: string;
  out AId: string; out ARevision: Int64);
var C: TPQConnection; Tx: TSQLTransaction; Q: TSQLQuery;
    Schema, Org: string;
begin
  if Trim(AName) = '' then raise Exception.Create('Nome do projeto obrigatorio');
  Connect(C, Tx, Schema, Org);
  try
    Q := QueryFor(C, Tx);
    try
      Q.SQL.Text := 'INSERT INTO ' + Schema +
        '.organizations (id, name) VALUES (CAST(:org AS uuid), :name) ' +
        'ON CONFLICT (id) DO NOTHING';
      Q.Params.ParamByName('org').AsString := Org;
      Q.Params.ParamByName('name').AsString := 'Organizacao padrao';
      Q.ExecSQL;
      Q.SQL.Text := 'WITH new_id AS (SELECT gen_random_uuid() AS id) ' +
        'INSERT INTO ' + Schema +
        '.projects (id, organization_id, code, name, document) ' +
        'SELECT id, CAST(:org AS uuid), CAST(id AS text), :name, ' +
        'CAST(:document AS jsonb) FROM new_id ' +
        'RETURNING CAST(id AS text) AS id, revision';
      Q.Params.ParamByName('org').AsString := Org;
      Q.Params.ParamByName('name').AsString := Trim(AName);
      Q.Params.ParamByName('document').AsString := ADocument;
      Q.Open;
      if Q.EOF then raise Exception.Create('Nao foi possivel incluir o projeto no PostgreSQL');
      AId := Q.FieldByName('id').AsString;
      ARevision := Q.FieldByName('revision').AsLargeInt;
      Q.Close;
      Tx.Commit;
    finally
      Q.Free;
    end;
  finally
    Disconnect(C, Tx);
  end;
end;

procedure PJPGRead(const AId: string; out AName, ADocument: string;
  out ARevision: Int64);
var C: TPQConnection; Tx: TSQLTransaction; Q: TSQLQuery;
    Schema, Org: string;
begin
  Connect(C, Tx, Schema, Org);
  try
    Q := QueryFor(C, Tx);
    try
      Q.SQL.Text := 'SELECT name, CAST(document AS text) AS document, revision ' +
        'FROM ' + Schema + '.projects WHERE id = CAST(:id AS uuid) ' +
        'AND organization_id = CAST(:org AS uuid)';
      Q.Params.ParamByName('id').AsString := AId;
      Q.Params.ParamByName('org').AsString := Org;
      Q.Open;
      if Q.EOF then raise Exception.Create('Projeto nao encontrado no banco de dados');
      AName := Q.FieldByName('name').AsString;
      ADocument := Q.FieldByName('document').AsString;
      ARevision := Q.FieldByName('revision').AsLargeInt;
      Q.Close;
      Tx.Commit;
    finally
      Q.Free;
    end;
  finally
    Disconnect(C, Tx);
  end;
end;

procedure PJPGUpdate(const AId, AName, ADocument: string;
  AExpectedRevision: Int64; out ANewRevision: Int64);
var C: TPQConnection; Tx: TSQLTransaction; Q: TSQLQuery;
    Schema, Org: string;
begin
  Connect(C, Tx, Schema, Org);
  try
    Q := QueryFor(C, Tx);
    try
      Q.SQL.Text := 'UPDATE ' + Schema +
        '.projects SET name = :name, document = CAST(:document AS jsonb), ' +
        'revision = revision + 1, updated_at = now() ' +
        'WHERE id = CAST(:id AS uuid) AND organization_id = CAST(:org AS uuid) ' +
        'AND revision = :revision RETURNING revision';
      Q.Params.ParamByName('name').AsString := Trim(AName);
      Q.Params.ParamByName('document').AsString := ADocument;
      Q.Params.ParamByName('id').AsString := AId;
      Q.Params.ParamByName('org').AsString := Org;
      Q.Params.ParamByName('revision').AsLargeInt := AExpectedRevision;
      Q.Open;
      if Q.EOF then
        raise Exception.Create('Conflito: projeto alterado por outra sessao ou excluido. Reabra o projeto antes de salvar.');
      ANewRevision := Q.FieldByName('revision').AsLargeInt;
      Q.Close;
      Tx.Commit;
    finally
      Q.Free;
    end;
  finally
    Disconnect(C, Tx);
  end;
end;

procedure PJPGDelete(const AId: string; AExpectedRevision: Int64);
var C: TPQConnection; Tx: TSQLTransaction; Q: TSQLQuery;
    Schema, Org: string;
begin
  Connect(C, Tx, Schema, Org);
  try
    Q := QueryFor(C, Tx);
    try
      Q.SQL.Text := 'DELETE FROM ' + Schema +
        '.projects WHERE id = CAST(:id AS uuid) AND ' +
        'organization_id = CAST(:org AS uuid) AND revision = :revision ' +
        'RETURNING id';
      Q.Params.ParamByName('id').AsString := AId;
      Q.Params.ParamByName('org').AsString := Org;
      Q.Params.ParamByName('revision').AsLargeInt := AExpectedRevision;
      Q.Open;
      if Q.EOF then raise Exception.Create('Conflito: projeto alterado ou excluido. Atualize a lista.');
      Q.Close;
      Tx.Commit;
    finally
      Q.Free;
    end;
  finally
    Disconnect(C, Tx);
  end;
end;

end.
