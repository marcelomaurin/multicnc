unit multicad_sketchtools;

{ MultiCAD - ferramentas do modo esboco (ARCHITECTURE 3A / TAREFA fase 3C).
  Sem LCL: recebe pontos ja no referencial do esboco (mm) e cria entidades,
  relacoes automaticas e cotas, como no SolidWorks:

  - Linha: clique-clique em cadeia (o fim vira o inicio da proxima);
    Esc/duplo clique encerra. Perto de horizontal/vertical (3 graus) a linha
    trava e ganha a relacao Horizontal/Vertical.
  - Retangulo de canto, circulo pelo centro, arco por 3 pontos
    (inicio, fim, ponto no arco), linha de centro, ponto.
  - Captura (snap) de pontos existentes e da origem dentro de PickTol, e de
    pontos sobre linhas/curvas; vira relacao Coincidente.
  - Cota inteligente: linha = comprimento; circulo = diametro; arco = raio;
    duas linhas = angulo (ou distancia se paralelas); ponto+ponto ou
    ponto+linha = distancia.
  - Relacoes pela selecao (AddRelation) e apagar selecao. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multicad_types, multicad_sketch, multicad_solver,
  multicad_document;

type
  TCadSketchToolKind = (tkSelect, tkLine, tkRectangle, tkCircle, tkArc3P,
    tkCenterline, tkPoint, tkDimension, tkArcCenter, tkArcTangent, tkFillet,
    tkChamfer);

  { Ponto capturado: Ent > 0 e Pt > 0 = ponto de entidade; Ent = origem;
    Ent > 0 e Pt = 0 = sobre a curva/linha; Ent > 0 e Pt = -1 = ponto medio
    da linha; Ent = 0 = livre. GuideX/GuideY: alinhado (linha de inferencia)
    com o ponto GX/GY na vertical/horizontal. OnGrid: preso na grade. }
  TCadSnap = record
    P: TCadVec2;
    Ent, Pt: Integer;
    GuideX, GuideY, OnGrid: Boolean;
    GX, GY: TCadVec2;
  end;

  TCadDimGeomKind = (dgLinear, dgRadius, dgDiameter, dgAngle);

  { Desenho de uma cota no esboco (mm): linhas de chamada A->DA e B->DB,
    linha de cota DA-DB com setas, texto em T. Angular: arco de centro C,
    raio R, de Ang0 a Ang1 (rad, anti-horario). Radial/diametral: linha
    DA-DB passando pelo centro C. }
  TCadDimGeom = record
    Kind: TCadDimGeomKind;
    A, B, DA, DB, T, C, Base: TCadVec2;
    R, Ang0, Ang1: Double;
    Text: string;
  end;

  TCadPickItem = record
    Ent, Pt: Integer;   { Pt = 0: a entidade inteira }
  end;

  TCadAskValueEvent = function(Sender: TObject; const ACaption: string;
    var AText: string): Boolean of object;
  { Valor da cota recem-colocada. RefOnly = so marcar a medida (cota de
    referencia, nao muda o desenho). }
  TCadAskDimEvent = function(Sender: TObject; const ACaption: string;
    var AText: string; var RefOnly: Boolean): Boolean of object;

  TCadSketchSession = class
  private
    FDoc: TCadDocument;
    FSketch: TCadSketch;
    FTool: TCadSketchToolKind;
    FClicks: array of TCadSnap;
    FChainEnt: Integer;      { linha anterior da cadeia }
    FDimFirst: TCadPickItem;
    FHasDimFirst: Boolean;
    FOnAskValue: TCadAskValueEvent;
    FOnAskDim: TCadAskDimEvent;
    FPlaceId: Integer;        { cota sendo colocada (segue o mouse) }
    FPairDone: Boolean;
    procedure FinishDimension(const P: TCadVec2);
    procedure MarkNewConstruction(AFrom: Integer);
    procedure SetTool(AValue: TCadSketchToolKind);
    procedure Bind(AEnt, APt: Integer; const S: TCadSnap);
    function CreateLine(const A, B: TCadSnap; AConstr, ACenter: Boolean): Integer;
    function Infer(const A: TCadSnap; var B: TCadSnap): TConstraintKind;
    function MakeDimension(const A: TCadPickItem; const B: TCadPickItem; HasB: Boolean): Integer;
    function FindCorner(const P: TCadVec2; out L1, P1, L2, P2: Integer): Boolean;
    function StartTangent(const S: TCadSnap; out T: TCadVec2): Boolean;
    procedure AddLinkedDim(AKind: TConstraintKind; AEnt, APt, BEnt, BPt: Integer;
      AValue: Double; const AText: string);
  public
    PickTol: Double;           { mm (o editor converte de pixels) }
    ConstructionMode: Boolean; { desenhar linhas de apoio (construcao, tracejadas) }
    GridStep: Double;          { passo da grade em mm (0 = sem grade) }
    GridSnap: Boolean;         { capturar na grade }
    FilletRadius: Double;      { ultimo raio de filete (mm) }
    ChamferD1, ChamferD2: Double; { ultimas distancias de chanfro (mm) }
    Cursor: TCadSnap;
    CursorInfer: Integer;      { 0 nada, 1 horizontal, 2 vertical }
    Selection: array of TCadPickItem;
    LastSolve: TSketchSolveResult;
    LastMessage: string;
    constructor Create(ADoc: TCadDocument; ASketch: TCadSketch);
    property Sketch: TCadSketch read FSketch;
    property Tool: TCadSketchToolKind read FTool write SetTool;
    property OnAskValue: TCadAskValueEvent read FOnAskValue write FOnAskValue;
    property OnAskDim: TCadAskDimEvent read FOnAskDim write FOnAskDim;
    { Cota em colocacao (Id da restricao; 0 = nenhuma). }
    property PlacingDim: Integer read FPlaceId;
    { Linha normal / linha de apoio nas entidades selecionadas. }
    function SetSelectionConstruction(AValue: Boolean): Boolean;
    { Estado de construcao da selecao: 0 nenhuma entidade, 1 normal, 2 apoio, 3 misto. }
    function SelectionConstructionState: Integer;
    { Descricao da selecao ("Linha: 80 mm, 0°"). }
    function SelectionText: string;
    { Pontos ja clicados da ferramenta atual (para o elastico). }
    function ClickCount: Integer;
    function ClickAt(I: Integer): TCadSnap;
    function Snap(const P: TCadVec2; AllowCurve: Boolean = True): TCadSnap;
    { Entidade (ou ponto) mais proxima dentro de PickTol. }
    function Hit(const P: TCadVec2; out Item: TCadPickItem): Boolean;
    function DistToEntity(const E: TSketchEntity; const P: TCadVec2): Double;
    procedure MouseMove(const P: TCadVec2);
    { Clique da ferramenta. Ctrl soma a selecao (ferramenta Selecionar).
      Devolve True se o esboco mudou. }
    function Click(const P: TCadVec2; AAdd: Boolean = False): Boolean;
    { Esc / duplo clique: encerra a cadeia ou volta para Selecionar. }
    procedure Cancel;
    procedure ClearSelection;
    function IsSelected(AEnt, APt: Integer): Boolean;
    { Relacao com a selecao atual. Devolve False e LastMessage se nao cabe. }
    function AddRelation(K: TConstraintKind): Boolean;
    { Apaga as entidades selecionadas. }
    function DeleteSelection: Boolean;
    { Cria a cota entre itens (usado pela ferramenta e pelos testes). }
    function AddSmartDimension(const A: TCadPickItem; const B: TCadPickItem;
      HasB: Boolean; const AValueText: string): Integer;
    procedure Solve;
    { Posicao (no esboco) onde mostrar o texto da cota de indice I. }
    function DimAnchor(AIndex: Integer; out P: TCadVec2): Boolean;
    { Linhas, setas e texto ("80 mm", "Ø8 mm", "R5 mm", "45°") da cota I. }
    function DimGeometry(AIndex: Integer; out G: TCadDimGeom): Boolean;
    { Arrastar o texto da cota para P (posicao gravada no esboco). }
    procedure MoveDimText(AIndex: Integer; const P: TCadVec2);
    { Digitar a medida durante o desenho (linha: comprimento [< angulo];
      retangulo: largura x altura; circulo: diametro). }
    function CanType: Boolean;
    function TypeHint: string;
    function ApplyTyped(const AText: string): Boolean;
    { Liga/desliga "construcao" nas entidades selecionadas. }
    function ToggleConstruction: Boolean;
    { Filete / chanfro no canto entre duas linhas perto de P. }
    function FilletCorner(const P: TCadVec2; R: Double): Boolean;
    function ChamferCorner(const P: TCadVec2; D1, D2: Double): Boolean;
    { Arco tangente: de S (fim de linha/arco) ate E. }
    function TangentArc(const S: TCadSnap; const E: TCadVec2; out Arc: TSketchEntity): Boolean;
  end;

function CadDimText(const C: TSketchConstraint): string;

const
  CAD_TOOL_NAMES: array[TCadSketchToolKind] of string = ('Selecionar', 'Linha',
    'Retângulo de canto', 'Círculo', 'Arco de 3 pontos', 'Linha de centro',
    'Ponto', 'Cota inteligente', 'Arco pelo centro', 'Arco tangente',
    'Filete de esboço', 'Chanfro de esboço');

function PickItem(AEnt, APt: Integer): TCadPickItem;

implementation

const
  INFER_TOL = 3.0;  { graus }

function PickItem(AEnt, APt: Integer): TCadPickItem;
begin
  Result.Ent := AEnt;
  Result.Pt := APt;
end;

function Dist2(const A, B: TCadVec2): Double;
begin
  Result := Sqrt(Sqr(A.X - B.X) + Sqr(A.Y - B.Y));
end;

function SegDist(const P, A, B: TCadVec2; out Q: TCadVec2): Double;
var
  DX, DY, L2, T: Double;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  L2 := DX * DX + DY * DY;
  if L2 < 1E-18 then
    T := 0
  else
    T := EnsureRange(((P.X - A.X) * DX + (P.Y - A.Y) * DY) / L2, 0, 1);
  Q := V2(A.X + DX * T, A.Y + DY * T);
  Result := Dist2(P, Q);
end;

function AngleIn(A0, A1, A: Double): Boolean;
var
  S, T: Double;
begin
  S := A1 - A0;
  while S <= 0 do
    S := S + 2 * Pi;
  T := A - A0;
  while T < 0 do
    T := T + 2 * Pi;
  while T >= 2 * Pi do
    T := T - 2 * Pi;
  Result := T <= S + 1E-9;
end;

{ ---------- sessao ---------- }

constructor TCadSketchSession.Create(ADoc: TCadDocument; ASketch: TCadSketch);
begin
  inherited Create;
  FDoc := ADoc;
  FSketch := ASketch;
  PickTol := 1;
  FTool := tkSelect;
  FilletRadius := 5;
  ChamferD1 := 2;
  ChamferD2 := 2;
  Solve;
end;

procedure TCadSketchSession.SetTool(AValue: TCadSketchToolKind);
begin
  Cancel;
  FTool := AValue;
  if AValue <> tkSelect then
    ClearSelection;
end;

function TCadSketchSession.ClickCount: Integer;
begin
  Result := Length(FClicks);
end;

function TCadSketchSession.ClickAt(I: Integer): TCadSnap;
begin
  Result := FClicks[I];
end;

procedure TCadSketchSession.Solve;
begin
  LastSolve := FDoc.SolveSketch(FSketch);
end;

function TCadSketchSession.DistToEntity(const E: TSketchEntity; const P: TCadVec2): Double;
var
  Q: TCadVec2;
  D, A: Double;
begin
  case E.Kind of
    seLine:
      Result := SegDist(P, E.P1, E.P2, Q);
    sePoint:
      Result := Dist2(P, E.P1);
    seCircle:
      Result := Abs(Dist2(P, E.P1) - E.Radius);
    seArc:
      begin
        D := Dist2(P, E.P1);
        A := ArcTan2(P.Y - E.P1.Y, P.X - E.P1.X);
        if AngleIn(ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X),
          ArcTan2(E.P3.Y - E.P1.Y, E.P3.X - E.P1.X), A) then
          Result := Abs(D - E.Radius)
        else
          Result := Min(Dist2(P, E.P2), Dist2(P, E.P3));
      end;
  else
    Result := 1E300;
  end;
