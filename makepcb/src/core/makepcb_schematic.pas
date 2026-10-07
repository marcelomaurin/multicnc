unit makepcb_schematic;

{ Esquematico do MakePCB (como o "circuit diagram" do PCB Wizard 3).

  - TMPSymbol: simbolo da biblioteca (tracos, pinos, prefixo, footprint
    padrao e o mapa pino -> pad do footprint).
  - TMPPart: simbolo colocado (referencia, valor, footprint, posicao,
    rotacao em passos de 90 graus).
  - TMPSchWire: fio (polilinha). Liga pinos cujas pontas tocam o fio,
    inclusive no meio de um segmento (juncao em T).
  - TMPSchLabel: rotulo de rede; rotulos com o mesmo nome sao a mesma rede.
    GND e VCC sao rotulos desenhados como simbolos de alimentacao.
  - MPSchNets: lista de redes (pinos de partes ligados).
  - MPConvertToPCB: cria ou atualiza na placa um componente por parte
    (mesma referencia; posicao mantida) e refaz as ligacoes da placa a
    partir das redes do esquema.

  Coordenadas em mm, Y para cima, grade de 2,54 mm. O esquema e guardado
  dentro do .mpcb (TMPDocument.SchematicJSON). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, makepcb_model, makepcb_library;

const
  MP_SCH_GRID = 2.54;

type
  TMPSymPin = record
    Name: string;
    X, Y: Double;         { ponta do pino (onde o fio liga) }
    Pad: Integer;         { indice do pad no footprint }
  end;

  TMPSymKind = (symPart, symGround, symPower, symLabel);

  TMPSymbol = class
  public
    Name, Category, RefPrefix, DefaultValue, DefaultFootprint: string;
    Kind: TMPSymKind;
    Pins: array of TMPSymPin;
    Lines: TMPPoints;      { pares de pontos: segmentos }
    Circles: array of TMPPoint;
    Radii: array of Double;
    Texts: TStringList;    { "x;y;h;texto" }
    constructor Create;
    destructor Destroy; override;
    procedure Line(X1, Y1, X2, Y2: Double);
    procedure Box(X1, Y1, X2, Y2: Double);
    procedure Circle(X, Y, R: Double);
    procedure Pin(const AName: string; X, Y: Double; APad: Integer);
    procedure Text(X, Y, H: Double; const S: string);
    function Bounds: TMPRect;
  end;

  TMPPart = class
  public
    Symbol: TMPSymbol;
    Ref, Value, Footprint: string;
    X, Y: Double;
    Rotation: Integer;
    function LocalToWorld(LX, LY: Double): TMPPoint;
    function PinPos(I: Integer): TMPPoint;
    function Bounds: TMPRect;
  end;

  TMPSchWire = class
  public
    Points: TMPPoints;
  end;

  TMPSchLabel = class
  public
    Name: string;
    X, Y: Double;
    Kind: TMPSymKind;     { symGround, symPower ou symLabel }
  end;

  TMPSchPin = record
    Part, Pin: Integer;
  end;
  TMPSchNet = record
    Name: string;
    Pins: array of TMPSchPin;
  end;
  TMPSchNets = array of TMPSchNet;

  TMPSchematic = class
  private
    FParts, FWires, FLabels: TList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function PartCount: Integer;
    function Part(I: Integer): TMPPart;
    function AddPart(S: TMPSymbol; AX, AY: Double): TMPPart;
    procedure DeletePart(I: Integer);
    function FindPart(const ARef: string): TMPPart;
    function NextRef(const Prefix: string): string;
    function WireCount: Integer;
    function Wire(I: Integer): TMPSchWire;
    function AddWire(const P: TMPPoints): TMPSchWire;
    procedure DeleteWire(I: Integer);
    function LabelCount: Integer;
    function Label_(I: Integer): TMPSchLabel;
    function AddLabel(const AName: string; AX, AY: Double; AKind: TMPSymKind): TMPSchLabel;
    procedure DeleteLabel(I: Integer);
    function IsEmpty: Boolean;
    function Bounds: TMPRect;
    function ToJSON: string;
    procedure FromJSON(const S: string);
  end;

  TMPSymbolLibrary = class
  private
    FItems: TList;
    FCategories: TStringList;
    function Add(const AName, ACategory, APrefix, AValue, AFootprint: string): TMPSymbol;
    procedure Build;
    procedure TwoPin(S: TMPSymbol);
    procedure DILBox(Pins: Integer; const AName, AValue: string; const PinNames: array of string);
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    function Item(I: Integer): TMPSymbol;
    function Find(const AName: string): TMPSymbol;
    property Categories: TStringList read FCategories;
  end;

function MPSymbols: TMPSymbolLibrary;
{ redes do esquema (so pinos de partes; rotulos e fios juntam) }
function MPSchNets(Sch: TMPSchematic): TMPSchNets;
{ pinos soltos (sem fio): avisos }
function MPSchUnconnected(Sch: TMPSchematic): Integer;
{ cria/atualiza componentes e ligacoes na placa; devolve um resumo }
function MPConvertToPCB(Sch: TMPSchematic; Doc: TMPDocument; Lib: TMPLibrary; Report: TStrings): Boolean;
{ exemplo: 555 astavel desenhado no esquema }
procedure MPAstableSchematic(Sch: TMPSchematic);

implementation

var
  GSymbols: TMPSymbolLibrary = nil;

function MPSymbols: TMPSymbolLibrary;
begin
  if GSymbols = nil then GSymbols := TMPSymbolLibrary.Create;
  Result := GSymbols;
end;

{ ---------------- TMPSymbol ---------------- }

constructor TMPSymbol.Create;
begin
  inherited Create;
  Texts := TStringList.Create;
end;

destructor TMPSymbol.Destroy;
begin
  Texts.Free;
  inherited Destroy;
end;

procedure TMPSymbol.Line(X1, Y1, X2, Y2: Double);
var
  N: Integer;
begin
  N := Length(Lines);
  SetLength(Lines, N + 2);
  Lines[N] := MPPoint(X1, Y1);
  Lines[N + 1] := MPPoint(X2, Y2);
end;

procedure TMPSymbol.Box(X1, Y1, X2, Y2: Double);
begin
  Line(X1, Y1, X2, Y1); Line(X2, Y1, X2, Y2);
  Line(X2, Y2, X1, Y2); Line(X1, Y2, X1, Y1);
end;

procedure TMPSymbol.Circle(X, Y, R: Double);
begin
  SetLength(Circles, Length(Circles) + 1);
  Circles[High(Circles)] := MPPoint(X, Y);
  SetLength(Radii, Length(Radii) + 1);
  Radii[High(Radii)] := R;
end;

procedure TMPSymbol.Pin(const AName: string; X, Y: Double; APad: Integer);
var
  N: Integer;
begin
  N := Length(Pins);
  SetLength(Pins, N + 1);
  Pins[N].Name := AName;
  Pins[N].X := X; Pins[N].Y := Y;
  Pins[N].Pad := APad;
end;

procedure TMPSymbol.Text(X, Y, H: Double; const S: string);
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Texts.Add(FloatToStr(X, FS) + ';' + FloatToStr(Y, FS) + ';' + FloatToStr(H, FS) + ';' + S);
end;

function TMPSymbol.Bounds: TMPRect;
var
  I: Integer;
begin
  Result := MPEmptyRect;
  for I := 0 to High(Lines) do MPRectInclude(Result, Lines[I].X, Lines[I].Y);
  for I := 0 to High(Circles) do
  begin
    MPRectInclude(Result, Circles[I].X - Radii[I], Circles[I].Y - Radii[I]);
    MPRectInclude(Result, Circles[I].X + Radii[I], Circles[I].Y + Radii[I]);
  end;
  for I := 0 to High(Pins) do MPRectInclude(Result, Pins[I].X, Pins[I].Y);
end;

{ ---------------- TMPPart ---------------- }

function TMPPart.LocalToWorld(LX, LY: Double): TMPPoint;
begin
  case ((Rotation mod 360) + 360) mod 360 of
    90: Result := MPPoint(X - LY, Y + LX);
    180: Result := MPPoint(X - LX, Y - LY);
    270: Result := MPPoint(X + LY, Y - LX);
  else Result := MPPoint(X + LX, Y + LY);
  end;
end;

function TMPPart.PinPos(I: Integer): TMPPoint;
begin
  Result := LocalToWorld(Symbol.Pins[I].X, Symbol.Pins[I].Y);
end;

function TMPPart.Bounds: TMPRect;
var
  B: TMPRect;
  P: TMPPoint;
begin
  B := Symbol.Bounds;
  Result := MPEmptyRect;
  if not B.Valid then begin MPRectInclude(Result, X, Y); Exit; end;
  P := LocalToWorld(B.MinX, B.MinY); MPRectInclude(Result, P.X, P.Y);
  P := LocalToWorld(B.MaxX, B.MaxY); MPRectInclude(Result, P.X, P.Y);
end;

{ ---------------- TMPSchematic ---------------- }

constructor TMPSchematic.Create;
begin
  inherited Create;
  FParts := TList.Create;
  FWires := TList.Create;
  FLabels := TList.Create;
end;

destructor TMPSchematic.Destroy;
begin
  Clear;
  FParts.Free; FWires.Free; FLabels.Free;
  inherited Destroy;
end;

procedure FreeAll(L: TList);
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do TObject(L[I]).Free;
  L.Clear;
end;

procedure TMPSchematic.Clear;
begin
  FreeAll(FParts); FreeAll(FWires); FreeAll(FLabels);
end;

function TMPSchematic.PartCount: Integer; begin Result := FParts.Count; end;
function TMPSchematic.Part(I: Integer): TMPPart; begin Result := TMPPart(FParts[I]); end;
function TMPSchematic.WireCount: Integer; begin Result := FWires.Count; end;
function TMPSchematic.Wire(I: Integer): TMPSchWire; begin Result := TMPSchWire(FWires[I]); end;
function TMPSchematic.LabelCount: Integer; begin Result := FLabels.Count; end;
function TMPSchematic.Label_(I: Integer): TMPSchLabel; begin Result := TMPSchLabel(FLabels[I]); end;

function TMPSchematic.NextRef(const Prefix: string): string;
var
  I, N, Best: Integer;
  R: string;
begin
  Best := 0;
  if Prefix = '' then Exit('');
  for I := 0 to PartCount - 1 do
  begin
    R := Part(I).Ref;
    if (Pos(Prefix, R) = 1) and TryStrToInt(Copy(R, Length(Prefix) + 1, 10), N) then
      Best := Max(Best, N);
  end;
  Result := Prefix + IntToStr(Best + 1);
end;

function TMPSchematic.AddPart(S: TMPSymbol; AX, AY: Double): TMPPart;
begin
  if S = nil then raise Exception.Create('Simbolo inexistente');
  Result := TMPPart.Create;
  Result.Symbol := S;
  Result.X := AX; Result.Y := AY;
  Result.Ref := NextRef(S.RefPrefix);
  Result.Value := S.DefaultValue;
  Result.Footprint := S.DefaultFootprint;
  FParts.Add(Result);
end;

procedure TMPSchematic.DeletePart(I: Integer);
begin
  Part(I).Free;
  FParts.Delete(I);
end;

function TMPSchematic.FindPart(const ARef: string): TMPPart;
var
  I: Integer;
begin
  for I := 0 to PartCount - 1 do
    if SameText(Part(I).Ref, ARef) then Exit(Part(I));
  Result := nil;
end;

function TMPSchematic.AddWire(const P: TMPPoints): TMPSchWire;
begin
  Result := TMPSchWire.Create;
  Result.Points := Copy(P);
  FWires.Add(Result);
end;

procedure TMPSchematic.DeleteWire(I: Integer);
begin
  Wire(I).Free;
  FWires.Delete(I);
end;

function TMPSchematic.AddLabel(const AName: string; AX, AY: Double; AKind: TMPSymKind): TMPSchLabel;
begin
  Result := TMPSchLabel.Create;
  Result.Name := UpperCase(Trim(AName));
  Result.X := AX; Result.Y := AY;
  Result.Kind := AKind;
  FLabels.Add(Result);
end;

procedure TMPSchematic.DeleteLabel(I: Integer);
begin
  Label_(I).Free;
  FLabels.Delete(I);
end;

function TMPSchematic.IsEmpty: Boolean;
begin
  Result := (PartCount = 0) and (WireCount = 0) and (LabelCount = 0);
end;

function TMPSchematic.Bounds: TMPRect;
var
  I, J: Integer;
  B: TMPRect;
begin
  Result := MPEmptyRect;
  for I := 0 to PartCount - 1 do
  begin
    B := Part(I).Bounds;
    if B.Valid then
    begin
      MPRectInclude(Result, B.MinX, B.MinY);
      MPRectInclude(Result, B.MaxX, B.MaxY);
    end;
  end;
  for I := 0 to WireCount - 1 do
    for J := 0 to High(Wire(I).Points) do
      MPRectInclude(Result, Wire(I).Points[J].X, Wire(I).Points[J].Y);
  for I := 0 to LabelCount - 1 do
  begin
    MPRectInclude(Result, Label_(I).X - 2, Label_(I).Y - 3);
    MPRectInclude(Result, Label_(I).X + 2, Label_(I).Y + 3);
  end;
end;

function TMPSchematic.ToJSON: string;
var
  Root, O: TJSONObject;
  A, P: TJSONArray;
  I, J: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', 'makepcb-schematic');
    A := TJSONArray.Create;
    for I := 0 to PartCount - 1 do
    begin
      O := TJSONObject.Create;
      O.Add('symbol', Part(I).Symbol.Name);
      O.Add('ref', Part(I).Ref);
      O.Add('value', Part(I).Value);
      O.Add('footprint', Part(I).Footprint);
      O.Add('x', Part(I).X); O.Add('y', Part(I).Y);
      O.Add('rotation', Part(I).Rotation);
      A.Add(O);
    end;
    Root.Add('parts', A);
    A := TJSONArray.Create;
    for I := 0 to WireCount - 1 do
    begin
      P := TJSONArray.Create;
      for J := 0 to High(Wire(I).Points) do
        P.Add(TJSONArray.Create([Wire(I).Points[J].X, Wire(I).Points[J].Y]));
      A.Add(P);
    end;
    Root.Add('wires', A);
    A := TJSONArray.Create;
    for I := 0 to LabelCount - 1 do
    begin
      O := TJSONObject.Create;
      O.Add('name', Label_(I).Name);
      O.Add('x', Label_(I).X); O.Add('y', Label_(I).Y);
      O.Add('kind', Ord(Label_(I).Kind));
      A.Add(O);
    end;
    Root.Add('labels', A);
    Result := Root.AsJSON;
  finally
    Root.Free;
  end;
end;

procedure TMPSchematic.FromJSON(const S: string);
var
  D: TJSONData;
  Root, O: TJSONObject;
  A, W: TJSONArray;
  I, J: Integer;
  Sym: TMPSymbol;
  P: TMPPart;
  Pts: TMPPoints;
begin
  Clear;
  if Trim(S) = '' then Exit;
  D := GetJSON(S);
  try
    if not (D is TJSONObject) then Exit;
    Root := TJSONObject(D);
    A := Root.Get('parts', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        Sym := MPSymbols.Find(O.Get('symbol', ''));
        if Sym = nil then Continue;
        P := AddPart(Sym, O.Get('x', 0.0), O.Get('y', 0.0));
        P.Ref := O.Get('ref', P.Ref);
        P.Value := O.Get('value', P.Value);
        P.Footprint := O.Get('footprint', P.Footprint);
        P.Rotation := O.Get('rotation', 0);
      end;
    A := Root.Get('wires', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        W := A.Arrays[I];
        SetLength(Pts, W.Count);
        for J := 0 to W.Count - 1 do
          Pts[J] := MPPoint(W.Arrays[J].Floats[0], W.Arrays[J].Floats[1]);
        if Length(Pts) >= 2 then AddWire(Pts);
      end;
    A := Root.Get('labels', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        AddLabel(O.Get('name', ''), O.Get('x', 0.0), O.Get('y', 0.0),
          TMPSymKind(EnsureRange(O.Get('kind', Ord(symLabel)), Ord(symGround), Ord(symLabel))));
      end;
  finally
    D.Free;
  end;
end;

{ ---------------- redes ---------------- }

function PointOnWire(const P: TMPPoint; W: TMPSchWire): Boolean;
var
  I: Integer;
begin
  for I := 1 to High(W.Points) do
    if MPSegDist(P, W.Points[I - 1], W.Points[I]) < 0.01 then Exit(True);
  Result := False;
end;

{ nos: pinos de partes, depois fios, depois rotulos }
function MPSchNets(Sch: TMPSchematic): TMPSchNets;
var
  Parent: array of Integer;
  PinBase: array of Integer;
  NPins, NWires, I, J, K, L, N, Root, Idx: Integer;
  P: TMPPoint;
  W, W2: TMPSchWire;
  Groups: TStringList;
  Names: array of string;

  function Find(X: Integer): Integer;
  begin
    while Parent[X] <> X do
    begin
      Parent[X] := Parent[Parent[X]];
      X := Parent[X];
    end;
    Result := X;
  end;

  procedure Union(A, B: Integer);
  begin
    A := Find(A); B := Find(B);
    if A <> B then Parent[A] := B;
  end;

begin
  Result := nil;
  SetLength(PinBase, Sch.PartCount);
  NPins := 0;
  for I := 0 to Sch.PartCount - 1 do
  begin
    PinBase[I] := NPins;
    Inc(NPins, Length(Sch.Part(I).Symbol.Pins));
  end;
  NWires := Sch.WireCount;
  SetLength(Parent, NPins + NWires + Sch.LabelCount);
  for I := 0 to High(Parent) do Parent[I] := I;
  { pino x fio e pino x pino }
  for I := 0 to Sch.PartCount - 1 do
    for J := 0 to High(Sch.Part(I).Symbol.Pins) do
    begin
      P := Sch.Part(I).PinPos(J);
      for K := 0 to NWires - 1 do
        if PointOnWire(P, Sch.Wire(K)) then Union(PinBase[I] + J, NPins + K);
      for K := I + 1 to Sch.PartCount - 1 do
        for L := 0 to High(Sch.Part(K).Symbol.Pins) do
          if MPDist(P, Sch.Part(K).PinPos(L)) < 0.01 then Union(PinBase[I] + J, PinBase[K] + L);
    end;
  { fio x fio: ponta de um sobre o outro (juncao) }
  for K := 0 to NWires - 1 do
  begin
    W := Sch.Wire(K);
    for L := 0 to NWires - 1 do
    begin
      if L = K then Continue;
      W2 := Sch.Wire(L);
      if PointOnWire(W.Points[0], W2) or PointOnWire(W.Points[High(W.Points)], W2) then
        Union(NPins + K, NPins + L);
    end;
  end;
  { rotulos: no ponto do rotulo; mesmo nome = mesma rede }
  SetLength(Names, Sch.LabelCount);
  Groups := TStringList.Create;
  try
    for I := 0 to Sch.LabelCount - 1 do
    begin
      P := MPPoint(Sch.Label_(I).X, Sch.Label_(I).Y);
      N := NPins + NWires + I;
      for K := 0 to NWires - 1 do
        if PointOnWire(P, Sch.Wire(K)) then Union(N, NPins + K);
      for J := 0 to Sch.PartCount - 1 do
        for L := 0 to High(Sch.Part(J).Symbol.Pins) do
          if MPDist(P, Sch.Part(J).PinPos(L)) < 0.01 then Union(N, PinBase[J] + L);
      Names[I] := Sch.Label_(I).Name;
      Idx := Groups.IndexOf(Names[I]);
      if Idx < 0 then Groups.AddObject(Names[I], TObject(PtrInt(N)))
      else Union(N, PtrInt(Groups.Objects[Idx]));
    end;
    { agrupa os pinos por raiz }
    Groups.Clear;
    for I := 0 to Sch.PartCount - 1 do
      for J := 0 to High(Sch.Part(I).Symbol.Pins) do
      begin
        Root := Find(PinBase[I] + J);
        Idx := Groups.IndexOf(IntToStr(Root));
        if Idx < 0 then
        begin
          Idx := Groups.Add(IntToStr(Root));
          SetLength(Result, Groups.Count);
          Result[Idx].Name := '';
          SetLength(Result[Idx].Pins, 0);
        end;
        SetLength(Result[Idx].Pins, Length(Result[Idx].Pins) + 1);
        Result[Idx].Pins[High(Result[Idx].Pins)].Part := I;
        Result[Idx].Pins[High(Result[Idx].Pins)].Pin := J;
      end;
    { nome da rede: rotulo ligado a ela }
    for I := 0 to Sch.LabelCount - 1 do
    begin
      Idx := Groups.IndexOf(IntToStr(Find(NPins + NWires + I)));
      if (Idx >= 0) and (Result[Idx].Name = '') then Result[Idx].Name := Names[I];
    end;
  finally
    Groups.Free;
  end;
  { so redes com 2 pinos ou mais }
  J := 0;
  for I := 0 to High(Result) do
    if Length(Result[I].Pins) >= 2 then
    begin
      Result[J] := Result[I];
      Inc(J);
    end;
  SetLength(Result, J);
end;

function MPSchUnconnected(Sch: TMPSchematic): Integer;
var
  Nets: TMPSchNets;
  I, Total, InNets: Integer;
begin
  Total := 0;
  for I := 0 to Sch.PartCount - 1 do Inc(Total, Length(Sch.Part(I).Symbol.Pins));
  Nets := MPSchNets(Sch);
  InNets := 0;
  for I := 0 to High(Nets) do Inc(InNets, Length(Nets[I].Pins));
  Result := Total - InNets;
end;

{ ---------------- conversao para a placa ---------------- }

function MPConvertToPCB(Sch: TMPSchematic; Doc: TMPDocument; Lib: TMPLibrary; Report: TStrings): Boolean;
var
  I, J, K, Created, Updated, NetCount, CA, CB, PadA, PadB, Errors: Integer;
  P: TMPPart;
  C: TMPComponent;
  FP: TMPFootprint;
  Nets: TMPSchNets;
  CompOf: array of Integer;
  X, Y, RowH, W, H: Double;
  B: TMPRect;

  function PadOf(PartIdx, PinIdx: Integer): Integer;
  begin
    if CompOf[PartIdx] < 0 then Exit(-1);
    Result := Sch.Part(PartIdx).Symbol.Pins[PinIdx].Pad;
    if (Result < 0) or (Result >= Doc.Component(CompOf[PartIdx]).PadCount) then
      Result := Min(PinIdx, Doc.Component(CompOf[PartIdx]).PadCount - 1);
  end;

begin
  Created := 0; Updated := 0; Errors := 0;
  CA := -1; PadA := -1;
  SetLength(CompOf, Sch.PartCount);
  { posicao livre para componentes novos: fileiras de baixo para cima }
  X := 2.54; Y := 2.54; RowH := 0;
  for I := 0 to Sch.PartCount - 1 do
  begin
    P := Sch.Part(I);
    CompOf[I] := -1;
    if P.Symbol.Kind <> symPart then Continue;
    if P.Ref = '' then
    begin
      if Report <> nil then Report.Add('Parte sem referencia ignorada (' + P.Symbol.Name + ')');
      Inc(Errors);
      Continue;
    end;
    FP := Lib.Find(P.Footprint);
    if FP = nil then FP := Lib.Find(P.Symbol.DefaultFootprint);
    if FP = nil then
    begin
      if Report <> nil then Report.Add(P.Ref + ': footprint "' + P.Footprint + '" nao encontrado');
      Inc(Errors);
      Continue;
    end;
    if Length(P.Symbol.Pins) > Length(FP.Pads) then
    begin
      if Report <> nil then Report.Add(Format('%s: o footprint %s tem %d pads e o simbolo %d pinos',
        [P.Ref, FP.Name, Length(FP.Pads), Length(P.Symbol.Pins)]));
      Inc(Errors);
      Continue;
    end;
    C := Doc.FindComponent(P.Ref);
    if C = nil then
    begin
      B := FP.Bounds;
      W := B.MaxX - B.MinX + 2.54; H := B.MaxY - B.MinY + 2.54;
      if X + W > Doc.BoardW then
      begin
        X := 2.54; Y := Y + RowH; RowH := 0;
      end;
      C := Doc.AddComponent(FP, Round((X - B.MinX + 1.27) / MP_GRID) * MP_GRID,
        Round((Y - B.MinY + 1.27) / MP_GRID) * MP_GRID);
      C.Ref := P.Ref;
      X := X + W; RowH := Max(RowH, H);
      if FP.HasSMD and not Doc.DoubleSided then C.Flipped := True;
      Inc(Created);
    end
    else if C.Footprint <> FP then
    begin
      C.Footprint := FP;
      Inc(Updated);
    end;
    C.Value := P.Value;
    CompOf[I] := Doc.IndexOfComponent(C);
  end;
  { ligacoes: o esquema manda; trilhas desenhadas continuam }
  SetLength(Doc.Wires, 0);
  Nets := MPSchNets(Sch);
  NetCount := 0;
  for I := 0 to High(Nets) do
  begin
    K := -1;
    for J := 0 to High(Nets[I].Pins) do
    begin
      CB := CompOf[Nets[I].Pins[J].Part];
      if CB < 0 then Continue;
      PadB := PadOf(Nets[I].Pins[J].Part, Nets[I].Pins[J].Pin);
      if PadB < 0 then Continue;
      if K < 0 then
      begin
        K := J; CA := CB; PadA := PadB;
        Continue;
      end;
      if (CA <> CB) or (PadA <> PadB) then Doc.AddWire(CA, PadA, CB, PadB);
    end;
    if K >= 0 then Inc(NetCount);
  end;
  Doc.Changed;
  if Report <> nil then
  begin
    Report.Add(Format('%d componentes novos, %d com footprint trocado, %d redes, %d ligacoes.',
      [Created, Updated, NetCount, Doc.WireCount]));
    if Created > 0 then Report.Add('Os novos ficam em fileiras: arraste-os para a posicao final.');
    for I := 0 to Doc.ComponentCount - 1 do
      if (not Doc.Component(I).IsPadOnly) and (Doc.Component(I).Ref <> '') and
         (Sch.FindPart(Doc.Component(I).Ref) = nil) then
        Report.Add(Doc.Component(I).Ref + ' esta na placa mas nao no esquema');
  end;
  Result := Errors = 0;
end;

{ ---------------- biblioteca de simbolos ---------------- }

constructor TMPSymbolLibrary.Create;
begin
  inherited Create;
  FItems := TList.Create;
  FCategories := TStringList.Create;
  Build;
end;

destructor TMPSymbolLibrary.Destroy;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do TObject(FItems[I]).Free;
  FItems.Free;
  FCategories.Free;
  inherited Destroy;
end;

function TMPSymbolLibrary.Count: Integer; begin Result := FItems.Count; end;
function TMPSymbolLibrary.Item(I: Integer): TMPSymbol; begin Result := TMPSymbol(FItems[I]); end;

function TMPSymbolLibrary.Find(const AName: string): TMPSymbol;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if SameText(Item(I).Name, AName) then Exit(Item(I));
  Result := nil;
end;

function TMPSymbolLibrary.Add(const AName, ACategory, APrefix, AValue, AFootprint: string): TMPSymbol;
begin
  Result := TMPSymbol.Create;
  Result.Name := AName;
  Result.Category := ACategory;
  Result.RefPrefix := APrefix;
  Result.DefaultValue := AValue;
  Result.DefaultFootprint := AFootprint;
  Result.Kind := symPart;
  FItems.Add(Result);
  if FCategories.IndexOf(ACategory) < 0 then FCategories.Add(ACategory);
end;

{ terminais de -5,08 a -2,54 e de 2,54 a 5,08 }
procedure TMPSymbolLibrary.TwoPin(S: TMPSymbol);
begin
  S.Line(-5.08, 0, -2.54, 0);
  S.Line(2.54, 0, 5.08, 0);
end;

procedure TMPSymbolLibrary.DILBox(Pins: Integer; const AName, AValue: string; const PinNames: array of string);
var
  S: TMPSymbol;
  N, I: Integer;
  H, Y: Double;
  Nm: string;
begin
  N := Pins div 2;
  S := Add(AName, 'Circuitos integrados', 'IC', AValue, Format('DIL-%d 0.3', [Pins]));
  { pinos na grade: do Y = (N div 2) * G descendo }
  H := (N div 2) * MP_SCH_GRID;           { Y do pino 1 }
  S.Box(-5.08, H - N * MP_SCH_GRID, 5.08, H + MP_SCH_GRID);
  S.Circle(-5.08 + 1.2, H + MP_SCH_GRID - 1.2, 0.5);
  { indice do pino = numero - 1 (1..N a esquerda de cima para baixo,
    N+1..2N a direita de baixo para cima, como no CI visto de cima) }
  for I := 0 to N - 1 do
  begin
    Y := H - I * MP_SCH_GRID;
    S.Line(-10.16, Y, -5.08, Y);
    if I < Length(PinNames) then Nm := PinNames[I] else Nm := IntToStr(I + 1);
    S.Pin(Nm, -10.16, Y, I);
    S.Text(-9.6, Y + 0.4, 1.0, IntToStr(I + 1));
    if I < Length(PinNames) then S.Text(-4.6, Y - 0.6, 1.2, Nm);
  end;
  for I := 0 to N - 1 do
  begin
    Y := H - (N - 1 - I) * MP_SCH_GRID;
    S.Line(5.08, Y, 10.16, Y);
    if N + I < Length(PinNames) then Nm := PinNames[N + I] else Nm := IntToStr(N + I + 1);
    S.Pin(Nm, 10.16, Y, N + I);
    S.Text(6.0, Y + 0.4, 1.0, IntToStr(N + I + 1));
    if N + I < Length(PinNames) then S.Text(4.6 - Length(Nm) * 0.9, Y - 0.6, 1.2, Nm);
  end;
end;

procedure TMPSymbolLibrary.Build;
var
  S: TMPSymbol;
  I, K: Integer;
  Y: Double;
begin
  { ---- passivos ---- }
  S := Add('Resistor', 'Passivos', 'R', '1K', 'Resistor 0.4 pol');
  TwoPin(S); S.Box(-2.54, -1.0, 2.54, 1.0);
  S.Pin('1', -5.08, 0, 0); S.Pin('2', 5.08, 0, 1);
  S := Add('Capacitor', 'Passivos', 'C', '100nF', 'Ceramico 0.1 pol');
  S.Line(-5.08, 0, -0.6, 0); S.Line(0.6, 0, 5.08, 0);
  S.Line(-0.6, -2.0, -0.6, 2.0); S.Line(0.6, -2.0, 0.6, 2.0);
  S.Pin('1', -5.08, 0, 0); S.Pin('2', 5.08, 0, 1);
  S := Add('Capacitor eletrolitico', 'Passivos', 'C', '10uF', 'Eletrolitico 5 mm');
  S.Line(-5.08, 0, -0.6, 0); S.Line(0.9, 0, 5.08, 0);
  S.Line(-0.6, -2.0, -0.6, 2.0);
  S.Line(0.6, -2.0, 0.9, -1.0); S.Line(0.9, -1.0, 0.9, 1.0); S.Line(0.9, 1.0, 0.6, 2.0);
  S.Line(-2.4, 1.2, -1.4, 1.2); S.Line(-1.9, 0.7, -1.9, 1.7);
  S.Pin('+', -5.08, 0, 0); S.Pin('-', 5.08, 0, 1);
  S := Add('Potenciometro', 'Passivos', 'VR', '10K', 'Potenciometro');
  TwoPin(S); S.Box(-2.54, -1.0, 2.54, 1.0);
  S.Line(0, 5.08, 0, 1.2); S.Line(-0.5, 1.8, 0, 1.2); S.Line(0.5, 1.8, 0, 1.2);
  S.Pin('1', -5.08, 0, 0); S.Pin('2', 0, 5.08, 1); S.Pin('3', 5.08, 0, 2);
  S := Add('LDR', 'Passivos', 'LDR', '', 'LDR');
  TwoPin(S); S.Box(-2.54, -1.0, 2.54, 1.0); S.Circle(0, 0, 3.4);
  S.Line(-3.2, 4.2, -1.6, 2.6); S.Line(-1.4, 4.6, 0.2, 3.0);
  S.Pin('1', -5.08, 0, 0); S.Pin('2', 5.08, 0, 1);
  S := Add('Cristal', 'Passivos', 'X', '16MHz', 'Cristal HC-49');
  S.Line(-5.08, 0, -1.6, 0); S.Line(1.6, 0, 5.08, 0);
  S.Line(-1.6, -1.6, -1.6, 1.6); S.Line(1.6, -1.6, 1.6, 1.6);
  S.Box(-0.9, -2.0, 0.9, 2.0);
  S.Pin('1', -5.08, 0, 0); S.Pin('2', 5.08, 0, 1);

  { ---- semicondutores (diodo/LED: pad 1 do footprint e o catodo) ---- }
  S := Add('Diodo', 'Semicondutores', 'D', '1N4007', 'Diodo 0.4 pol');
  TwoPin(S);
  S.Line(-1.5, -1.5, -1.5, 1.5); S.Line(-1.5, 1.5, 1.5, 0); S.Line(-1.5, -1.5, 1.5, 0);
  S.Line(1.5, -1.5, 1.5, 1.5); S.Line(1.5, 0, 2.54, 0); S.Line(-2.54, 0, -1.5, 0);
  S.Pin('A', -5.08, 0, 1); S.Pin('K', 5.08, 0, 0);
  S := Add('LED', 'Semicondutores', 'D', 'Vermelho', 'LED 5 mm');
  TwoPin(S);
  S.Line(-1.5, -1.5, -1.5, 1.5); S.Line(-1.5, 1.5, 1.5, 0); S.Line(-1.5, -1.5, 1.5, 0);
  S.Line(1.5, -1.5, 1.5, 1.5); S.Line(1.5, 0, 2.54, 0); S.Line(-2.54, 0, -1.5, 0);
  S.Line(0, 2.0, 1.4, 3.4); S.Line(1.2, 1.4, 2.6, 2.8);
  S.Pin('A', -5.08, 0, 1); S.Pin('K', 5.08, 0, 0);
  S := Add('Transistor NPN', 'Semicondutores', 'Q', 'BC548', 'TO-92');
  S.Circle(0.6, 0, 3.2);
  S.Line(-5.08, 0, -1.0, 0); S.Line(-1.0, -1.8, -1.0, 1.8);
  S.Line(-1.0, 0.8, 2.54, 2.54); S.Line(2.54, 2.54, 2.54, 5.08);
  S.Line(-1.0, -0.8, 2.54, -2.54); S.Line(2.54, -2.54, 2.54, -5.08);
  S.Line(1.6, -2.5, 2.4, -2.5); S.Line(2.4, -2.5, 2.0, -1.7);
  S.Pin('B', -5.08, 0, 1); S.Pin('C', 2.54, 5.08, 2); S.Pin('E', 2.54, -5.08, 0);
  S := Add('Transistor PNP', 'Semicondutores', 'Q', 'BC558', 'TO-92');
  S.Circle(0.6, 0, 3.2);
  S.Line(-5.08, 0, -1.0, 0); S.Line(-1.0, -1.8, -1.0, 1.8);
  S.Line(-1.0, 0.8, 2.54, 2.54); S.Line(2.54, 2.54, 2.54, 5.08);
  S.Line(-1.0, -0.8, 2.54, -2.54); S.Line(2.54, -2.54, 2.54, -5.08);
  S.Line(-0.2, -1.3, 0.6, -1.3); S.Line(-0.2, -1.3, 0.2, -0.5);
  S.Pin('B', -5.08, 0, 1); S.Pin('C', 2.54, -5.08, 2); S.Pin('E', 2.54, 5.08, 0);
  S := Add('Regulador 78xx', 'Semicondutores', 'IC', '7805', 'TO-220');
  S.Box(-5.08, -2.54, 5.08, 2.54);
  S.Line(-10.16, 0, -5.08, 0); S.Line(5.08, 0, 10.16, 0); S.Line(0, -2.54, 0, -5.08);
  S.Text(-4.4, -0.6, 1.2, 'IN'); S.Text(1.0, -0.6, 1.2, 'OUT'); S.Text(-1.3, -2.2, 1.0, 'GND');
  S.Pin('IN', -10.16, 0, 0); S.Pin('GND', 0, -5.08, 1); S.Pin('OUT', 10.16, 0, 2);

  { ---- circuitos integrados (pinos na ordem fisica do DIL) ---- }
  DILBox(8, '555', 'NE555', ['GND', 'TRIG', 'OUT', 'RST', 'CTRL', 'THR', 'DIS', 'VCC']);
  DILBox(8, 'CI 8 pinos', '', []);
  DILBox(14, 'CI 14 pinos', '', []);
  DILBox(16, 'CI 16 pinos', '', []);

  { ---- conectores ---- }
  S := Add('Borne 2 vias', 'Conectores', 'TB', '', 'Borne 2 vias');
  S.Box(-2.54, -3.81, 0, 3.81);
  S.Line(0, 2.54, 2.54, 2.54); S.Line(0, -2.54, 2.54, -2.54);
  S.Circle(-1.27, 2.54, 0.6); S.Circle(-1.27, -2.54, 0.6);
  S.Pin('1', 2.54, 2.54, 0); S.Pin('2', 2.54, -2.54, 1);
  S := Add('Bateria', 'Conectores', 'B', '9V', 'Bateria 9 V');
  S.Line(0, 5.08, 0, 1.0); S.Line(0, -1.0, 0, -5.08);
  S.Line(-2.4, 1.0, 2.4, 1.0); S.Line(-1.2, -1.0, 1.2, -1.0);
  S.Line(1.6, 2.2, 2.6, 2.2); S.Line(2.1, 1.7, 2.1, 2.7);
  S.Pin('+', 0, 5.08, 0); S.Pin('-', 0, -5.08, 1);
  for I := 2 to 6 do
  begin
    S := Add(Format('Barra %d pinos', [I]), 'Conectores', 'J', '', Format('Barra 1x%d', [I]));
    S.Box(-2.54, ((I div 2) - I + 0.5) * MP_SCH_GRID, 0, ((I div 2) + 0.5) * MP_SCH_GRID);
    for K := 0 to I - 1 do
    begin
      Y := ((I div 2) - K) * MP_SCH_GRID;
      S.Line(0, Y, 2.54, Y);
      S.Circle(-1.27, Y, 0.5);
      S.Pin(IntToStr(K + 1), 2.54, Y, K);
    end;
  end;

  { ---- diversos ---- }
  S := Add('Chave', 'Diversos', 'SW', '', 'Botao 6x6');
  S.Line(-5.08, 0, -2.0, 0); S.Line(2.0, 0, 5.08, 0);
  S.Circle(-2.0, 0, 0.4); S.Circle(2.0, 0, 0.4);
  S.Line(-2.0, 1.4, 2.0, 1.4); S.Line(0, 1.4, 0, 2.6);
  S.Pin('1', -5.08, 0, 0); S.Pin('2', 5.08, 0, 2);
  S := Add('Buzzer', 'Diversos', 'LS', '', 'Buzzer 12 mm');
  S.Line(-5.08, 0, -2.54, 0); S.Line(2.54, 0, 5.08, 0);
  S.Box(-2.54, -1.6, 2.54, 1.6); S.Line(-1.6, 1.6, -2.6, 3.2); S.Line(1.6, 1.6, 2.6, 3.2);
  S.Line(-2.6, 3.2, 2.6, 3.2);
  S.Pin('+', -5.08, 0, 0); S.Pin('-', 5.08, 0, 1);

  { ---- alimentacao (rotulos): nao viram componente ---- }
  S := Add('GND', 'Alimentacao', '', 'GND', '');
  S.Kind := symGround;
  S := Add('VCC', 'Alimentacao', '', 'VCC', '');
  S.Kind := symPower;
  S := Add('Rotulo', 'Alimentacao', '', '', '');
  S.Kind := symLabel;
end;

{ ---------------- exemplo ---------------- }

procedure MPAstableSchematic(Sch: TMPSchematic);
{ mesmas redes do exemplo da placa (MPAstableExample):
  VCC: TB1.1 IC1.8 IC1.4 R1.1 | DIS: R1.2 IC1.7 R2.1 | THR: R2.2 IC1.6 IC1.2 C1.+
  OUT: IC1.3 R3.1 | LED: R3.2 D1.A | CTRL: IC1.5 C2.1 | GND: TB1.2 IC1.1 C1.- C2.2 D1.K }
var
  IC, R1, R2, R3, C1, C2, D1, TB: TMPPart;

  function Put(const Sym, Ref, Value: string; X, Y: Double; Rot: Integer): TMPPart;
  begin
    Result := Sch.AddPart(MPSymbols.Find(Sym), X, Y);
    Result.Ref := Ref;
    if Value <> '' then Result.Value := Value;
    Result.Rotation := Rot;
  end;

  procedure W(const Pts: array of Double);
  var
    P: TMPPoints;
    I: Integer;
  begin
    SetLength(P, Length(Pts) div 2);
    for I := 0 to High(P) do P[I] := MPPoint(Pts[2 * I], Pts[2 * I + 1]);
    Sch.AddWire(P);
  end;

  procedure Pwr(Part: TMPPart; Pin: Integer; const Net: string);
  var
    P: TMPPoint;
  begin
    P := Part.PinPos(Pin);
    if Net = 'GND' then Sch.AddLabel(Net, P.X, P.Y, symGround)
    else Sch.AddLabel(Net, P.X, P.Y, symPower);
  end;

begin
  Sch.Clear;
  { 555 em (60,96; 50,8): pinos 1-4 em X 50,8 (Y 55,88 / 53,34 / 50,8 / 48,26),
    pinos 5-8 em X 71,12 (Y 48,26 / 50,8 / 53,34 / 55,88) }
  IC := Put('555', 'IC1', 'NE555', 60.96, 50.8, 0);
  R1 := Put('Resistor', 'R1', '10K', 81.28, 63.5, 270);
  R2 := Put('Resistor', 'R2', '100K', 81.28, 48.26, 270);
  C1 := Put('Capacitor eletrolitico', 'C1', '10uF', 81.28, 33.02, 270);
  C2 := Put('Capacitor', 'C2', '10nF', 71.12, 38.1, 270);
  R3 := Put('Resistor', 'R3', '470R', 35.56, 50.8, 180);
  D1 := Put('LED', 'D1', 'Vermelho', 25.4, 43.18, 270);
  TB := Put('Borne 2 vias', 'TB1', '9V', 12.7, 50.8, 0);
  { alimentacao }
  Pwr(TB, 0, 'VCC'); Pwr(IC, 7, 'VCC'); Pwr(IC, 3, 'VCC'); Pwr(R1, 0, 'VCC');
  Pwr(TB, 1, 'GND'); Pwr(IC, 0, 'GND'); Pwr(C1, 1, 'GND'); Pwr(C2, 1, 'GND'); Pwr(D1, 1, 'GND');
  { DIS: R1.2 - R2.1 e pino 7 }
  W([81.28, 58.42, 81.28, 53.34]);
  W([71.12, 53.34, 81.28, 53.34]);
  { THR: R2.2 - C1.+, pino 6 e pino 2 (juncoes em T) }
  W([81.28, 43.18, 81.28, 38.1]);
  W([71.12, 50.8, 76.2, 50.8, 76.2, 43.18, 81.28, 43.18]);
  W([50.8, 53.34, 45.72, 53.34, 45.72, 45.72, 76.2, 45.72]);
  { CTRL: pino 5 - C2 }
  W([71.12, 48.26, 71.12, 43.18]);
  { OUT: pino 3 - R3 - LED }
  W([50.8, 50.8, 40.64, 50.8]);
  W([30.48, 50.8, 25.4, 50.8, 25.4, 48.26]);
end;

end.
