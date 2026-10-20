unit multiproject_views;

{ Preenche as vistas genericas do CHATGPT (TAIGanttView, TAINetworkView,
  TAIBoardView) a partir do documento e do cronograma do MultiProject, com a
  paleta e os icones da MultiSuite (LAYOUT.md, "Vistas centrais").

  Filtros (PJ-V08): todas, criticas, atrasadas, sugeridas, uma cadeia, por
  tipo. Agrupamento: EAP (padrao), por tipo ou por estado (linhas de grupo
  sinteticas, sem ID). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Graphics, DateUtils,
  aiprojectduration, aitaskgraph, aicpmscheduler, aiganttview, ainetworkview, aiboardview,
  multisuite_controls, multisuite_icons,
  multiproject_types, multiproject_document, multiproject_graph, multiproject_schedule;

type
  TPJFilter = (pfAll, pfCritical, pfLate, pfSuggested, pfChain, pfKind);
  TPJGroupBy = (pgOutline, pgKind, pgState);

  TPJViewOptions = record
    Filter: TPJFilter;
    FilterKind: TPJTaskKind;
    FilterChain: Integer;
    GroupBy: TPJGroupBy;
    HighlightCritical: Boolean;
  end;

const
  { colunas do Gantt }
  GC_WBS = 0; GC_ID = 1; GC_NAME = 2; GC_TOOL = 3; GC_DUR = 4; GC_START = 5;
  GC_FINISH = 6; GC_PRED = 7;
  { colunas do quadro: indice -> estado }
  BOARD_STATES: array[0..5] of TPJTaskState = (tsSuggested, tsPlanned, tsInProgress,
    tsReview, tsDone, tsBlocked);

function DefaultViewOptions: TPJViewOptions;
function KindIcon(K: TPJTaskKind): TSuiteIconKind;
function KindColor(K: TPJTaskKind): TColor;
function KindToolName(K: TPJTaskKind): string;
function FmtDateTime(D: TDateTime): string;
procedure StyleGantt(G: TAIGanttView);
procedure StyleNetwork(N: TAINetworkView);
procedure StyleBoard(B: TAIBoardView);
procedure FillGantt(G: TAIGanttView; P: TPJProject; Sc: TPJSchedule; const O: TPJViewOptions);
procedure FillNetwork(N: TAINetworkView; P: TPJProject; Sc: TPJSchedule);
procedure FillBoard(B: TAIBoardView; P: TPJProject; Sc: TPJSchedule);
function BoardColumnOf(S: TPJTaskState): Integer;
function TaskPassesFilter(P: TPJProject; Sc: TPJSchedule; I: Integer; const O: TPJViewOptions;
  const Chains: TPJChains): Boolean;

implementation

function DefaultViewOptions: TPJViewOptions;
begin
  Result.Filter := pfAll;
  Result.FilterKind := tkGeneral;
  Result.FilterChain := 0;
  Result.GroupBy := pgOutline;
  Result.HighlightCritical := True;
end;

function KindIcon(K: TPJTaskKind): TSuiteIconKind;
begin
  case K of
    tkSummary: Result := sikLayers;
    tkMilestone: Result := sikFlag;
    tkGeneral: Result := sikFile;
    tkPurchase: Result := sikImport;
    tkPart: Result := sikCAD;
    tkElectronics: Result := sikMakePCB;
    tkAssembly: Result := sikAssembly;
    tkValidation: Result := sikPhysics;
    tkPrint3D: Result := sikSlicer;
    tkRouter: Result := sikMakeRouter;
    tkLaserCut, tkLaserArt: Result := sikLaserArt;
    tkLathe: Result := sikGear;
    tkPCBFab: Result := sikLaserPCB;
    tkPhysicalAssembly: Result := sikMove;
    tkFunctionalTest: Result := sikTests;
  else
    Result := sikFile;
  end;
end;

function KindColor(K: TPJTaskKind): TColor;
begin
  { mesmas cores das ferramentas na bandeja }
  case K of
    tkPart: Result := SuiteRGB(59, 130, 246);
    tkElectronics: Result := SuiteRGB(5, 150, 105);
    tkAssembly, tkPhysicalAssembly: Result := SuiteRGB(79, 70, 229);
    tkValidation: Result := SuiteRGB(124, 58, 237);
    tkPrint3D: Result := SuiteRGB(234, 88, 12);
    tkRouter: Result := SuiteRGB(146, 64, 14);
    tkLaserCut, tkLaserArt: Result := SuiteRGB(219, 39, 119);
    tkPCBFab: Result := SuiteRGB(239, 68, 68);
    tkLathe: Result := SuiteRGB(71, 85, 105);
    tkFunctionalTest: Result := SuiteRGB(22, 163, 74);
    tkMilestone: Result := clSuiteNavy;
  else
    Result := clSuiteMuted;
  end;
end;

function KindToolName(K: TPJTaskKind): string;
begin
  case K of
    tkPart: Result := 'MultiCAD';
    tkElectronics: Result := 'MakePCB';
    tkAssembly: Result := 'MultiAssembly';
    tkValidation: Result := 'MultiPhysics';
    tkPrint3D: Result := 'MultiSlicer';
    tkRouter: Result := 'MakeRouter';
    tkLaserCut, tkLaserArt: Result := 'LaserArt';
    tkPCBFab: Result := 'LaserPCB';
    tkLathe: Result := 'Torno (manual)';
  else
    Result := '';
  end;
end;

function FmtDateTime(D: TDateTime): string;
begin
  if D = 0 then Exit('');
  Result := FormatDateTime('ddd dd"/"mm"/"yy hh":"nn', D);
end;

procedure StyleGantt(G: TAIGanttView);
begin
  G.Font.Name := SUITE_FONT;
  G.Font.Size := 9;
  G.ColorBackground := clSuiteCard;
  G.ColorText := clSuiteText;
  G.ColorMuted := clSuiteMuted;
  G.ColorGrid := clSuiteBorder;
  G.ColorHeader := clSuiteSurface;
  G.ColorHeaderText := clSuiteText;
  G.ColorBar := clSuitePrimary;
  G.ColorCritical := clSuiteDanger;
  G.ColorSummary := clSuiteNavy;
  G.ColorMilestone := clSuiteNavy;
  G.ColorBaseline := clSuiteFaint;
  G.ColorSelection := SuiteMix(clSuitePrimary, clWhite, 0.85);
  G.ColorNonWork := SuiteMix(clSuiteSurface, clSuiteBorder, 0.35);
  G.ColorStatusLine := clSuiteWarning;
  G.ColorLink := clSuiteMuted;
  G.IconWidth := 16;
  G.ClearColumns;
  G.AddColumn('EAP', 44);
  G.AddColumn('ID', 62);
  G.AddColumn('Nome da tarefa', 230, True);
  G.AddColumn('Ferramenta', 96);
  G.AddColumn('Duracao', 66, True, taRightJustify);
  G.AddColumn('Inicio', 118);
  G.AddColumn('Termino', 118);
  G.AddColumn('Predecessoras', 140, True);
  G.TreeColumn := GC_NAME;
  G.TableWidth := 44 + 62 + 230 + 96 + 66;
end;

procedure StyleNetwork(N: TAINetworkView);
begin
  N.Font.Name := SUITE_FONT;
  N.Font.Size := 9;
  N.ColorBackground := clSuiteSurface;
  N.ColorBox := clSuiteCard;
  N.ColorBorder := clSuiteBorder;
  N.ColorText := clSuiteText;
  N.ColorMuted := clSuiteMuted;
  N.ColorCritical := clSuiteDanger;
  N.ColorSelection := clSuitePrimary;
  N.ColorPredecessor := clSuiteInfo;
  N.ColorSuccessor := clSuiteSuccess;
  N.ColorLink := clSuiteFaint;
  N.ColorGroup := clSuiteMuted;
end;

procedure StyleBoard(B: TAIBoardView);
var I: Integer;
begin
  B.Font.Name := SUITE_FONT;
  B.Font.Size := 9;
  B.ColorBackground := clSuiteSurface;
  B.ColorColumn := SuiteMix(clSuiteSurface, clSuiteBorder, 0.5);
  B.ColorCard := clSuiteCard;
  B.ColorBorder := clSuiteBorder;
  B.ColorText := clSuiteText;
  B.ColorMuted := clSuiteMuted;
  B.ColorSelection := clSuitePrimary;
  B.ColorDanger := clSuiteDanger;
  B.ClearColumns;
  for I := 0 to High(BOARD_STATES) do
    case BOARD_STATES[I] of
      tsSuggested: B.AddColumn(StateCaption(tsSuggested), clSuiteFaint);
      tsPlanned: B.AddColumn(StateCaption(tsPlanned), clSuiteInfo);
      tsInProgress: B.AddColumn(StateCaption(tsInProgress), clSuitePrimary);
      tsReview: B.AddColumn('Pronta p/ revisao', clSuiteWarning);
      tsDone: B.AddColumn(StateCaption(tsDone), clSuiteSuccess);
      tsBlocked: B.AddColumn(StateCaption(tsBlocked), clSuiteDanger);
    end;
end;

function BoardColumnOf(S: TPJTaskState): Integer;
var I: Integer;
begin
  for I := 0 to High(BOARD_STATES) do
    if BOARD_STATES[I] = S then Exit(I);
  { desatualizada volta para revisao; cancelada nao aparece }
  if S = tsOutdated then Result := 3 else Result := -1;
end;

function IsLate(Sc: TPJSchedule; P: TPJProject; I: Integer): Boolean;
var T: TPJTask; R: TAICPMResult;
begin
  T := P[I];
  R := Sc[I];
  Result := ((T.Deadline > 0) and (R.Finish > T.Deadline + 1 / 2880)) or (R.TotalSlack < 0) or
    ((P.StatusDate > 0) and (R.Finish < P.StatusDate) and not (T.State in [tsDone, tsCancelled]));
end;

function TaskPassesFilter(P: TPJProject; Sc: TPJSchedule; I: Integer; const O: TPJViewOptions;
  const Chains: TPJChains): Boolean;
var K: Integer;
begin
  case O.Filter of
    pfAll: Result := True;
    pfCritical: Result := Sc.Valid and Sc[I].Critical;
    pfLate: Result := Sc.Valid and IsLate(Sc, P, I);
    pfSuggested: Result := P[I].State = tsSuggested;
    pfKind: Result := P[I].Kind = O.FilterKind;
    pfChain:
      begin
        Result := False;
        if (O.FilterChain >= 0) and (O.FilterChain <= High(Chains)) then
          for K in Chains[O.FilterChain] do
            if K = I then Exit(True);
      end;
  else
    Result := True;
  end;
end;

function TaskRow(P: TPJProject; Sc: TPJSchedule; I, Level: Integer; const O: TPJViewOptions): TAIGanttRow;
var T: TPJTask; R: TAICPMResult;
begin
  T := P[I];
  if Sc.Valid then R := Sc[I] else FillChar(R, SizeOf(R), 0);
  if P.HasChildren(I) and (O.GroupBy = pgOutline) then
    Result := AIGanttRow(T.Id, Level, R.Start, R.Finish, agbSummary)
  else if T.Kind = tkMilestone then
    Result := AIGanttRow(T.Id, Level, R.Start, R.Finish, agbMilestone)
  else
    Result := AIGanttRow(T.Id, Level, R.Start, R.Finish, agbTask);
  Result.Critical := O.HighlightCritical and Sc.Valid and R.Critical and not P.HasChildren(I);
  Result.Dashed := T.State = tsSuggested;
  if T.State = tsDone then Result.Progress := 100
  else if T.State in [tsInProgress, tsReview] then Result.Progress := 50;
  Result.Tag := I;
  SetLength(Result.Cells, 8);
  Result.Cells[GC_WBS] := P.WBS(I);
  Result.Cells[GC_ID] := T.Id;
  Result.Cells[GC_NAME] := T.Name;
  Result.Cells[GC_TOOL] := KindToolName(T.Kind);
  Result.Cells[GC_DUR] := P.FormatDur(T.Duration);
  Result.Cells[GC_START] := FmtDateTime(R.Start);
  Result.Cells[GC_FINISH] := FmtDateTime(R.Finish);
  Result.Cells[GC_PRED] := P.PredecessorsText(T.Id);
end;

procedure FillGantt(G: TAIGanttView; P: TPJProject; Sc: TPJSchedule; const O: TPJViewOptions);
var
  I, J, K, A, B, GroupCount: Integer;
  RowOf: array of Integer;
  Chains: TPJChains;
  Keep: string;
  GK: TPJTaskKind;
  GS: TPJTaskState;
  Gr: TAIGanttRow;
begin
  if G.Selected >= 0 then Keep := G.Row(G.Selected).Id else Keep := '';
  Chains := nil;
  if O.Filter = pfChain then Chains := TaskChains(P);
  SetLength(RowOf, P.Count);
  for I := 0 to P.Count - 1 do RowOf[I] := -1;
  G.BeginUpdate;
  try
    G.Clear;
    G.StatusDate := P.StatusDate;
    case O.GroupBy of
      pgOutline:
        for I := 0 to P.Count - 1 do
        begin
          { com filtro, mostra a tarefa e os resumos acima dela }
          if (O.Filter <> pfAll) and not P.HasChildren(I) and not TaskPassesFilter(P, Sc, I, O, Chains) then Continue;
          if (O.Filter <> pfAll) and P.HasChildren(I) then
          begin
            B := 0;
            for J := I + 1 to P.SubtreeEnd(I) do
              if not P.HasChildren(J) and TaskPassesFilter(P, Sc, J, O, Chains) then begin B := 1; Break; end;
            if B = 0 then Continue;
          end;
          RowOf[I] := G.AddRow(TaskRow(P, Sc, I, P[I].Level, O));
        end;
      pgKind:
        for GK := Low(GK) to High(GK) do
        begin
          GroupCount := 0;
          for I := 0 to P.Count - 1 do
            if not P.HasChildren(I) and (P[I].Kind = GK) and TaskPassesFilter(P, Sc, I, O, Chains) then
            begin
              if GroupCount = 0 then
              begin
                Gr := AIGanttRow('', 1, 0, 0, agbSummary);
                SetLength(Gr.Cells, 8);
                Gr.Cells[GC_NAME] := KindCaption(GK);
                Gr.Tag := -1;
                G.AddRow(Gr);
              end;
              Inc(GroupCount);
              RowOf[I] := G.AddRow(TaskRow(P, Sc, I, 2, O));
            end;
        end;
      pgState:
        for GS := Low(GS) to High(GS) do
        begin
          GroupCount := 0;
          for I := 0 to P.Count - 1 do
            if not P.HasChildren(I) and (P[I].State = GS) and TaskPassesFilter(P, Sc, I, O, Chains) then
            begin
              if GroupCount = 0 then
              begin
                Gr := AIGanttRow('', 1, 0, 0, agbSummary);
                SetLength(Gr.Cells, 8);
                Gr.Cells[GC_NAME] := StateCaption(GS);
                Gr.Tag := -1;
                G.AddRow(Gr);
              end;
              Inc(GroupCount);
              RowOf[I] := G.AddRow(TaskRow(P, Sc, I, 2, O));
            end;
        end;
    end;
    { setas: vinculos do documento entre linhas visiveis }
    for K := 0 to P.LinkCount - 1 do
    begin
      A := P.IndexOfId(P.Links[K].FromId);
      B := P.IndexOfId(P.Links[K].ToId);
      if (A < 0) or (B < 0) or (RowOf[A] < 0) or (RowOf[B] < 0) then Continue;
      G.AddLink(RowOf[A], RowOf[B], Ord(P.Links[K].LinkType),
        O.HighlightCritical and Sc.Valid and Sc[A].Critical and Sc[B].Critical);
    end;
  finally
    G.EndUpdate;
  end;
  if Keep <> '' then G.SelectId(Keep);
end;

{ rotulo do vinculo na rede: so tipo e latencia ("II+2h"); TI simples fica vazio }
function LinkCaption(const L: TAITaskLink; P: TPJProject): string;
var Item: TAIPredecessorItem;
begin
  Item.Id := '';
  Item.LinkType := L.LinkType;
  Item.Lag := L.Lag;
  Result := AIFormatPredecessor(Item, P.MinutesPerDay, P.MinutesPerWeek);
end;

procedure FillNetwork(N: TAINetworkView; P: TPJProject; Sc: TPJSchedule);
var
  Chains: TPJChains;
  NodeOf: array of Integer;
  C, K, I, A, B, Keep: Integer;
  Nd: TAINetworkNode;
  T: TPJTask;
  G: TAITaskGraph;
  Err, Cap: string;
  L: TAITaskLink;
  KeepId: string;
begin
  if N.Selected >= 0 then KeepId := N.Node(N.Selected).Id else KeepId := '';
  Chains := TaskChains(P);
  SetLength(NodeOf, P.Count);
  for I := 0 to P.Count - 1 do NodeOf[I] := -1;
  N.BeginUpdate;
  try
    N.Clear;
    for C := 0 to High(Chains) do
    begin
      if Length(Chains) > 1 then N.SetGroupTitle(C, Format('Cadeia %d  (%d tarefas)', [C + 1, Length(Chains[C])]))
      else N.SetGroupTitle(C, Format('Cadeia unica  (%d tarefas)', [Length(Chains[C])]));
      for K in Chains[C] do
      begin
        T := P[K];
        Nd := AINetworkNode(T.Id, T.Id + '  ' + T.Name, C);
        SetLength(Nd.Lines, 3);
        Nd.Lines[0] := KindCaption(T.Kind) + IfThen(KindToolName(T.Kind) <> '', ' - ' + KindToolName(T.Kind), '');
        if Sc.Valid then
        begin
          Nd.Lines[1] := FormatDateTime('dd"/"mm hh":"nn', Sc[K].Start) + '  ->  ' + FormatDateTime('dd"/"mm hh":"nn', Sc[K].Finish);
          Nd.Lines[2] := 'Dur. ' + P.FormatDur(T.Duration) + '   Margem ' +
            P.FormatDur(AIMakeDuration(Max(0, Sc[K].TotalSlack), aduHour));
          Nd.Critical := Sc[K].Critical;
        end;
        Nd.Dashed := T.State = tsSuggested;
        Nd.AccentColor := KindColor(T.Kind);
        Nd.Tag := K;
        NodeOf[K] := N.AddNode(Nd);
      end;
    end;
    { arestas do grafo expandido (resumos ja viraram folhas) }
    G := BuildTaskGraph(P, Err);
    if G <> nil then
      try
        for I := 0 to G.LinkCount - 1 do
        begin
          L := G.Links[I];
          A := NodeOf[L.FromNode];
          B := NodeOf[L.ToNode];
          if (A < 0) or (B < 0) then Continue;
          Cap := LinkCaption(L, P);
          N.AddLink(A, B, Cap);
        end;
      finally
        G.Free;
      end;
  finally
    N.EndUpdate;
  end;
  Keep := -1;
  if KeepId <> '' then Keep := N.IndexOfId(KeepId);
  N.Selected := Keep;
end;

procedure FillBoard(B: TAIBoardView; P: TPJProject; Sc: TPJSchedule);
var I, C, KeepIdx: Integer; Cd: TAIBoardCard; T: TPJTask; KeepId: string;
begin
  if B.Selected >= 0 then KeepId := B.Card(B.Selected).Id else KeepId := '';
  B.BeginUpdate;
  try
    B.Clear;
    for I := 0 to P.Count - 1 do
    begin
      if P.HasChildren(I) then Continue;
      T := P[I];
      C := BoardColumnOf(T.State);
      if C < 0 then Continue;
      Cd := AIBoardCard(T.Id, T.Id + '  ' + T.Name, C);
      Cd.Subtitle := KindCaption(T.Kind) + IfThen(KindToolName(T.Kind) <> '', ' - ' + KindToolName(T.Kind), '');
      if Sc.Valid then Cd.Footer := 'Termino ' + FormatDateTime('dd"/"mm hh":"nn', Sc[I].Finish);
      if T.State = tsOutdated then
      begin
        Cd.Badge := 'desatualizada';
        Cd.BadgeColor := clSuiteWarning;
      end
      else if Sc.Valid and Sc[I].Critical then
      begin
        Cd.Badge := 'critica';
        Cd.BadgeColor := clSuiteDanger;
      end;
      Cd.AccentColor := KindColor(T.Kind);
      Cd.Dashed := T.State = tsSuggested;
      Cd.Tag := I;
      B.AddCard(Cd);
    end;
  finally
    B.EndUpdate;
  end;
  KeepIdx := -1;
  if KeepId <> '' then KeepIdx := B.IndexOfId(KeepId);
  B.Selected := KeepIdx;
end;

end.