end;

function TCadSketchSession.Snap(const P: TCadVec2; AllowCurve: Boolean): TCadSnap;
var
  I, K, NP: Integer;
  E: TSketchEntity;
  Best, D, BX, BY: Double;
  Q, BestQ: TCadVec2;
  BestEnt: Integer;
  Pts: array of TCadVec2;
  Drawing: Boolean;

  procedure AddPt(const APt: TCadVec2);
  begin
    SetLength(Pts, Length(Pts) + 1);
    Pts[High(Pts)] := APt;
  end;

begin
  Result := Default(TCadSnap);
  Result.P := P;
  Best := PickTol;
  Drawing := AllowCurve and not (FTool in [tkSelect, tkDimension, tkFillet, tkChamfer]);
  SetLength(Pts, 0);
  { origem }
  AddPt(V2(0, 0));
  D := Dist2(P, V2(0, 0));
  if D <= Best then
  begin
    Best := D;
    Result.P := V2(0, 0);
    Result.Ent := CAD_SKETCH_ORIGIN;
    Result.Pt := 1;
  end;
  { pontos das entidades e pontos medios das linhas }
  for I := 0 to FSketch.EntityCount - 1 do
  begin
    E := FSketch.Entity(I);
    case E.Kind of
      seLine: NP := 2;
      seArc: NP := 3;
      sePoint, seCircle: NP := 1;
    else
      NP := 0;
    end;
    for K := 1 to NP do
    begin
      case K of
        1: Q := E.P1;
        2: Q := E.P2;
      else
        Q := E.P3;
      end;
      AddPt(Q);
      D := Dist2(P, Q);
      if D < Best then
      begin
        Best := D;
        Result.P := Q;
        Result.Ent := E.Id;
        Result.Pt := K;
      end;
    end;
    if Drawing and (E.Kind = seLine) then
    begin
      Q := V2((E.P1.X + E.P2.X) / 2, (E.P1.Y + E.P2.Y) / 2);
      D := Dist2(P, Q);
      if D < Best * 0.8 then
      begin
        Best := D;
        Result.P := Q;
        Result.Ent := E.Id;
        Result.Pt := -1;
      end;
    end;
  end;
  { o ponto ja clicado tambem guia o alinhamento }
  for I := 0 to High(FClicks) do
    AddPt(FClicks[I].P);
  if (Result.Ent <> 0) or not AllowCurve then
    Exit;
  { sobre linha ou curva }
  Best := PickTol;
  BestEnt := 0;
  for I := 0 to FSketch.EntityCount - 1 do
  begin
    E := FSketch.Entity(I);
    if not (E.Kind in [seLine, seCircle, seArc]) then
      Continue;
    D := DistToEntity(E, P);
    if D < Best * 0.6 then
    begin
      Best := D;
      BestEnt := E.Id;
      if E.Kind = seLine then
        SegDist(P, E.P1, E.P2, BestQ)
      else
      begin
        D := Max(Dist2(P, E.P1), 1E-12);
        BestQ := V2(E.P1.X + (P.X - E.P1.X) * E.Radius / D, E.P1.Y + (P.Y - E.P1.Y) * E.Radius / D);
      end;
    end;
  end;
  if BestEnt <> 0 then
  begin
    Result.P := BestQ;
    Result.Ent := BestEnt;
    Result.Pt := 0;
    Exit;
  end;
  { linhas de inferencia: alinhado na vertical/horizontal com pontos }
  if Drawing then
  begin
    BX := PickTol * 0.8;
    BY := PickTol * 0.8;
    for I := 0 to High(Pts) do
    begin
      if (Abs(P.X - Pts[I].X) < BX) and (Abs(P.Y - Pts[I].Y) > PickTol) then
      begin
        BX := Abs(P.X - Pts[I].X);
        Result.GuideX := True;
        Result.GX := Pts[I];
      end;
      if (Abs(P.Y - Pts[I].Y) < BY) and (Abs(P.X - Pts[I].X) > PickTol) then
      begin
        BY := Abs(P.Y - Pts[I].Y);
        Result.GuideY := True;
        Result.GY := Pts[I];
      end;
    end;
    if Result.GuideX then
      Result.P.X := Result.GX.X;
    if Result.GuideY then
      Result.P.Y := Result.GY.Y;
  end;
  { grade }
  if Drawing and GridSnap and (GridStep > 0) then
  begin
    if not Result.GuideX then
      Result.P.X := Round(P.X / GridStep) * GridStep;
    if not Result.GuideY then
      Result.P.Y := Round(P.Y / GridStep) * GridStep;
    Result.OnGrid := True;
  end;
end;

function TCadSketchSession.Hit(const P: TCadVec2; out Item: TCadPickItem): Boolean;
var
  S: TCadSnap;
  I: Integer;
  Best, D: Double;
begin
  Item := PickItem(0, 0);
  S := Snap(P, False);
  if (S.Ent <> 0) and (Dist2(S.P, P) <= PickTol * 0.7) then
  begin
    Item := PickItem(S.Ent, S.Pt);
    Exit(True);
  end;
  Best := PickTol;
  for I := 0 to FSketch.EntityCount - 1 do
  begin
    D := DistToEntity(FSketch.Entity(I), P);
    if D < Best then
    begin
      Best := D;
      Item := PickItem(FSketch.Entity(I).Id, 0);
    end;
  end;
  Result := Item.Ent <> 0;
end;

function TCadSketchSession.Infer(const A: TCadSnap; var B: TCadSnap): TConstraintKind;
var
  DX, DY, Ang: Double;
begin
  Result := ckFixed;   { = nenhuma }
  if B.Ent <> 0 then
    Exit;
  DX := B.P.X - A.P.X;
  DY := B.P.Y - A.P.Y;
  if Sqrt(DX * DX + DY * DY) < PickTol then
    Exit;
  Ang := RadToDeg(ArcTan2(Abs(DY), Abs(DX)));
  if Ang <= INFER_TOL then
  begin
    B.P.Y := A.P.Y;
    Result := ckHorizontal;
  end
  else if Ang >= 90 - INFER_TOL then
  begin
    B.P.X := A.P.X;
    Result := ckVertical;
  end;
end;

procedure TCadSketchSession.MouseMove(const P: TCadVec2);
var
  K: TConstraintKind;
  I: Integer;
begin
  if FPlaceId <> 0 then
  begin
    I := FSketch.ConstraintIndex(FPlaceId);
    if I >= 0 then
      MoveDimText(I, P);
  end;
  Cursor := Snap(P);
  CursorInfer := 0;
  if (FTool in [tkLine, tkCenterline]) and (Length(FClicks) = 1) then
  begin
    K := Infer(FClicks[0], Cursor);
    if K = ckHorizontal then
      CursorInfer := 1
    else if K = ckVertical then
      CursorInfer := 2;
  end;
end;

procedure TCadSketchSession.Bind(AEnt, APt: Integer; const S: TCadSnap);
begin
  if S.Ent = 0 then
    Exit;
  if S.Pt < 0 then
    FSketch.AddConstraint(ckMidpoint, AEnt, APt, S.Ent, 0)
  else if S.Pt > 0 then
    FSketch.AddConstraint(ckCoincident, AEnt, APt, S.Ent, S.Pt)
  else
    FSketch.AddConstraint(ckCoincident, AEnt, APt, S.Ent, 0);
