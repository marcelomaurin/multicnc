unit multiproject_artifacts;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, multiproject_document, multiproject_types;
function PJArtifactFile(T: TPJTask; const ProjectFile: string): string;
procedure PJLinkArtifact(P: TPJProject; T: TPJTask; const ProjectFile, FileName: string);
function PJRefreshArtifacts(P: TPJProject; const ProjectFile: string; ForceCheck: Boolean; out Warnings: string): Boolean;
implementation
uses sha1, multiproject_checks, multiproject_kinds;
function ArtifactChain(P: TPJProject; const Id: string): string;
var IDs: TStringList; N, I: Integer;
begin
  IDs := TStringList.Create;
  try
    IDs.Add(Id); N := 0;
    while N < IDs.Count do
    begin
      for I := 0 to P.LinkCount-1 do
        if P.Links[I].Artifact and (P.Links[I].FromId = IDs[N]) and
          (IDs.IndexOf(P.Links[I].ToId) < 0) then IDs.Add(P.Links[I].ToId);
      Inc(N);
    end;
    Result := IDs.CommaText;
  finally IDs.Free; end;
end;
function PJArtifactFile(T: TPJTask; const ProjectFile: string): string;
begin
  Result := T.Artifact.Path;
  if Result = '' then Exit;
  if (ExtractFileDrive(Result) = '') and not (Result[1] in ['/', '\']) then
    Result := ExpandFileName(ExtractFilePath(ExpandFileName(ProjectFile)) + Result);
end;
procedure PJLinkArtifact(P: TPJProject; T: TPJTask; const ProjectFile, FileName: string);
begin
  P.BeginChange('Vincular arquivo');
  try
    T.Artifact.Tool := PJKindInfo(T.Kind).ToolName;
    if PJIsGCode(FileName) then T.Artifact.Tool := 'MultiCNC';
    T.Artifact.Path := ExtractRelativePath(ExtractFilePath(ExpandFileName(ProjectFile)), ExpandFileName(FileName));
    { Keep the previous hash until refresh so replacing a ready file invalidates consumers. }
    T.Artifact.Size := -1; T.Artifact.MTime := -1; T.Artifact.Status := 'none';
  finally P.EndChange; end;
end;
function PJRefreshArtifacts(P: TPJProject; const ProjectFile: string; ForceCheck: Boolean; out Warnings: string): Boolean;
var I, K: Integer; T, S: TPJTask; SR: TSearchRec; FN, Hash, Status, Msg: string;
    Size, MTime: Int64; Verified, Valid, Changed, Recording: Boolean;
  procedure BeginUpdate;
  begin
    if Recording then Exit;
    P.BeginChange('Conferir artefatos'); Recording := True;
  end;
begin
  Result := False; Warnings := ''; Recording := False;
  try
    for I := 0 to P.Count-1 do
    begin
      T := P[I]; FN := PJArtifactFile(T, ProjectFile);
      if FN = '' then Continue;
      Size := -1; MTime := -1; Hash := '';
      if FindFirst(FN, faAnyFile, SR) = 0 then
      begin
        if (SR.Attr and faDirectory) = 0 then begin Size := SR.Size; MTime := SR.Time; end;
        FindClose(SR);
      end;
      if not ForceCheck and (Size = T.Artifact.Size) and (MTime = T.Artifact.MTime) then Continue;
      try
        if Size >= 0 then Hash := SHA1Print(SHA1File(FN));
        Changed := (T.Artifact.Hash <> '') and (Hash <> T.Artifact.Hash);
        if Changed then
        begin
          BeginUpdate;
          if T.State in [tsReview, tsDone] then T.State := tsReview;
          for K := 0 to P.LinkCount-1 do
            if P.Links[K].Artifact and (P.Links[K].FromId = T.Id) then
            begin
              S := P.FindTask(P.Links[K].ToId);
              if (S <> nil) and (S.State <> tsCancelled) then S.State := tsOutdated;
            end;
          Warnings := Warnings + T.Id + ': arquivo alterado; revisar sucessoras. Cadeia: ' + ArtifactChain(P, T.Id) + LineEnding;
        end;
        Valid := PJCheckArtifact(T.Kind, FN, Verified, Msg);
        Status := 'none';
        if Size >= 0 then Status := 'created';
        if Valid and Verified then Status := 'valid';
        if Valid and Verified and (T.State = tsDone) then Status := 'ready';
        if (T.Artifact.Hash <> Hash) or (T.Artifact.Status <> Status) or
          (T.Artifact.Size <> Size) or (T.Artifact.MTime <> MTime) or
          (T.Artifact.CheckMessage <> Msg) then
        begin
          BeginUpdate;
          T.Artifact.Hash := Hash; T.Artifact.Size := Size; T.Artifact.MTime := MTime;
          T.Artifact.Status := Status; T.Artifact.CheckMessage := Msg;
          T.Artifact.CheckedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
          Result := True;
        end;
      except on E: Exception do
      begin
        BeginUpdate; T.Artifact.Status := 'created'; T.Artifact.MTime := -1;
        T.Artifact.CheckMessage := E.Message; Result := True;
        Warnings := Warnings + T.Id + ': ' + E.Message + LineEnding;
      end; end;
    end;
  finally if Recording then P.EndChange; end;
end;
end.
