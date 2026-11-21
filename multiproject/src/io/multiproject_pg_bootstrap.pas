unit multiproject_pg_bootstrap;

{ PostgreSQL bootstrap. Opt-in: config/postgres.ini or MULTIPROJECT_DB_CONFIG.
  Runs only numbered single-statement SQL migrations, each in its own
  transaction. No project content is imported or overwritten here. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function PJBootstrapPostgres(out AStatus: string): Boolean;

implementation

uses
  Classes, IniFiles, SQLDB, PQConnection;

function SQLIdentifier(const S: string): string;
var I: Integer;
begin
  if (Length(S) = 0) or (Length(S) > 63) then
    raise Exception.Create('Nome do schema PostgreSQL invalido');
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', 'A'..'Z', '_', '0'..'9']) or
       ((I = 1) and (S[I] in ['0'..'9'])) then
      raise Exception.Create('Nome do schema contem caracteres invalidos');
  Result := '"' + S + '"';
end;

function FindMigrations(const AConfigured: string): string;
var
  Base, Candidate: string;
  I: Integer;
const
  Candidates: array[0..4] of string = (
    'sql/migrations',
    '../sql/migrations',
    '../../sql/migrations',
    '../multiproject/sql/migrations',
    'multiproject/sql/migrations');
begin
  if Trim(AConfigured) <> '' then
  begin
    Result := ExpandFileName(AConfigured);
    if not DirectoryExists(Result) then
      raise Exception.Create('Pasta sql/migrations nao encontrada: ' + Result);
    Exit;
  end;
  Base := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  for I := Low(Candidates) to High(Candidates) do
  begin
    Candidate := ExpandFileName(Base + Candidates[I]);
    if DirectoryExists(Candidate) then Exit(Candidate);
  end;
  raise Exception.Create('Pasta sql/migrations nao encontrada ao lado do executavel');
end;

procedure ExecOne(Q: TSQLQuery; const SQL: string);
begin
  Q.Close;
  Q.SQL.Text := SQL;
  Q.ExecSQL;
end;

function PJBootstrapPostgres(out AStatus: string): Boolean;
var
  ConfigPath, Schema, QuotedSchema, DirectoryName, Version, SQL: string;
  Host, DatabaseName, Username, PasswordEnv, SSLMode: string;
  Port, I, CountApplied: Integer;
  Cfg: TIniFile;
  Conn: TPQConnection;
  Tx: TSQLTransaction;
  Q: TSQLQuery;
  Files, Source: TStringList;
  Search: TSearchRec;
  AlreadyApplied: Boolean;
begin
  Result := False;
  AStatus := 'Banco desabilitado: projetos locais continuam disponiveis';
  ConfigPath := Trim(GetEnvironmentVariable('MULTIPROJECT_DB_CONFIG'));
  if ConfigPath = '' then
    ConfigPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
      'config' + DirectorySeparator + 'postgres.ini';
  if not FileExists(ConfigPath) then Exit;

  Cfg := TIniFile.Create(ConfigPath);
  try
    if not Cfg.ReadBool('postgres', 'enabled', False) then Exit;
    Host := Trim(Cfg.ReadString('postgres', 'host', '127.0.0.1'));
    DatabaseName := Trim(Cfg.ReadString('postgres', 'database', ''));
    Username := Trim(Cfg.ReadString('postgres', 'user', ''));
    Port := Cfg.ReadInteger('postgres', 'port', 5432);
    Schema := Trim(Cfg.ReadString('postgres', 'schema', 'multiproject'));
    SSLMode := Trim(Cfg.ReadString('postgres', 'sslmode', 'prefer'));
    PasswordEnv := Trim(Cfg.ReadString('postgres', 'password_env',
      'MULTIPROJECT_DB_PASSWORD'));
    DirectoryName := FindMigrations(
      Cfg.ReadString('postgres', 'migrations_dir', ''));
  finally
    Cfg.Free;
  end;
  if (Host = '') or (DatabaseName = '') or (Username = '') or
     (Port < 1) or (Port > 65535) then
    raise Exception.Create('Confira host, database, user e port no postgres.ini');
  if not ((SSLMode = 'disable') or (SSLMode = 'allow') or
     (SSLMode = 'prefer') or (SSLMode = 'require') or
     (SSLMode = 'verify-ca') or (SSLMode = 'verify-full')) then
    raise Exception.Create('sslmode PostgreSQL invalido');
  QuotedSchema := SQLIdentifier(Schema);

  Conn := TPQConnection.Create(nil);
  Tx := TSQLTransaction.Create(nil);
  Q := TSQLQuery.Create(nil);
  Files := TStringList.Create;
  Source := TStringList.Create;
  try
    Conn.HostName := Host;
    Conn.DatabaseName := DatabaseName;
    Conn.UserName := Username;
    Conn.Password := GetEnvironmentVariable(PasswordEnv);
    Conn.LoginPrompt := False;
    Conn.CharSet := 'UTF8';
    Conn.Params.Values['port'] := IntToStr(Port);
    Conn.Params.Values['sslmode'] := SSLMode;
    Conn.Transaction := Tx;
    Tx.Database := Conn;
    Q.Database := Conn;
    Q.Transaction := Tx;
    Conn.Connected := True;

    Tx.StartTransaction;
    try
      ExecOne(Q, 'CREATE SCHEMA IF NOT EXISTS ' + QuotedSchema);
      ExecOne(Q, 'CREATE TABLE IF NOT EXISTS ' + QuotedSchema +
        '.schema_migrations (version TEXT PRIMARY KEY,' +
        ' applied_at TIMESTAMPTZ NOT NULL DEFAULT now())');
      Tx.Commit;
    except
      if Tx.Active then Tx.Rollback;
      raise;
    end;

    if FindFirst(IncludeTrailingPathDelimiter(DirectoryName) + '*.sql',
      faAnyFile, Search) = 0 then
    begin
      repeat
        if (Search.Attr and faDirectory = 0) then
          Files.Add(Search.Name);
      until FindNext(Search) <> 0;
      FindClose(Search);
    end;
    Files.Sort;
    if Files.Count = 0 then
      raise Exception.Create('Nao foram encontradas migracoes SQL');
    CountApplied := 0;
    for I := 0 to Files.Count - 1 do
    begin
      Version := Files[I];
      Source.LoadFromFile(IncludeTrailingPathDelimiter(DirectoryName) + Version);
      SQL := Trim(StringReplace(Source.Text, '{{schema}}', QuotedSchema,
        [rfReplaceAll]));
      if SQL = '' then
        raise Exception.Create('Migracao SQL vazia: ' + Version);
      Tx.StartTransaction;
      try
        { Serializa aplicacoes concorrentes da mesma versao no mesmo schema. }
        ExecOne(Q, 'LOCK TABLE ' + QuotedSchema +
          '.schema_migrations IN EXCLUSIVE MODE');
        Q.Close;
        Q.SQL.Text := 'SELECT 1 FROM ' + QuotedSchema +
          '.schema_migrations WHERE version = :v';
        Q.Params.ParamByName('v').AsString := Version;
        Q.Open;
        AlreadyApplied := not Q.EOF;
        Q.Close;
        if not AlreadyApplied then
        begin
          { Cada arquivo deve conter exatamente uma instrucao SQL. }
          ExecOne(Q, SQL);
          Q.SQL.Text := 'INSERT INTO ' + QuotedSchema +
            '.schema_migrations (version) VALUES (:v)';
          Q.Params.ParamByName('v').AsString := Version;
          Q.ExecSQL;
          Inc(CountApplied);
        end;
        Tx.Commit;
      except
        on E: Exception do
        begin
          if Tx.Active then Tx.Rollback;
          raise Exception.Create('Falha na migracao ' + Version + ': ' + E.Message);
        end;
      end;
    end;
    AStatus := Format('PostgreSQL conectado; %d migracao(oes) aplicada(s)',
      [CountApplied]);
    Result := True;
  finally
    Source.Free;
    Files.Free;
    Q.Free;
    if Conn.Connected then Conn.Connected := False;
    Tx.Free;
    Conn.Free;
  end;
end;

end.