end;

function TCadSketchSession.CreateLine(const A, B: TCadSnap; AConstr, ACenter: Boolean): Integer;
var
  BB: TCadSnap;
  K: TConstraintKind;
begin
  BB := B;
  K := Infer(A, BB);
  if Dist2(A.P, BB.P) < 1E-6 then
    Exit(0);
  if ACenter then
    Result := FSketch.AddCenterline(A.P.X, A.P.Y, BB.P.X, BB.P.Y)
  else
    Result := FSketch.AddLine(A.P.X, A.P.Y, BB.P.X, BB.P.Y, AConstr);
  Bind(Result, 1, A);
  Bind(Result, 2, BB);
  if K in [ckHorizontal, ckVertical] then
    FSketch.AddConstraint(K, Result, 0, 0, 0);
end;

function TCadSketchSession.Click(const P: TCadVec2; AAdd: Boolean): Boolean;
var
  S, Prev: TCadSnap;
  Id, I: Integer;
  Item: TCadPickItem;
  R, D1, D2: Double;
  Tg: TCadVec2;
  Arc: TSketchEntity;
  Txt: string;
  HitOk: Boolean;
  NBefore: Integer;

  { "2", "2 x 3", "2;3" }
  function ParsePair(const T: string; out A, B: Double): Boolean;
  var
    U, E1, E2: string;
    K: Integer;
  begin
    U := StringReplace(LowerCase(Trim(T)), '×', 'x', [rfReplaceAll]);
    K := Pos('x', U);
    if K = 0 then
      K := Pos(';', U);
    if K = 0 then
    begin
      Result := FDoc.Eval(U, A, E1);
      B := A;
      Exit;
    end;
    Result := FDoc.Eval(Copy(U, 1, K - 1), A, E1) and FDoc.Eval(Copy(U, K + 1, MaxInt), B, E2);
  end;

begin
  Result := False;
  LastMessage := '';
  MouseMove(P);
  S := Cursor;
  NBefore := FSketch.EntityCount;
  case FTool of
    tkSelect:
      begin
        if not AAdd then
          ClearSelection;
        if Hit(P, Item) then
        begin
          if IsSelected(Item.Ent, Item.Pt) then
          begin
            for I := 0 to High(Selection) do
              if (Selection[I].Ent = Item.Ent) and (Selection[I].Pt = Item.Pt) then
              begin
                Delete(Selection, I, 1);
                Break;
              end;
          end
          else
            Insert(Item, Selection, Length(Selection));
        end;
      end;
    tkPoint:
      begin
        Id := FSketch.AddPoint(S.P.X, S.P.Y);
        Bind(Id, 1, S);
        Result := True;
      end;
    tkLine, tkCenterline:
      begin
        if Length(FClicks) = 0 then
        begin
          SetLength(FClicks, 1);
          FClicks[0] := S;
          FChainEnt := 0;
        end
        else
        begin
          Prev := FClicks[0];
          if FChainEnt <> 0 then
          begin
            Prev.Ent := FChainEnt;
            Prev.Pt := 2;
          end;
          Id := CreateLine(Prev, S, False, FTool = tkCenterline);
          if Id <> 0 then
          begin
            Result := True;
            if (S.Ent <> 0) and (S.Pt > 0) or (FTool = tkCenterline) then
              { fechou num ponto existente (ou linha de centro): fim da cadeia }
              SetLength(FClicks, 0)
            else
            begin
              FClicks[0].P := FSketch.Entity(FSketch.EntityIndex(Id)).P2;
              FChainEnt := Id;
            end;
          end;
        end;
      end;
    tkRectangle:
      if Length(FClicks) = 0 then
      begin
        SetLength(FClicks, 1);
        FClicks[0] := S;
      end
      else
      begin
        if (Abs(S.P.X - FClicks[0].P.X) > 1E-6) and (Abs(S.P.Y - FClicks[0].P.Y) > 1E-6) then
        begin
          Id := FSketch.AddRectangle(FClicks[0].P.X, FClicks[0].P.Y, S.P.X, S.P.Y);
          { canto inicial e o canto oposto: o retangulo comeca no inferior esquerdo }
          if (FClicks[0].Ent <> 0) then
          begin
            if Dist2(FSketch.Entity(FSketch.EntityIndex(Id)).P1, FClicks[0].P) < 1E-9 then
              Bind(Id, 1, FClicks[0])
            else if Dist2(FSketch.Entity(FSketch.EntityIndex(Id + 1)).P1, FClicks[0].P) < 1E-9 then
              Bind(Id + 1, 1, FClicks[0])
            else if Dist2(FSketch.Entity(FSketch.EntityIndex(Id + 2)).P1, FClicks[0].P) < 1E-9 then
              Bind(Id + 2, 1, FClicks[0])
            else
              Bind(Id + 3, 1, FClicks[0]);
          end;
          Result := True;
        end;
        SetLength(FClicks, 0);
      end;
    tkCircle:
      if Length(FClicks) = 0 then
      begin
        SetLength(FClicks, 1);
        FClicks[0] := S;
      end
      else
      begin
        R := Dist2(FClicks[0].P, S.P);
        if R > 1E-6 then
        begin
          Id := FSketch.AddCircle(FClicks[0].P.X, FClicks[0].P.Y, R);
          if (FClicks[0].Ent <> 0) and (FClicks[0].Pt > 0) then
            Bind(Id, 1, FClicks[0]);
          Result := True;
        end;
        SetLength(FClicks, 0);
      end;
    tkArc3P:
      begin
        Insert(S, FClicks, Length(FClicks));
        if Length(FClicks) = 3 then
        begin
          Id := FSketch.AddArc3P(FClicks[0].P.X, FClicks[0].P.Y, FClicks[2].P.X,
            FClicks[2].P.Y, FClicks[1].P.X, FClicks[1].P.Y);
          if Id <> 0 then
          begin
            { AddArc3P guarda inicio/fim anti-horario: liga cada clique ao ponto certo }
            for I := 0 to 1 do
              if FClicks[I].Ent <> 0 then
              begin
                if Dist2(FSketch.Entity(FSketch.EntityIndex(Id)).P2, FClicks[I].P) < 1E-6 then
                  Bind(Id, 2, FClicks[I])
                else
                  Bind(Id, 3, FClicks[I]);
              end;
            Result := True;
          end
          else
            LastMessage := 'Os três pontos estão alinhados';
          SetLength(FClicks, 0);
        end;
      end;
    tkArcCenter:
      begin
        Insert(S, FClicks, Length(FClicks));
        if Length(FClicks) = 3 then
        begin
          R := Dist2(FClicks[0].P, FClicks[1].P);
          if (R > 1E-6) and (Dist2(FClicks[0].P, FClicks[2].P) > 1E-6) then
          begin
            Id := FSketch.AddArc(FClicks[0].P.X, FClicks[0].P.Y, FClicks[1].P.X,
              FClicks[1].P.Y, FClicks[2].P.X, FClicks[2].P.Y);
            if (FClicks[0].Ent <> 0) and (FClicks[0].Pt > 0) then
              Bind(Id, 1, FClicks[0]);
            Bind(Id, 2, FClicks[1]);
            if (FClicks[2].Ent <> 0) and (FClicks[2].Pt <> 0) then
              Bind(Id, 3, FClicks[2]);
            Result := True;
          end;
          SetLength(FClicks, 0);
        end;
      end;
    tkArcTangent:
      if Length(FClicks) = 0 then
      begin
        if StartTangent(S, Tg) then
        begin
          SetLength(FClicks, 1);
          FClicks[0] := S;
        end
        else
          LastMessage := 'Comece o arco tangente no fim de uma linha ou arco';
      end
      else
      begin
        if TangentArc(FClicks[0], S.P, Arc) then
        begin
          Id := FSketch.AddArc(Arc.P1.X, Arc.P1.Y, Arc.P2.X, Arc.P2.Y, Arc.P3.X, Arc.P3.Y);
          { o inicio do arco tangente e P2 (anti-horario) ou P3 (horario) }
          if Dist2(Arc.P2, FClicks[0].P) < 1E-6 then
          begin
            Bind(Id, 2, FClicks[0]);
            if S.Ent <> 0 then
              Bind(Id, 3, S);
          end
          else
          begin
            Bind(Id, 3, FClicks[0]);
            if S.Ent <> 0 then
              Bind(Id, 2, S);
          end;
          FSketch.AddConstraint(ckTangent, Id, 0, FClicks[0].Ent, 0);
          Result := True;
        end
        else
          LastMessage := 'O fim está na direção da tangente: use uma linha';
        SetLength(FClicks, 0);
      end;
    tkFillet:
      begin
        R := FilletRadius;
        if Assigned(FOnAskValue) then
        begin
          Txt := FormatFloat('0.###', R);
          if not FOnAskValue(Self, 'Raio do filete (mm)', Txt) then
            Exit;
          if not FDoc.Eval(Txt, R, Txt) then
          begin
            LastMessage := 'Valor inválido: ' + Txt;
            Exit;
          end;
        end;
        Result := FilletCorner(P, R);
        if Result then
          FilletRadius := R;
      end;
    tkChamfer:
      begin
        D1 := ChamferD1;
        D2 := ChamferD2;
        if Assigned(FOnAskValue) then
        begin
          Txt := FormatFloat('0.###', D1);
          if Abs(D2 - D1) > 1E-9 then
            Txt := Txt + ' x ' + FormatFloat('0.###', D2);
          if not FOnAskValue(Self, 'Chanfro: distância ou "d1 x d2" (mm)', Txt) then
            Exit;
          if not ParsePair(Txt, D1, D2) then
          begin
            LastMessage := 'Valor inválido: ' + Txt;
            Exit;
          end;
        end;
        Result := ChamferCorner(P, D1, D2);
        if Result then
        begin
          ChamferD1 := D1;
          ChamferD2 := D2;
        end;
      end;
    tkDimension:
      begin
        { como a Cota inteligente do SolidWorks: escolher a linha/circulo (ou
          dois itens), a cota segue o mouse e o clique seguinte a coloca }
        HitOk := Hit(P, Item);
        if FPairDone or ((FPlaceId <> 0) and not HitOk) then
        begin
          FinishDimension(P);
          Result := True;
        end
        else if HitOk and not FHasDimFirst then
        begin
          FDimFirst := Item;
          FHasDimFirst := True;
          ClearSelection;
          Insert(Item, Selection, 0);
          if Item.Pt = 0 then
          begin
            FPlaceId := AddSmartDimension(Item, PickItem(0, 0), False, '');
            if FPlaceId <> 0 then
              MoveDimText(FSketch.ConstraintIndex(FPlaceId), P);
            LastMessage := '';
          end;
        end
        else if HitOk and FHasDimFirst and
          not ((Item.Ent = FDimFirst.Ent) and (Item.Pt = FDimFirst.Pt)) then
        begin
          if FPlaceId <> 0 then
          begin
            FSketch.DeleteConstraint(FPlaceId);
            FPlaceId := 0;
          end;
          FPlaceId := AddSmartDimension(FDimFirst, Item, True, '');
          if FPlaceId <> 0 then
          begin
            FPairDone := True;
            Insert(Item, Selection, Length(Selection));
            MoveDimText(FSketch.ConstraintIndex(FPlaceId), P);
          end
          else
          begin
            FHasDimFirst := False;
            ClearSelection;
          end;
        end;
      end;
  end;
  if Result and ConstructionMode and (FTool in [tkLine, tkRectangle, tkCircle, tkArc3P,
    tkPoint, tkArcCenter, tkArcTangent]) then
    MarkNewConstruction(NBefore);
  if Result then
    Solve;
