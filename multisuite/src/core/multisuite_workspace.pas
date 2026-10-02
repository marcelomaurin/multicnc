unit multisuite_workspace;
{$mode objfpc}{$H+}

interface
uses Classes, SysUtils, StrUtils, multisuite_types;
type
  // Novos tipos ficam no fim: os ordinais fazem parte do formato legado.
  TArtifactKind = (akCAD, akPCB, akAssembly, akCAM, akSlicer, akLaserPCB,
    akLaserArt, akGCode, akOther, akPhysics);
  TProjectArtifact = record
    Name, FileName: string;
    Kind: TArtifactKind;
    Tool: TSuiteToolID;
  end;
  TWorkflowStage = (wsDesign, wsElectronics, wsAssembly, wsManufacturing, wsSimulation, wsExecution);
  TStageState = (ssPending, ssReady, ssDone, ssBlocked);
  TWorkflowState = array[TWorkflowStage] of TStageState;
  EWorkspaceFormat = class(Exception);
  TWorkspace = class
  private
    FProject: TSuiteProject;
    FArtifacts: array of TProjectArtifact;
    FWorkflow: TWorkflowState;
    FFileName: string;
    FModified: Boolean;
  public
    procedure NewProject(const AName, ARoot: string);
    procedure AddArtifact(const A: TProjectArtifact);
    procedure RemoveArtifact(I: Integer);
    function ArtifactCount: Integer;
    function Artifact(I: Integer): TProjectArtifact;
    function ArtifactPath(I: Integer): string;
    procedure SetStage(S: TWorkflowStage; State: TStageState);
    function Stage(S: TWorkflowStage): TStageState;
    procedure Save(const FN: string);
    procedure Load(const FN: string);
    property Project: TSuiteProject read FProject;
    property FileName: string read FFileName;
    property Modified: Boolean read FModified;
  end;
function ArtifactKindName(K: TArtifactKind): string;
function StageName(S: TWorkflowStage): string;
function StateName(S: TStageState): string;

implementation

function ArtifactKindName(K: TArtifactKind): string;
begin
  case K of
    akCAD: Result := 'CAD'; akPCB: Result := 'PCB';
    akAssembly: Result := 'Assembly'; akCAM: Result := 'CAM';
    akSlicer: Result := 'Slicer'; akLaserPCB: Result := 'LaserPCB';
    akLaserArt: Result := 'LaserArt'; akGCode: Result := 'G-code';
    akPhysics: Result := 'Physics';
  else Result := 'Outro'; end;
end;
function StageName(S: TWorkflowStage): string;
begin
  case S of
    wsDesign: Result := 'Projeto'; wsElectronics: Result := 'Eletronica';
    wsAssembly: Result := 'Montagem'; wsManufacturing: Result := 'Fabricacao';
    wsSimulation: Result := 'Simulacao'; wsExecution: Result := 'Execucao';
  end;
end;
function StateName(S: TStageState): string;
begin
  case S of
    ssPending: Result := 'Pendente'; ssReady: Result := 'Pronto';
    ssDone: Result := 'Concluido'; ssBlocked: Result := 'Bloqueado';
  end;
end;

// Escape somente no formato 2; arquivos antigos continuam sendo lidos.
function Encode(const S: string): string;
var I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '%', '|', #10, #13: Result := Result + '%' + IntToHex(Ord(S[I]), 2);
    else Result := Result + S[I]; end;
end;
function Decode(const S: string): string;
var I, V: Integer;
begin
  Result := ''; I := 1;
  while I <= Length(S) do begin
    if S[I] = '%' then begin
      if (I + 2 > Length(S)) or not TryStrToInt('$' + Copy(S, I + 1, 2), V) then
        raise EWorkspaceFormat.Create('Escape invalido no projeto.');
      Result := Result + Chr(V); Inc(I, 3);
    end else begin Result := Result + S[I]; Inc(I); end;
  end;
