unit makepcb_drc;

{ Verificacao de regras (DRC) do MakePCB.

  - Folga entre cobres de redes diferentes: pad-pad, trilha-pad e
    trilha-trilha na mesma face. Pads sao poligonos reais (retangulo ou
    capsula), entao a distancia e geometrica, nao por caixas.
  - Curtos: cobre unindo pads que o esquema (fios) poe em redes diferentes.
  - Ligacoes ainda nao roteadas (MPPendingConnections).
  - Itens fora da placa (TMPDocument.ValidateBoard).
  - Trilhas mais finas que o minimo para isolacao a laser.

  Cada problema traz a posicao para a tela destacar. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, makepcb_model, makepcb_route;

type
  TMPDrcKind = (dkClearance, dkShort, dkUnrouted, dkBoard, dkWidth);

  TMPDrcIssue = record
    Kind: TMPDrcKind;
    X, Y: Double;
    Text: string;
  end;
  TMPDrcIssues = array of TMPDrcIssue;

function MPCheckDesign(Doc: TMPDocument; MinWidth: Double = 0.3): TMPDrcIssues;
{ contorno do pad em coordenadas da placa }
function MPPadOutline(C: TMPComponent; P: Integer): TMPPoints;

implementation

procedure AddIssue(var R: TMPDrcIssues; AKind: TMPDrcKind; AX, AY: Double; const AText: string);
var
  N: Integer;
begin
  N := Length(R);
  SetLength(R, N + 1);
  R[N].Kind := AKind;
  R[N].X := AX;
  R[N].Y := AY;
  R[N].Text := AText;
end;

function MPPadOutline(C: TMPComponent; P: Integer): TMPPoints;
var
  Pos: TMPPoint;
  W, H, R, HalfL, A0: Double;
  I, N: Integer;
begin
  Result := nil;
  Pos := C.PadPos(P);
  C.PadSize(P, W, H);
  if C.Footprint.Pads[P].Shape = psSquare then
  begin
    SetLength(Result, 4);
    Result[0] := MPPoint(Pos.X - W / 2, Pos.Y - H / 2);
    Result[1] := MPPoint(Pos.X + W / 2, Pos.Y - H / 2);
    Result[2] := MPPoint(Pos.X + W / 2, Pos.Y + H / 2);
    Result[3] := MPPoint(Pos.X - W / 2, Pos.Y + H / 2);
    Exit;
  end;
  R := Min(W, H) / 2;
  HalfL := (Max(W, H) - Min(W, H)) / 2;
  N := 12;
  SetLength(Result, 2 * (N + 1));
  if W >= H then A0 := -Pi / 2 else A0 := 0;
  for I := 0 to N do
  begin
    if W >= H then
      Result[I] := MPPoint(Pos.X + HalfL + R * Cos(A0 + Pi * I / N), Pos.Y + R * Sin(A0 + Pi * I / N))
    else
      Result[I] := MPPoint(Pos.X + R * Cos(A0 + Pi * I / N), Pos.Y + HalfL + R * Sin(A0 + Pi * I / N));
  end;
  for I := 0 to N do
  begin
    if W >= H then
      Result[N + 1 + I] := MPPoint(Pos.X - HalfL + R * Cos(A0 + Pi + Pi * I / N), Pos.Y + R * Sin(A0 + Pi + Pi * I / N))
    else
      Result[N + 1 + I] := MPPoint(Pos.X + R * Cos(A0 + Pi + Pi * I / N), Pos.Y - HalfL + R * Sin(A0 + Pi + Pi * I / N));
  end;
end;

{ distancia entre um segmento e um poligono fechado (0 se cruza ou esta dentro) }
function SegPolyDist(const A, B: TMPPoint; const Poly: TMPPoints): Double;
var
  K: Integer;
begin
  if MPPointInPolygon(A, Poly) or MPPointInPolygon(B, Poly) then Exit(0);
  Result := MaxDouble;
  for K := 0 to High(Poly) do
    Result := Min(Result, MPSegSegDist(A, B, Poly[K], Poly[(K + 1) mod Length(Poly)]));
end;

function PolyPolyDist(const P1, P2: TMPPoints): Double;
var
  K: Integer;
begin
  Result := MaxDouble;
  for K := 0 to High(P1) do
    Result := Min(Result, SegPolyDist(P1[K], P1[(K + 1) mod Length(P1)], P2));
end;

function MPCheckDesign(Doc: TMPDocument; MinWidth: Double): TMPDrcIssues;
var
  Outlines: array of array of TMPPoints;
  Nets: array of array of Integer;
  I, J, K, L, S, T, U, NetA, NetB: Integer;
  CA, CB: TMPComponent;
  PA, PB: TMPPoint;
  D, Clr: Double;
  Errors: TStringList;
  Cons: TMPConnections;
  TA, TB: TMPTrack;
  RA, RB: TMPRect;
  WireParent: array of Integer;
  Base: array of Integer;
  NetOwner, WireSize: array of Integer;
  NetPadName: array of string;
  NPads, Root: Integer;

  function WFind(X: Integer): Integer;
  begin
    while WireParent[X] <> X do
    begin
      WireParent[X] := WireParent[WireParent[X]];
      X := WireParent[X];
    end;
    Result := X;
  end;

  function Different(N1, N2: Integer): Boolean;
  begin
    { pads sem rede (-1) sao sempre "outra rede" }
    Result := (N1 < 0) or (N2 < 0) or (N1 <> N2);
  end;

  function PadName(C: TMPComponent; P: Integer): string;
  begin
    if C.Ref <> '' then Result := C.Ref + '.' + C.Footprint.Pads[P].Name
    else Result := C.Footprint.Name;
  end;

begin
  Result := nil;
  Clr := Doc.Clearance;
  Doc.ComputeNets;
  Errors := TStringList.Create;
  try
    Doc.ValidateBoard(Errors);
    for I := 0 to Errors.Count - 1 do AddIssue(Result, dkBoard, 0, 0, Errors[I]);
  finally
    Errors.Free;
  end;
  SetLength(Outlines, Doc.ComponentCount);
  SetLength(Nets, Doc.ComponentCount);
  for I := 0 to Doc.ComponentCount - 1 do
  begin
    SetLength(Outlines[I], Doc.Component(I).PadCount);
    SetLength(Nets[I], Doc.Component(I).PadCount);
    for J := 0 to Doc.Component(I).PadCount - 1 do
    begin
      Outlines[I][J] := MPPadOutline(Doc.Component(I), J);
      Nets[I][J] := Doc.PadNet(I, J);
    end;
  end;
  { curtos: grupos do esquema (so fios) contra redes de cobre }
  SetLength(Base, Doc.ComponentCount);
  NPads := 0;
  for I := 0 to Doc.ComponentCount - 1 do
  begin
    Base[I] := NPads;
    Inc(NPads, Doc.Component(I).PadCount);
  end;
  SetLength(WireParent, NPads);
  for I := 0 to NPads - 1 do WireParent[I] := I;
  for I := 0 to High(Doc.Wires) do
    with Doc.Wires[I] do
      if (A.Comp >= 0) and (A.Comp < Doc.ComponentCount) and (B.Comp >= 0) and
         (B.Comp < Doc.ComponentCount) then
        WireParent[WFind(Base[A.Comp] + A.Pad)] := WFind(Base[B.Comp] + B.Pad);
  SetLength(WireSize, NPads);
  for I := 0 to NPads - 1 do WireSize[I] := 0;
  for I := 0 to NPads - 1 do Inc(WireSize[WFind(I)]);
  SetLength(NetOwner, Doc.NetCount);
  SetLength(NetPadName, Doc.NetCount);
  for I := 0 to High(NetOwner) do NetOwner[I] := -1;
  for I := 0 to Doc.ComponentCount - 1 do
    for J := 0 to Doc.Component(I).PadCount - 1 do
    begin
      NetA := Nets[I][J];
      if NetA < 0 then Continue;
      { pad sem fio (trilha desenhada a mao, via) nao define rede do esquema }
      Root := WFind(Base[I] + J);
      if WireSize[Root] < 2 then Continue;
      if NetOwner[NetA] < 0 then
      begin
        NetOwner[NetA] := Root;
        NetPadName[NetA] := PadName(Doc.Component(I), J);
      end
      else if (NetOwner[NetA] <> Root) and (NetOwner[NetA] >= 0) then
      begin
        PA := Doc.Component(I).PadPos(J);
        AddIssue(Result, dkShort, PA.X, PA.Y,
          'Curto: ' + PadName(Doc.Component(I), J) + ' ligado a ' + NetPadName[NetA] +
          ' (redes diferentes no esquema)');
        NetOwner[NetA] := -2;   { um aviso por rede }
      end;
    end;
  { pad x pad }
  for I := 0 to Doc.ComponentCount - 1 do
  begin
    CA := Doc.Component(I);
    RA := CA.Bounds;
    for K := I to Doc.ComponentCount - 1 do
    begin
      CB := Doc.Component(K);
      RB := CB.Bounds;
      if (RA.MaxX + Clr < RB.MinX) or (RB.MaxX + Clr < RA.MinX) or
         (RA.MaxY + Clr < RB.MinY) or (RB.MaxY + Clr < RA.MinY) then Continue;
      for J := 0 to CA.PadCount - 1 do
        for L := 0 to CB.PadCount - 1 do
        begin
          if (K = I) and (L <= J) then Continue;
          if not Different(Nets[I][J], Nets[K][L]) then Continue;
          D := PolyPolyDist(Outlines[I][J], Outlines[K][L]);
          if D < Clr - 1e-6 then
          begin
            PA := CA.PadPos(J);
            PB := CB.PadPos(L);
            AddIssue(Result, dkClearance, (PA.X + PB.X) / 2, (PA.Y + PB.Y) / 2,
              Format('Folga %.2f mm entre %s e %s (minimo %.2f)', [D, PadName(CA, J), PadName(CB, L), Clr]));
          end;
        end;
    end;
  end;
  { trilha x pad e trilha x trilha }
  for T := 0 to Doc.TrackCount - 1 do
  begin
    TA := Doc.Track(T);
    NetA := Doc.TrackNet(T);
    if TA.Width < MinWidth - 1e-9 then
      AddIssue(Result, dkWidth, TA.Points[0].X, TA.Points[0].Y,
        Format('Trilha %d com %.2f mm (minimo %.2f)', [T + 1, TA.Width, MinWidth]));
    for S := 1 to High(TA.Points) do
    begin
      for I := 0 to Doc.ComponentCount - 1 do
        for J := 0 to Doc.Component(I).PadCount - 1 do
        begin
          if not Different(NetA, Nets[I][J]) then Continue;
          D := SegPolyDist(TA.Points[S - 1], TA.Points[S], Outlines[I][J]) - TA.Width / 2;
          if D < Clr - 1e-6 then
          begin
            PA := Doc.Component(I).PadPos(J);
            AddIssue(Result, dkClearance, PA.X, PA.Y,
              Format('Folga %.2f mm entre a trilha %d e %s', [Max(0, D), T + 1, PadName(Doc.Component(I), J)]));
          end;
        end;
      for U := T + 1 to Doc.TrackCount - 1 do
      begin
        TB := Doc.Track(U);
        if TB.Layer <> TA.Layer then Continue;
        NetB := Doc.TrackNet(U);
        if not Different(NetA, NetB) then Continue;
        for K := 1 to High(TB.Points) do
        begin
          D := MPSegSegDist(TA.Points[S - 1], TA.Points[S], TB.Points[K - 1], TB.Points[K]) -
            (TA.Width + TB.Width) / 2;
          if D < Clr - 1e-6 then
            AddIssue(Result, dkClearance, (TA.Points[S].X + TB.Points[K].X) / 2,
              (TA.Points[S].Y + TB.Points[K].Y) / 2,
              Format('Folga %.2f mm entre as trilhas %d e %d', [Max(0, D), T + 1, U + 1]));
        end;
      end;
    end;
  end;
  { ligacoes pendentes }
  Cons := MPPendingConnections(Doc);
  for I := 0 to High(Cons) do
  begin
    PA := Doc.PadPoint(Cons[I].A);
    PB := Doc.PadPoint(Cons[I].B);
    AddIssue(Result, dkUnrouted, (PA.X + PB.X) / 2, (PA.Y + PB.Y) / 2,
      'Nao roteada: ' + PadName(Doc.Component(Cons[I].A.Comp), Cons[I].A.Pad) + ' - ' +
      PadName(Doc.Component(Cons[I].B.Comp), Cons[I].B.Pad));
  end;
end;

end.