end;

procedure TCadSketchSession.MarkNewConstruction(AFrom: Integer);
var
  I: Integer;
  E: TSketchEntity;
begin
  for I := AFrom to FSketch.EntityCount - 1 do
  begin
    E := FSketch.Entity(I);
    if E.Centerline then
      Continue;
    E.Construction := True;
    FSketch.SetEntity(I, E);
  end;
end;

procedure TCadSketchSession.FinishDimension(const P: TCadVec2);
var
  I: Integer;
  Txt: string;
  RefOnly, Ok: Boolean;
begin
  I := FSketch.ConstraintIndex(FPlaceId);
  FPlaceId := 0;
  FPairDone := False;
  FHasDimFirst := False;
  ClearSelection;
  if I < 0 then
    Exit;
  MoveDimText(I, P);
  Txt := FormatFloat('0.###', FSketch.Constraint(I).Value);
  RefOnly := not FSketch.Constraint(I).Driving;
  if Assigned(FOnAskDim) then
    Ok := FOnAskDim(Self, FSketch.Constraint(I).DimName, Txt, RefOnly)
  else if Assigned(FOnAskValue) then
  begin
    Ok := FOnAskValue(Self, FSketch.Constraint(I).DimName, Txt);
    RefOnly := False;
  end
  else
    Ok := False;
  if not Ok then
    Exit;   { fica com o valor medido }
  if RefOnly then
  begin
    FSketch.SetConstraintDriving(I, False);
    FSketch.SetConstraintExpr(I, '');
  end
  else
  begin
    FSketch.SetConstraintDriving(I, True);
    if Trim(Txt) <> '' then
      FSketch.SetConstraintExpr(I, Trim(Txt));
  end;
  Solve;
  if LastSolve.Status in [ssConflict, ssOverDefined] then
  begin
    if not RefOnly then
    begin
      FSketch.SetConstraintDriving(I, False);
      FSketch.SetConstraintExpr(I, '');
      Solve;
    end;
    LastMessage := 'A cota superdefine o esboço: ficou só marcando a medida';
  end;
end;

procedure TCadSketchSession.Cancel;
begin
  if FPlaceId <> 0 then
  begin
    FSketch.DeleteConstraint(FPlaceId);
    FPlaceId := 0;
    Solve;
  end;
  FPairDone := False;
  SetLength(FClicks, 0);
  FChainEnt := 0;
  FHasDimFirst := False;
  CursorInfer := 0;
end;

function TCadSketchSession.SetSelectionConstruction(AValue: Boolean): Boolean;
var
  I, Idx: Integer;
  E: TSketchEntity;
begin
  Result := False;
  for I := 0 to High(Selection) do
    if Selection[I].Pt = 0 then
    begin
      Idx := FSketch.EntityIndex(Selection[I].Ent);
      if Idx < 0 then
        Continue;
      E := FSketch.Entity(Idx);
      if E.Centerline or (E.Construction = AValue) then
        Continue;
      E.Construction := AValue;
      FSketch.SetEntity(Idx, E);
      Result := True;
    end;
end;

function TCadSketchSession.SelectionConstructionState: Integer;
var
  I, Idx: Integer;
  E: TSketchEntity;
  HasN, HasC: Boolean;
begin
  HasN := False;
  HasC := False;
  for I := 0 to High(Selection) do
    if Selection[I].Pt = 0 then
    begin
      Idx := FSketch.EntityIndex(Selection[I].Ent);
      if Idx < 0 then
        Continue;
      E := FSketch.Entity(Idx);
      if E.Construction or E.Centerline then
        HasC := True
      else
        HasN := True;
    end;
  Result := Ord(HasN) + 2 * Ord(HasC);
end;

function TCadSketchSession.SelectionText: string;
var
  Idx: Integer;
  E: TSketchEntity;
  L, A, Sw: Double;
begin
  Result := '';
  if Length(Selection) = 0 then
    Exit;
  if Length(Selection) > 1 then
    Exit(Format('%d itens selecionados', [Length(Selection)]));
  if Selection[0].Ent = CAD_SKETCH_ORIGIN then
    Exit('Origem do esboço');
  Idx := FSketch.EntityIndex(Selection[0].Ent);
  if Idx < 0 then
    Exit;
  E := FSketch.Entity(Idx);
  if Selection[0].Pt > 0 then
  begin
    case Selection[0].Pt of
      2: Result := Format('Ponto: X %s  Y %s mm', [FormatFloat('0.##', E.P2.X), FormatFloat('0.##', E.P2.Y)]);
      3: Result := Format('Ponto: X %s  Y %s mm', [FormatFloat('0.##', E.P3.X), FormatFloat('0.##', E.P3.Y)]);
    else
      Result := Format('Ponto: X %s  Y %s mm', [FormatFloat('0.##', E.P1.X), FormatFloat('0.##', E.P1.Y)]);
    end;
    Exit;
  end;
  case E.Kind of
    seLine:
      begin
        L := Dist2(E.P1, E.P2);
        A := RadToDeg(ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X));
        if E.Centerline then
          Result := 'Linha de centro'
        else if E.Construction then
          Result := 'Linha de apoio'
        else
          Result := 'Linha';
        Result := Result + Format(': %s mm, %s°', [FormatFloat('0.##', L), FormatFloat('0.#', A)]);
      end;
    seCircle:
      Result := Format('Círculo: Ø%s mm', [FormatFloat('0.##', 2 * E.Radius)]);
    seArc:
      begin
        Sw := RadToDeg(ArcTan2(E.P3.Y - E.P1.Y, E.P3.X - E.P1.X) - ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X));
        while Sw <= 0 do Sw := Sw + 360;
        Result := Format('Arco: R%s mm, %s°', [FormatFloat('0.##', E.Radius), FormatFloat('0.#', Sw)]);
      end;
    sePoint:
      Result := Format('Ponto: X %s  Y %s mm', [FormatFloat('0.##', E.P1.X), FormatFloat('0.##', E.P1.Y)]);
  end;
  if E.Construction and (E.Kind <> seLine) then
    Result := Result + ' (apoio)';
end;

procedure TCadSketchSession.ClearSelection;
begin
  SetLength(Selection, 0);
end;

function TCadSketchSession.IsSelected(AEnt, APt: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Selection) do
    if (Selection[I].Ent = AEnt) and (Selection[I].Pt = APt) then
      Exit(True);
  Result := False;
end;

function TCadSketchSession.MakeDimension(const A: TCadPickItem; const B: TCadPickItem;
  HasB: Boolean): Integer;
var
  Txt: string;
  I: Integer;
  V: Double;
begin
  Result := AddSmartDimension(A, B, HasB, '');
  if Result = 0 then
    Exit;
  I := FSketch.ConstraintIndex(Result);
  if Assigned(FOnAskValue) and (I >= 0) then
  begin
    V := FSketch.Constraint(I).Value;
    Txt := FormatFloat('0.###', V);
    if FOnAskValue(Self, FSketch.Constraint(I).DimName, Txt) and (Trim(Txt) <> '') then
    begin
      FSketch.SetConstraintExpr(I, Trim(Txt));
      Solve;
      if LastSolve.Status = ssConflict then
        LastMessage := LastSolve.Message;
    end;
  end;
end;

function TCadSketchSession.AddSmartDimension(const A: TCadPickItem; const B: TCadPickItem;
  HasB: Boolean; const AValueText: string): Integer;
var
  EA, EB: TSketchEntity;
  KA, KB: TSketchEntityKind;
  IA, IB, I: Integer;
  Kind: TConstraintKind;
  V, Cr: Double;
  Ok: Boolean;

  function KindOf(const It: TCadPickItem; out E: TSketchEntity; out Idx: Integer): TSketchEntityKind;
  begin
    Idx := -1;
    if It.Ent = CAD_SKETCH_ORIGIN then
      Exit(sePoint);
    Idx := FSketch.EntityIndex(It.Ent);
    if Idx < 0 then
      Exit(sePoint);
    E := FSketch.Entity(Idx);
    if It.Pt > 0 then
      Result := sePoint
    else
      Result := E.Kind;
  end;

