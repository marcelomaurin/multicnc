unit multiproject_graph;

{ Adaptador do documento do MultiProject para o grafo generico TAITaskGraph
  (CHATGPT / AI Project Core, unit aitaskgraph). Fase 2 (PJ-G01..G07, PJ-G10).

  - Cada tarefa vira um no, com indice igual ao da tarefa no documento.
  - Vinculo com tarefa de resumo vale para as folhas dela (PJ-G07): o vinculo
    S -> X vira um vinculo de cada folha de S para cada folha de X. O grafo
    expandido e sempre aciclico, entao ligar um resumo a propria subtarefa e
    recusado.
  - Cadeias (PJ-G04) = componentes conexos das tarefas que nao sao resumo.
  - "Em cadeia" x "em paralelo" sobre o grafo expandido. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, aitaskgraph, multiproject_types, multiproject_document;

type
  TPJChains = array of TPJIntArray;

{ grafo do documento; nil e Err preenchido se algum vinculo for invalido }
function BuildTaskGraph(P: TPJProject; out Err: string): TAITaskGraph;
{ mesmo calculo sobre listas soltas (usado pela leitura do arquivo antes de
  substituir o documento): ATasks = TPJTask em ordem de topicos, ALinks = TPJLink }
function BuildTaskGraphFrom(ATasks, ALinks: TFPObjectList; out Err: string): TAITaskGraph;
function LeafIndexes(P: TPJProject; I: Integer): TPJIntArray;
function TaskChains(P: TPJProject): TPJChains;
function TaskRelation(P: TPJProject; const AId, BId: string): TAITaskRelation;
function RelationCaption(R: TAITaskRelation): string;

implementation

function LevelOf(L: TFPObjectList; I: Integer): Integer; inline;
begin
  Result := TPJTask(L[I]).Level;
end;

function SubtreeEndOf(L: TFPObjectList; I: Integer): Integer;
begin
  Result := I;
  while (Result + 1 < L.Count) and (LevelOf(L, Result + 1) > LevelOf(L, I)) do Inc(Result);
end;

function IsLeaf(L: TFPObjectList; I: Integer): Boolean; inline;
begin
  Result := not ((I + 1 < L.Count) and (LevelOf(L, I + 1) > LevelOf(L, I)));
end;

function LeavesOf(L: TFPObjectList; I: Integer): TPJIntArray;
var J, E: Integer;
begin
  Result := nil;
  if IsLeaf(L, I) then
  begin
    SetLength(Result, 1);
    Result[0] := I;
    Exit;
  end;
  E := SubtreeEndOf(L, I);
  for J := I + 1 to E do
    if IsLeaf(L, J) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := J;
    end;
end;

{ se o ciclo passa por um vinculo de resumo expandido, diz qual e (o usuario
  ve os vinculos do documento, nao as arestas das folhas) }
function ViaSummaries(G: TAITaskGraph; ALinks: TFPObjectList; const AFrom, ATo: string): string;
var
  P: TAIStrArray;
  I, K: Integer;
  DL: TPJLink;
  Seen: string;
begin
  Result := '';
  Seen := '';
  P := G.CyclePath(AFrom, ATo);
  for I := 1 to High(P) - 1 do
  begin
    K := G.IndexOfLink(P[I], P[I + 1]);
    if K < 0 then Continue;
    DL := TPJLink(ALinks[G.Links[K].Tag]);
    if SameText(DL.FromId, P[I]) and SameText(DL.ToId, P[I + 1]) then Continue;
    if Pos('|' + DL.FromId + '>' + DL.ToId + '|', Seen) > 0 then Continue;
    Seen := Seen + '|' + DL.FromId + '>' + DL.ToId + '|';
    if Result = '' then Result := ' (pelas subtarefas do vinculo de resumo ' else Result := Result + ', ';
    Result := Result + DL.FromId + ' -> ' + DL.ToId;
  end;
  if Result <> '' then Result := Result + ')';
end;

function BuildTaskGraphFrom(ATasks, ALinks: TFPObjectList; out Err: string): TAITaskGraph;
var
  G: TAITaskGraph;
  I, A, B, X, Y: Integer;
  LA, LB: TPJIntArray;
  L: TPJLink;
  E: string;
begin
  Err := '';
  G := TAITaskGraph.Create;
  try
    for I := 0 to ATasks.Count - 1 do G.AddNode(TPJTask(ATasks[I]).Id);
    for I := 0 to ALinks.Count - 1 do
    begin
      L := TPJLink(ALinks[I]);
      { o no tem o mesmo indice da tarefa; a busca do grafo e indexada }
      A := G.IndexOfNode(L.FromId);
      B := G.IndexOfNode(L.ToId);
      if A < 0 then begin Err := 'vinculo com tarefa inexistente: ' + L.FromId; Exit(nil); end;
      if B < 0 then begin Err := 'vinculo com tarefa inexistente: ' + L.ToId; Exit(nil); end;
      if A = B then
      begin
        Err := Format('%s nao pode depender de si mesma', [L.FromId]);
        Exit(nil);
      end;
      if ((B > A) and (B <= SubtreeEndOf(ATasks, A))) or ((A > B) and (A <= SubtreeEndOf(ATasks, B))) then
      begin
        Err := Format('nao e possivel vincular um resumo as proprias subtarefas (%s -> %s)', [L.FromId, L.ToId]);
        Exit(nil);
      end;
      LA := LeavesOf(ATasks, A);
      LB := LeavesOf(ATasks, B);
      for X in LA do
        for Y in LB do
        begin
          { dois vinculos de resumo podem gerar o mesmo par de folhas }
          if G.IndexOfLink(G.NodeIds[X], G.NodeIds[Y]) >= 0 then Continue;
          if G.AddLink(G.NodeIds[X], G.NodeIds[Y], L.LinkType, L.Lag, E, I) < 0 then
          begin
            if (X = A) and (Y = B) then Err := E + ViaSummaries(G, ALinks, G.NodeIds[X], G.NodeIds[Y])
            else Err := Format('vinculo %s -> %s (pelas subtarefas %s -> %s): %s',
              [L.FromId, L.ToId, G.NodeIds[X], G.NodeIds[Y], E]);
            Exit(nil);
          end;
        end;
    end;
    Result := G;
    G := nil;
  finally
    G.Free;
  end;
end;

function BuildTaskGraph(P: TPJProject; out Err: string): TAITaskGraph;
var T, L: TFPObjectList; I: Integer;
begin
  { listas sem posse: so referenciam os objetos do documento }
  T := TFPObjectList.Create(False);
  L := TFPObjectList.Create(False);
  try
    for I := 0 to P.Count - 1 do T.Add(P[I]);
    for I := 0 to P.LinkCount - 1 do L.Add(P.Links[I]);
    Result := BuildTaskGraphFrom(T, L, Err);
  finally
    T.Free;
    L.Free;
  end;
end;

function LeafIndexes(P: TPJProject; I: Integer): TPJIntArray;
var T: TFPObjectList; J: Integer;
begin
  T := TFPObjectList.Create(False);
  try
    for J := 0 to P.Count - 1 do T.Add(P[J]);
    Result := LeavesOf(T, I);
  finally
    T.Free;
  end;
end;

function TaskChains(P: TPJProject): TPJChains;
var
  G: TAITaskGraph;
  Err: string;
  Map: TPJIntArray;
  I, C: Integer;
begin
  Result := nil;
  G := BuildTaskGraph(P, Err);
  if G = nil then raise EPJError.Create('vinculos invalidos: ' + Err);
  try
    SetLength(Map, G.ComponentCount);
    for I := 0 to High(Map) do Map[I] := -1;
    { componentes na ordem da primeira tarefa; resumos ficam de fora }
    for I := 0 to P.Count - 1 do
    begin
      if P.HasChildren(I) then Continue;
      C := G.ComponentOf(I);
      if Map[C] < 0 then
      begin
        Map[C] := Length(Result);
        SetLength(Result, Length(Result) + 1);
      end;
      SetLength(Result[Map[C]], Length(Result[Map[C]]) + 1);
      Result[Map[C]][High(Result[Map[C]])] := I;
    end;
  finally
    G.Free;
  end;
end;

function TaskRelation(P: TPJProject; const AId, BId: string): TAITaskRelation;
var G: TAITaskGraph; Err: string;
begin
  G := BuildTaskGraph(P, Err);
  if G = nil then raise EPJError.Create('vinculos invalidos: ' + Err);
  try
    Result := G.Relation(AId, BId);
  finally
    G.Free;
  end;
end;

function RelationCaption(R: TAITaskRelation): string;
begin
  case R of
    atrSame: Result := 'mesma tarefa';
    atrPredecessor: Result := 'em cadeia (antes)';
    atrSuccessor: Result := 'em cadeia (depois)';
    atrParallel: Result := 'em paralelo';
  end;
end;

end.
