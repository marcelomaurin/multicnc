unit multiproject_lathe;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, multiproject_types, multiproject_document;
function PJLatheSheet(P: TPJProject; T: TPJTask): string;
procedure PJSaveLatheSheet(P: TPJProject; T: TPJTask; const FileName: string; ReplaceExisting: Boolean = False);
implementation
function Cell(const S: string): string;
begin
  Result:=StringReplace(StringReplace(StringReplace(S,'|','\|',[rfReplaceAll]),#13,' ',[rfReplaceAll]),#10,' ',[rfReplaceAll]);
end;
function PJLatheSheet(P: TPJProject; T: TPJTask): string;
var L, Ops: TStringList; Src: TPJTask; I: Integer;
  function Value(const K: string): string;
  begin Result:=Src.TechValue(K); if Result='' then Result:='A definir'; Result:=Cell(Result); end;
begin
  if T.Kind<>tkLathe then raise EPJError.Create('Selecione uma tarefa de torno');
  Src:=T;
  for I:=0 to High(T.Origin.Sources) do
    if (P.FindTask(T.Origin.Sources[I])<>nil) and (P.FindTask(T.Origin.Sources[I]).Kind=tkPart) then Src:=P.FindTask(T.Origin.Sources[I]);
  L:=TStringList.Create; Ops:=TStringList.Create;
  try
    L.Add('# Folha de processo de torno'); L.Add('');
    L.Add('Projeto: '+Cell(P.Name)+' ('+Cell(P.Id)+')');
    L.Add('Tarefa: '+Cell(T.Id)+' - '+Cell(T.Name)); L.Add('Desenho de referencia: '+Cell(Src.Id)+' '+Cell(Src.Artifact.Path));
    L.Add(''); L.Add('Recurso: Torno (operacao manual).'); L.Add('');
    L.Add('## Especificacao tecnica'); L.Add(''); L.Add('| Item | Valor | Unidade |'); L.Add('|---|---|---|');
    for I:=0 to High(Src.TechItems) do
      L.Add('| '+Cell(Src.TechItems[I].Key)+' | '+Cell(Src.TechItems[I].Value)+' | '+Cell(Src.TechItems[I].UnitName)+' |');
    L.Add(''); L.Add(Src.TechText); L.Add(''); L.Add('## Operacoes e controle'); L.Add('');
    L.Add('| Operacao | Ferramenta | Rotacao (rpm) | Avanco (mm/rot) | Cota de controle |');
    L.Add('|---|---|---|---|---|');
    Ops.StrictDelimiter:=True; Ops.Delimiter:=';'; Ops.DelimitedText:=Src.TechValue('operacoes');
    if Ops.Count=0 then begin Ops.Add('Preparacao e fixacao'); Ops.Add('Usinagem conforme desenho'); Ops.Add('Controle dimensional'); end;
    for I:=0 to Ops.Count-1 do
      L.Add('| '+Cell(Ops[I])+' | '+Value('ferramenta')+' | '+Value('rotacao_rpm')+' | '+Value('avanco_mm_rot')+' | '+Value('cota_controle')+' |');
    L.Add(''); L.Add('Preencher os campos A definir e conferir a folha e o desenho antes da operacao.');
    L.Add(''); L.Add('Operador: ____________________  Data: __________  Revisao: '+Cell(P.Revision));
    Result:=L.Text;
  finally Ops.Free; L.Free; end;
end;
procedure PJSaveLatheSheet(P: TPJProject; T: TPJTask; const FileName: string; ReplaceExisting: Boolean);
var L: TStringList;
begin
  if FileExists(FileName) and not ReplaceExisting then raise EPJError.Create('A folha ja existe: '+FileName);
  if not ForceDirectories(ExtractFilePath(ExpandFileName(FileName))) then raise EPJError.Create('Nao foi possivel criar a pasta da folha');
  L:=TStringList.Create;
  try L.Text:=PJLatheSheet(P,T); L.SaveToFile(FileName); finally L.Free; end;
end;
end.