end;
function AbsolutePath(const S: string): Boolean;
begin
  Result := (S <> '') and ((S[1] in ['/', '\']) or (ExtractFileDrive(S) <> ''));
end;
function ResolvePath(const Base, S: string): string;
begin
  if AbsolutePath(S) then Result := ExpandFileName(S)
  else Result := ExpandFileName(IncludeTrailingPathDelimiter(Base) + S);
end;

procedure TWorkspace.NewProject(const AName, ARoot: string);
var S: TWorkflowStage;
begin
  if (Trim(AName) = '') or (Trim(ARoot) = '') then
    raise EWorkspaceFormat.Create('Informe o nome e o diretorio do projeto.');
  FProject.Name := AName; FProject.RootPath := ExpandFileName(ARoot);
  FProject.Description := ''; FFileName := ''; SetLength(FArtifacts, 0);
  for S := Low(TWorkflowStage) to High(TWorkflowStage) do FWorkflow[S] := ssPending;
  FWorkflow[wsDesign] := ssReady; FModified := True;
end;
procedure TWorkspace.AddArtifact(const A: TProjectArtifact);
var N: Integer; Relative: string;
begin
  if FProject.Name = '' then raise EWorkspaceFormat.Create('Crie ou abra um projeto primeiro.');
  if (Trim(A.Name) = '') or (Trim(A.FileName) = '') then
    raise EWorkspaceFormat.Create('O artefato precisa de nome e arquivo.');
  N := Length(FArtifacts); SetLength(FArtifacts, N + 1); FArtifacts[N] := A;
  if AbsolutePath(A.FileName) then begin
    Relative := ExtractRelativePath(IncludeTrailingPathDelimiter(FProject.RootPath), ExpandFileName(A.FileName));
    if (Copy(Relative, 1, 3) <> '..' + DirectorySeparator) and not AbsolutePath(Relative) then
      FArtifacts[N].FileName := Relative
    else FArtifacts[N].FileName := ExpandFileName(A.FileName);
  end;
  FModified := True;
end;
procedure TWorkspace.RemoveArtifact(I: Integer);
var J: Integer;
begin
  if (I < 0) or (I >= Length(FArtifacts)) then raise ERangeError.Create('Artefato invalido.');
  for J := I to High(FArtifacts) - 1 do FArtifacts[J] := FArtifacts[J + 1];
  SetLength(FArtifacts, Length(FArtifacts) - 1); FModified := True;
end;
function TWorkspace.ArtifactCount: Integer;
begin Result := Length(FArtifacts); end;
function TWorkspace.Artifact(I: Integer): TProjectArtifact;
begin
  if (I < 0) or (I >= Length(FArtifacts)) then raise ERangeError.Create('Artefato invalido.');
  Result := FArtifacts[I];
end;
function TWorkspace.ArtifactPath(I: Integer): string;
begin Result := ResolvePath(FProject.RootPath, Artifact(I).FileName); end;
procedure TWorkspace.SetStage(S: TWorkflowStage; State: TStageState);
begin
  if FWorkflow[S] <> State then begin FWorkflow[S] := State; FModified := True; end;
end;
function TWorkspace.Stage(S: TWorkflowStage): TStageState;
begin Result := FWorkflow[S]; end;

procedure TWorkspace.Save(const FN: string);
var Lines: TStringList; I: Integer; St: TWorkflowStage; A: TProjectArtifact;
  Target, Temp, Backup, Dir: string;
begin
  if FProject.Name = '' then raise EWorkspaceFormat.Create('Nenhum projeto para salvar.');
  if FN = '' then raise EWorkspaceFormat.Create('Informe o arquivo do projeto.');
  Target := ExpandFileName(FN); Dir := ExtractFileDir(Target);
  if not ForceDirectories(Dir) then raise EInOutError.Create('Nao foi possivel criar: ' + Dir);
  Lines := TStringList.Create; Temp := ''; Backup := '';
  try
    Lines.Add('[project]'); Lines.Add('version=2');
    Lines.Add('name=' + Encode(FProject.Name));
    Lines.Add('root=' + Encode(StringReplace(ExtractRelativePath(IncludeTrailingPathDelimiter(Dir),
      IncludeTrailingPathDelimiter(FProject.RootPath)), DirectorySeparator, '/', [rfReplaceAll])));
    Lines.Add('description=' + Encode(FProject.Description));
    Lines.Add('[workflow]');
    for St := Low(TWorkflowStage) to High(TWorkflowStage) do
      Lines.Add(IntToStr(Ord(St)) + '=' + IntToStr(Ord(FWorkflow[St])));
    Lines.Add('[artifacts]');
    for I := 0 to High(FArtifacts) do begin
      A := FArtifacts[I];
      Lines.Add(IntToStr(Ord(A.Kind)) + '|' + IntToStr(Ord(A.Tool)) + '|' +
        Encode(A.Name) + '|' + Encode(StringReplace(A.FileName, DirectorySeparator, '/', [rfReplaceAll])));
    end;
    // Grava antes de substituir. Em Windows, RenameFile nao substitui o destino.
    Temp := GetTempFileName(Dir, 'msu'); Lines.SaveToFile(Temp);
    if FileExists(Target) then begin
      Backup := GetTempFileName(Dir, 'bak'); DeleteFile(Backup);
      if not RenameFile(Target, Backup) then
        raise EInOutError.Create('Nao foi possivel substituir: ' + Target);
    end;
    if not RenameFile(Temp, Target) then begin
      if Backup <> '' then RenameFile(Backup, Target);
      raise EInOutError.Create('Nao foi possivel salvar: ' + Target);
    end;
    Temp := ''; if Backup <> '' then DeleteFile(Backup);
    FFileName := Target; FModified := False;
  finally
    if Temp <> '' then DeleteFile(Temp);
    Lines.Free;
  end;
end;

procedure TWorkspace.Load(const FN: string);
var Lines: TStringList; Candidate: TWorkspace; Stream: TFileStream;
  I, P1, P2, P3, N, V, Version: Integer;
  Sec, L, Key, Value, Name, Root, Description, Target: string;
  A: TProjectArtifact;
  function TextValue(const S: string): string;
  begin if Version = 2 then Result := Decode(S) else Result := S; end;
  function CheckedInt(const S: string; Lo, Hi: Integer): Integer;
  begin
    if not TryStrToInt(S, Result) or (Result < Lo) or (Result > Hi) then
      raise EWorkspaceFormat.CreateFmt('Valor invalido na linha %d: %s', [I + 1, S]);
  end;
begin
  Target := ExpandFileName(FN); Lines := TStringList.Create; Candidate := TWorkspace.Create;
  try
    Stream := TFileStream.Create(Target, fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size > 4 * 1024 * 1024 then raise EWorkspaceFormat.Create('Projeto maior que 4 MB.');
      Lines.LoadFromStream(Stream);
    finally Stream.Free; end;
    Version := 1; Sec := ''; Name := ''; Root := ''; Description := '';
    for I := 0 to Lines.Count - 1 do begin
      L := Trim(Lines[I]);
      if (L <> '') and (L[1] = '[') then Sec := L
      else if (Sec = '[project]') and (Pos('version=', L) = 1) then
        Version := CheckedInt(Copy(L, 9, MaxInt), 1, 2);
    end;
    Sec := '';
    for I := 0 to Lines.Count - 1 do begin
      L := Lines[I];
      if (Trim(L) = '') or (L[1] in [';', '#']) then Continue;
      if L[1] = '[' then begin Sec := Trim(L); Continue; end;
      if Sec <> '[project]' then Continue;
      P1 := Pos('=', L); if P1 = 0 then raise EWorkspaceFormat.Create('Chave de projeto invalida.');
      Key := Copy(L, 1, P1 - 1); Value := TextValue(Copy(L, P1 + 1, MaxInt));
      if Key = 'name' then Name := Value else if Key = 'root' then Root := Value
      else if Key = 'description' then Description := Value;
    end;
    if Root = '' then Root := '.';
    if Version = 2 then Root := StringReplace(Root, '/', DirectorySeparator, [rfReplaceAll]);
    Candidate.NewProject(Name, ResolvePath(ExtractFileDir(Target), Root));
    Candidate.FProject.Description := Description; Sec := '';
    for I := 0 to Lines.Count - 1 do begin
      L := Lines[I];
      if (Trim(L) = '') or (L[1] in [';', '#']) then Continue;
      if L[1] = '[' then begin Sec := Trim(L); Continue; end;
      if Sec = '[workflow]' then begin
        P1 := Pos('=', L); if P1 = 0 then raise EWorkspaceFormat.Create('Etapa de projeto invalida.');
        N := CheckedInt(Copy(L, 1, P1 - 1), Ord(Low(TWorkflowStage)), Ord(High(TWorkflowStage)));
        V := CheckedInt(Copy(L, P1 + 1, MaxInt), Ord(Low(TStageState)), Ord(High(TStageState)));
        Candidate.SetStage(TWorkflowStage(N), TStageState(V));
      end else if Sec = '[artifacts]' then begin
        P1 := Pos('|', L); P2 := PosEx('|', L, P1 + 1); P3 := PosEx('|', L, P2 + 1);
        if (P1 = 0) or (P2 <= P1) or (P3 <= P2) then
          raise EWorkspaceFormat.CreateFmt('Artefato invalido na linha %d.', [I + 1]);
        A.Kind := TArtifactKind(CheckedInt(Copy(L, 1, P1 - 1), Ord(Low(TArtifactKind)), Ord(High(TArtifactKind))));
        A.Tool := TSuiteToolID(CheckedInt(Copy(L, P1 + 1, P2 - P1 - 1), Ord(Low(TSuiteToolID)), Ord(High(TSuiteToolID))));
        A.Name := TextValue(Copy(L, P2 + 1, P3 - P2 - 1));
        A.FileName := TextValue(Copy(L, P3 + 1, MaxInt));
        if Version = 2 then A.FileName := StringReplace(A.FileName, '/', DirectorySeparator, [rfReplaceAll]);
        Candidate.AddArtifact(A);
      end;
    end;
    // Publica o novo estado apenas depois de validar o documento inteiro.
    FProject := Candidate.FProject; FArtifacts := Candidate.FArtifacts;
    FWorkflow := Candidate.FWorkflow; FFileName := Target; FModified := False;
  finally Candidate.Free; Lines.Free; end;
end;
end.