begin
  Result := 0;
  LastMessage := '';
  KA := KindOf(A, EA, IA);
  if (A.Ent <> CAD_SKETCH_ORIGIN) and (IA < 0) then
    Exit;
  Ok := False;
  if not HasB then
  begin
    case KA of
      seLine:
        begin
          Result := FSketch.AddDimension(ckDistance, A.Ent, 0, 0, 0, 0);
          Ok := True;
        end;
      seCircle:
        begin
          Result := FSketch.AddDimension(ckDiameter, A.Ent, 0, 0, 0, 0);
          Ok := True;
        end;
      seArc:
        begin
          Result := FSketch.AddDimension(ckRadius, A.Ent, 0, 0, 0, 0);
          Ok := True;
        end;
    end;
  end
  else
  begin
    KB := KindOf(B, EB, IB);
    if (B.Ent <> CAD_SKETCH_ORIGIN) and (IB < 0) then
      Exit;
    if (KA = seLine) and (KB = seLine) then
    begin
      Cr := (EA.P2.X - EA.P1.X) * (EB.P2.Y - EB.P1.Y) - (EA.P2.Y - EA.P1.Y) * (EB.P2.X - EB.P1.X);
      if Abs(Cr) > 1E-6 * Max(1, Dist2(EA.P1, EA.P2) * Dist2(EB.P1, EB.P2)) then
        Kind := ckAngle
      else
        Kind := ckDistance;
      if Kind = ckAngle then
        Result := FSketch.AddDimension(ckAngle, A.Ent, 0, B.Ent, 0, 0)
      else
        Result := FSketch.AddDimension(ckDistance, A.Ent, 1, B.Ent, 0, 0);
      Ok := True;
    end
    else if (KA in [sePoint, seCircle, seArc]) and (KB in [sePoint, seCircle, seArc]) then
    begin
      { centro de curva quando a entidade inteira foi escolhida (Pt = 0) }
      Result := FSketch.AddDimension(ckDistance, A.Ent, A.Pt, B.Ent, B.Pt, 0);
      Ok := True;
    end
    else if (KA in [sePoint, seCircle, seArc]) and (KB = seLine) then
    begin
      Result := FSketch.AddDimension(ckDistance, A.Ent, A.Pt, B.Ent, 0, 0);
      Ok := True;
    end
    else if (KA = seLine) and (KB in [sePoint, seCircle, seArc]) then
    begin
      Result := FSketch.AddDimension(ckDistance, B.Ent, B.Pt, A.Ent, 0, 0);
      Ok := True;
    end;
  end;
  if not Ok or (Result = 0) then
  begin
    LastMessage := 'Não é possível cotar essa seleção';
    Exit(0);
  end;
  { valor atual medido }
  I := FSketch.ConstraintIndex(Result);
  if CadMeasureDimension(FSketch, I, V) then
    FSketch.SetConstraintValue(I, Abs(V));
  if AValueText <> '' then
    FSketch.SetConstraintExpr(I, AValueText);
  Solve;
  if LastSolve.Status in [ssOverDefined, ssConflict] then
  begin
    { como no SolidWorks: cota que superdefine vira dirigida }
    FSketch.SetConstraintDriving(I, False);
    FSketch.SetConstraintExpr(I, '');
    Solve;
    LastMessage := 'A cota superdefine o esboço: criada como cota dirigida';
  end;
end;

function TCadSketchSession.AddRelation(K: TConstraintKind): Boolean;
var
  N, I, CId: Integer;
  A, B: TCadPickItem;
  EA, EB: TSketchEntity;

  function Kind(const It: TCadPickItem; out E: TSketchEntity): TSketchEntityKind;
  var
    Idx: Integer;
  begin
    if It.Ent = CAD_SKETCH_ORIGIN then
      Exit(sePoint);
    Idx := FSketch.EntityIndex(It.Ent);
    E := FSketch.Entity(Idx);
    if It.Pt > 0 then
      Result := sePoint
    else
      Result := E.Kind;
  end;

begin
  Result := False;
  LastMessage := '';
  N := Length(Selection);
  CId := 0;
  if N = 0 then
  begin
    LastMessage := 'Selecione entidades do esboço';
    Exit;
  end;
  A := Selection[0];
  if N >= 2 then
    B := Selection[1]
  else
    B := PickItem(0, 0);
  case K of
    ckHorizontal, ckVertical:
      if (N = 1) and (Kind(A, EA) = seLine) then
        CId := FSketch.AddConstraint(K, A.Ent, 0, 0, 0)
      else if (N = 2) and (Kind(A, EA) = sePoint) and (Kind(B, EB) = sePoint) then
        CId := FSketch.AddConstraint(K, A.Ent, Max(A.Pt, 1), B.Ent, Max(B.Pt, 1))
      else if N >= 1 then
      begin
        { varias linhas de uma vez }
        for I := 0 to N - 1 do
          if Kind(Selection[I], EA) = seLine then
            CId := FSketch.AddConstraint(K, Selection[I].Ent, 0, 0, 0);
      end;
    ckCoincident:
      if (N = 2) and (Kind(A, EA) = sePoint) and (Kind(B, EB) = sePoint) then
        CId := FSketch.AddConstraint(K, A.Ent, Max(A.Pt, 1), B.Ent, Max(B.Pt, 1))
      else if (N = 2) and (Kind(A, EA) = sePoint) and (Kind(B, EB) in [seLine, seCircle, seArc]) then
        CId := FSketch.AddConstraint(K, A.Ent, Max(A.Pt, 1), B.Ent, 0)
      else if (N = 2) and (Kind(B, EB) = sePoint) and (Kind(A, EA) in [seLine, seCircle, seArc]) then
        CId := FSketch.AddConstraint(K, B.Ent, Max(B.Pt, 1), A.Ent, 0);
    ckParallel, ckPerpendicular:
      if (N = 2) and (Kind(A, EA) = seLine) and (Kind(B, EB) = seLine) then
        CId := FSketch.AddConstraint(K, A.Ent, 0, B.Ent, 0);
    ckEqual:
      if (N >= 2) then
      begin
        for I := 1 to N - 1 do
          if (Kind(A, EA) = Kind(Selection[I], EB)) or
            ((Kind(A, EA) in [seCircle, seArc]) and (Kind(Selection[I], EB) in [seCircle, seArc])) then
            CId := FSketch.AddConstraint(K, A.Ent, 0, Selection[I].Ent, 0);
      end;
    ckTangent:
      if (N = 2) and ((Kind(A, EA) in [seCircle, seArc]) or (Kind(B, EB) in [seCircle, seArc])) and
        (Kind(A, EA) <> sePoint) and (Kind(B, EB) <> sePoint) then
        CId := FSketch.AddConstraint(K, A.Ent, 0, B.Ent, 0);
    ckConcentric:
      if (N = 2) and (Kind(A, EA) in [seCircle, seArc]) and (Kind(B, EB) in [seCircle, seArc]) then
        CId := FSketch.AddConstraint(K, A.Ent, 0, B.Ent, 0)
      else if (N = 2) and (Kind(A, EA) in [seCircle, seArc]) and (Kind(B, EB) = sePoint) then
        CId := FSketch.AddConstraint(K, A.Ent, 0, B.Ent, Max(B.Pt, 1))
      else if (N = 2) and (Kind(B, EB) in [seCircle, seArc]) and (Kind(A, EA) = sePoint) then
        CId := FSketch.AddConstraint(K, B.Ent, 0, A.Ent, Max(A.Pt, 1));
    ckMidpoint:
      if (N = 2) and (Kind(A, EA) = sePoint) and (Kind(B, EB) = seLine) then
        CId := FSketch.AddConstraint(K, A.Ent, Max(A.Pt, 1), B.Ent, 0)
      else if (N = 2) and (Kind(B, EB) = sePoint) and (Kind(A, EA) = seLine) then
        CId := FSketch.AddConstraint(K, B.Ent, Max(B.Pt, 1), A.Ent, 0);
    ckFixed:
      for I := 0 to N - 1 do
        if Selection[I].Ent > 0 then
          CId := FSketch.AddFixed(Selection[I].Ent, Selection[I].Pt);
    ckSymmetric:
      if (N = 3) and (Kind(Selection[2], EA) = seLine) and (Kind(A, EA) = sePoint) and
        (Kind(B, EB) = sePoint) then
        CId := FSketch.AddSymmetric(A.Ent, Max(A.Pt, 1), B.Ent, Max(B.Pt, 1), Selection[2].Ent);
  end;
  if CId = 0 then
  begin
    LastMessage := 'A relação "' + CadConstraintName(K) + '" não se aplica a essa seleção';
    Exit;
  end;
  Solve;
  if LastSolve.Status = ssConflict then
  begin
    FSketch.DeleteConstraint(CId);
    Solve;
    LastMessage := 'A relação gera conflito e foi desfeita';
    Exit;
  end;
  Result := True;
end;

function TCadSketchSession.DeleteSelection: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Selection) do
    if (Selection[I].Ent > 0) and (FSketch.EntityIndex(Selection[I].Ent) >= 0) then
    begin
      FSketch.DeleteEntity(Selection[I].Ent);
      Result := True;
    end;
  ClearSelection;
  if Result then
    Solve;
end;

function TCadSketchSession.DimAnchor(AIndex: Integer; out P: TCadVec2): Boolean;
var
  G: TCadDimGeom;
begin
  Result := DimGeometry(AIndex, G);
  P := G.T;
end;

function CadDimText(const C: TSketchConstraint): string;
var
  V: string;
