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
    tkCenterline, tkPoint, tkDimension);

  { Ponto capturado: Ent > 0 e Pt > 0 = ponto de entidade; Ent = origem;
    Ent > 0 e Pt = 0 = sobre a curva/linha; Ent = 0 = livre. }
  TCadSnap = record
    P: TCadVec2;
    Ent, Pt: Integer;
  end;

  TCadPickItem = record
    Ent, Pt: Integer;   { Pt = 0: a entidade inteira }
  end;

  TCadAskValueEvent = function(Sender: TObject; const ACaption: string;
    var AText: string): Boolean of object;

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
    procedure SetTool(AValue: TCadSketchToolKind);
    procedure Bind(AEnt, APt: Integer; const S: TCadSnap);
    function CreateLine(const A, B: TCadSnap; AConstr, ACenter: Boolean): Integer;
    function Infer(const A: TCadSnap; var B: TCadSnap): TConstraintKind;
    function MakeDimension(const A: TCadPickItem; const B: TCadPickItem; HasB: Boolean): Integer;
  public
    PickTol: Double;           { mm (o editor converte de pixels) }
    Cursor: TCadSnap;
    CursorInfer: Integer;      { 0 nada, 1 horizontal, 2 vertical }
    Selection: array of TCadPickItem;
    LastSolve: TSketchSolveResult;
    LastMessage: string;
    constructor Create(ADoc: TCadDocument; ASketch: TCadSketch);
    property Sketch: TCadSketch read FSketch;
    property Tool: TCadSketchToolKind read FTool write SetTool;
    property OnAskValue: TCadAskValueEvent read FOnAskValue write FOnAskValue;
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
  end;

const
  CAD_TOOL_NAMES: array[TCadSketchToolKind] of string = ('Selecionar', 'Linha',
    'Retângulo de canto', 'Círculo', 'Arco de 3 pontos', 'Linha de centro',
    'Ponto', 'Cota inteligente');

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
  Best, D: Double;
  Q, BestQ: TCadVec2;
  BestEnt: Integer;
begin
  Result.P := P;
  Result.Ent := 0;
  Result.Pt := 0;
  Best := PickTol;
  { origem }
  D := Dist2(P, V2(0, 0));
  if D <= Best then
  begin
    Best := D;
    Result.P := V2(0, 0);
    Result.Ent := CAD_SKETCH_ORIGIN;
    Result.Pt := 1;
  end;
  { pontos das entidades }
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
      D := Dist2(P, Q);
      if D < Best then
      begin
        Best := D;
        Result.P := Q;
        Result.Ent := E.Id;
        Result.Pt := K;
      end;
    end;
  end;
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
    if D < Best then
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
begin
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
  if S.Pt > 0 then
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
  R: Double;
begin
  Result := False;
  LastMessage := '';
  MouseMove(P);
  S := Cursor;
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
    tkDimension:
      if Hit(P, Item) then
      begin
        if not FHasDimFirst then
        begin
          FDimFirst := Item;
          FHasDimFirst := True;
          ClearSelection;
          Insert(Item, Selection, 0);
          { circulo, arco ou linha sozinhos ja podem ser cotados no proximo
            clique fora; ponto espera o segundo item }
        end
        else
        begin
          Result := MakeDimension(FDimFirst, Item, True) <> 0;
          FHasDimFirst := False;
          ClearSelection;
        end;
      end
      else if FHasDimFirst then
      begin
        Result := MakeDimension(FDimFirst, PickItem(0, 0), False) <> 0;
        FHasDimFirst := False;
        ClearSelection;
      end;
  end;
  if Result then
    Solve;
end;

procedure TCadSketchSession.Cancel;
begin
  SetLength(FClicks, 0);
  FChainEnt := 0;
  FHasDimFirst := False;
  CursorInfer := 0;
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
  C: TSketchConstraint;
  IA, IB: Integer;
  EA, EB: TSketchEntity;
  PA, PB: TCadVec2;
  DX, DY, L: Double;

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
      if (APt = 0) and (E.Kind = seLine) then
        Q := V2((E.P1.X + E.P2.X) / 2, (E.P1.Y + E.P2.Y) / 2)
      else
        Q := E.P1;
    end;
  end;

begin
  Result := False;
  C := FSketch.Constraint(AIndex);
  if not IsDimensionKind(C.Kind) then
    Exit;
  IA := FSketch.EntityIndex(C.EntityA);
  case C.Kind of
    ckRadius, ckDiameter:
      begin
        if IA < 0 then
          Exit;
        EA := FSketch.Entity(IA);
        P := V2(EA.P1.X + EA.Radius * 0.75, EA.P1.Y + EA.Radius * 0.75);
        Exit(True);
      end;
    ckAngle:
      begin
        IB := FSketch.EntityIndex(C.EntityB);
        if (IA < 0) or (IB < 0) then
          Exit;
        EA := FSketch.Entity(IA);
        EB := FSketch.Entity(IB);
        P := V2((EA.P1.X + EA.P2.X + EB.P1.X + EB.P2.X) / 4,
          (EA.P1.Y + EA.P2.Y + EB.P1.Y + EB.P2.Y) / 4);
        Exit(True);
      end;
  end;
  if (C.EntityB = 0) and (IA >= 0) and (FSketch.Entity(IA).Kind = seLine) then
  begin
    EA := FSketch.Entity(IA);
    PA := EA.P1;
    PB := EA.P2;
  end
  else
  begin
    if not PtOf(C.EntityA, C.PointA, PA) or not PtOf(C.EntityB, C.PointB, PB) then
      Exit;
  end;
  DX := PB.X - PA.X;
  DY := PB.Y - PA.Y;
  L := Max(Sqrt(DX * DX + DY * DY), 1E-9);
  { texto um pouco ao lado da linha medida }
  P := V2((PA.X + PB.X) / 2 - DY / L * PickTol * 1.5, (PA.Y + PB.Y) / 2 + DX / L * PickTol * 1.5);
  Result := True;
end;

end.
