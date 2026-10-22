unit multiproject_checks;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, multiproject_types;
function PJCheckArtifact(K: TPJTaskKind; const FileName: string; out Verified: Boolean; out Msg: string): Boolean;
implementation
uses fpjson, jsonparser, multisuite_gcode_writer, multiproject_kinds,
  makepcb_model, makepcb_library, makepcb_drc,
  multicad_document, multicad_rebuild;
function HasNonempty(const Pattern: string): Boolean;
var S: TSearchRec;
begin
  Result := False;
  if FindFirst(Pattern, faAnyFile, S) <> 0 then Exit;
  try
    repeat
      if ((S.Attr and faDirectory) = 0) and (S.Size > 0) then Exit(True);
    until FindNext(S) <> 0;
  finally FindClose(S); end;
end;
function PJCheckArtifact(K: TPJTaskKind; const FileName: string; out Verified: Boolean; out Msg: string): Boolean;
var L, Errors: TStringList; J: TJSONData; H: TSuiteGCodeHeader; B: TSuiteBounds;
    Expected, Folder, Base: string; I: Integer; PCB: TMPDocument; Issues: TMPDrcIssues;
    CAD: TCadDocument; RB: TCadRebuilder; Info: TPJKindInfo;
begin
  Result := False; Verified := False; Msg := 'Arquivo nao encontrado';
  if not FileExists(FileName) then Exit;
  L := TStringList.Create; Errors := TStringList.Create; J := nil;
  try
    try
      L.LoadFromFile(FileName);
      if L.Count = 0 then begin Msg := 'Arquivo vazio'; Exit; end;
      Info := PJKindInfo(K);
      if PJIsGCode(FileName) then
      begin
        Verified := True;
        if not Info.Fabrication then begin Msg := 'Este tipo exige o documento da ferramenta'; Exit; end;
        if not SuiteParseHeader(L, H, B) then begin Msg := 'Cabecalho MS ausente ou invalido'; Exit; end;
        Expected := '';
        case K of
          tkPrint3D: Expected := 'printer3d';
          tkRouter: Expected := 'router';
          tkLaserCut, tkLaserArt: Expected := 'laser';
        end;
        if ((Expected <> '') and (H.Machine <> Expected)) or
          ((K = tkPCBFab) and (H.Machine <> 'laser') and (H.Machine <> 'router')) then
        begin Msg := 'MS-MACHINE incompativel com a tarefa: ' + H.Machine; Exit; end;
        if not SuiteCheckGCode(L, Errors, H.Machine = 'printer3d') then begin Msg := Errors.Text; Exit; end;
        Result := True; Msg := 'G-code e MS-MACHINE conferidos'; Exit;
      end;
      if Info.HasTool and not SameText(ExtractFileExt(FileName), Info.Extension) then
      begin Msg := 'Extensao incompativel: esperado ' + Info.Extension; Exit; end;
      if K=tkLathe then
      begin
        Verified:=True;
        Result:=SameText(ExtractFileExt(FileName),'.md') and
          (Pos('# Folha de processo de torno',L.Text)>0) and (Pos('| Operacao |',L.Text)>0);
        if Result then Msg:='Folha de processo manual anexada' else Msg:='Esperada folha de processo de torno em Markdown';
        Exit;
      end;
      J := GetJSON(L.Text);
      if not (J is TJSONObject) then begin Msg := 'Documento JSON deve ser um objeto'; Exit; end;
      if K = tkPart then
      begin
        Verified := True; CAD := TCadDocument.Create;
        try
          if not CAD.LoadFromFile(FileName, Msg) then Exit;
          RB := TCadRebuilder.Create(CAD);
          try
            if RB.Rebuild <> 0 then begin Msg := 'Falha ao reconstruir a peca'; Exit; end;
            if RB.BodyCount < 1 then begin Msg := 'Peca sem corpo solido'; Exit; end;
          finally RB.Free; end;
        finally CAD.Free; end;
        Result := True; Msg := 'Peca reconstruida com corpo solido';
      end
      else if K = tkElectronics then
      begin
        Verified := True; PCB := TMPDocument.Create;
        try
          PCB.FromJSON(L.Text, @MakePCBLibrary.Resolve);
          Issues := MPCheckDesign(PCB);
          if Length(Issues) > 0 then begin Msg := 'DRC: ' + Issues[0].Text; Exit; end;
          Base := Trim(PCB.Name);
          for I := 1 to Length(Base) do
            if not (Base[I] in ['A'..'Z','a'..'z','0'..'9','-','_']) then Base[I] := '_';
          if Base = '' then Base := 'placa';
          Folder := ExtractFilePath(FileName) + Base + '_gerber' + DirectorySeparator;
          if not HasNonempty(Folder + '*.gbl') or not HasNonempty(Folder + '*.drl') then
          begin Msg := 'Faltam Gerber/Excellon em ' + Folder; Exit; end;
        finally PCB.Free; end;
        Result := True; Msg := 'DRC sem erros; Gerber e Excellon encontrados';
      end
      else begin Result := True; Msg := 'Nao verificado: verificador especifico ainda indisponivel'; end;
    except on E: Exception do begin Result := False; Msg := E.Message; end; end;
  finally J.Free; Errors.Free; L.Free; end;
end;
end.