begin
  V := FormatFloat('0.##', Abs(C.Value));
  case C.Kind of
    ckDiameter: Result := 'Ø' + V + ' mm';
    ckRadius: Result := 'R' + V + ' mm';
    ckAngle: Result := V + '°';
  else
    Result := V + ' mm';
  end;
  if not C.Driving then
    Result := '(' + Result + ')';
end;

function Perp(const U: TCadVec2): TCadVec2;
begin
  Result := V2(-U.Y, U.X);
end;

function Unit2(const A, B: TCadVec2): TCadVec2;
var
  L: Double;
begin
  L := Max(Dist2(A, B), 1E-12);
  Result := V2((B.X - A.X) / L, (B.Y - A.Y) / L);
end;

function TCadSketchSession.DimGeometry(AIndex: Integer; out G: TCadDimGeom): Boolean;
var
  C: TSketchConstraint;
  IA, IB: Integer;
  EA, EB: TSketchEntity;
  PA, PB, U, N, Dir, M: TCadVec2;
  H, Den, T, A0, A1, Am, Sweep: Double;
  Gap: Double;
  Cen: TCadVec2;

  function SketchCenter: TCadVec2;
  var
    K, Cnt: Integer;
    E: TSketchEntity;
  begin
    Result := V2(0, 0);
    Cnt := 0;
    for K := 0 to FSketch.EntityCount - 1 do
    begin
      E := FSketch.Entity(K);
      if E.Construction then
        Continue;
      Result := V2(Result.X + E.P1.X, Result.Y + E.P1.Y);
      Inc(Cnt);
      if E.Kind = seLine then
      begin
        Result := V2(Result.X + E.P2.X, Result.Y + E.P2.Y);
        Inc(Cnt);
      end;
    end;
    if Cnt > 0 then
      Result := V2(Result.X / Cnt, Result.Y / Cnt);
  end;

  function PtOf(AEnt, APt: Integer; out Q: TCadVec2): Boolean;
  var
    Idx: Integer;
    E: TSketchEntity;
  begin
    Result := True;
    if AEnt = CAD_SKETCH_ORIGIN then
    begin
      Q := V2(0, 0);
      Exit;
    end;
    Idx := FSketch.EntityIndex(AEnt);
    if Idx < 0 then
      Exit(False);
    E := FSketch.Entity(Idx);
    case APt of
      2: Q := E.P2;
      3: Q := E.P3;
    else
      Q := E.P1;
    end;
  end;

begin
  Result := False;
  G := Default(TCadDimGeom);
  C := FSketch.Constraint(AIndex);
  if not IsDimensionKind(C.Kind) then
    Exit;
  G.Text := CadDimText(C);
  Gap := PickTol * 4;     { afastamento padrao da linha de cota (~28 px) }
  IA := FSketch.EntityIndex(C.EntityA);
  case C.Kind of
    ckRadius, ckDiameter:
      begin
        if IA < 0 then
          Exit;
        EA := FSketch.Entity(IA);
        G.C := EA.P1;
        G.R := EA.Radius;
        G.Base := EA.P1;
        if C.HasTextOff then
          G.T := V2(G.Base.X + C.TextOff.X, G.Base.Y + C.TextOff.Y)
        else
        begin
          { arco: no meio do arco; circulo: a 45 graus }
          if EA.Kind = seArc then
          begin
            A0 := ArcTan2(EA.P2.Y - EA.P1.Y, EA.P2.X - EA.P1.X);
            A1 := ArcTan2(EA.P3.Y - EA.P1.Y, EA.P3.X - EA.P1.X);
            Sweep := A1 - A0;
            while Sweep <= 0 do
              Sweep := Sweep + 2 * Pi;
            Am := A0 + Sweep / 2;
          end
          else
            Am := Pi / 4;
          G.T := V2(G.C.X + (G.R + Gap) * Cos(Am), G.C.Y + (G.R + Gap) * Sin(Am));
        end;
        Dir := Unit2(G.C, G.T);
        if Dist2(G.C, G.T) < 1E-9 then
          Dir := V2(1, 0);
        if C.Kind = ckDiameter then
        begin
          G.Kind := dgDiameter;
          G.DA := V2(G.C.X - Dir.X * G.R, G.C.Y - Dir.Y * G.R);
          G.DB := V2(G.C.X + Dir.X * G.R, G.C.Y + Dir.Y * G.R);
        end
        else
        begin
          G.Kind := dgRadius;
          G.DA := G.C;
          G.DB := V2(G.C.X + Dir.X * G.R, G.C.Y + Dir.Y * G.R);
        end;
        G.A := G.DA;
        G.B := G.DB;
        Exit(True);
      end;
    ckAngle:
      begin
        IB := FSketch.EntityIndex(C.EntityB);
        if (IA < 0) or (IB < 0) then
          Exit;
        EA := FSketch.Entity(IA);
        EB := FSketch.Entity(IB);
        G.Kind := dgAngle;
        { vertice: intersecao das retas }
        U := Unit2(EA.P1, EA.P2);
        N := Unit2(EB.P1, EB.P2);
        Den := U.X * N.Y - U.Y * N.X;
        if Abs(Den) < 1E-12 then
          G.C := EA.P2
        else
        begin
          T := ((EB.P1.X - EA.P1.X) * N.Y - (EB.P1.Y - EA.P1.Y) * N.X) / Den;
          G.C := V2(EA.P1.X + U.X * T, EA.P1.Y + U.Y * T);
        end;
        G.Base := G.C;
        { lados: do vertice para o meio de cada linha }
        PA := V2((EA.P1.X + EA.P2.X) / 2, (EA.P1.Y + EA.P2.Y) / 2);
        PB := V2((EB.P1.X + EB.P2.X) / 2, (EB.P1.Y + EB.P2.Y) / 2);
        if Dist2(PA, G.C) < 1E-9 then PA := EA.P2;
        if Dist2(PB, G.C) < 1E-9 then PB := EB.P2;
        A0 := ArcTan2(PA.Y - G.C.Y, PA.X - G.C.X);
        A1 := ArcTan2(PB.Y - G.C.Y, PB.X - G.C.X);
        Sweep := A1 - A0;
        while Sweep <= -Pi do Sweep := Sweep + 2 * Pi;
        while Sweep > Pi do Sweep := Sweep - 2 * Pi;
        if Sweep < 0 then
        begin
          G.Ang0 := A1;
          G.Ang1 := A0;
        end
        else
        begin
          G.Ang0 := A0;
          G.Ang1 := A1;
        end;
        G.R := Max(Min(Dist2(G.C, PA), Dist2(G.C, PB)) * 0.6, Gap);
        Am := G.Ang0 + Abs(Sweep) / 2;
        if C.HasTextOff then
        begin
          G.T := V2(G.Base.X + C.TextOff.X, G.Base.Y + C.TextOff.Y);
          G.R := Max(Dist2(G.C, G.T), PickTol);
        end
        else
          G.T := V2(G.C.X + G.R * Cos(Am), G.C.Y + G.R * Sin(Am));
        G.A := PA;
        G.B := PB;
        Exit(True);
      end;
  end;
  { lineares }
  G.Kind := dgLinear;
  if (C.EntityB = 0) and (IA >= 0) and (FSketch.Entity(IA).Kind = seLine) then
  begin
    EA := FSketch.Entity(IA);
    PA := EA.P1;
    PB := EA.P2;
  end
  else
  begin
    IB := FSketch.EntityIndex(C.EntityB);
    if (IB >= 0) and (FSketch.Entity(IB).Kind = seLine) and (C.PointB = 0) then
    begin
      { ponto ate reta: pe da perpendicular }
      if not PtOf(C.EntityA, C.PointA, PA) then
        Exit;
      EB := FSketch.Entity(IB);
      U := Unit2(EB.P1, EB.P2);
      T := (PA.X - EB.P1.X) * U.X + (PA.Y - EB.P1.Y) * U.Y;
      PB := V2(EB.P1.X + U.X * T, EB.P1.Y + U.Y * T);
    end
    else if not PtOf(C.EntityA, C.PointA, PA) or not PtOf(C.EntityB, C.PointB, PB) then
      Exit;
  end;
  G.A := PA;
  G.B := PB;
  M := V2((PA.X + PB.X) / 2, (PA.Y + PB.Y) / 2);
  G.Base := M;
  case C.Kind of
    ckHorizontalDistance: begin U := V2(1, 0); N := V2(0, 1); end;
    ckVerticalDistance: begin U := V2(0, 1); N := V2(-1, 0); end;
  else
    if Dist2(PA, PB) < 1E-9 then
      U := V2(1, 0)
    else
      U := Unit2(PA, PB);
    N := Perp(U);
  end;
  if C.HasTextOff then
    G.T := V2(M.X + C.TextOff.X, M.Y + C.TextOff.Y)
  else
  begin
    { cota para fora do desenho: lado oposto ao centro do esboco }
    Cen := SketchCenter;
    if (M.X - Cen.X) * N.X + (M.Y - Cen.Y) * N.Y < 0 then
      N := V2(-N.X, -N.Y);
    G.T := V2(M.X + N.X * Gap, M.Y + N.Y * Gap);
  end;
  { linha de cota paralela a U passando pela altura do texto }
  H := (G.T.X - PA.X) * N.X + (G.T.Y - PA.Y) * N.Y;
  G.DA := V2(PA.X + N.X * H, PA.Y + N.Y * H);
  H := (G.T.X - PB.X) * N.X + (G.T.Y - PB.Y) * N.Y;
  G.DB := V2(PB.X + N.X * H, PB.Y + N.Y * H);
  Result := True;
end;

procedure TCadSketchSession.MoveDimText(AIndex: Integer; const P: TCadVec2);
var
  G: TCadDimGeom;
