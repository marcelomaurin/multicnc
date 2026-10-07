unit makepcb_editor;

{ Editor da placa do MakePCB (area de desenho).

  Ferramentas:
    etSelect  - seleciona e arrasta componentes, textos e trilhas;
                R gira 90 graus, Del apaga, duplo clique numa trilha a apaga.
    etPlace   - coloca o footprint escolhido na galeria (R gira antes).
    etTrack   - trilha na face ativa: clique nos pontos, termina num pad,
                com duplo clique ou botao direito. Ctrl libera os 45 graus.
    etWire    - ligacao (ratsnest): clique no pad A e no pad B.
    etText    - texto na face ativa ou na serigrafia.
    etArea    - area de cobre: clique nos vertices, duplo clique fecha.
  Roda do mouse: zoom no cursor. Botao do meio (ou direito em Selecionar):
  arrasta a vista. Tudo encaixa na grade da placa; trilhas e ligacoes
  encaixam no centro do pad mais proximo.

  Desfazer/Refazer guardam o documento inteiro (.mpcb em JSON). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, Forms, Dialogs, LCLType,
  makepcb_model, makepcb_library, makepcb_render, makepcb_drc, makepcb_select;

type
  TMPTool = (etSelect, etPlace, etTrack, etWire, etText, etArea);

  TMPStatusEvent = procedure(Sender: TObject; const Text: string) of object;

  TMPEditor = class(TCustomControl)
  private
    FDoc: TMPDocument;
    FLib: TMPLibrary;
    FR: TMPRenderer;
    FView: TMPViewport;
    FFitted: Boolean;
    FTool: TMPTool;
    FPlaceFP: TMPFootprint;
    FGhost: TMPComponent;
    FActiveLayer: TMPLayer;
    FMouse: TMPPoint;
    FMousePx: TPoint;
    FPanning: Boolean;
    FPanStart: TPoint;
    FPanOrigin: TMPViewport;
    FDragging, FDragMoved: Boolean;
    FDragStart: TMPPoint;
    FPoints: TMPPoints;         { trilha / area em construcao }
    FWireFrom: TMPPadRef;
    FHasWireFrom: Boolean;
    FUndo, FRedo: TStringList;
    FOnChange, FOnSelect: TNotifyEvent;
    FOnStatus: TMPStatusEvent;
    FModified: Boolean;
    FFree45: Boolean;
    FSel: TMPSelection;
    FBanding: Boolean;
    FBandStart, FBandEnd: TPoint;
    FApplied: TMPPoint;          { deslocamento ja aplicado no arraste }
    FVertexTrack, FVertexIndex: Integer;
    FRotCenter: TMPPoint;
    FRotValid: Boolean;          { centro de giro fixo enquanto a selecao nao muda }
    function SelToItem(K: TMPSelKind; out IK: TMPItemKind): Boolean;
    procedure SyncPrimary;
    function VertexAt(const P: TMPPoint; out T, V: Integer): Boolean;
    procedure SetDoc(AValue: TMPDocument);
    procedure SetTool(AValue: TMPTool);
    procedure SetMode(AValue: TMPViewMode);
    function GetMode: TMPViewMode;
    function GetSelKind: TMPSelKind;
    function GetSelIndex: Integer;
    function Snap(const P: TMPPoint): TMPPoint;
    function SnapPad(const P: TMPPoint; out Ref: TMPPadRef): Boolean;
    function Constrain(const A, B: TMPPoint): TMPPoint;
    procedure DoChanged;
    procedure Status(const S: string);
    procedure FinishTrack;
    procedure FinishArea;
    procedure HitTest(const P: TMPPoint; out Kind: TMPSelKind; out Index: Integer);
    procedure DrawRulers;
    procedure UpdateGhost;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ZoomToBoard;
    procedure ZoomBy(F: Double);
    { guarda o estado para desfazer (chamar antes de alterar o documento) }
    procedure Snapshot;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    procedure ClearHistory;
    procedure Select(Kind: TMPSelKind; Index: Integer);
    procedure DeleteSelection;
    procedure RotateSelection;
    { vira os componentes selecionados (em cima/embaixo) }
    procedure FlipSelection;
    procedure CancelOperation;
    procedure SetIssues(const AIssues: TMPDrcIssues);
    procedure SetPlaceFootprint(FP: TMPFootprint);
    { selecao multipla e area de transferencia }
    procedure SelectAll;
    procedure CopySelection;
    procedure CutSelection;
    procedure PasteClipboard;
    procedure DuplicateSelection;
    procedure NudgeSelection(DX, DY: Double);
    property Selection: TMPSelection read FSel;
    procedure Changed;
    property Doc: TMPDocument read FDoc write SetDoc;
    property Lib: TMPLibrary read FLib write FLib;
    property Renderer: TMPRenderer read FR;
    property Tool: TMPTool read FTool write SetTool;
    property ViewMode: TMPViewMode read GetMode write SetMode;
    property ActiveLayer: TMPLayer read FActiveLayer write FActiveLayer;
    property SelKind: TMPSelKind read GetSelKind;
    property SelIndex: Integer read GetSelIndex;
    property Modified: Boolean read FModified write FModified;
    property Viewport: TMPViewport read FView;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnStatus: TMPStatusEvent read FOnStatus write FOnStatus;
  end;

const
  RULER = 22;

function ToolName(T: TMPTool): string;

implementation

uses Clipbrd, makepcb_route, makepcb_font, multisuite_controls;

const
  MAX_UNDO = 60;

function ToolName(T: TMPTool): string;
begin
  case T of
    etSelect: Result := 'Selecionar';
    etPlace: Result := 'Colocar componente';
    etTrack: Result := 'Trilha';
    etWire: Result := 'Ligacao';
    etText: Result := 'Texto';
    etArea: Result := 'Area de cobre';
  end;
end;

constructor TMPEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FR := TMPRenderer.Create;
  FUndo := TStringList.Create;
  FRedo := TStringList.Create;
  FSel := TMPSelection.Create;
  FR.Selection := FSel;
  FVertexTrack := -1;
  FView.Scale := 8;
  FTool := etSelect;
  FActiveLayer := mlBottomCopper;
  TabStop := True;
  DoubleBuffered := True;
  Color := clWhite;
end;

destructor TMPEditor.Destroy;
begin
  FGhost.Free;
  FR.Free;
  FSel.Free;
  FUndo.Free;
  FRedo.Free;
  inherited Destroy;
end;

procedure TMPEditor.SetDoc(AValue: TMPDocument);
begin
  FDoc := AValue;
  FR.Doc := AValue;
  FR.SelKind := selNone; FR.SelIndex := -1;
  FSel.Clear;
  FFitted := False;
  Invalidate;
end;

procedure TMPEditor.SetTool(AValue: TMPTool);
begin
  CancelOperation;
  FTool := AValue;
  if FTool <> etPlace then FreeAndNil(FGhost) else UpdateGhost;
  case FTool of
    etTrack: Status('Trilha: clique nos pontos; termine num pad, com duplo clique ou botao direito.');
    etWire: Status('Ligacao: clique no primeiro pad e depois no segundo.');
    etText: Status('Texto: clique onde o texto deve comecar.');
    etArea: Status('Area de cobre: clique nos vertices; duplo clique fecha.');
    etPlace: Status('Clique na placa para colocar. R gira, Esc termina.');
  else
    Status('Selecionar: arraste para mover; R gira; Del apaga.');
  end;
  Invalidate;
end;

procedure TMPEditor.SetMode(AValue: TMPViewMode);
begin
  FR.Mode := AValue;
  Invalidate;
end;

function TMPEditor.GetMode: TMPViewMode;
begin
  Result := FR.Mode;
end;

function TMPEditor.GetSelKind: TMPSelKind;
begin
  Result := FR.SelKind;
end;

function TMPEditor.GetSelIndex: Integer;
begin
  Result := FR.SelIndex;
end;

procedure TMPEditor.SetPlaceFootprint(FP: TMPFootprint);
begin
  FPlaceFP := FP;
  if FP <> nil then
  begin
    FTool := etPlace;
    UpdateGhost;
    Status('Colocar ' + FP.Name + ': clique na placa. R gira, Esc termina.');
  end;
  Invalidate;
end;

procedure TMPEditor.UpdateGhost;
var
  Rot: Integer;
begin
  Rot := 0;
  if FGhost <> nil then Rot := FGhost.Rotation;
  FreeAndNil(FGhost);
  if FPlaceFP = nil then Exit;
  FGhost := TMPComponent.Create;
  FGhost.Footprint := FPlaceFP;
  FGhost.Rotation := Rot;
  { SMD em face simples vai do lado do cobre (embaixo, espelhado) }
  FGhost.Flipped := FPlaceFP.HasSMD and (FDoc <> nil) and not FDoc.DoubleSided;
  FGhost.X := FMouse.X; FGhost.Y := FMouse.Y;
end;

procedure TMPEditor.Status(const S: string);
begin
  if Assigned(FOnStatus) then FOnStatus(Self, S);
end;

procedure TMPEditor.DoChanged;
begin
  FModified := True;
  if FDoc <> nil then FDoc.Changed;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMPEditor.Changed;
begin
  DoChanged;
end;

procedure TMPEditor.SetIssues(const AIssues: TMPDrcIssues);
begin
  FR.Issues := Copy(AIssues);
  Invalidate;
end;

{ ---------------- historico ---------------- }

procedure TMPEditor.Snapshot;
begin
  if FDoc = nil then Exit;
  FUndo.Add(FDoc.ToJSON);
  while FUndo.Count > MAX_UNDO do FUndo.Delete(0);
  FRedo.Clear;
end;

procedure TMPEditor.Undo;
begin
  if (FDoc = nil) or (FUndo.Count = 0) then Exit;
  CancelOperation;
  FRedo.Add(FDoc.ToJSON);
  FDoc.FromJSON(FUndo[FUndo.Count - 1], @FLib.Resolve);
  FUndo.Delete(FUndo.Count - 1);
  Select(selNone, -1);
  DoChanged;
end;

procedure TMPEditor.Redo;
begin
  if (FDoc = nil) or (FRedo.Count = 0) then Exit;
  CancelOperation;
  FUndo.Add(FDoc.ToJSON);
  FDoc.FromJSON(FRedo[FRedo.Count - 1], @FLib.Resolve);
  FRedo.Delete(FRedo.Count - 1);
  Select(selNone, -1);
  DoChanged;
end;

function TMPEditor.CanUndo: Boolean;
begin
  Result := FUndo.Count > 0;
end;

function TMPEditor.CanRedo: Boolean;
begin
  Result := FRedo.Count > 0;
end;

procedure TMPEditor.ClearHistory;
begin
  FUndo.Clear;
  FRedo.Clear;
end;

{ ---------------- vista ---------------- }

procedure TMPEditor.ZoomToBoard;
var
  W, H: Double;
begin
  if FDoc = nil then Exit;
  W := Max(ClientWidth - RULER - 40, 50);
  H := Max(ClientHeight - RULER - 40, 50);
  FView.Scale := Max(0.5, Min(W / FDoc.BoardW, H / FDoc.BoardH));
  FView.OX := RULER + (ClientWidth - RULER) / 2 - FDoc.BoardW * FView.Scale / 2;
  FView.OY := RULER + (ClientHeight - RULER) / 2 + FDoc.BoardH * FView.Scale / 2;
  FFitted := True;
  Invalidate;
end;

procedure TMPEditor.ZoomBy(F: Double);
var
  C: TMPPoint;
  CX, CY: Double;
begin
  CX := RULER + (ClientWidth - RULER) / 2; CY := RULER + (ClientHeight - RULER) / 2;
  C := MPToBoard(FView, Round(CX), Round(CY));
  FView.Scale := EnsureRange(FView.Scale * F, 0.5, 200);
  FView.OX := CX - C.X * FView.Scale;
  FView.OY := CY + C.Y * FView.Scale;
  Invalidate;
end;

procedure TMPEditor.Resize;
begin
  inherited Resize;
  if (FDoc <> nil) and not FFitted and (ClientWidth > 100) then ZoomToBoard;
end;

function TMPEditor.Snap(const P: TMPPoint): TMPPoint;
var
  G: Double;
begin
  G := MP_GRID;
  if (FDoc <> nil) and (FDoc.Grid > 0) then G := FDoc.Grid;
  Result.X := Round(P.X / G) * G;
  Result.Y := Round(P.Y / G) * G;
end;

function TMPEditor.SnapPad(const P: TMPPoint; out Ref: TMPPadRef): Boolean;
begin
  Result := (FDoc <> nil) and FDoc.PadAt(P.X, P.Y, Max(1.2, 8 / FView.Scale), Ref);
end;

{ trilha em 0/45/90 graus a partir de A (como no PCB Wizard) }
function TMPEditor.Constrain(const A, B: TMPPoint): TMPPoint;
var
  DX, DY, D: Double;
begin
  Result := B;
  if FFree45 then Exit;
  DX := B.X - A.X; DY := B.Y - A.Y;
  if Abs(DX) > 2 * Abs(DY) then Result.Y := A.Y
  else if Abs(DY) > 2 * Abs(DX) then Result.X := A.X
  else
  begin
    D := (Abs(DX) + Abs(DY)) / 2;
    Result.X := A.X + Sign(DX) * D;
    Result.Y := A.Y + Sign(DY) * D;
    Result := Snap(Result);
    { o snap pode desfazer o 45; ajusta pelo menor eixo }
    D := Min(Abs(Result.X - A.X), Abs(Result.Y - A.Y));
    Result.X := A.X + Sign(DX) * D;
    Result.Y := A.Y + Sign(DY) * D;
  end;
end;

{ ---------------- selecao ---------------- }

procedure TMPEditor.HitTest(const P: TMPPoint; out Kind: TMPSelKind; out Index: Integer);
var
  I, J: Integer;
  B: TMPRect;
  T: TMPTrack;
  Tol, W: Double;
  Tx: TMPText;
  PRef: TMPPadRef;
begin
  Kind := selNone; Index := -1;
  if FDoc = nil then Exit;
  Tol := 4 / FView.Scale;
  { textos }
  for I := FDoc.TextCount - 1 downto 0 do
  begin
    Tx := FDoc.Text(I);
    W := MPTextWidth(Tx.Text, Tx.Height);
    if Tx.Layer = mlBottomCopper then
    begin
      if (P.X <= Tx.X + Tol) and (P.X >= Tx.X - W - Tol) and (P.Y >= Tx.Y - Tol) and (P.Y <= Tx.Y + Tx.Height + Tol) then
      begin Kind := selText; Index := I; Exit; end;
    end
    else if (P.X >= Tx.X - Tol) and (P.X <= Tx.X + W + Tol) and (P.Y >= Tx.Y - Tol) and (P.Y <= Tx.Y + Tx.Height + Tol) then
    begin Kind := selText; Index := I; Exit; end;
  end;
  { trilhas (antes dos componentes: ficam por cima dos pads) }
  for I := FDoc.TrackCount - 1 downto 0 do
  begin
    T := FDoc.Track(I);
    for J := 1 to High(T.Points) do
      if MPSegDist(P, T.Points[J - 1], T.Points[J]) <= T.Width / 2 + Tol then
      begin
        { clique no pad seleciona o componente, nao a trilha }
        if not FDoc.PadAt(P.X, P.Y, 0.6, PRef) then
        begin Kind := selTrack; Index := I; Exit; end;
      end;
  end;
  { componentes }
  for I := FDoc.ComponentCount - 1 downto 0 do
  begin
    B := FDoc.Component(I).Bounds;
    if (P.X >= B.MinX - Tol) and (P.X <= B.MaxX + Tol) and (P.Y >= B.MinY - Tol) and (P.Y <= B.MaxY + Tol) then
    begin Kind := selComponent; Index := I; Exit; end;
  end;
  { areas }
  for I := FDoc.AreaCount - 1 downto 0 do
    if MPPointInPolygon(P, FDoc.Area(I).Points) then
    begin Kind := selArea; Index := I; Exit; end;
end;

function TMPEditor.SelToItem(K: TMPSelKind; out IK: TMPItemKind): Boolean;
begin
  Result := True;
  case K of
    selComponent: IK := ikComponent;
    selTrack: IK := ikTrack;
    selText: IK := ikText;
    selArea: IK := ikArea;
  else
    begin IK := ikComponent; Result := False; end;
  end;
end;

{ o item "principal" (painel de propriedades) e o unico selecionado }
procedure TMPEditor.SyncPrimary;
const
  KINDS: array[TMPItemKind] of TMPSelKind = (selComponent, selTrack, selText, selArea);
begin
  FRotValid := False;
  if FSel.Count = 1 then
  begin
    FR.SelKind := KINDS[FSel[0].Kind];
    FR.SelIndex := FSel[0].Index;
  end
  else
  begin
    FR.SelKind := selNone;
    FR.SelIndex := -1;
  end;
  FR.HighlightNet := -1;
  if (FDoc <> nil) and (FR.SelKind = selTrack) and (FR.SelIndex >= 0) then
    FR.HighlightNet := FDoc.TrackNet(FR.SelIndex);
  Invalidate;
  if Assigned(FOnSelect) then FOnSelect(Self);
end;

procedure TMPEditor.Select(Kind: TMPSelKind; Index: Integer);
var
  IK: TMPItemKind;
begin
  FSel.Clear;
  FRotValid := False;
  if SelToItem(Kind, IK) and (Index >= 0) then FSel.Add(IK, Index);
  FR.SelKind := Kind;
  FR.SelIndex := Index;
  FR.HighlightNet := -1;
  if (FDoc <> nil) and (Kind = selTrack) and (Index >= 0) then
    FR.HighlightNet := FDoc.TrackNet(Index);
  Invalidate;
  if Assigned(FOnSelect) then FOnSelect(Self);
end;

procedure TMPEditor.DeleteSelection;
begin
  if (FDoc = nil) or (FSel.Count = 0) then Exit;
  Snapshot;
  MPDeleteSelection(FDoc, FSel);
  Select(selNone, -1);
  DoChanged;
end;

procedure TMPEditor.SelectAll;
begin
  if FDoc = nil then Exit;
  MPSelectAll(FDoc, FSel);
  SyncPrimary;
end;

procedure TMPEditor.CopySelection;
begin
  if (FDoc = nil) or (FSel.Count = 0) then Exit;
  Clipboard.AsText := MPCopySelection(FDoc, FSel);
  Status(Format('%d itens copiados.', [FSel.Count]));
end;

procedure TMPEditor.CutSelection;
begin
  CopySelection;
  DeleteSelection;
end;

procedure TMPEditor.PasteClipboard;
var
  S: string;
  B: TMPRect;
  DX, DY, G: Double;
  Tmp: TMPDocument;
  TmpSel: TMPSelection;
begin
  if FDoc = nil then Exit;
  S := Clipboard.AsText;
  if not MPIsClip(S) then
  begin
    Status('A area de transferencia nao tem itens do MakePCB.');
    Exit;
  end;
  { mede o que sera colado para centralizar no cursor (ou deslocar 2 passos) }
  Tmp := TMPDocument.Create;
  TmpSel := TMPSelection.Create;
  try
    MPPaste(Tmp, S, 0, 0, @FLib.Resolve, TmpSel);
    B := MPSelectionBounds(Tmp, TmpSel);
  finally
    TmpSel.Free;
    Tmp.Free;
  end;
  G := FDoc.Grid;
  if G <= 0 then G := MP_GRID;
  if B.Valid and (FMouse.X >= 0) and (FMouse.X <= FDoc.BoardW) and (FMouse.Y >= 0) and (FMouse.Y <= FDoc.BoardH) then
  begin
    DX := Round((FMouse.X - (B.MinX + B.MaxX) / 2) / G) * G;
    DY := Round((FMouse.Y - (B.MinY + B.MaxY) / 2) / G) * G;
  end
  else
  begin
    DX := 2 * G; DY := -2 * G;
  end;
  Snapshot;
  MPPaste(FDoc, S, DX, DY, @FLib.Resolve, FSel);
  SyncPrimary;
  DoChanged;
  Status(Format('%d itens colados. Arraste para posicionar.', [FSel.Count]));
end;

procedure TMPEditor.DuplicateSelection;
var
  S: string;
  G: Double;
begin
  if (FDoc = nil) or (FSel.Count = 0) then Exit;
  G := FDoc.Grid;
  if G <= 0 then G := MP_GRID;
  S := MPCopySelection(FDoc, FSel);
  Snapshot;
  MPPaste(FDoc, S, 2 * G, -2 * G, @FLib.Resolve, FSel);
  SyncPrimary;
  DoChanged;
end;

procedure TMPEditor.NudgeSelection(DX, DY: Double);
begin
  if (FDoc = nil) or (FSel.Count = 0) then Exit;
  Snapshot;
  MPMoveSelection(FDoc, FSel, DX, DY);
  DoChanged;
end;

function TMPEditor.VertexAt(const P: TMPPoint; out T, V: Integer): Boolean;
var
  I, J: Integer;
  Tol: Double;
begin
  Result := False;
  T := -1; V := -1;
  if FDoc = nil then Exit;
  Tol := Max(0.4, 6 / FView.Scale);
  for I := FDoc.TrackCount - 1 downto 0 do
    if FSel.Contains(ikTrack, I) then
      for J := 0 to High(FDoc.Track(I).Points) do
        if MPDist(P, FDoc.Track(I).Points[J]) <= Tol then
        begin
          T := I; V := J;
          Exit(True);
        end;
end;

procedure TMPEditor.RotateSelection;
begin
  if (FTool = etPlace) and (FGhost <> nil) then
  begin
    FGhost.Rotation := (FGhost.Rotation + 90) mod 360;
    Invalidate;
    Exit;
  end;
  if (FDoc = nil) or (FSel.Count = 0) then Exit;
  Snapshot;
  if not FRotValid then
  begin
    FRotCenter := MPRotationCenter(FDoc, FSel, FDoc.Grid);
    FRotValid := True;
  end;
  MPRotateSelectionAbout(FDoc, FSel, FRotCenter.X, FRotCenter.Y);
  FModified := True;
  FDoc.Changed;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMPEditor.FlipSelection;
var
  I: Integer;
begin
  if (FTool = etPlace) and (FGhost <> nil) then
  begin
    FGhost.Flipped := not FGhost.Flipped;
    Invalidate;
    Exit;
  end;
  if (FDoc = nil) or (FSel.CountOf(ikComponent) = 0) then Exit;
  Snapshot;
  MPFlipSelection(FDoc, FSel);
  DoChanged;
  I := 0;
  while (I < FSel.Count - 1) and (FSel[I].Kind <> ikComponent) do Inc(I);
  if FDoc.Component(FSel[I].Index).Flipped then
    Status('Componente embaixo (lado da solda), espelhado.')
  else
    Status('Componente em cima (lado dos componentes).');
end;

procedure TMPEditor.CancelOperation;
begin
  SetLength(FPoints, 0);
  FHasWireFrom := False;
  FDragging := False;
  Invalidate;
end;

{ ---------------- construcao ---------------- }

procedure TMPEditor.FinishTrack;
var
  T: TMPTrack;
  I: Integer;
begin
  if Length(FPoints) >= 2 then
  begin
    Snapshot;
    T := FDoc.AddTrack(FActiveLayer, FDoc.TrackWidth);
    if FActiveLayer = mlTopSilk then T.Layer := mlBottomCopper;
    for I := 0 to High(FPoints) do T.AddPoint(FPoints[I].X, FPoints[I].Y);
    DoChanged;
  end;
  SetLength(FPoints, 0);
  Invalidate;
end;

procedure TMPEditor.FinishArea;
var
  A: TMPArea;
  I, J, K, Best, BestCount, BestC, BestP: Integer;
  Counts: array of Integer;
  FirstC, FirstP: array of Integer;
  L: TMPLayer;
begin
  if Length(FPoints) >= 3 then
  begin
    Snapshot;
    L := FActiveLayer;
    if L = mlTopSilk then L := mlBottomCopper;
    A := FDoc.AddArea(L);
    A.Points := Copy(FPoints);
    A.Clearance := FDoc.Clearance;
    { a area fica na rede com mais pads dentro dela (tipicamente o GND) }
    FDoc.ComputeNets;
    SetLength(Counts, FDoc.NetCount + 1);
    SetLength(FirstC, FDoc.NetCount + 1);
    SetLength(FirstP, FDoc.NetCount + 1);
    for I := 0 to FDoc.ComponentCount - 1 do
      for J := 0 to FDoc.Component(I).PadCount - 1 do
      begin
        K := FDoc.PadNet(I, J);
        if (K < 0) or (K > High(Counts)) then Continue;
        if MPPointInPolygon(FDoc.Component(I).PadPos(J), A.Points) then
        begin
          if Counts[K] = 0 then begin FirstC[K] := I; FirstP[K] := J; end;
          Inc(Counts[K]);
        end;
      end;
    Best := -1; BestCount := 1; BestC := -1; BestP := -1;
    for K := 0 to High(Counts) do
      if Counts[K] > BestCount then begin Best := K; BestCount := Counts[K]; BestC := FirstC[K]; BestP := FirstP[K]; end;
    if Best >= 0 then begin A.NetComp := BestC; A.NetPad := BestP; end
    else begin A.NetComp := -1; A.NetPad := -1; end;
    DoChanged;
    Select(selArea, FDoc.AreaCount - 1);
  end;
  SetLength(FPoints, 0);
  Invalidate;
end;

{ ---------------- mouse ---------------- }

procedure TMPEditor.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P, Q: TMPPoint;
  Ref: TMPPadRef;
  K: TMPSelKind;
  Idx, N: Integer;
  C: TMPComponent;
  S: string;
  L: TMPLayer;
  IK: TMPItemKind;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  if FDoc = nil then Exit;
  P := MPToBoard(FView, X, Y);
  if (Button = mbMiddle) or ((Button = mbRight) and (FTool = etSelect)) then
  begin
    FPanning := True; FPanStart := Point(X, Y); FPanOrigin := FView;
    Exit;
  end;
  if Button = mbRight then
  begin
    case FTool of
      etTrack: FinishTrack;
      etArea: FinishArea;
      etPlace: SetTool(etSelect);
    else CancelOperation;
    end;
    Exit;
  end;
  if FR.Mode <> vmNormal then
  begin
    { nas outras vistas so seleciona }
    HitTest(P, K, Idx);
    Select(K, Idx);
    Exit;
  end;
  case FTool of
    etSelect:
      begin
        { vertice de uma trilha selecionada: arrasta so o ponto }
        if (not (ssShift in Shift)) and VertexAt(P, FVertexTrack, FVertexIndex) then
        begin
          FDragging := True; FDragMoved := False;
          FDragStart := Snap(P);
          Snapshot;
          Exit;
        end;
        FVertexTrack := -1;
        HitTest(P, K, Idx);
        if (K <> selNone) and SelToItem(K, IK) then
        begin
          if ssShift in Shift then
          begin
            FSel.Toggle(IK, Idx);
            SyncPrimary;
            Exit;
          end;
          if not FSel.Contains(IK, Idx) then Select(K, Idx);
          FDragging := True; FDragMoved := False;
          FDragStart := Snap(P);
          FApplied := MPPoint(0, 0);
          Snapshot;
        end
        else
        begin
          { retangulo de selecao }
          if not (ssShift in Shift) then Select(selNone, -1);
          FBanding := True;
          FBandStart := Point(X, Y);
          FBandEnd := FBandStart;
        end;
      end;
    etPlace:
      if FPlaceFP <> nil then
      begin
        Snapshot;
        Q := Snap(P);
        C := FDoc.AddComponent(FPlaceFP, Q.X, Q.Y);
        if FGhost <> nil then
        begin
          C.Rotation := FGhost.Rotation;
          C.Flipped := FGhost.Flipped;
        end;
        DoChanged;
        Select(selComponent, FDoc.ComponentCount - 1);
        Status(C.Ref + ' colocado. Clique para outro; Esc termina.');
      end;
    etTrack:
      begin
        if SnapPad(P, Ref) then Q := FDoc.PadPoint(Ref)
        else if Length(FPoints) > 0 then Q := Constrain(FPoints[High(FPoints)], Snap(P))
        else Q := Snap(P);
        N := Length(FPoints);
        if (N = 0) or (MPDist(FPoints[N - 1], Q) > 1e-6) then
        begin
          SetLength(FPoints, N + 1);
          FPoints[N] := Q;
        end;
        { chegou num pad: termina }
        if (Length(FPoints) >= 2) and SnapPad(P, Ref) then FinishTrack;
        Invalidate;
      end;
    etWire:
      if SnapPad(P, Ref) then
      begin
        if not FHasWireFrom then
        begin
          FWireFrom := Ref; FHasWireFrom := True;
          Status('Agora clique no segundo pad.');
        end
        else if (Ref.Comp <> FWireFrom.Comp) or (Ref.Pad <> FWireFrom.Pad) then
        begin
          Snapshot;
          FDoc.AddWire(FWireFrom.Comp, FWireFrom.Pad, Ref.Comp, Ref.Pad);
          FHasWireFrom := False;
          DoChanged;
          Status('Ligacao criada. Clique no proximo pad.');
        end;
        Invalidate;
      end;
    etText:
      begin
        S := '';
        if InputQuery('Texto', 'Texto a gravar na placa:', S) and (Trim(S) <> '') then
        begin
          Snapshot;
          Q := Snap(P);
          L := FActiveLayer;
          FDoc.AddText(UpperCase(Trim(S)), Q.X, Q.Y, 1.8, L);
          DoChanged;
          Select(selText, FDoc.TextCount - 1);
        end;
      end;
    etArea:
      begin
        Q := Snap(P);
        N := Length(FPoints);
        SetLength(FPoints, N + 1);
        FPoints[N] := Q;
        Invalidate;
      end;
  end;
end;

procedure TMPEditor.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  P, D: TMPPoint;
  I: Integer;
  Ref: TMPPadRef;
  S: string;
  FS: TFormatSettings;
begin
  inherited MouseMove(Shift, X, Y);
  FFree45 := ssCtrl in Shift;
  FMousePx := Point(X, Y);
  if FPanning then
  begin
    FView.OX := FPanOrigin.OX + (X - FPanStart.X);
    FView.OY := FPanOrigin.OY + (Y - FPanStart.Y);
    Invalidate;
    Exit;
  end;
  if FDoc = nil then Exit;
  P := MPToBoard(FView, X, Y);
  FMouse := Snap(P);
  if (FTool = etTrack) and SnapPad(P, Ref) then FMouse := FDoc.PadPoint(Ref);
  if FGhost <> nil then begin FGhost.X := FMouse.X; FGhost.Y := FMouse.Y; end;
  if FBanding then
  begin
    FBandEnd := Point(X, Y);
    Invalidate;
  end
  else if FDragging and (FVertexTrack >= 0) and (FVertexTrack < FDoc.TrackCount) then
  begin
    I := FVertexIndex;
    with FDoc.Track(FVertexTrack) do
      if I <= High(Points) then
      begin
        if SnapPad(P, Ref) then Points[I] := FDoc.PadPoint(Ref)
        else Points[I] := FMouse;
        FDragMoved := True;
      end;
    FDoc.Changed;
  end
  else if FDragging and (FSel.Count > 0) then
  begin
    D.X := FMouse.X - FDragStart.X - FApplied.X;
    D.Y := FMouse.Y - FDragStart.Y - FApplied.Y;
    if (Abs(D.X) > 1e-9) or (Abs(D.Y) > 1e-9) then
    begin
      MPMoveSelection(FDoc, FSel, D.X, D.Y);
      FRotValid := False;
      FApplied.X := FApplied.X + D.X;
      FApplied.Y := FApplied.Y + D.Y;
      FDragMoved := True;
    end;
  end;
  FS := DefaultFormatSettings; FS.DecimalSeparator := ',';
  S := Format('X %.2f  Y %.2f mm  (%.0f  %.0f mil)', [P.X, P.Y, P.X / MP_MIL, P.Y / MP_MIL], FS);
  Status(S);
  Invalidate;
end;

procedure TMPEditor.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  A, B: TMPPoint;
  R: TMPRect;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FPanning then begin FPanning := False; Exit; end;
  if FBanding then
  begin
    FBanding := False;
    if (Abs(FBandEnd.X - FBandStart.X) > 3) or (Abs(FBandEnd.Y - FBandStart.Y) > 3) then
    begin
      A := MPToBoard(FView, Min(FBandStart.X, FBandEnd.X), Max(FBandStart.Y, FBandEnd.Y));
      B := MPToBoard(FView, Max(FBandStart.X, FBandEnd.X), Min(FBandStart.Y, FBandEnd.Y));
      R := MPEmptyRect;
      MPRectInclude(R, A.X, A.Y);
      MPRectInclude(R, B.X, B.Y);
      MPSelectInRect(FDoc, R, FSel, ssShift in Shift);
      SyncPrimary;
      if FSel.Count > 1 then
        Status(Format('%d itens selecionados: arraste, R gira, Del apaga, Ctrl+C copia.', [FSel.Count]));
    end;
    Invalidate;
    Exit;
  end;
  if FDragging then
  begin
    FDragging := False;
    FVertexTrack := -1;
    if FDragMoved then DoChanged
    else if FUndo.Count > 0 then FUndo.Delete(FUndo.Count - 1);   { clique sem mover }
  end;
end;

procedure TMPEditor.DblClick;
begin
  inherited DblClick;
  case FTool of
    etTrack: FinishTrack;
    etArea:
      begin
        { o duplo clique repete o ultimo ponto }
        if (Length(FPoints) >= 2) and (MPDist(FPoints[High(FPoints)], FPoints[High(FPoints) - 1]) < 1e-6) then
          SetLength(FPoints, Length(FPoints) - 1);
        FinishArea;
      end;
  end;
end;

function TMPEditor.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  P: TMPPoint;
  F: Double;
begin
  Result := True;
  P := MPToBoard(FView, MousePos.X, MousePos.Y);
  if WheelDelta > 0 then F := 1.2 else F := 1 / 1.2;
  FView.Scale := EnsureRange(FView.Scale * F, 0.5, 200);
  FView.OX := MousePos.X - P.X * FView.Scale;
  FView.OY := MousePos.Y + P.Y * FView.Scale;
  Invalidate;
end;

procedure TMPEditor.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_ESCAPE:
      begin
        if (Length(FPoints) > 0) or FHasWireFrom then CancelOperation
        else if FTool <> etSelect then SetTool(etSelect)
        else Select(selNone, -1);
        Key := 0;
      end;
    VK_DELETE: begin DeleteSelection; Key := 0; end;
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN:
      if (FSel.Count > 0) and (FDoc <> nil) then
      begin
        case Key of
          VK_LEFT: NudgeSelection(-FDoc.Grid, 0);
          VK_RIGHT: NudgeSelection(FDoc.Grid, 0);
          VK_UP: NudgeSelection(0, FDoc.Grid);
          VK_DOWN: NudgeSelection(0, -FDoc.Grid);
        end;
        Key := 0;
      end;
    VK_R: begin RotateSelection; Key := 0; end;
    VK_F: if Shift = [] then begin FlipSelection; Key := 0; end;
    VK_BACK:
      if Length(FPoints) > 0 then
      begin
        SetLength(FPoints, Length(FPoints) - 1);
        Invalidate; Key := 0;
      end;
    VK_ADD, VK_OEM_PLUS: begin ZoomBy(1.25); Key := 0; end;
    VK_SUBTRACT, VK_OEM_MINUS: begin ZoomBy(0.8); Key := 0; end;
  end;
end;

{ ---------------- desenho ---------------- }

procedure TMPEditor.DrawRulers;
var
  Step, X, Y: Double;
  PX, PY, I: Integer;
  S: string;
begin
  Canvas.Brush.Color := clSuiteCard;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(0, 0, ClientWidth, RULER);
  Canvas.Rectangle(0, 0, RULER, ClientHeight);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := clSuiteBorder;
  Canvas.Line(0, RULER, ClientWidth, RULER);
  Canvas.Line(RULER, 0, RULER, ClientHeight);
  { passo em mm: 1, 2, 5, 10, 20, 50 conforme o zoom }
  Step := 1;
  while Step * FView.Scale < 40 do
    if Step < 2 then Step := 2 else if Step < 5 then Step := 5 else Step := Step * 2;
  Canvas.Font.Size := 7;
  Canvas.Font.Color := clSuiteMuted;
  Canvas.Brush.Style := bsClear;
  X := Floor(MPToBoard(FView, RULER, 0).X / Step) * Step;
  I := 0;
  while I < 400 do
  begin
    PX := Round(FView.OX + X * FView.Scale);
    if PX > ClientWidth then Break;
    if PX >= RULER then
    begin
      Canvas.Line(PX, RULER - 7, PX, RULER);
      S := FloatToStr(X);
      Canvas.TextOut(PX + 2, 2, S);
    end;
    PX := Round(FView.OX + (X + Step / 2) * FView.Scale);
    if PX > RULER then Canvas.Line(PX, RULER - 3, PX, RULER);
    X := X + Step; Inc(I);
  end;
  Y := Floor(MPToBoard(FView, 0, ClientHeight).Y / Step) * Step;
  I := 0;
  while I < 400 do
  begin
    PY := Round(FView.OY - Y * FView.Scale);
    if PY < RULER then Break;
    if PY <= ClientHeight then
    begin
      Canvas.Line(RULER - 7, PY, RULER, PY);
      S := FloatToStr(Y);
      Canvas.TextOut(2, PY + 1, S);
    end;
    PY := Round(FView.OY - (Y + Step / 2) * FView.Scale);
    if PY > RULER then Canvas.Line(RULER - 3, PY, RULER, PY);
    Y := Y + Step; Inc(I);
  end;
  { cursor nas reguas }
  Canvas.Pen.Color := MP_SELECT_COLOR;
  if FMousePx.X > RULER then Canvas.Line(FMousePx.X, 0, FMousePx.X, RULER);
  if FMousePx.Y > RULER then Canvas.Line(0, FMousePx.Y, RULER, FMousePx.Y);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clSuiteCard;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(0, 0, RULER + 1, RULER + 1);
  Canvas.Pen.Style := psSolid;
  Canvas.Font.Color := clSuiteMuted;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(4, 5, 'mm');
  Canvas.Brush.Style := bsSolid;
end;

procedure TMPEditor.Paint;
var
  R: TRect;
  I: Integer;
  Pts: array of TPoint;
  C: TColor;
  W: Integer;
  A, B: TPoint;
  Ref: TMPPadRef;
begin
  R := Rect(0, 0, ClientWidth, ClientHeight);
  if FDoc = nil then
  begin
    Canvas.Brush.Color := clSuiteSurface;
    Canvas.FillRect(R);
    Exit;
  end;
  FR.Paint(Canvas, FView, R);
  if FR.Mode = vmNormal then
  begin
    if FActiveLayer = mlTopCopper then C := MP_TOP_COLOR else C := MP_BOTTOM_COLOR;
    { trilha ou area em construcao }
    if Length(FPoints) > 0 then
    begin
      SetLength(Pts, Length(FPoints) + 1);
      for I := 0 to High(FPoints) do Pts[I] := MPToScreen(FView, FPoints[I].X, FPoints[I].Y);
      if FTool = etTrack then
        with Constrain(FPoints[High(FPoints)], FMouse) do Pts[High(Pts)] := MPToScreen(FView, X, Y)
      else
        Pts[High(Pts)] := MPToScreen(FView, FMouse.X, FMouse.Y);
      Canvas.Brush.Style := bsClear;
      if FTool = etTrack then
      begin
        W := Max(1, Round(FDoc.TrackWidth * FView.Scale));
        Canvas.Pen.Color := C; Canvas.Pen.Width := W;
        Canvas.Pen.EndCap := pecRound; Canvas.Pen.JoinStyle := pjsRound;
        Canvas.Polyline(Pts);
      end
      else
      begin
        Canvas.Pen.Color := C; Canvas.Pen.Width := 2; Canvas.Pen.Style := psDash;
        Canvas.Polyline(Pts);
        Canvas.Line(Pts[High(Pts)], Pts[0]);
        Canvas.Pen.Style := psSolid;
      end;
      Canvas.Brush.Style := bsSolid;
    end;
    { ligacao em construcao }
    if FHasWireFrom then
    begin
      A := MPToScreen(FView, FDoc.PadPoint(FWireFrom).X, FDoc.PadPoint(FWireFrom).Y);
      B := MPToScreen(FView, FMouse.X, FMouse.Y);
      if SnapPad(FMouse, Ref) then
        B := MPToScreen(FView, FDoc.PadPoint(Ref).X, FDoc.PadPoint(Ref).Y);
      Canvas.Pen.Color := MP_RATS_COLOR; Canvas.Pen.Width := 2;
      Canvas.Line(A, B);
    end;
    if FGhost <> nil then FR.PaintGhost(Canvas, FView, FGhost);
    { cursor em cruz na grade }
    if FTool in [etTrack, etWire, etArea, etText, etPlace] then
    begin
      A := MPToScreen(FView, FMouse.X, FMouse.Y);
      Canvas.Pen.Color := MP_SELECT_COLOR; Canvas.Pen.Width := 1;
      Canvas.Line(A.X - 8, A.Y, A.X + 9, A.Y);
      Canvas.Line(A.X, A.Y - 8, A.X, A.Y + 9);
    end;
  end;
  if FBanding then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := MP_SELECT_COLOR; Canvas.Pen.Width := 1; Canvas.Pen.Style := psDash;
    Canvas.Rectangle(Min(FBandStart.X, FBandEnd.X), Min(FBandStart.Y, FBandEnd.Y),
      Max(FBandStart.X, FBandEnd.X), Max(FBandStart.Y, FBandEnd.Y));
    Canvas.Pen.Style := psSolid; Canvas.Brush.Style := bsSolid;
  end;
  { vertices da trilha selecionada (alcas) }
  if (FR.Mode = vmNormal) and (FTool = etSelect) then
    for I := 0 to FDoc.TrackCount - 1 do
      if FSel.Contains(ikTrack, I) and (FSel.Count <= 3) then
        for W := 0 to High(FDoc.Track(I).Points) do
        begin
          A := MPToScreen(FView, FDoc.Track(I).Points[W].X, FDoc.Track(I).Points[W].Y);
          Canvas.Brush.Color := clWhite; Canvas.Pen.Color := MP_SELECT_COLOR; Canvas.Pen.Width := 1;
          Canvas.Rectangle(A.X - 4, A.Y - 4, A.X + 5, A.Y + 5);
        end;
  DrawRulers;
end;

end.
