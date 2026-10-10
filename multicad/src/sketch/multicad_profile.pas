unit multicad_profile;

{ MultiCAD - perfis do esboco: lacos fechados e regioes com ilhas
  (ARCHITECTURE 3: "Perfis").

  - Usa so entidades que nao sao de construcao: linhas, arcos e circulos.
  - Extremidades a menos de PROFILE_TOL viram o mesmo no.
  - Erros como no SolidWorks: contorno aberto (no com uma entidade) e
    ramificacao (no com tres ou mais). Lacos que se cruzam ou se tocam
    tambem sao recusados.
  - Regiao = laco externo (anti-horario) menos os lacos que ficam
    diretamente dentro dele (ilhas, horario). Um laco dentro de uma ilha
    vira outra regiao.
  - Id da regiao: "region:<menor Id de entidade do laco externo>", estavel
    enquanto o laco existir (usado em "Contornos selecionados").
  - Cada segmento do poligono guarda a entidade de origem, para o nome da
    face lateral ("Extrude2/lat:7"). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multicad_types, multicad_sketch;

const
  PROFILE_TOL = 1E-4;   { mm, juncao de extremidades depois do solver }

type
  TCadLoopEdge = record
    Entity: Integer;    { Id da entidade }
    Reversed: Boolean;  { percorrida do fim para o inicio }
  end;

  TCadLoop = record
    Edges: array of TCadLoopEdge;
    Poly: array of TCadVec2;      { sem repetir o primeiro ponto }
    SegEntity: array of Integer;  { entidade do segmento Poly[i] -> Poly[i+1] }
    Area: Double;                 { com sinal: > 0 anti-horario }
    Depth: Integer;               { quantos lacos o contem }
    Parent: Integer;              { laco que o contem diretamente (-1) }
  end;

  TCadRegion = record
    Id: string;
    Outer: TCadLoop;
    Holes: array of TCadLoop;
    Area: Double;       { area liquida (externo - ilhas) }
  end;

  TCadProfileResult = record
    Ok: Boolean;
    Message: string;
    Loops: array of TCadLoop;
    Regions: array of TCadRegion;
    OpenPoints: array of TCadVec2;   { extremidades soltas }
    BranchPoints: array of TCadVec2; { nos com 3 ou mais entidades }
  end;

{ Acha os perfis. ChordTol = erro maximo de corda na discretizacao dos arcos. }
function CadSketchProfiles(S: TCadSketch; ChordTol: Double = 0.01): TCadProfileResult;
{ Um unico contorno aberto (para Recurso fino com perfil aberto): linhas e
  arcos encadeados com duas pontas soltas. Poly vai de uma ponta a outra;
  SegEntity[i] e a entidade do trecho Poly[i] -> Poly[i+1]. }
function CadSketchOpenChain(S: TCadSketch; out Chain: TCadLoop; out AError: string;
  ChordTol: Double = 0.01): Boolean;
function CadPolyArea(const P: array of TCadVec2): Double;
function CadPointInPoly(const P: TCadVec2; const Poly: array of TCadVec2): Boolean;
function CadFindRegion(const R: TCadProfileResult; const AId: string): Integer;

implementation

uses
  multicad_mesh;

type
  TNode = record
    P: TCadVec2;
    Edges: array of Integer;   { indices em Items }
  end;

  TItem = record
    EntIdx: Integer;
    N0, N1: Integer;           { nos inicial e final }
    Used: Boolean;
  end;

function CadPolyArea(const P: array of TCadVec2): Double;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(P) do
  begin
    J := (I + 1) mod Length(P);
    Result := Result + P[I].X * P[J].Y - P[J].X * P[I].Y;
  end;
  Result := Result / 2;
end;

function CadPointInPoly(const P: TCadVec2; const Poly: array of TCadVec2): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  J := High(Poly);
  for I := 0 to High(Poly) do
  begin
    if ((Poly[I].Y > P.Y) <> (Poly[J].Y > P.Y)) and
      (P.X < (Poly[J].X - Poly[I].X) * (P.Y - Poly[I].Y) / (Poly[J].Y - Poly[I].Y) + Poly[I].X) then
      Result := not Result;
    J := I;
  end;
end;

function CadFindRegion(const R: TCadProfileResult; const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(R.Regions) do
    if R.Regions[I].Id = AId then
      Exit(I);
  Result := -1;
end;

function Dist2(const A, B: TCadVec2): Double;
begin
  Result := Sqrt(Sqr(A.X - B.X) + Sqr(A.Y - B.Y));
end;

procedure AddPt(var L: TCadLoop; const P: TCadVec2; AEnt: Integer);
var
  N: Integer;
begin
  N := Length(L.Poly);
  if (N > 0) and (Dist2(L.Poly[N - 1], P) < 1E-9) then
    Exit;
  SetLength(L.Poly, N + 1);
  SetLength(L.SegEntity, N + 1);
  L.Poly[N] := P;
  L.SegEntity[N] := AEnt;
end;

{ Pontos do arco de A0 a A0+Sweep (anti-horario), sem o ultimo. }
procedure ArcPoints(var L: TCadLoop; const C: TCadVec2; R, A0, Sweep: Double;
  AEnt: Integer; Reverse: Boolean; ChordTol: Double);
var
  N, I: Integer;
  T: Double;
begin
  N := Max(2, Ceil(CadCircleSegments(R, ChordTol) * Abs(Sweep) / (2 * Pi)));
  for I := 0 to N - 1 do
  begin
    if Reverse then
      T := A0 + Sweep - Sweep * I / N
    else
      T := A0 + Sweep * I / N;
    AddPt(L, V2(C.X + R * Cos(T), C.Y + R * Sin(T)), AEnt);
  end;
end;

function SegIntersect(const A, B, C, D: TCadVec2): Boolean;
var
  D1, D2, D3, D4: Double;
  function Cross(const O, P, Q: TCadVec2): Double;
  begin
    Result := (P.X - O.X) * (Q.Y - O.Y) - (P.Y - O.Y) * (Q.X - O.X);
  end;
  function OnSeg(const P, Q, R: TCadVec2): Boolean;
  begin
    Result := (Min(P.X, Q.X) - 1E-9 <= R.X) and (R.X <= Max(P.X, Q.X) + 1E-9) and
      (Min(P.Y, Q.Y) - 1E-9 <= R.Y) and (R.Y <= Max(P.Y, Q.Y) + 1E-9);
  end;
begin
  D1 := Cross(C, D, A);
  D2 := Cross(C, D, B);
  D3 := Cross(A, B, C);
  D4 := Cross(A, B, D);
  if (((D1 > 1E-12) and (D2 < -1E-12)) or ((D1 < -1E-12) and (D2 > 1E-12))) and
    (((D3 > 1E-12) and (D4 < -1E-12)) or ((D3 < -1E-12) and (D4 > 1E-12))) then
    Exit(True);
  Result := ((Abs(D1) <= 1E-12) and OnSeg(C, D, A)) or ((Abs(D2) <= 1E-12) and OnSeg(C, D, B)) or
    ((Abs(D3) <= 1E-12) and OnSeg(A, B, C)) or ((Abs(D4) <= 1E-12) and OnSeg(A, B, D));
end;

procedure ReverseLoop(var L: TCadLoop);
var
  I, N: Integer;
  P: array of TCadVec2;
  S: array of Integer;
  E: array of TCadLoopEdge;
begin
  N := Length(L.Poly);
  SetLength(P, N);
  SetLength(S, N);
  { segmento i (Poly[i] -> Poly[i+1]) passa a ser o segmento N-2-i do reverso;
    o novo Poly[k] = antigo Poly[N-1-k]; o segmento k vai de antigo N-1-k para
    N-2-k, que era o segmento N-2-k (com o ultimo fechando em 0). }
  for I := 0 to N - 1 do
    P[I] := L.Poly[N - 1 - I];
  for I := 0 to N - 1 do
    S[I] := L.SegEntity[(2 * N - 2 - I) mod N];
  L.Poly := P;
  L.SegEntity := S;
  SetLength(E, Length(L.Edges));
  for I := 0 to High(L.Edges) do
  begin
    E[I] := L.Edges[High(L.Edges) - I];
    E[I].Reversed := not E[I].Reversed;
  end;
  L.Edges := E;
  L.Area := -L.Area;
end;


function CadSketchOpenChain(S: TCadSketch; out Chain: TCadLoop; out AError: string;
  ChordTol: Double): Boolean;
type
  TItem = record
    EI, N0, N1: Integer;
  end;
var
  Pts: array of TCadVec2;
  Deg: array of Integer;
  Items: array of TItem;
  Used: array of Boolean;
  I, K, Node, Start, Cur, Guard: Integer;
  E: TSketchEntity;
  A0, A1, Sweep: Double;
  Rev: Boolean;
  function NodeFor(const P: TCadVec2): Integer;
  var
    Q: Integer;
  begin
    for Q := 0 to High(Pts) do
      if Dist2(Pts[Q], P) <= PROFILE_TOL then
        Exit(Q);
    Result := Length(Pts);
    SetLength(Pts, Result + 1);
    SetLength(Deg, Result + 1);
    Pts[Result] := P;
    Deg[Result] := 0;
  end;
  procedure AddP(const P: TCadVec2; AEnt: Integer);
  var
    N: Integer;
  begin
    N := Length(Chain.Poly);
    if (N > 0) and (Dist2(Chain.Poly[N - 1], P) < 1E-9) then
      Exit;
    SetLength(Chain.Poly, N + 1);
    SetLength(Chain.SegEntity, N + 1);
    Chain.Poly[N] := P;
    Chain.SegEntity[N] := AEnt;
  end;
begin
  Result := False;
  AError := '';
  Chain := Default(TCadLoop);
  Pts := nil;
  Items := nil;
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    if E.Construction then
      Continue;
    if E.Kind = seCircle then
    begin
      AError := 'Contorno aberto não pode ter círculos';
      Exit;
    end;
    if not (E.Kind in [seLine, seArc]) then
      Continue;
    K := Length(Items);
    SetLength(Items, K + 1);
    Items[K].EI := I;
    if E.Kind = seLine then
    begin
      Items[K].N0 := NodeFor(E.P1);
      Items[K].N1 := NodeFor(E.P2);
    end
    else
    begin
      Items[K].N0 := NodeFor(E.P2);
      Items[K].N1 := NodeFor(E.P3);
    end;
    Inc(Deg[Items[K].N0]);
    Inc(Deg[Items[K].N1]);
  end;
  if Length(Items) = 0 then
  begin
    AError := 'O esboço não tem linhas ou arcos';
    Exit;
  end;
  Start := -1;
  K := 0;
  for I := 0 to High(Deg) do
  begin
    if Deg[I] > 2 then
    begin
      AError := 'O contorno aberto tem ramificação';
      Exit;
    end;
    if Deg[I] = 1 then
    begin
      Inc(K);
      if Start < 0 then
        Start := I;
    end;
  end;
  if K <> 2 then
  begin
    if K = 0 then
      AError := 'O contorno é fechado (use o perfil normal)'
    else
      AError := 'O esboço tem mais de um contorno aberto';
    Exit;
  end;
  SetLength(Used, Length(Items));
  Node := Start;
  Guard := 0;
  repeat
    Cur := -1;
    for I := 0 to High(Items) do
      if not Used[I] and ((Items[I].N0 = Node) or (Items[I].N1 = Node)) then
      begin
        Cur := I;
        Break;
      end;
    if Cur < 0 then
      Break;
    Used[Cur] := True;
    E := S.Entity(Items[Cur].EI);
    Rev := Items[Cur].N0 <> Node;
    case E.Kind of
      seLine:
        if Rev then AddP(E.P2, E.Id) else AddP(E.P1, E.Id);
      seArc:
        begin
          A0 := ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X);
          A1 := ArcTan2(E.P3.Y - E.P1.Y, E.P3.X - E.P1.X);
          Sweep := A1 - A0;
          while Sweep <= 1E-12 do
            Sweep := Sweep + 2 * Pi;
          ArcPoints(Chain, E.P1, E.Radius, A0, Sweep, E.Id, Rev, ChordTol);
        end;
    end;
    if Rev then Node := Items[Cur].N0 else Node := Items[Cur].N1;
    Inc(Guard);
  until Guard > Length(Items);
  for I := 0 to High(Used) do
    if not Used[I] then
    begin
      AError := 'O esboço tem mais de um contorno';
      Exit;
    end;
  { ultimo ponto (a outra ponta) }
  SetLength(Chain.Poly, Length(Chain.Poly) + 1);
  Chain.Poly[High(Chain.Poly)] := Pts[Node];
  SetLength(Chain.SegEntity, Length(Chain.Poly));
  Chain.SegEntity[High(Chain.SegEntity)] := -1;
  Result := Length(Chain.Poly) >= 2;
end;

function CadSketchProfiles(S: TCadSketch; ChordTol: Double): TCadProfileResult;
var
  Nodes: array of TNode;
  Items: array of TItem;
  I, J, K, NI, Cur, Node, Next, Start, Guard, Best, MinId: Integer;
  E: TSketchEntity;
  L: TCadLoop;
  A0, A1, Sweep: Double;
  Rev: Boolean;
  SA, SB, SC, SD: TCadVec2;
  NA, NB: Integer;

  function NodeFor(const P: TCadVec2): Integer;
  var
    Q: Integer;
  begin
    for Q := 0 to High(Nodes) do
      if Dist2(Nodes[Q].P, P) <= PROFILE_TOL then
        Exit(Q);
    Result := Length(Nodes);
    SetLength(Nodes, Result + 1);
    Nodes[Result].P := P;
    Nodes[Result].Edges := nil;
  end;

  procedure Link(ANode, AItem: Integer);
  begin
    SetLength(Nodes[ANode].Edges, Length(Nodes[ANode].Edges) + 1);
    Nodes[ANode].Edges[High(Nodes[ANode].Edges)] := AItem;
  end;

  procedure EmitEntity(EI: Integer; AReversed: Boolean);
  var
    En: TSketchEntity;
  begin
    En := S.Entity(EI);
    SetLength(L.Edges, Length(L.Edges) + 1);
    L.Edges[High(L.Edges)].Entity := En.Id;
    L.Edges[High(L.Edges)].Reversed := AReversed;
    case En.Kind of
      seLine:
        if AReversed then
          AddPt(L, En.P2, En.Id)
        else
          AddPt(L, En.P1, En.Id);
      seArc:
        begin
          A0 := ArcTan2(En.P2.Y - En.P1.Y, En.P2.X - En.P1.X);
          A1 := ArcTan2(En.P3.Y - En.P1.Y, En.P3.X - En.P1.X);
          Sweep := A1 - A0;
          while Sweep <= 1E-12 do
            Sweep := Sweep + 2 * Pi;
          ArcPoints(L, En.P1, En.Radius, A0, Sweep, En.Id, AReversed, ChordTol);
        end;
    end;
  end;

begin
  Result := Default(TCadProfileResult);
  Nodes := nil;
  Items := nil;
  { circulos: um laco cada }
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    if E.Construction or (E.Kind <> seCircle) then
      Continue;
    L := Default(TCadLoop);
    SetLength(L.Edges, 1);
    L.Edges[0].Entity := E.Id;
    L.Edges[0].Reversed := False;
    ArcPoints(L, E.P1, E.Radius, 0, 2 * Pi, E.Id, False, ChordTol);
    SetLength(Result.Loops, Length(Result.Loops) + 1);
    Result.Loops[High(Result.Loops)] := L;
  end;
  { grafo das linhas e arcos }
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    if E.Construction or not (E.Kind in [seLine, seArc]) then
      Continue;
    if E.Kind = seLine then
    begin
      NA := NodeFor(E.P1);
      NB := NodeFor(E.P2);
    end
    else
    begin
      NA := NodeFor(E.P2);
      NB := NodeFor(E.P3);
    end;
    if NA = NB then
      Continue;   { linha nula ou arco degenerado }
    K := Length(Items);
    SetLength(Items, K + 1);
    Items[K].EntIdx := I;
    Items[K].N0 := NA;
    Items[K].N1 := NB;
    Items[K].Used := False;
    Link(NA, K);
    Link(NB, K);
  end;
  for I := 0 to High(Nodes) do
    if Length(Nodes[I].Edges) = 1 then
    begin
      SetLength(Result.OpenPoints, Length(Result.OpenPoints) + 1);
      Result.OpenPoints[High(Result.OpenPoints)] := Nodes[I].P;
    end
    else if Length(Nodes[I].Edges) > 2 then
    begin
      SetLength(Result.BranchPoints, Length(Result.BranchPoints) + 1);
      Result.BranchPoints[High(Result.BranchPoints)] := Nodes[I].P;
    end;
  if Length(Result.OpenPoints) > 0 then
  begin
    Result.Message := Format('O esboço tem contornos abertos (%d extremidade(s) solta(s))',
      [Length(Result.OpenPoints)]);
    Exit;
  end;
  if Length(Result.BranchPoints) > 0 then
  begin
    Result.Message := Format('O esboço tem %d ponto(s) onde três ou mais entidades se encontram; ' +
      'use Contornos selecionados ou separe os contornos', [Length(Result.BranchPoints)]);
    Exit;
  end;
  { percorre os lacos }
  for I := 0 to High(Items) do
  begin
    if Items[I].Used then
      Continue;
    L := Default(TCadLoop);
    Cur := I;
    Start := Items[I].N0;
    Node := Start;
    Guard := 0;
    repeat
      Items[Cur].Used := True;
      Rev := Items[Cur].N0 <> Node;
      EmitEntity(Items[Cur].EntIdx, Rev);
      if Rev then
        Node := Items[Cur].N0
      else
        Node := Items[Cur].N1;
      if Node = Start then
        Break;
      Next := -1;
      for J := 0 to High(Nodes[Node].Edges) do
        if Nodes[Node].Edges[J] <> Cur then
          Next := Nodes[Node].Edges[J];
      Cur := Next;
      Inc(Guard);
    until (Cur < 0) or (Guard > Length(Items));
    if Length(L.Poly) < 3 then
      Continue;
    SetLength(Result.Loops, Length(Result.Loops) + 1);
    Result.Loops[High(Result.Loops)] := L;
  end;
  { area, cruzamentos }
  for I := 0 to High(Result.Loops) do
    Result.Loops[I].Area := CadPolyArea(Result.Loops[I].Poly);
  for I := 0 to High(Result.Loops) do
    for J := I to High(Result.Loops) do
      for NI := 0 to High(Result.Loops[I].Poly) do
      begin
        SA := Result.Loops[I].Poly[NI];
        SB := Result.Loops[I].Poly[(NI + 1) mod Length(Result.Loops[I].Poly)];
        for K := 0 to High(Result.Loops[J].Poly) do
        begin
          if I = J then
          begin
            { mesmo laco: ignora o proprio segmento e os vizinhos }
            if (K <= NI + 1) and (K >= NI - 1) then
              Continue;
            if ((NI = 0) and (K = High(Result.Loops[J].Poly))) or
              ((K = 0) and (NI = High(Result.Loops[I].Poly))) then
              Continue;
          end;
          SC := Result.Loops[J].Poly[K];
          SD := Result.Loops[J].Poly[(K + 1) mod Length(Result.Loops[J].Poly)];
          if (Max(SA.X, SB.X) < Min(SC.X, SD.X)) or (Max(SC.X, SD.X) < Min(SA.X, SB.X)) or
            (Max(SA.Y, SB.Y) < Min(SC.Y, SD.Y)) or (Max(SC.Y, SD.Y) < Min(SA.Y, SB.Y)) then
            Continue;
          if SegIntersect(SA, SB, SC, SD) then
          begin
            if I = J then
              Result.Message := 'O esboço tem um contorno que cruza a si mesmo'
            else
              Result.Message := 'O esboço tem contornos que se cruzam ou se tocam';
            Exit;
          end;
        end;
      end;
  { aninhamento }
  for I := 0 to High(Result.Loops) do
  begin
    Result.Loops[I].Depth := 0;
    Result.Loops[I].Parent := -1;
    Best := -1;
    for J := 0 to High(Result.Loops) do
      if (J <> I) and CadPointInPoly(Result.Loops[I].Poly[0], Result.Loops[J].Poly) then
      begin
        Inc(Result.Loops[I].Depth);
        if (Best < 0) or (Abs(Result.Loops[J].Area) < Abs(Result.Loops[Best].Area)) then
          Best := J;
      end;
    Result.Loops[I].Parent := Best;
  end;
  { orientacao: externos anti-horarios, ilhas horarias }
  for I := 0 to High(Result.Loops) do
    if ((Result.Loops[I].Depth mod 2 = 0) and (Result.Loops[I].Area < 0)) or
      ((Result.Loops[I].Depth mod 2 = 1) and (Result.Loops[I].Area > 0)) then
      ReverseLoop(Result.Loops[I]);
  { regioes }
  for I := 0 to High(Result.Loops) do
  begin
    if Result.Loops[I].Depth mod 2 <> 0 then
      Continue;
    K := Length(Result.Regions);
    SetLength(Result.Regions, K + 1);
    Result.Regions[K].Outer := Result.Loops[I];
    Result.Regions[K].Area := Result.Loops[I].Area;
    MinId := MaxInt;
    for J := 0 to High(Result.Loops[I].Edges) do
      MinId := Min(MinId, Result.Loops[I].Edges[J].Entity);
    Result.Regions[K].Id := 'region:' + IntToStr(MinId);
    for J := 0 to High(Result.Loops) do
      if Result.Loops[J].Parent = I then
      begin
        SetLength(Result.Regions[K].Holes, Length(Result.Regions[K].Holes) + 1);
        Result.Regions[K].Holes[High(Result.Regions[K].Holes)] := Result.Loops[J];
        Result.Regions[K].Area := Result.Regions[K].Area + Result.Loops[J].Area;
      end;
  end;
  Result.Ok := Length(Result.Regions) > 0;
  if not Result.Ok then
    Result.Message := 'O esboço não tem contornos fechados';
end;

end.