begin
  if not DimGeometry(AIndex, G) then
    Exit;
  FSketch.SetConstraintTextOffset(AIndex, V2(P.X - G.Base.X, P.Y - G.Base.Y));
end;

{ ---------- digitar a medida ---------- }

function TCadSketchSession.CanType: Boolean;
begin
  Result := (FTool in [tkLine, tkCenterline, tkRectangle, tkCircle]) and (Length(FClicks) = 1);
end;

function TCadSketchSession.TypeHint: string;
begin
  case FTool of
    tkLine, tkCenterline: Result := 'Comprimento em mm (ex.: 80, ou 80<30 para 30°)';
    tkRectangle: Result := 'Largura x altura em mm (ex.: 80 x 50)';
    tkCircle: Result := 'Diâmetro em mm (ex.: 12)';
  else
    Result := '';
  end;
end;

procedure TCadSketchSession.AddLinkedDim(AKind: TConstraintKind; AEnt, APt, BEnt, BPt: Integer;
  AValue: Double; const AText: string);
var
  CId, I: Integer;
  V: Double;
begin
  CId := FSketch.AddDimension(AKind, AEnt, APt, BEnt, BPt, AValue);
  I := FSketch.ConstraintIndex(CId);
  if (AText <> '') and not TryStrToFloat(StringReplace(AText, ',', '.', []), V,
    DefaultFormatSettings) and not TryStrToFloat(AText, V) then
    FSketch.SetConstraintExpr(I, AText);
end;

function TCadSketchSession.ApplyTyped(const AText: string): Boolean;
var
  T, A, B, Err: string;
  K, Id: Integer;
  L, Ang, W, H, D: Double;
  S0, E: TCadSnap;
  Dir: TCadVec2;
  SX, SY: Double;
  HasAng: Boolean;
  NB: Integer;
begin
  Result := False;
  LastMessage := '';
  if not CanType then
    Exit;
  T := StringReplace(LowerCase(Trim(AText)), '×', 'x', [rfReplaceAll]);
  T := StringReplace(T, 'mm', '', [rfReplaceAll]);
  S0 := FClicks[0];
  NB := FSketch.EntityCount;
  case FTool of
    tkLine, tkCenterline:
      begin
        K := Pos('<', T);
        HasAng := K > 0;
        if HasAng then
        begin
          A := Trim(Copy(T, 1, K - 1));
          B := Trim(Copy(T, K + 1, MaxInt));
        end
        else
          A := T;
        if not FDoc.Eval(A, L, Err) or (L <= 0) then
        begin
          LastMessage := 'Comprimento inválido: ' + A;
          Exit;
        end;
        if HasAng then
        begin
          B := StringReplace(B, '°', '', [rfReplaceAll]);
          if not FDoc.Eval(B, Ang, Err) then
          begin
            LastMessage := 'Ângulo inválido: ' + B;
            Exit;
          end;
          Dir := V2(Cos(DegToRad(Ang)), Sin(DegToRad(Ang)));
        end
        else
        begin
          Dir := Unit2(S0.P, Cursor.P);
          if Dist2(S0.P, Cursor.P) < 1E-9 then
            Dir := V2(1, 0);
          { travas H/V da inferencia }
          if CursorInfer = 1 then Dir := V2(Sign(Dir.X), 0);
          if CursorInfer = 2 then Dir := V2(0, Sign(Dir.Y));
          if (Dir.X = 0) and (Dir.Y = 0) then Dir := V2(1, 0);
        end;
        E := Default(TCadSnap);
        E.P := V2(S0.P.X + Dir.X * L, S0.P.Y + Dir.Y * L);
        if FChainEnt <> 0 then
        begin
          S0.Ent := FChainEnt;
          S0.Pt := 2;
        end;
        Id := CreateLine(S0, E, False, FTool = tkCenterline);
        if Id = 0 then
          Exit;
        AddLinkedDim(ckDistance, Id, 0, 0, 0, L, A);
        if FTool = tkCenterline then
          SetLength(FClicks, 0)
        else
        begin
          FClicks[0].P := FSketch.Entity(FSketch.EntityIndex(Id)).P2;
          FClicks[0].Ent := 0;
          FChainEnt := Id;
        end;
        Result := True;
      end;
    tkRectangle:
      begin
        K := Pos('x', T);
        if K = 0 then K := Pos(';', T);
        if K = 0 then K := Pos(' ', T);
        if K = 0 then
        begin
          LastMessage := 'Digite largura x altura (ex.: 80 x 50)';
          Exit;
        end;
        A := Trim(Copy(T, 1, K - 1));
        B := Trim(Copy(T, K + 1, MaxInt));
        if not FDoc.Eval(A, W, Err) or not FDoc.Eval(B, H, Err) or (W <= 0) or (H <= 0) then
        begin
          LastMessage := 'Medidas inválidas: ' + T;
          Exit;
        end;
        SX := 1;
        SY := 1;
        if Cursor.P.X < S0.P.X then SX := -1;
        if Cursor.P.Y < S0.P.Y then SY := -1;
        Id := FSketch.AddRectangle(S0.P.X, S0.P.Y, S0.P.X + SX * W, S0.P.Y + SY * H);
        if S0.Ent <> 0 then
        begin
          for K := 0 to 3 do
            if Dist2(FSketch.Entity(FSketch.EntityIndex(Id + K)).P1, S0.P) < 1E-9 then
            begin
              Bind(Id + K, 1, S0);
              Break;
            end;
        end;
        AddLinkedDim(ckHorizontalDistance, Id, 0, 0, 0, W, A);
        AddLinkedDim(ckVerticalDistance, Id + 1, 0, 0, 0, H, B);
        SetLength(FClicks, 0);
        Result := True;
      end;
    tkCircle:
      begin
        if not FDoc.Eval(T, D, Err) or (D <= 0) then
        begin
          LastMessage := 'Diâmetro inválido: ' + T;
          Exit;
        end;
        Id := FSketch.AddCircle(S0.P.X, S0.P.Y, D / 2);
        if (S0.Ent <> 0) and (S0.Pt > 0) then
          Bind(Id, 1, S0);
        AddLinkedDim(ckDiameter, Id, 0, 0, 0, D, T);
        SetLength(FClicks, 0);
        Result := True;
      end;
  end;
  if Result then
  begin
    if ConstructionMode then
      MarkNewConstruction(NB);
    Solve;
    if LastSolve.Status = ssConflict then
      LastMessage := LastSolve.Message;
  end;
end;

{ ---------- construcao ---------- }

function TCadSketchSession.ToggleConstruction: Boolean;
var
  I, Idx: Integer;
  E: TSketchEntity;
begin
  Result := False;
  for I := 0 to High(Selection) do
    if Selection[I].Pt = 0 then
    begin
      Idx := FSketch.EntityIndex(Selection[I].Ent);
      if Idx < 0 then
        Continue;
      E := FSketch.Entity(Idx);
      if E.Centerline then
        Continue;
      E.Construction := not E.Construction;
      FSketch.SetEntity(Idx, E);
      Result := True;
    end;
  if not Result then
    LastMessage := 'Selecione linhas, arcos ou círculos';
end;

{ ---------- arco tangente ---------- }

function TCadSketchSession.StartTangent(const S: TCadSnap; out T: TCadVec2): Boolean;
var
  Idx: Integer;
  E: TSketchEntity;
  R: TCadVec2;
begin
  Result := False;
  T := V2(1, 0);
  if (S.Ent <= 0) or (S.Pt <= 0) then
    Exit;
  Idx := FSketch.EntityIndex(S.Ent);
  if Idx < 0 then
    Exit;
  E := FSketch.Entity(Idx);
  case E.Kind of
    seLine:
      if S.Pt = 2 then
        T := Unit2(E.P1, E.P2)
      else
        T := Unit2(E.P2, E.P1);
    seArc:
      begin
        if S.Pt = 2 then
        begin
          R := Unit2(E.P1, E.P2);
          T := V2(R.Y, -R.X);      { sai do inicio no sentido horario }
        end
        else if S.Pt = 3 then
        begin
          R := Unit2(E.P1, E.P3);
          T := V2(-R.Y, R.X);      { continua no sentido anti-horario }
        end
        else
          Exit;
      end;
  else
    Exit;
  end;
  Result := True;
end;

function TCadSketchSession.TangentArc(const S: TCadSnap; const E: TCadVec2;
  out Arc: TSketchEntity): Boolean;
var
  T, N, D, C: TCadVec2;
  Den, R: Double;
begin
  Result := False;
  Arc := Default(TSketchEntity);
  if not StartTangent(S, T) then
    Exit;
  N := Perp(T);
  D := V2(E.X - S.P.X, E.Y - S.P.Y);
  Den := 2 * (N.X * D.X + N.Y * D.Y);
  if Abs(Den) < 1E-9 * Max(1, D.X * D.X + D.Y * D.Y) then
    Exit;
  R := (D.X * D.X + D.Y * D.Y) / Den;
  C := V2(S.P.X + N.X * R, S.P.Y + N.Y * R);
  Arc.Kind := seArc;
  Arc.P1 := C;
  Arc.Radius := Abs(R);
  if R > 0 then
  begin
    Arc.P2 := S.P;   { vira a esquerda: anti-horario de S para E }
    Arc.P3 := E;
  end
  else
  begin
    Arc.P2 := E;
    Arc.P3 := S.P;
  end;
  Result := True;
end;

{ ---------- filete e chanfro ---------- }

function TCadSketchSession.FindCorner(const P: TCadVec2; out L1, P1, L2, P2: Integer): Boolean;
var
  I, J, K, M: Integer;
  EI, EJ: TSketchEntity;
  QI, QJ: TCadVec2;
  Best, D: Double;
