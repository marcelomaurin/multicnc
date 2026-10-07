unit makepcb_model;

{ Modelo do MakePCB (projeto de placa de circuito impresso do zero).

  Convencoes (iguais ao LaserPCB): milimetros, Y para cima, origem no canto
  inferior esquerdo da placa. Grade padrao de 0,05 pol (1,27 mm).

  - TMPFootprint: desenho de um componente (pads, serigrafia, corpo).
  - TMPComponent: footprint colocado na placa (referencia, valor, posicao,
    rotacao em passos de 90 graus). Pads avulsos e vias tambem sao
    componentes de um pino, como no PCB Wizard.
  - TMPTrack: trilha de cobre (polilinha) numa face.
  - TMPWire: ligacao (ratsnest) entre dois pads, ainda sem trilha.
  - TMPArea: area de cobre (poligono) com folga em volta de outras redes.
  - TMPText: texto no cobre ou na serigrafia.
  - TMPDocument: placa, listas acima, redes e arquivo .mpcb (JSON).

  Todos os pads sao passantes (aparecem nas duas faces); Plated = False
  marca furos sem metalizacao (fixacao). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser;

const
  MP_INCH = 25.4;
  MP_MIL = 0.0254;
  MP_GRID = 1.27;          { 0,05 pol }

type
  TMPPoint = record
    X, Y: Double;
  end;
  TMPPoints = array of TMPPoint;

  TMPRect = record
    MinX, MinY, MaxX, MaxY: Double;
    Valid: Boolean;
  end;

  { faces de cobre e camadas graficas }
  TMPLayer = (mlBottomCopper, mlTopCopper, mlTopSilk);

  TMPPadShape = (psRound, psSquare, psOblong);

  TMPPadDef = record
    Name: string;
    X, Y: Double;          { posicao no footprint }
    Shape: TMPPadShape;
    W, H: Double;          { tamanho do pad (oblongo: W > H na horizontal) }
    Drill: Double;
    Plated: Boolean;
  end;

  TMPSilkKind = (skLine, skCircle, skRect);

  TMPSilk = record
    Kind: TMPSilkKind;
    X1, Y1, X2, Y2, R: Double;   { linha X1..X2; circulo centro X1,Y1 raio R; retangulo cantos }
  end;

  { corpo usado na visao "Mundo real" }
  TMPBodyKind = (bkNone, bkResistor, bkCapCeramic, bkCapFilm, bkCapElectrolytic,
    bkDiode, bkLED, bkTransistor, bkPower, bkIC, bkHeader, bkTerminal, bkPot,
    bkCrystal, bkSwitch, bkBuzzer, bkLDR, bkPad);

  TMPFootprint = class
  public
    Name, Category, Description, RefPrefix, DefaultValue: string;
    Pads: array of TMPPadDef;
    Silk: array of TMPSilk;
    Body: TMPBodyKind;
    BodyX1, BodyY1, BodyX2, BodyY2: Double;   { caixa do corpo (mundo real) }
    BodyColor: LongWord;                      { RGB }
    procedure AddPad(const AName: string; AX, AY: Double; AShape: TMPPadShape;
      AW, AH, ADrill: Double; APlated: Boolean = True);
    procedure AddLine(X1, Y1, X2, Y2: Double);
    procedure AddCircle(CX, CY, R: Double);
    procedure AddRect(X1, Y1, X2, Y2: Double);
    procedure SetBody(AKind: TMPBodyKind; X1, Y1, X2, Y2: Double; AColor: LongWord);
    function Bounds: TMPRect;
  end;

  TMPComponent = class
  public
    Footprint: TMPFootprint;
    Ref, Value: string;
    X, Y: Double;
    Rotation: Integer;        { 0, 90, 180, 270 }
    function LocalToWorld(LX, LY: Double): TMPPoint;
    function PadCount: Integer;
    function PadPos(I: Integer): TMPPoint;
    { tamanho do pad ja girado }
    procedure PadSize(I: Integer; out W, H: Double);
    function Bounds: TMPRect;
    function IsPadOnly: Boolean;
  end;

  TMPPadRef = record
    Comp, Pad: Integer;
  end;

  TMPTrack = class
  public
    Layer: TMPLayer;
    Width: Double;
    Points: TMPPoints;
    procedure AddPoint(AX, AY: Double);
    function Length: Double;
  end;

  TMPWire = record
    A, B: TMPPadRef;
  end;

  TMPArea = class
  public
    Layer: TMPLayer;
    Clearance: Double;
    Points: TMPPoints;
    { a area pertence a rede deste pad (NetComp = -1: isolada de tudo) }
    NetComp, NetPad: Integer;
  end;

  TMPText = class
  public
    X, Y, Height: Double;
    Text: string;
    Layer: TMPLayer;
  end;

  TMPFootprintResolver = function(const Name: string): TMPFootprint of object;

  TMPDocument = class
  private
    FComponents, FTracks, FAreas, FTexts: TList;
    FPadNet: array of array of Integer;   { [comp][pad] -> rede }
    FNetCount: Integer;
    FNetsValid: Boolean;
  public
    Name: string;
    BoardW, BoardH: Double;
    DoubleSided: Boolean;
    TrackWidth, Clearance, Grid: Double;
    Wires: array of TMPWire;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Changed;
    { componentes }
    function ComponentCount: Integer;
    function Component(I: Integer): TMPComponent;
    function AddComponent(FP: TMPFootprint; AX, AY: Double): TMPComponent;
    procedure DeleteComponent(I: Integer);
    function IndexOfComponent(C: TMPComponent): Integer;
    function FindComponent(const ARef: string): TMPComponent;
    function NextRef(const Prefix: string): string;
    { trilhas, areas, textos }
    function TrackCount: Integer;
    function Track(I: Integer): TMPTrack;
    function AddTrack(ALayer: TMPLayer; AWidth: Double): TMPTrack;
    procedure DeleteTrack(I: Integer);
    procedure ClearTracks;
    function AreaCount: Integer;
    function Area(I: Integer): TMPArea;
    function AddArea(ALayer: TMPLayer): TMPArea;
    procedure DeleteArea(I: Integer);
    function TextCount: Integer;
    function Text(I: Integer): TMPText;
    function AddText(const S: string; AX, AY, AHeight: Double; ALayer: TMPLayer): TMPText;
    procedure DeleteText(I: Integer);
    { ligacoes }
    procedure AddWire(CA, PA, CB, PB: Integer);
    procedure DeleteWire(I: Integer);
    function WireCount: Integer;
    { pad mais proximo de (X,Y) dentro de MaxDist; False se nenhum }
    function PadAt(AX, AY, MaxDist: Double; out Ref: TMPPadRef): Boolean;
    function PadPoint(const R: TMPPadRef): TMPPoint;
    { redes: ligacoes + trilhas que tocam pads ou outras trilhas }
    procedure ComputeNets;
    function NetCount: Integer;
    function PadNet(C, P: Integer): Integer;
    function TrackNet(I: Integer): Integer;
    { rede da area (-1 = isolada ou pad sem rede) }
    function AreaNet(I: Integer): Integer;
    { o pad/trilha liga na area (nao recebe folga) }
    function PadInArea(AreaIndex, C, P: Integer): Boolean;
    function TrackInArea(AreaIndex, T: Integer): Boolean;
    function ValidateBoard(Errors: TStrings): Boolean;
    function Bounds: TMPRect;
    { arquivo .mpcb }
    function ToJSON: string;
    procedure FromJSON(const S: string; Resolver: TMPFootprintResolver);
    procedure SaveToFile(const FileName: string);
    procedure LoadFromFile(const FileName: string; Resolver: TMPFootprintResolver);
  end;

function MPPoint(AX, AY: Double): TMPPoint; inline;
function MPDist(const A, B: TMPPoint): Double; inline;
function MPEmptyRect: TMPRect;
procedure MPRectInclude(var R: TMPRect; AX, AY: Double);
function MPPadRef(C, P: Integer): TMPPadRef; inline;
{ distancia do ponto P ao segmento A-B }
function MPSegDist(const P, A, B: TMPPoint): Double;
{ distancia minima entre os segmentos A-B e C-D }
function MPSegSegDist(const A, B, C, D: TMPPoint): Double;
function LayerName(L: TMPLayer): string;

implementation

var
  InvFS: TFormatSettings;

function MPPoint(AX, AY: Double): TMPPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function MPDist(const A, B: TMPPoint): Double;
begin
  Result := Hypot(A.X - B.X, A.Y - B.Y);
end;

function MPEmptyRect: TMPRect;
begin
  Result.MinX := 0; Result.MinY := 0; Result.MaxX := 0; Result.MaxY := 0;
  Result.Valid := False;
end;

procedure MPRectInclude(var R: TMPRect; AX, AY: Double);
begin
  if not R.Valid then
  begin
    R.MinX := AX; R.MaxX := AX; R.MinY := AY; R.MaxY := AY;
    R.Valid := True;
  end
  else
  begin
    R.MinX := Min(R.MinX, AX); R.MaxX := Max(R.MaxX, AX);
    R.MinY := Min(R.MinY, AY); R.MaxY := Max(R.MaxY, AY);
  end;
end;

function MPPadRef(C, P: Integer): TMPPadRef;
begin
  Result.Comp := C;
  Result.Pad := P;
end;

function MPSegDist(const P, A, B: TMPPoint): Double;
var
  DX, DY, L2, T: Double;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  L2 := DX * DX + DY * DY;
  if L2 < 1e-18 then Exit(MPDist(P, A));
  T := EnsureRange(((P.X - A.X) * DX + (P.Y - A.Y) * DY) / L2, 0, 1);
  Result := Hypot(P.X - (A.X + T * DX), P.Y - (A.Y + T * DY));
end;

function MPSegSegDist(const A, B, C, D: TMPPoint): Double;
var
  D1, D2, D3, D4: Double;

  function Cross(const O, P, Q: TMPPoint): Double;
  begin
    Result := (P.X - O.X) * (Q.Y - O.Y) - (P.Y - O.Y) * (Q.X - O.X);
  end;

begin
  D1 := Cross(C, D, A);
  D2 := Cross(C, D, B);
  D3 := Cross(A, B, C);
  D4 := Cross(A, B, D);
  if (((D1 > 0) and (D2 < 0)) or ((D1 < 0) and (D2 > 0))) and
     (((D3 > 0) and (D4 < 0)) or ((D3 < 0) and (D4 > 0))) then Exit(0);
  Result := Min(Min(MPSegDist(A, C, D), MPSegDist(B, C, D)),
                Min(MPSegDist(C, A, B), MPSegDist(D, A, B)));
end;

function LayerName(L: TMPLayer): string;
begin
  case L of
    mlBottomCopper: Result := 'Cobre inferior';
    mlTopCopper: Result := 'Cobre superior';
    mlTopSilk: Result := 'Serigrafia';
  else Result := '?';
  end;
end;

{ ---------------- TMPFootprint ---------------- }

procedure TMPFootprint.AddPad(const AName: string; AX, AY: Double; AShape: TMPPadShape;
  AW, AH, ADrill: Double; APlated: Boolean);
var
  N: Integer;
begin
  N := Length(Pads);
  SetLength(Pads, N + 1);
  Pads[N].Name := AName;
  Pads[N].X := AX; Pads[N].Y := AY;
  Pads[N].Shape := AShape;
  Pads[N].W := AW; Pads[N].H := AH;
  Pads[N].Drill := ADrill;
  Pads[N].Plated := APlated;
end;

procedure TMPFootprint.AddLine(X1, Y1, X2, Y2: Double);
var
  N: Integer;
begin
  N := Length(Silk);
  SetLength(Silk, N + 1);
  Silk[N].Kind := skLine;
  Silk[N].X1 := X1; Silk[N].Y1 := Y1; Silk[N].X2 := X2; Silk[N].Y2 := Y2;
end;

procedure TMPFootprint.AddCircle(CX, CY, R: Double);
var
  N: Integer;
begin
  N := Length(Silk);
  SetLength(Silk, N + 1);
  Silk[N].Kind := skCircle;
  Silk[N].X1 := CX; Silk[N].Y1 := CY; Silk[N].R := R;
end;

procedure TMPFootprint.AddRect(X1, Y1, X2, Y2: Double);
var
  N: Integer;
begin
  N := Length(Silk);
  SetLength(Silk, N + 1);
  Silk[N].Kind := skRect;
  Silk[N].X1 := Min(X1, X2); Silk[N].Y1 := Min(Y1, Y2);
  Silk[N].X2 := Max(X1, X2); Silk[N].Y2 := Max(Y1, Y2);
end;

procedure TMPFootprint.SetBody(AKind: TMPBodyKind; X1, Y1, X2, Y2: Double; AColor: LongWord);
begin
  Body := AKind;
  BodyX1 := Min(X1, X2); BodyY1 := Min(Y1, Y2);
  BodyX2 := Max(X1, X2); BodyY2 := Max(Y1, Y2);
  BodyColor := AColor;
end;

function TMPFootprint.Bounds: TMPRect;
var
  I: Integer;
begin
  Result := MPEmptyRect;
  for I := 0 to High(Pads) do
  begin
    MPRectInclude(Result, Pads[I].X - Pads[I].W / 2, Pads[I].Y - Pads[I].H / 2);
    MPRectInclude(Result, Pads[I].X + Pads[I].W / 2, Pads[I].Y + Pads[I].H / 2);
  end;
  for I := 0 to High(Silk) do
    case Silk[I].Kind of
      skLine, skRect:
        begin
          MPRectInclude(Result, Silk[I].X1, Silk[I].Y1);
          MPRectInclude(Result, Silk[I].X2, Silk[I].Y2);
        end;
      skCircle:
        begin
          MPRectInclude(Result, Silk[I].X1 - Silk[I].R, Silk[I].Y1 - Silk[I].R);
          MPRectInclude(Result, Silk[I].X1 + Silk[I].R, Silk[I].Y1 + Silk[I].R);
        end;
    end;
  if Body <> bkNone then
  begin
    MPRectInclude(Result, BodyX1, BodyY1);
    MPRectInclude(Result, BodyX2, BodyY2);
  end;
end;

{ ---------------- TMPComponent ---------------- }

function TMPComponent.LocalToWorld(LX, LY: Double): TMPPoint;
begin
  case ((Rotation mod 360) + 360) mod 360 of
    90: Result := MPPoint(X - LY, Y + LX);
    180: Result := MPPoint(X - LX, Y - LY);
    270: Result := MPPoint(X + LY, Y - LX);
  else Result := MPPoint(X + LX, Y + LY);
  end;
end;

function TMPComponent.PadCount: Integer;
begin
  Result := Length(Footprint.Pads);
end;

function TMPComponent.PadPos(I: Integer): TMPPoint;
begin
  Result := LocalToWorld(Footprint.Pads[I].X, Footprint.Pads[I].Y);
end;

procedure TMPComponent.PadSize(I: Integer; out W, H: Double);
begin
  if (((Rotation mod 360) + 360) mod 360 = 90) or (((Rotation mod 360) + 360) mod 360 = 270) then
  begin
    W := Footprint.Pads[I].H;
    H := Footprint.Pads[I].W;
  end
  else
  begin
    W := Footprint.Pads[I].W;
    H := Footprint.Pads[I].H;
  end;
end;

function TMPComponent.Bounds: TMPRect;
var
  B: TMPRect;
  P: TMPPoint;
begin
  B := Footprint.Bounds;
  Result := MPEmptyRect;
  if not B.Valid then
  begin
    MPRectInclude(Result, X, Y);
    Exit;
  end;
  P := LocalToWorld(B.MinX, B.MinY); MPRectInclude(Result, P.X, P.Y);
  P := LocalToWorld(B.MaxX, B.MaxY); MPRectInclude(Result, P.X, P.Y);
end;

function TMPComponent.IsPadOnly: Boolean;
begin
  Result := Footprint.Body = bkPad;
end;

{ ---------------- TMPTrack ---------------- }

procedure TMPTrack.AddPoint(AX, AY: Double);
var
  N: Integer;
begin
  N := System.Length(Points);
  if (N > 0) and (Abs(Points[N - 1].X - AX) < 1e-9) and (Abs(Points[N - 1].Y - AY) < 1e-9) then Exit;
  SetLength(Points, N + 1);
  Points[N] := MPPoint(AX, AY);
end;

function TMPTrack.Length: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to High(Points) do Result := Result + MPDist(Points[I - 1], Points[I]);
end;

{ ---------------- TMPDocument ---------------- }

constructor TMPDocument.Create;
begin
  inherited Create;
  FComponents := TList.Create;
  FTracks := TList.Create;
  FAreas := TList.Create;
  FTexts := TList.Create;
  Clear;
end;

destructor TMPDocument.Destroy;
begin
  Clear;
  FComponents.Free;
  FTracks.Free;
  FAreas.Free;
  FTexts.Free;
  inherited Destroy;
end;

procedure FreeItems(L: TList);
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do TObject(L[I]).Free;
  L.Clear;
end;

procedure TMPDocument.Clear;
begin
  FreeItems(FComponents);
  FreeItems(FTracks);
  FreeItems(FAreas);
  FreeItems(FTexts);
  SetLength(Wires, 0);
  Name := 'Nova placa';
  BoardW := 80;
  BoardH := 50;
  DoubleSided := False;
  TrackWidth := 0.8;
  Clearance := 0.5;
  Grid := MP_GRID;
  Changed;
end;

procedure TMPDocument.Changed;
begin
  FNetsValid := False;
end;

function TMPDocument.ComponentCount: Integer;
begin
  Result := FComponents.Count;
end;

function TMPDocument.Component(I: Integer): TMPComponent;
begin
  Result := TMPComponent(FComponents[I]);
end;

function TMPDocument.NextRef(const Prefix: string): string;
var
  I, N, Best: Integer;
  R: string;
begin
  Best := 0;
  if Prefix = '' then Exit('');
  for I := 0 to ComponentCount - 1 do
  begin
    R := Component(I).Ref;
    if (Pos(Prefix, R) = 1) and TryStrToInt(Copy(R, System.Length(Prefix) + 1, 10), N) then
      Best := Max(Best, N);
  end;
  Result := Prefix + IntToStr(Best + 1);
end;

function TMPDocument.AddComponent(FP: TMPFootprint; AX, AY: Double): TMPComponent;
begin
  if FP = nil then raise Exception.Create('Footprint inexistente');
  Result := TMPComponent.Create;
  Result.Footprint := FP;
  Result.X := AX;
  Result.Y := AY;
  Result.Ref := NextRef(FP.RefPrefix);
  Result.Value := FP.DefaultValue;
  FComponents.Add(Result);
  Changed;
end;

procedure TMPDocument.DeleteComponent(I: Integer);
var
  K, N: Integer;
begin
  { remove as ligacoes do componente e ajusta os indices das demais }
  N := 0;
  for K := 0 to High(Wires) do
    if (Wires[K].A.Comp <> I) and (Wires[K].B.Comp <> I) then
    begin
      Wires[N] := Wires[K];
      if Wires[N].A.Comp > I then Dec(Wires[N].A.Comp);
      if Wires[N].B.Comp > I then Dec(Wires[N].B.Comp);
      Inc(N);
    end;
  SetLength(Wires, N);
  for K := 0 to AreaCount - 1 do
    if Area(K).NetComp = I then begin Area(K).NetComp := -1; Area(K).NetPad := -1; end
    else if Area(K).NetComp > I then Dec(Area(K).NetComp);
  Component(I).Free;
  FComponents.Delete(I);
  Changed;
end;

function TMPDocument.IndexOfComponent(C: TMPComponent): Integer;
begin
  Result := FComponents.IndexOf(C);
end;

function TMPDocument.FindComponent(const ARef: string): TMPComponent;
var
  I: Integer;
begin
  for I := 0 to ComponentCount - 1 do
    if SameText(Component(I).Ref, ARef) then Exit(Component(I));
  Result := nil;
end;

function TMPDocument.TrackCount: Integer;
begin
  Result := FTracks.Count;
end;

function TMPDocument.Track(I: Integer): TMPTrack;
begin
  Result := TMPTrack(FTracks[I]);
end;

function TMPDocument.AddTrack(ALayer: TMPLayer; AWidth: Double): TMPTrack;
begin
  Result := TMPTrack.Create;
  Result.Layer := ALayer;
  Result.Width := AWidth;
  FTracks.Add(Result);
  Changed;
end;

procedure TMPDocument.DeleteTrack(I: Integer);
begin
  Track(I).Free;
  FTracks.Delete(I);
  Changed;
end;

procedure TMPDocument.ClearTracks;
begin
  FreeItems(FTracks);
  Changed;
end;

function TMPDocument.AreaCount: Integer;
begin
  Result := FAreas.Count;
end;

function TMPDocument.Area(I: Integer): TMPArea;
begin
  Result := TMPArea(FAreas[I]);
end;

function TMPDocument.AddArea(ALayer: TMPLayer): TMPArea;
begin
  Result := TMPArea.Create;
  Result.Layer := ALayer;
  Result.Clearance := Max(Clearance, 0.5);
  Result.NetComp := -1;
  Result.NetPad := -1;
  FAreas.Add(Result);
  Changed;
end;

procedure TMPDocument.DeleteArea(I: Integer);
begin
  Area(I).Free;
  FAreas.Delete(I);
  Changed;
end;

function TMPDocument.TextCount: Integer;
begin
  Result := FTexts.Count;
end;

function TMPDocument.Text(I: Integer): TMPText;
begin
  Result := TMPText(FTexts[I]);
end;

function TMPDocument.AddText(const S: string; AX, AY, AHeight: Double; ALayer: TMPLayer): TMPText;
begin
  Result := TMPText.Create;
  Result.Text := S;
  Result.X := AX;
  Result.Y := AY;
  Result.Height := AHeight;
  Result.Layer := ALayer;
  FTexts.Add(Result);
end;

procedure TMPDocument.DeleteText(I: Integer);
begin
  Text(I).Free;
  FTexts.Delete(I);
end;

procedure TMPDocument.AddWire(CA, PA, CB, PB: Integer);
var
  N, K: Integer;
begin
  if (CA = CB) and (PA = PB) then Exit;
  for K := 0 to High(Wires) do
    if ((Wires[K].A.Comp = CA) and (Wires[K].A.Pad = PA) and (Wires[K].B.Comp = CB) and (Wires[K].B.Pad = PB)) or
       ((Wires[K].A.Comp = CB) and (Wires[K].A.Pad = PB) and (Wires[K].B.Comp = CA) and (Wires[K].B.Pad = PA)) then Exit;
  N := System.Length(Wires);
  SetLength(Wires, N + 1);
  Wires[N].A := MPPadRef(CA, PA);
  Wires[N].B := MPPadRef(CB, PB);
  Changed;
end;

procedure TMPDocument.DeleteWire(I: Integer);
var
  K: Integer;
begin
  for K := I to High(Wires) - 1 do Wires[K] := Wires[K + 1];
  SetLength(Wires, System.Length(Wires) - 1);
  Changed;
end;

function TMPDocument.WireCount: Integer;
begin
  Result := System.Length(Wires);
end;

function TMPDocument.PadAt(AX, AY, MaxDist: Double; out Ref: TMPPadRef): Boolean;
var
  I, J: Integer;
  D, Best, W, H: Double;
  P: TMPPoint;
begin
  Result := False;
  Best := MaxDouble;
  Ref := MPPadRef(-1, -1);
  for I := 0 to ComponentCount - 1 do
    for J := 0 to Component(I).PadCount - 1 do
    begin
      P := Component(I).PadPos(J);
      Component(I).PadSize(J, W, H);
      D := Max(0, Max(Abs(AX - P.X) - W / 2, Abs(AY - P.Y) - H / 2));
      if (D <= MaxDist) and (MPDist(P, MPPoint(AX, AY)) < Best) then
      begin
        Best := MPDist(P, MPPoint(AX, AY));
        Ref := MPPadRef(I, J);
        Result := True;
      end;
    end;
end;

function TMPDocument.PadPoint(const R: TMPPadRef): TMPPoint;
begin
  Result := Component(R.Comp).PadPos(R.Pad);
end;

{ ---- redes ---- }

procedure TMPDocument.ComputeNets;
var
  Parent: array of Integer;
  Base: array of Integer;
  NPads, I, J, K, T, Root: Integer;
  Map: array of Integer;
  W, H, R: Double;
  Trk, Other: TMPTrack;

  function Find(X: Integer): Integer;
  begin
    while Parent[X] <> X do
    begin
      Parent[X] := Parent[Parent[X]];
      X := Parent[X];
    end;
    Result := X;
  end;

  procedure Union(X, Y: Integer);
  begin
    X := Find(X);
    Y := Find(Y);
    if X <> Y then Parent[X] := Y;
  end;

  function PadIndex(C, Pd: Integer): Integer;
  begin
    Result := Base[C] + Pd;
  end;

  function TouchesPad(Tr: TMPTrack; C, Pd: Integer): Boolean;
  var
    S: Integer;
    Pp: TMPPoint;
  begin
    Pp := Component(C).PadPos(Pd);
    Component(C).PadSize(Pd, W, H);
    R := Min(W, H) / 2 + Tr.Width / 2;
    if System.Length(Tr.Points) = 1 then Exit(MPDist(Tr.Points[0], Pp) <= R);
    for S := 1 to High(Tr.Points) do
      if MPSegDist(Pp, Tr.Points[S - 1], Tr.Points[S]) <= R then Exit(True);
    Result := False;
  end;

  function TracksTouch(T1, T2: TMPTrack): Boolean;
  var
    S1, S2: Integer;
  begin
    if T1.Layer <> T2.Layer then Exit(False);
    for S1 := 1 to High(T1.Points) do
      for S2 := 1 to High(T2.Points) do
        if MPSegSegDist(T1.Points[S1 - 1], T1.Points[S1], T2.Points[S2 - 1], T2.Points[S2]) <=
           (T1.Width + T2.Width) / 2 - 1e-6 then Exit(True);
    Result := False;
  end;

begin
  SetLength(Base, ComponentCount);
  NPads := 0;
  for I := 0 to ComponentCount - 1 do
  begin
    Base[I] := NPads;
    Inc(NPads, Component(I).PadCount);
  end;
  { nos: pads primeiro, depois trilhas }
  SetLength(Parent, NPads + TrackCount);
  for I := 0 to High(Parent) do Parent[I] := I;
  for K := 0 to High(Wires) do
    if (Wires[K].A.Comp >= 0) and (Wires[K].A.Comp < ComponentCount) and
       (Wires[K].B.Comp >= 0) and (Wires[K].B.Comp < ComponentCount) then
      Union(PadIndex(Wires[K].A.Comp, Wires[K].A.Pad), PadIndex(Wires[K].B.Comp, Wires[K].B.Pad));
  for T := 0 to TrackCount - 1 do
  begin
    Trk := Track(T);
    for I := 0 to ComponentCount - 1 do
      for J := 0 to Component(I).PadCount - 1 do
        if TouchesPad(Trk, I, J) then Union(NPads + T, PadIndex(I, J));
    for K := T + 1 to TrackCount - 1 do
    begin
      Other := Track(K);
      if TracksTouch(Trk, Other) then Union(NPads + T, NPads + K);
    end;
  end;
  { numera as raizes: so redes com mais de um no recebem numero >= 0 }
  SetLength(Map, System.Length(Parent));
  for I := 0 to High(Map) do Map[I] := 0;
  for I := 0 to High(Parent) do Inc(Map[Find(I)]);
  FNetCount := 0;
  for I := 0 to High(Map) do
    if Map[I] > 1 then
    begin
      Map[I] := -(FNetCount + 2);   { marca com o numero da rede }
      Inc(FNetCount);
    end
    else Map[I] := 0;
  SetLength(FPadNet, ComponentCount + 1);
  for I := 0 to ComponentCount - 1 do
  begin
    SetLength(FPadNet[I], Component(I).PadCount);
    for J := 0 to Component(I).PadCount - 1 do
    begin
      Root := Find(PadIndex(I, J));
      if Map[Root] < 0 then FPadNet[I][J] := -Map[Root] - 2 else FPadNet[I][J] := -1;
    end;
  end;
  { trilhas: ultima linha }
  SetLength(FPadNet[ComponentCount], TrackCount);
  for T := 0 to TrackCount - 1 do
  begin
    Root := Find(NPads + T);
    if Map[Root] < 0 then FPadNet[ComponentCount][T] := -Map[Root] - 2
    else FPadNet[ComponentCount][T] := -1;
  end;
  FNetsValid := True;
end;

function TMPDocument.NetCount: Integer;
begin
  if not FNetsValid then ComputeNets;
  Result := FNetCount;
end;

function TMPDocument.PadNet(C, P: Integer): Integer;
begin
  if not FNetsValid then ComputeNets;
  Result := FPadNet[C][P];
end;

function TMPDocument.TrackNet(I: Integer): Integer;
begin
  if not FNetsValid then ComputeNets;
  Result := FPadNet[ComponentCount][I];
end;

function TMPDocument.AreaNet(I: Integer): Integer;
var
  A: TMPArea;
begin
  A := Area(I);
  if (A.NetComp < 0) or (A.NetComp >= ComponentCount) or (A.NetPad < 0) or
     (A.NetPad >= Component(A.NetComp).PadCount) then Exit(-1);
  Result := PadNet(A.NetComp, A.NetPad);
end;

function TMPDocument.PadInArea(AreaIndex, C, P: Integer): Boolean;
var
  A: TMPArea;
  N: Integer;
begin
  A := Area(AreaIndex);
  if (A.NetComp = C) and (A.NetPad = P) then Exit(True);
  N := AreaNet(AreaIndex);
  Result := (N >= 0) and (PadNet(C, P) = N);
end;

function TMPDocument.TrackInArea(AreaIndex, T: Integer): Boolean;
var
  N: Integer;
begin
  N := AreaNet(AreaIndex);
  Result := (N >= 0) and (TrackNet(T) = N);
end;

function TMPDocument.Bounds: TMPRect;
begin
  Result := MPEmptyRect;
  MPRectInclude(Result, 0, 0);
  MPRectInclude(Result, BoardW, BoardH);
end;

function TMPDocument.ValidateBoard(Errors: TStrings): Boolean;
var
  N, I, J: Integer;
  B: TMPRect;
  C: TMPComponent;
  P: TMPPoint;
  W, H: Double;
begin
  N := Errors.Count;
  if (BoardW < 5) or (BoardH < 5) or (BoardW > 1000) or (BoardH > 1000) then
    Errors.Add('Placa: tamanho deve ficar entre 5 e 1000 mm');
  if (TrackWidth <= 0) or (Clearance <= 0) then Errors.Add('Placa: trilha e folga devem ser positivas');
  for I := 0 to ComponentCount - 1 do
  begin
    C := Component(I);
    for J := 0 to C.PadCount - 1 do
    begin
      P := C.PadPos(J);
      C.PadSize(J, W, H);
      if (P.X - W / 2 < -1e-6) or (P.Y - H / 2 < -1e-6) or
         (P.X + W / 2 > BoardW + 1e-6) or (P.Y + H / 2 > BoardH + 1e-6) then
      begin
        Errors.Add(C.Ref + ': pad fora da placa');
        Break;
      end;
    end;
  end;
  for I := 0 to TrackCount - 1 do
  begin
    B := MPEmptyRect;
    for J := 0 to High(Track(I).Points) do MPRectInclude(B, Track(I).Points[J].X, Track(I).Points[J].Y);
    if B.Valid and ((B.MinX < -1e-6) or (B.MinY < -1e-6) or (B.MaxX > BoardW + 1e-6) or (B.MaxY > BoardH + 1e-6)) then
      Errors.Add(Format('Trilha %d fora da placa', [I + 1]));
  end;
  Result := Errors.Count = N;
end;

{ ---- arquivo ---- }

function PointsToJSON(const P: TMPPoints): TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := 0 to High(P) do Result.Add(TJSONArray.Create([P[I].X, P[I].Y]));
end;

function PointsFromJSON(A: TJSONArray): TMPPoints;
var
  I: Integer;
begin
  Result := nil;
  if A = nil then Exit;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
  begin
    Result[I].X := A.Arrays[I].Floats[0];
    Result[I].Y := A.Arrays[I].Floats[1];
  end;
end;

function TMPDocument.ToJSON: string;
var
  Root, O: TJSONObject;
  A: TJSONArray;
  I: Integer;
  C: TMPComponent;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', 'makepcb');
    Root.Add('version', 1);
    O := TJSONObject.Create;
    O.Add('name', Name);
    O.Add('width', BoardW);
    O.Add('height', BoardH);
    O.Add('double_sided', DoubleSided);
    O.Add('track_width', TrackWidth);
    O.Add('clearance', Clearance);
    O.Add('grid', Grid);
    Root.Add('board', O);
    A := TJSONArray.Create;
    for I := 0 to ComponentCount - 1 do
    begin
      C := Component(I);
      O := TJSONObject.Create;
      O.Add('footprint', C.Footprint.Name);
      O.Add('ref', C.Ref);
      O.Add('value', C.Value);
      O.Add('x', C.X);
      O.Add('y', C.Y);
      O.Add('rotation', C.Rotation);
      A.Add(O);
    end;
    Root.Add('components', A);
    A := TJSONArray.Create;
    for I := 0 to TrackCount - 1 do
    begin
      O := TJSONObject.Create;
      O.Add('layer', Ord(Track(I).Layer));
      O.Add('width', Track(I).Width);
      O.Add('points', PointsToJSON(Track(I).Points));
      A.Add(O);
    end;
    Root.Add('tracks', A);
    A := TJSONArray.Create;
    for I := 0 to High(Wires) do
      A.Add(TJSONArray.Create([Wires[I].A.Comp, Wires[I].A.Pad, Wires[I].B.Comp, Wires[I].B.Pad]));
    Root.Add('wires', A);
    A := TJSONArray.Create;
    for I := 0 to AreaCount - 1 do
    begin
      O := TJSONObject.Create;
      O.Add('layer', Ord(Area(I).Layer));
      O.Add('clearance', Area(I).Clearance);
      O.Add('net_comp', Area(I).NetComp);
      O.Add('net_pad', Area(I).NetPad);
      O.Add('points', PointsToJSON(Area(I).Points));
      A.Add(O);
    end;
    Root.Add('areas', A);
    A := TJSONArray.Create;
    for I := 0 to TextCount - 1 do
    begin
      O := TJSONObject.Create;
      O.Add('text', Text(I).Text);
      O.Add('x', Text(I).X);
      O.Add('y', Text(I).Y);
      O.Add('height', Text(I).Height);
      O.Add('layer', Ord(Text(I).Layer));
      A.Add(O);
    end;
    Root.Add('texts', A);
    Result := Root.FormatJSON;
  finally
    Root.Free;
  end;
end;

procedure TMPDocument.FromJSON(const S: string; Resolver: TMPFootprintResolver);
var
  D: TJSONData;
  Root, O: TJSONObject;
  A: TJSONArray;
  I: Integer;
  FP: TMPFootprint;
  C: TMPComponent;
  T: TMPTrack;
  Ar: TMPArea;
  W: TJSONArray;

  function LayerOf(V: Integer): TMPLayer;
  begin
    Result := TMPLayer(EnsureRange(V, 0, Ord(High(TMPLayer))));
  end;

begin
  D := GetJSON(S);
  try
    if not (D is TJSONObject) then raise Exception.Create('Arquivo MakePCB invalido');
    Root := TJSONObject(D);
    if Root.Get('format', '') <> 'makepcb' then raise Exception.Create('Arquivo nao e do MakePCB');
    Clear;
    O := Root.Get('board', TJSONObject(nil));
    if O <> nil then
    begin
      Name := O.Get('name', Name);
      BoardW := O.Get('width', BoardW);
      BoardH := O.Get('height', BoardH);
      DoubleSided := O.Get('double_sided', False);
      TrackWidth := O.Get('track_width', TrackWidth);
      Clearance := O.Get('clearance', Clearance);
      Grid := O.Get('grid', Grid);
    end;
    A := Root.Get('components', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        FP := Resolver(O.Get('footprint', ''));
        if FP = nil then raise Exception.Create('Footprint desconhecido: ' + O.Get('footprint', ''));
        C := TMPComponent.Create;
        C.Footprint := FP;
        C.Ref := O.Get('ref', '');
        C.Value := O.Get('value', '');
        C.X := O.Get('x', 0.0);
        C.Y := O.Get('y', 0.0);
        C.Rotation := O.Get('rotation', 0);
        FComponents.Add(C);
      end;
    A := Root.Get('tracks', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        T := AddTrack(LayerOf(O.Get('layer', 0)), O.Get('width', TrackWidth));
        T.Points := PointsFromJSON(O.Get('points', TJSONArray(nil)));
      end;
    A := Root.Get('wires', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        W := A.Arrays[I];
        AddWire(W.Integers[0], W.Integers[1], W.Integers[2], W.Integers[3]);
      end;
    A := Root.Get('areas', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        Ar := AddArea(LayerOf(O.Get('layer', 0)));
        Ar.Clearance := O.Get('clearance', Ar.Clearance);
        Ar.NetComp := O.Get('net_comp', -1);
        Ar.NetPad := O.Get('net_pad', -1);
        Ar.Points := PointsFromJSON(O.Get('points', TJSONArray(nil)));
      end;
    A := Root.Get('texts', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        AddText(O.Get('text', ''), O.Get('x', 0.0), O.Get('y', 0.0), O.Get('height', 2.0),
          LayerOf(O.Get('layer', Ord(mlTopSilk))));
      end;
    Changed;
  finally
    D.Free;
  end;
end;

procedure TMPDocument.SaveToFile(const FileName: string);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ToJSON;
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

procedure TMPDocument.LoadFromFile(const FileName: string; Resolver: TMPFootprintResolver);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    FromJSON(SL.Text, Resolver);
  finally
    SL.Free;
  end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
