unit makepcb_select;

{ Selecao de varios itens do MakePCB e area de transferencia.

  TMPSelection guarda pares (tipo, indice) de componentes, trilhas, textos
  e areas. As operacoes trabalham sobre o documento e mantem a selecao
  valida: mover, girar 90 graus em torno do centro (encaixado na grade),
  apagar (indices em ordem decrescente) e copiar/colar.

  O texto copiado e um JSON proprio ("makepcb-clip"): componentes com o
  nome do footprint, trilhas, textos, areas e as ligacoes entre os
  componentes copiados (indices locais). Colar cria referencias novas
  (R1 -> proxima livre) e devolve a selecao dos itens colados. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, makepcb_model;

type
  TMPItemKind = (ikComponent, ikTrack, ikText, ikArea);

  TMPItem = record
    Kind: TMPItemKind;
    Index: Integer;
  end;

  TMPSelection = class
  private
    FItems: array of TMPItem;
    function GetItem(I: Integer): TMPItem;
  public
    procedure Clear;
    function Count: Integer;
    function IndexOf(K: TMPItemKind; I: Integer): Integer;
    function Contains(K: TMPItemKind; I: Integer): Boolean;
    procedure Add(K: TMPItemKind; I: Integer);
    procedure Remove(K: TMPItemKind; I: Integer);
    procedure Toggle(K: TMPItemKind; I: Integer);
    procedure Assign(Src: TMPSelection);
    function CountOf(K: TMPItemKind): Integer;
    property Items[I: Integer]: TMPItem read GetItem; default;
  end;

  { o que esta inteiramente dentro do retangulo (coordenadas da placa) }
procedure MPSelectInRect(Doc: TMPDocument; const R: TMPRect; Sel: TMPSelection; AddTo: Boolean = False);
procedure MPSelectAll(Doc: TMPDocument; Sel: TMPSelection);
function MPSelectionBounds(Doc: TMPDocument; Sel: TMPSelection): TMPRect;
procedure MPMoveSelection(Doc: TMPDocument; Sel: TMPSelection; DX, DY: Double);
{ gira 90 graus (anti-horario) em torno do centro da selecao, na grade }
procedure MPRotateSelection(Doc: TMPDocument; Sel: TMPSelection; Grid: Double);
{ centro de giro (na grade; componente sozinho gira na propria origem) }
function MPRotationCenter(Doc: TMPDocument; Sel: TMPSelection; Grid: Double): TMPPoint;
{ giro em torno de um centro fixo: 4 giros voltam ao inicio }
procedure MPRotateSelectionAbout(Doc: TMPDocument; Sel: TMPSelection; CX, CY: Double);
procedure MPDeleteSelection(Doc: TMPDocument; Sel: TMPSelection);
function MPCopySelection(Doc: TMPDocument; Sel: TMPSelection): string;
function MPIsClip(const S: string): Boolean;
{ cola deslocado de (DX, DY); a selecao passa a ser os itens colados }
procedure MPPaste(Doc: TMPDocument; const Clip: string; DX, DY: Double;
  Resolver: TMPFootprintResolver; Sel: TMPSelection);

implementation

const
  CLIP_TAG = 'makepcb-clip';

var
  InvFS: TFormatSettings;

{ ---------------- TMPSelection ---------------- }

function TMPSelection.GetItem(I: Integer): TMPItem;
begin
  Result := FItems[I];
end;

procedure TMPSelection.Clear;
begin
  SetLength(FItems, 0);
end;

function TMPSelection.Count: Integer;
begin
  Result := Length(FItems);
end;

function TMPSelection.IndexOf(K: TMPItemKind; I: Integer): Integer;
var
  J: Integer;
begin
  for J := 0 to High(FItems) do
    if (FItems[J].Kind = K) and (FItems[J].Index = I) then Exit(J);
  Result := -1;
end;

function TMPSelection.Contains(K: TMPItemKind; I: Integer): Boolean;
begin
  Result := IndexOf(K, I) >= 0;
end;

procedure TMPSelection.Add(K: TMPItemKind; I: Integer);
var
  N: Integer;
begin
  if (I < 0) or Contains(K, I) then Exit;
  N := Length(FItems);
  SetLength(FItems, N + 1);
  FItems[N].Kind := K;
  FItems[N].Index := I;
end;

procedure TMPSelection.Remove(K: TMPItemKind; I: Integer);
var
  J: Integer;
begin
  J := IndexOf(K, I);
  if J < 0 then Exit;
  FItems[J] := FItems[High(FItems)];
  SetLength(FItems, Length(FItems) - 1);
end;

procedure TMPSelection.Toggle(K: TMPItemKind; I: Integer);
begin
  if Contains(K, I) then Remove(K, I) else Add(K, I);
end;

procedure TMPSelection.Assign(Src: TMPSelection);
begin
  FItems := Copy(Src.FItems);
end;

function TMPSelection.CountOf(K: TMPItemKind): Integer;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to High(FItems) do
    if FItems[J].Kind = K then Inc(Result);
end;

{ ---------------- geometria ---------------- }

function PointsInside(const P: TMPPoints; const R: TMPRect): Boolean;
var
  I: Integer;
begin
  Result := Length(P) > 0;
  for I := 0 to High(P) do
    if (P[I].X < R.MinX) or (P[I].X > R.MaxX) or (P[I].Y < R.MinY) or (P[I].Y > R.MaxY) then
      Exit(False);
end;

procedure IncludePoints(var B: TMPRect; const P: TMPPoints);
var
  I: Integer;
begin
  for I := 0 to High(P) do MPRectInclude(B, P[I].X, P[I].Y);
end;

procedure MPSelectInRect(Doc: TMPDocument; const R: TMPRect; Sel: TMPSelection; AddTo: Boolean);
var
  I: Integer;
  B: TMPRect;
  T: TMPText;
begin
  if not AddTo then Sel.Clear;
  for I := 0 to Doc.ComponentCount - 1 do
  begin
    B := Doc.Component(I).Bounds;
    if (B.MinX >= R.MinX) and (B.MaxX <= R.MaxX) and (B.MinY >= R.MinY) and (B.MaxY <= R.MaxY) then
      Sel.Add(ikComponent, I);
  end;
  for I := 0 to Doc.TrackCount - 1 do
    if PointsInside(Doc.Track(I).Points, R) then Sel.Add(ikTrack, I);
  for I := 0 to Doc.TextCount - 1 do
  begin
    T := Doc.Text(I);
    if (T.X >= R.MinX) and (T.X <= R.MaxX) and (T.Y >= R.MinY) and (T.Y + T.Height <= R.MaxY) then
      Sel.Add(ikText, I);
  end;
  for I := 0 to Doc.AreaCount - 1 do
    if PointsInside(Doc.Area(I).Points, R) then Sel.Add(ikArea, I);
end;

procedure MPSelectAll(Doc: TMPDocument; Sel: TMPSelection);
var
  I: Integer;
begin
  Sel.Clear;
  for I := 0 to Doc.ComponentCount - 1 do Sel.Add(ikComponent, I);
  for I := 0 to Doc.TrackCount - 1 do Sel.Add(ikTrack, I);
  for I := 0 to Doc.TextCount - 1 do Sel.Add(ikText, I);
  for I := 0 to Doc.AreaCount - 1 do Sel.Add(ikArea, I);
end;

function MPSelectionBounds(Doc: TMPDocument; Sel: TMPSelection): TMPRect;
var
  I: Integer;
  B: TMPRect;
  It: TMPItem;
  T: TMPText;
begin
  Result := MPEmptyRect;
  for I := 0 to Sel.Count - 1 do
  begin
    It := Sel[I];
    case It.Kind of
      ikComponent:
        begin
          B := Doc.Component(It.Index).Bounds;
          if B.Valid then
          begin
            MPRectInclude(Result, B.MinX, B.MinY);
            MPRectInclude(Result, B.MaxX, B.MaxY);
          end;
        end;
      ikTrack: IncludePoints(Result, Doc.Track(It.Index).Points);
      ikArea: IncludePoints(Result, Doc.Area(It.Index).Points);
      ikText:
        begin
          T := Doc.Text(It.Index);
          MPRectInclude(Result, T.X, T.Y);
          MPRectInclude(Result, T.X, T.Y + T.Height);
        end;
    end;
  end;
end;

procedure MovePoints(var P: TMPPoints; DX, DY: Double);
var
  I: Integer;
begin
  for I := 0 to High(P) do
  begin
    P[I].X := P[I].X + DX;
    P[I].Y := P[I].Y + DY;
  end;
end;

procedure MPMoveSelection(Doc: TMPDocument; Sel: TMPSelection; DX, DY: Double);
var
  I: Integer;
  It: TMPItem;
begin
  for I := 0 to Sel.Count - 1 do
  begin
    It := Sel[I];
    case It.Kind of
      ikComponent:
        with Doc.Component(It.Index) do begin X := X + DX; Y := Y + DY; end;
      ikTrack: MovePoints(Doc.Track(It.Index).Points, DX, DY);
      ikArea: MovePoints(Doc.Area(It.Index).Points, DX, DY);
      ikText:
        with Doc.Text(It.Index) do begin X := X + DX; Y := Y + DY; end;
    end;
  end;
  Doc.Changed;
end;

{ (X,Y) -> (CX - (Y - CY), CY + (X - CX)) }
procedure Rot90(var X, Y: Double; CX, CY: Double);
var
  NX: Double;
begin
  NX := CX - (Y - CY);
  Y := CY + (X - CX);
  X := NX;
end;

procedure RotPoints(var P: TMPPoints; CX, CY: Double);
var
  I: Integer;
begin
  for I := 0 to High(P) do Rot90(P[I].X, P[I].Y, CX, CY);
end;

function MPRotationCenter(Doc: TMPDocument; Sel: TMPSelection; Grid: Double): TMPPoint;
var
  B: TMPRect;
  C: TMPComponent;
begin
  Result := MPPoint(0, 0);
  if Sel.Count = 0 then Exit;
  if (Sel.Count = 1) and (Sel[0].Kind = ikComponent) then
  begin
    C := Doc.Component(Sel[0].Index);
    Exit(MPPoint(C.X, C.Y));
  end;
  B := MPSelectionBounds(Doc, Sel);
  if not B.Valid then Exit;
  if Grid <= 0 then Grid := MP_GRID;
  Result.X := Round((B.MinX + B.MaxX) / 2 / Grid) * Grid;
  Result.Y := Round((B.MinY + B.MaxY) / 2 / Grid) * Grid;
end;

procedure MPRotateSelection(Doc: TMPDocument; Sel: TMPSelection; Grid: Double);
var
  P: TMPPoint;
begin
  if Sel.Count = 0 then Exit;
  P := MPRotationCenter(Doc, Sel, Grid);
  MPRotateSelectionAbout(Doc, Sel, P.X, P.Y);
end;

procedure MPRotateSelectionAbout(Doc: TMPDocument; Sel: TMPSelection; CX, CY: Double);
var
  I: Integer;
  It: TMPItem;
  C: TMPComponent;
  T: TMPText;
begin
  for I := 0 to Sel.Count - 1 do
  begin
    It := Sel[I];
    case It.Kind of
      ikComponent:
        begin
          C := Doc.Component(It.Index);
          Rot90(C.X, C.Y, CX, CY);
          C.Rotation := (C.Rotation + 90) mod 360;
        end;
      ikTrack: RotPoints(Doc.Track(It.Index).Points, CX, CY);
      ikArea: RotPoints(Doc.Area(It.Index).Points, CX, CY);
      ikText:
        begin
          { texto nao gira (fonte horizontal): so muda de lugar }
          T := Doc.Text(It.Index);
          Rot90(T.X, T.Y, CX, CY);
        end;
    end;
  end;
  Doc.Changed;
end;

procedure MPDeleteSelection(Doc: TMPDocument; Sel: TMPSelection);
var
  K: TMPItemKind;
  Idx: array of Integer;
  I, J, T: Integer;
begin
  for K := High(TMPItemKind) downto Low(TMPItemKind) do
  begin
    SetLength(Idx, 0);
    for I := 0 to Sel.Count - 1 do
      if Sel[I].Kind = K then
      begin
        SetLength(Idx, Length(Idx) + 1);
        Idx[High(Idx)] := Sel[I].Index;
      end;
    { ordem decrescente para os indices continuarem validos }
    for I := 0 to High(Idx) do
      for J := I + 1 to High(Idx) do
        if Idx[J] > Idx[I] then begin T := Idx[I]; Idx[I] := Idx[J]; Idx[J] := T; end;
    for I := 0 to High(Idx) do
      case K of
        ikComponent: Doc.DeleteComponent(Idx[I]);
        ikTrack: Doc.DeleteTrack(Idx[I]);
        ikText: Doc.DeleteText(Idx[I]);
        ikArea: Doc.DeleteArea(Idx[I]);
      end;
  end;
  Sel.Clear;
  Doc.Changed;
end;

{ ---------------- area de transferencia ---------------- }

function PointsJSON(const P: TMPPoints): TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := 0 to High(P) do
    Result.Add(TJSONArray.Create([P[I].X, P[I].Y]));
end;

function PointsFrom(A: TJSONArray; DX, DY: Double): TMPPoints;
var
  I: Integer;
begin
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
  begin
    Result[I].X := TJSONArray(A[I]).Floats[0] + DX;
    Result[I].Y := TJSONArray(A[I]).Floats[1] + DY;
  end;
end;

function MPCopySelection(Doc: TMPDocument; Sel: TMPSelection): string;
var
  Root, O: TJSONObject;
  Comps, Tracks, Texts, Areas, Wires: TJSONArray;
  LocalOf: array of Integer;
  I, N: Integer;
  C: TMPComponent;
  W: TMPWire;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('type', CLIP_TAG);
    Comps := TJSONArray.Create; Root.Add('components', Comps);
    Tracks := TJSONArray.Create; Root.Add('tracks', Tracks);
    Texts := TJSONArray.Create; Root.Add('texts', Texts);
    Areas := TJSONArray.Create; Root.Add('areas', Areas);
    Wires := TJSONArray.Create; Root.Add('wires', Wires);
    SetLength(LocalOf, Doc.ComponentCount);
    for I := 0 to High(LocalOf) do LocalOf[I] := -1;
    N := 0;
    for I := 0 to Doc.ComponentCount - 1 do
      if Sel.Contains(ikComponent, I) then
      begin
        C := Doc.Component(I);
        O := TJSONObject.Create;
        O.Add('fp', C.Footprint.Name);
        O.Add('ref', C.Ref);
        O.Add('value', C.Value);
        O.Add('x', C.X); O.Add('y', C.Y);
        O.Add('rot', C.Rotation);
        Comps.Add(O);
        LocalOf[I] := N; Inc(N);
      end;
    for I := 0 to Doc.TrackCount - 1 do
      if Sel.Contains(ikTrack, I) then
      begin
        O := TJSONObject.Create;
        O.Add('layer', Ord(Doc.Track(I).Layer));
        O.Add('width', Doc.Track(I).Width);
        O.Add('points', PointsJSON(Doc.Track(I).Points));
        Tracks.Add(O);
      end;
    for I := 0 to Doc.TextCount - 1 do
      if Sel.Contains(ikText, I) then
      begin
        O := TJSONObject.Create;
        O.Add('text', Doc.Text(I).Text);
        O.Add('layer', Ord(Doc.Text(I).Layer));
        O.Add('x', Doc.Text(I).X); O.Add('y', Doc.Text(I).Y);
        O.Add('height', Doc.Text(I).Height);
        Texts.Add(O);
      end;
    for I := 0 to Doc.AreaCount - 1 do
      if Sel.Contains(ikArea, I) then
      begin
        O := TJSONObject.Create;
        O.Add('layer', Ord(Doc.Area(I).Layer));
        O.Add('clearance', Doc.Area(I).Clearance);
        O.Add('points', PointsJSON(Doc.Area(I).Points));
        if (Doc.Area(I).NetComp >= 0) and (Doc.Area(I).NetComp <= High(LocalOf)) then
          O.Add('net_comp', LocalOf[Doc.Area(I).NetComp])
        else
          O.Add('net_comp', -1);
        O.Add('net_pad', Doc.Area(I).NetPad);
        Areas.Add(O);
      end;
    for I := 0 to Doc.WireCount - 1 do
    begin
      W := Doc.Wires[I];
      if (LocalOf[W.A.Comp] >= 0) and (LocalOf[W.B.Comp] >= 0) then
        Wires.Add(TJSONArray.Create([LocalOf[W.A.Comp], W.A.Pad, LocalOf[W.B.Comp], W.B.Pad]));
    end;
    Result := Root.AsJSON;
  finally
    Root.Free;
  end;
end;

function MPIsClip(const S: string): Boolean;
begin
  Result := Pos('"' + CLIP_TAG + '"', S) > 0;
end;

function LayerFrom(V: Integer): TMPLayer;
begin
  if (V < Ord(Low(TMPLayer))) or (V > Ord(High(TMPLayer))) then Result := mlBottomCopper
  else Result := TMPLayer(V);
end;

procedure MPPaste(Doc: TMPDocument; const Clip: string; DX, DY: Double;
  Resolver: TMPFootprintResolver; Sel: TMPSelection);
var
  Data: TJSONData;
  Root, O: TJSONObject;
  A: TJSONArray;
  I, Base, NC: Integer;
  FP: TMPFootprint;
  C: TMPComponent;
  T: TMPTrack;
  Tx: TMPText;
  Ar: TMPArea;
  NewIdx: array of Integer;
  W: TJSONArray;
  Ref: string;
begin
  Sel.Clear;
  if not MPIsClip(Clip) then Exit;
  Data := GetJSON(Clip);
  try
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    A := Root.Arrays['components'];
    SetLength(NewIdx, A.Count);
    for I := 0 to A.Count - 1 do
    begin
      O := A.Objects[I];
      NewIdx[I] := -1;
      FP := Resolver(O.Strings['fp']);
      if FP = nil then Continue;
      C := Doc.AddComponent(FP, O.Floats['x'] + DX, O.Floats['y'] + DY);
      C.Rotation := O.Integers['rot'];
      C.Value := O.Strings['value'];
      Ref := O.Strings['ref'];
      { referencia nova so se ja existir }
      if (Ref <> '') and (Doc.FindComponent(Ref) = nil) then C.Ref := Ref;
      NewIdx[I] := Doc.IndexOfComponent(C);
      Sel.Add(ikComponent, NewIdx[I]);
    end;
    A := Root.Arrays['tracks'];
    for I := 0 to A.Count - 1 do
    begin
      O := A.Objects[I];
      T := Doc.AddTrack(LayerFrom(O.Integers['layer']), O.Floats['width']);
      T.Points := PointsFrom(O.Arrays['points'], DX, DY);
      Sel.Add(ikTrack, Doc.TrackCount - 1);
    end;
    A := Root.Arrays['texts'];
    for I := 0 to A.Count - 1 do
    begin
      O := A.Objects[I];
      Tx := Doc.AddText(O.Strings['text'], O.Floats['x'] + DX, O.Floats['y'] + DY,
        O.Floats['height'], LayerFrom(O.Integers['layer']));
      if Tx <> nil then Sel.Add(ikText, Doc.TextCount - 1);
    end;
    A := Root.Arrays['areas'];
    for I := 0 to A.Count - 1 do
    begin
      O := A.Objects[I];
      Ar := Doc.AddArea(LayerFrom(O.Integers['layer']));
      Ar.Clearance := O.Floats['clearance'];
      Ar.Points := PointsFrom(O.Arrays['points'], DX, DY);
      NC := O.Integers['net_comp'];
      if (NC >= 0) and (NC <= High(NewIdx)) and (NewIdx[NC] >= 0) then
      begin
        Ar.NetComp := NewIdx[NC];
        Ar.NetPad := O.Integers['net_pad'];
      end;
      Sel.Add(ikArea, Doc.AreaCount - 1);
    end;
    A := Root.Arrays['wires'];
    for I := 0 to A.Count - 1 do
    begin
      W := A.Arrays[I];
      Base := W.Integers[0];
      NC := W.Integers[2];
      if (Base <= High(NewIdx)) and (NC <= High(NewIdx)) and (NewIdx[Base] >= 0) and (NewIdx[NC] >= 0) then
        Doc.AddWire(NewIdx[Base], W.Integers[1], NewIdx[NC], W.Integers[3]);
    end;
  finally
    Data.Free;
  end;
  Doc.Changed;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