begin
  Result := False;
  L1 := 0; P1 := 0; L2 := 0; P2 := 0;
  Best := PickTol * 1.5;
  for I := 0 to FSketch.EntityCount - 1 do
  begin
    EI := FSketch.Entity(I);
    if (EI.Kind <> seLine) or EI.Construction or EI.Centerline then
      Continue;
    for K := 1 to 2 do
    begin
      if K = 1 then QI := EI.P1 else QI := EI.P2;
      D := Dist2(P, QI);
      if D > Best then
        Continue;
      for J := I + 1 to FSketch.EntityCount - 1 do
      begin
        EJ := FSketch.Entity(J);
        if (EJ.Kind <> seLine) or EJ.Construction or EJ.Centerline then
          Continue;
        for M := 1 to 2 do
        begin
          if M = 1 then QJ := EJ.P1 else QJ := EJ.P2;
          if Dist2(QI, QJ) < 1E-5 then
          begin
            Best := D;
            L1 := EI.Id; P1 := K;
            L2 := EJ.Id; P2 := M;
            Result := True;
          end;
        end;
      end;
    end;
  end;
end;

{ apaga a coincidente entre (A, PA) e (B, PB) }
procedure DropCoincident(S: TCadSketch; A, PA, B, PB: Integer);
var
  I: Integer;
  C: TSketchConstraint;
begin
  for I := S.ConstraintCount - 1 downto 0 do
  begin
    C := S.Constraint(I);
    if (C.Kind = ckCoincident) and (((C.EntityA = A) and (C.PointA = PA) and
      (C.EntityB = B) and (C.PointB = PB)) or ((C.EntityA = B) and (C.PointA = PB) and
      (C.EntityB = A) and (C.PointB = PA))) then
      S.DeleteConstraint(C.Id);
  end;
end;

{ Canto virtual (como o "virtual sharp" do SolidWorks): ponto de construcao
  no canto original, preso as duas linhas; as restricoes e cotas que usavam
  a ponta cortada passam a usar esse ponto, entao as medidas da peca nao
  mudam com o filete/chanfro. Devolve o Id do ponto. }
function VirtualSharp(S: TCadSketch; const V: TCadVec2; L1, P1, L2, P2: Integer): Integer;
var
  Idx: Integer;
  E: TSketchEntity;
  C: TSketchConstraint;

  procedure Retarget(L, Pt: Integer);
  var
    K: Integer;
  begin
    for K := 0 to S.ConstraintCount - 1 do
    begin
      C := S.Constraint(K);
      if IsDimensionKind(C.Kind) and (C.EntityA = L) and (C.EntityB = 0) and
        (C.PointA = 0) and (C.Kind <> ckAngle) then
      begin
        { cota do comprimento da linha: vira cota ate o canto virtual }
        if Pt = 1 then
          S.SetConstraintRefs(K, Result, 1, L, 2)
        else
          S.SetConstraintRefs(K, L, 1, Result, 1);
        Continue;
      end;
      if (C.EntityA = L) and (C.PointA = Pt) then
        S.SetConstraintRefs(K, Result, 1, C.EntityB, C.PointB)
      else if (C.EntityB = L) and (C.PointB = Pt) then
        S.SetConstraintRefs(K, C.EntityA, C.PointA, Result, 1);
    end;
  end;

begin
  Result := S.AddPoint(V.X, V.Y);
  Idx := S.EntityIndex(Result);
  E := S.Entity(Idx);
  E.Construction := True;
  S.SetEntity(Idx, E);
  Retarget(L1, P1);
  Retarget(L2, P2);
  S.AddConstraint(ckCoincident, Result, 1, L1, 0);
  S.AddConstraint(ckCoincident, Result, 1, L2, 0);
end;

{ move a extremidade APt da linha AEnt para Q }
procedure MoveEnd(S: TCadSketch; AEnt, APt: Integer; const Q: TCadVec2);
var
  Idx: Integer;
  E: TSketchEntity;
begin
  Idx := S.EntityIndex(AEnt);
  E := S.Entity(Idx);
  if APt = 1 then E.P1 := Q else E.P2 := Q;
  S.SetEntity(Idx, E);
end;

function TCadSketchSession.FilletCorner(const P: TCadVec2; R: Double): Boolean;
var
  L1, P1, L2, P2, Id: Integer;
  E1, E2: TSketchEntity;
  V, O1, O2, U1, U2, T1, T2, Bis, C: TCadVec2;
  Ang, D, Cr: Double;
begin
  Result := False;
  LastMessage := '';
  if R <= 0 then
  begin
    LastMessage := 'O raio deve ser maior que zero';
    Exit;
  end;
  if not FindCorner(P, L1, P1, L2, P2) then
  begin
    LastMessage := 'Clique no canto onde duas linhas se encontram';
    Exit;
  end;
  E1 := FSketch.Entity(FSketch.EntityIndex(L1));
  E2 := FSketch.Entity(FSketch.EntityIndex(L2));
  if P1 = 1 then begin V := E1.P1; O1 := E1.P2; end else begin V := E1.P2; O1 := E1.P1; end;
  if P2 = 1 then O2 := E2.P2 else O2 := E2.P1;
  U1 := Unit2(V, O1);
  U2 := Unit2(V, O2);
  Ang := ArcCos(EnsureRange(U1.X * U2.X + U1.Y * U2.Y, -1, 1));
  if (Ang < DegToRad(1)) or (Ang > DegToRad(179)) then
  begin
    LastMessage := 'As linhas estão alinhadas: não há canto para o filete';
    Exit;
  end;
  D := R / Tan(Ang / 2);
  if (D >= Dist2(V, O1) - 1E-6) or (D >= Dist2(V, O2) - 1E-6) then
  begin
    LastMessage := 'Raio grande demais para as linhas do canto';
    Exit;
  end;
  T1 := V2(V.X + U1.X * D, V.Y + U1.Y * D);
  T2 := V2(V.X + U2.X * D, V.Y + U2.Y * D);
  Bis := Unit2(V2(0, 0), V2(U1.X + U2.X, U1.Y + U2.Y));
  C := V2(V.X + Bis.X * R / Sin(Ang / 2), V.Y + Bis.Y * R / Sin(Ang / 2));
  DropCoincident(FSketch, L1, P1, L2, P2);
  VirtualSharp(FSketch, V, L1, P1, L2, P2);
  MoveEnd(FSketch, L1, P1, T1);
  MoveEnd(FSketch, L2, P2, T2);
  { arco curto entre T1 e T2, anti-horario }
  Cr := (T1.X - C.X) * (T2.Y - C.Y) - (T1.Y - C.Y) * (T2.X - C.X);
  if Cr > 0 then
  begin
    Id := FSketch.AddArc(C.X, C.Y, T1.X, T1.Y, T2.X, T2.Y);
    FSketch.AddConstraint(ckCoincident, Id, 2, L1, P1);
    FSketch.AddConstraint(ckCoincident, Id, 3, L2, P2);
  end
  else
  begin
    Id := FSketch.AddArc(C.X, C.Y, T2.X, T2.Y, T1.X, T1.Y);
    FSketch.AddConstraint(ckCoincident, Id, 2, L2, P2);
    FSketch.AddConstraint(ckCoincident, Id, 3, L1, P1);
  end;
  FSketch.AddConstraint(ckTangent, Id, 0, L1, 0);
  FSketch.AddConstraint(ckTangent, Id, 0, L2, 0);
  FSketch.AddDimension(ckRadius, Id, 0, 0, 0, R);
  Solve;
  if LastSolve.Status = ssConflict then
    LastMessage := LastSolve.Message;
  Result := True;
end;

function TCadSketchSession.ChamferCorner(const P: TCadVec2; D1, D2: Double): Boolean;
var
  L1, P1, L2, P2, Id: Integer;
  E1, E2: TSketchEntity;
  V, O1, O2, U1, U2, T1, T2: TCadVec2;
begin
  Result := False;
  LastMessage := '';
  if (D1 <= 0) or (D2 <= 0) then
  begin
    LastMessage := 'As distâncias devem ser maiores que zero';
    Exit;
  end;
  if not FindCorner(P, L1, P1, L2, P2) then
  begin
    LastMessage := 'Clique no canto onde duas linhas se encontram';
    Exit;
  end;
  E1 := FSketch.Entity(FSketch.EntityIndex(L1));
  E2 := FSketch.Entity(FSketch.EntityIndex(L2));
  if P1 = 1 then begin V := E1.P1; O1 := E1.P2; end else begin V := E1.P2; O1 := E1.P1; end;
  if P2 = 1 then O2 := E2.P2 else O2 := E2.P1;
  if (D1 >= Dist2(V, O1) - 1E-6) or (D2 >= Dist2(V, O2) - 1E-6) then
  begin
    LastMessage := 'Chanfro maior que as linhas do canto';
    Exit;
  end;
  U1 := Unit2(V, O1);
  U2 := Unit2(V, O2);
  if Abs(U1.X * U2.Y - U1.Y * U2.X) < 1E-6 then
  begin
    LastMessage := 'As linhas estão alinhadas: não há canto para o chanfro';
    Exit;
  end;
  T1 := V2(V.X + U1.X * D1, V.Y + U1.Y * D1);
  T2 := V2(V.X + U2.X * D2, V.Y + U2.Y * D2);
  DropCoincident(FSketch, L1, P1, L2, P2);
  VirtualSharp(FSketch, V, L1, P1, L2, P2);
  MoveEnd(FSketch, L1, P1, T1);
  MoveEnd(FSketch, L2, P2, T2);
  Id := FSketch.AddLine(T1.X, T1.Y, T2.X, T2.Y);
  FSketch.AddConstraint(ckCoincident, Id, 1, L1, P1);
  FSketch.AddConstraint(ckCoincident, Id, 2, L2, P2);
  Solve;
  if LastSolve.Status = ssConflict then
    LastMessage := LastSolve.Message;
  Result := True;
end;

end.
