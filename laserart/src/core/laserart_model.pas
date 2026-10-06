unit laserart_model;

{ Modelo do LaserArt: camadas (cortes), objetos graficos e documento.

  Coordenadas em milimetros, sistema da maquina: origem no canto inferior
  esquerdo da mesa, X para a direita e Y para cima.

  Cada objeto pertence a uma camada (0..29). A camada define COMO o laser
  processa o objeto (linha, preenchimento ou imagem) e com quais parametros.
  Seguranca: camadas novas comecam com velocidade e potencia zeradas; o
  G-code so e gerado depois que o usuario informa valores calibrados. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, fpjson, jsonparser, multisuite_numfmt;

const
  LA_LAYER_COUNT = 30;
  LA_FILE_EXT = '.lart';

type
  TLAPoint = record
    X, Y: Double;
  end;

  TLAPath = record
    Pts: array of TLAPoint;
    Closed: Boolean;
  end;

  TLAPaths = array of TLAPath;

  TLALayerMode = (lmLine, lmFill, lmImage);
  TLADither = (ldThreshold, ldFloyd, ldJarvis, ldGrayscale);
  TLAShapeKind = (skRect, skEllipse, skPolygon, skPath, skText, skImage);
  TLAStartFrom = (sfAbsolute, sfUserOrigin, sfWorkZero);

  TLALayer = class
  public
    Index: Integer;
    Mode: TLALayerMode;
    Speed: Double;       { mm/min }
    PowerMax: Double;    { % }
    PowerMin: Double;    { % (cinza em imagens; M4 dinamico) }
    Passes: Integer;
    Interval: Double;    { mm entre linhas (preenchimento / imagem) }
    AirAssist: Boolean;
    Output: Boolean;
    Show: Boolean;
    constructor Create(AIndex: Integer);
    procedure Assign(Src: TLALayer);
    function Calibrated: Boolean;
    function Caption: string;   { "C02" }
  end;

  TLAShape = class
  public
    Kind: TLAShapeKind;
    Layer: Integer;
    Name: string;
    X, Y, W, H: Double;          { caixa (antes da rotacao), canto inferior esquerdo }
    Angle: Double;               { graus, anti-horario, em torno do centro }
    MirrorX, MirrorY: Boolean;
    Locked: Boolean;
    Sides: Integer;              { poligono }
    CornerRadius: Double;        { retangulo }
    Local: TLAPaths;             { caminho/texto: geometria propria }
    LocalW, LocalH: Double;      { tamanho da geometria propria }
    Text, FontName: string;
    Bold, Italic: Boolean;
    ImageFile: string;
    Dither: TLADither;
    Brightness, Contrast: Integer; { -100..100 }
    Invert: Boolean;
    { dados de execucao (nao salvos) }
    Preview: TObject;            { cache de bitmap do editor }
    PreviewKey: string;
    constructor Create(AKind: TLAShapeKind);
    destructor Destroy; override;
    procedure Assign(Src: TLAShape);
    function Clone: TLAShape;
    procedure InvalidatePreview;
    function KindName: string;
  end;

  TLADocument = class
  private
    FShapes: TList;
    function GetLayer(I: Integer): TLALayer;
  public
    Name, FileName: string;
    BedW, BedH: Double;
    Layers: array[0..LA_LAYER_COUNT - 1] of TLALayer;
    LayerOrder: array of Integer;   { ordem de execucao das camadas em uso }
    StartFrom: TLAStartFrom;
    JobOrigin: Integer;             { 0..8: linha a linha a partir do canto superior esquerdo }
    UserOriginX, UserOriginY: Double;
    SMax: Double;                   { $30 do GRBL }
    UseM3: Boolean;                 { False = M4 (potencia dinamica) }
    RapidSpeed: Double;             { estimativa de tempo }
    Optimize: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function Shape(I: Integer): TLAShape;
    function Add(S: TLAShape): TLAShape;
    procedure Insert(Index: Integer; S: TLAShape);
    procedure Remove(S: TLAShape);
    function IndexOf(S: TLAShape): Integer;
    procedure MoveShape(S: TLAShape; NewIndex: Integer);
    { camadas }
    procedure EnsureLayerInOrder(L: Integer);
    procedure SyncLayerOrder;
    function LayerUsed(L: Integer): Boolean;
    procedure MoveLayer(L, Delta: Integer);
    property Layer[I: Integer]: TLALayer read GetLayer;
    { persistencia }
    function ToJSON: string;
    procedure FromJSON(const S: string);
    procedure SaveToFile(const FN: string);
    procedure LoadFromFile(const FN: string);
  end;

function LAPoint(X, Y: Double): TLAPoint; inline;
function LayerColor(I: Integer): TColor;
function LayerModeName(M: TLALayerMode): string;
function DitherName(D: TLADither): string;

implementation

const
  { Paleta de camadas (estilo LightBurn 00..29) }
  PALETTE: array[0..LA_LAYER_COUNT - 1] of array[0..2] of Byte = (
    (0, 0, 0), (0, 0, 255), (255, 0, 0), (0, 200, 0), (208, 208, 0),
    (255, 128, 0), (0, 200, 200), (255, 0, 255), (160, 160, 160), (0, 0, 160),
    (160, 0, 0), (0, 128, 0), (128, 128, 0), (192, 96, 0), (0, 128, 255),
    (160, 0, 160), (96, 96, 96), (125, 135, 185), (187, 119, 132), (142, 6, 59),
    (211, 63, 106), (110, 200, 120), (240, 170, 140), (230, 120, 170), (120, 60, 160),
    (180, 100, 40), (0, 96, 96), (16, 72, 88), (200, 160, 40), (90, 160, 210));

function LAPoint(X, Y: Double): TLAPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function LayerColor(I: Integer): TColor;
begin
  I := EnsureRange(I, 0, LA_LAYER_COUNT - 1);
  Result := RGBToColor(PALETTE[I][0], PALETTE[I][1], PALETTE[I][2]);
end;

function LayerModeName(M: TLALayerMode): string;
begin
  case M of
    lmLine:  Result := 'Linha';
    lmFill:  Result := 'Preencher';
  else
    Result := 'Imagem';
  end;
end;

function DitherName(D: TLADither): string;
begin
  case D of
    ldThreshold: Result := 'Limiar';
    ldFloyd:     Result := 'Floyd-Steinberg';
    ldJarvis:    Result := 'Jarvis';
  else
    Result := 'Tons de cinza';
  end;
end;

{ ---------------------------------------------------------------------------- }

constructor TLALayer.Create(AIndex: Integer);
begin
  inherited Create;
  Index := AIndex;
  Mode := lmLine;
  Speed := 0;
  PowerMax := 0;
  PowerMin := 0;
  Passes := 1;
  Interval := 0.1;
  AirAssist := False;
  Output := True;
  Show := True;
end;

procedure TLALayer.Assign(Src: TLALayer);
begin
  Mode := Src.Mode;
  Speed := Src.Speed;
  PowerMax := Src.PowerMax;
  PowerMin := Src.PowerMin;
  Passes := Src.Passes;
  Interval := Src.Interval;
  AirAssist := Src.AirAssist;
  Output := Src.Output;
  Show := Src.Show;
end;

function TLALayer.Calibrated: Boolean;
begin
  Result := (Speed > 0) and (PowerMax > 0) and (Passes >= 1) and
    ((Mode = lmLine) or (Interval > 0));
end;

function TLALayer.Caption: string;
begin
  Result := Format('C%.2d', [Index]);
end;

{ ---------------------------------------------------------------------------- }

constructor TLAShape.Create(AKind: TLAShapeKind);
begin
  inherited Create;
  Kind := AKind;
  Sides := 6;
  FontName := 'Arial';
  Dither := ldFloyd;
  W := 20;
  H := 20;
end;

destructor TLAShape.Destroy;
begin
  InvalidatePreview;
  inherited Destroy;
end;

procedure TLAShape.InvalidatePreview;
begin
  FreeAndNil(Preview);
  PreviewKey := '';
end;

procedure TLAShape.Assign(Src: TLAShape);
var
  I: Integer;
begin
  Kind := Src.Kind;
  Layer := Src.Layer;
  Name := Src.Name;
  X := Src.X; Y := Src.Y; W := Src.W; H := Src.H;
  Angle := Src.Angle;
  MirrorX := Src.MirrorX; MirrorY := Src.MirrorY;
  Locked := Src.Locked;
  Sides := Src.Sides;
  CornerRadius := Src.CornerRadius;
  SetLength(Local, Length(Src.Local));
  for I := 0 to High(Src.Local) do
  begin
    Local[I].Closed := Src.Local[I].Closed;
    Local[I].Pts := Copy(Src.Local[I].Pts);
  end;
  LocalW := Src.LocalW; LocalH := Src.LocalH;
  Text := Src.Text; FontName := Src.FontName;
  Bold := Src.Bold; Italic := Src.Italic;
  ImageFile := Src.ImageFile;
  Dither := Src.Dither;
  Brightness := Src.Brightness; Contrast := Src.Contrast;
  Invert := Src.Invert;
  InvalidatePreview;
end;

function TLAShape.Clone: TLAShape;
begin
  Result := TLAShape.Create(Kind);
  Result.Assign(Self);
end;

function TLAShape.KindName: string;
begin
  case Kind of
    skRect:    Result := 'Retangulo';
    skEllipse: Result := 'Elipse';
    skPolygon: Result := 'Poligono';
    skPath:    Result := 'Vetor';
    skText:    Result := 'Texto';
  else
    Result := 'Imagem';
  end;
end;

{ ---------------------------------------------------------------------------- }

constructor TLADocument.Create;
var
  I: Integer;
begin
  inherited Create;
  FShapes := TList.Create;
  for I := 0 to LA_LAYER_COUNT - 1 do
    Layers[I] := TLALayer.Create(I);
  Clear;
end;

destructor TLADocument.Destroy;
var
  I: Integer;
begin
  Clear;
  FShapes.Free;
  for I := 0 to LA_LAYER_COUNT - 1 do
    Layers[I].Free;
  inherited Destroy;
end;

procedure TLADocument.Clear;
var
  I: Integer;
  Fresh: TLALayer;
begin
  for I := FShapes.Count - 1 downto 0 do
    TObject(FShapes[I]).Free;
  FShapes.Clear;
  for I := 0 to LA_LAYER_COUNT - 1 do
  begin
    Fresh := TLALayer.Create(I);
    Layers[I].Assign(Fresh);
    Fresh.Free;
  end;
  SetLength(LayerOrder, 0);
  Name := 'Nova arte';
  FileName := '';
  BedW := 400;
  BedH := 400;
  StartFrom := sfAbsolute;
  JobOrigin := 6;
  UserOriginX := 0;
  UserOriginY := 0;
  SMax := 1000;
  UseM3 := False;
  RapidSpeed := 6000;
  Optimize := True;
end;

function TLADocument.GetLayer(I: Integer): TLALayer;
begin
  Result := Layers[EnsureRange(I, 0, LA_LAYER_COUNT - 1)];
end;

function TLADocument.Count: Integer;
begin
  Result := FShapes.Count;
end;

function TLADocument.Shape(I: Integer): TLAShape;
begin
  Result := TLAShape(FShapes[I]);
end;

function TLADocument.Add(S: TLAShape): TLAShape;
begin
  FShapes.Add(S);
  EnsureLayerInOrder(S.Layer);
  Result := S;
end;

procedure TLADocument.Insert(Index: Integer; S: TLAShape);
begin
  FShapes.Insert(EnsureRange(Index, 0, FShapes.Count), S);
  EnsureLayerInOrder(S.Layer);
end;

procedure TLADocument.Remove(S: TLAShape);
begin
  FShapes.Remove(S);
  S.Free;
end;

function TLADocument.IndexOf(S: TLAShape): Integer;
begin
  Result := FShapes.IndexOf(S);
end;

procedure TLADocument.MoveShape(S: TLAShape; NewIndex: Integer);
var
  I: Integer;
begin
  I := FShapes.IndexOf(S);
  if I < 0 then Exit;
  FShapes.Move(I, EnsureRange(NewIndex, 0, FShapes.Count - 1));
end;

function TLADocument.LayerUsed(L: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to FShapes.Count - 1 do
    if TLAShape(FShapes[I]).Layer = L then
      Exit(True);
  Result := False;
end;

procedure TLADocument.EnsureLayerInOrder(L: Integer);
var
  I: Integer;
begin
  for I := 0 to High(LayerOrder) do
    if LayerOrder[I] = L then
      Exit;
  SetLength(LayerOrder, Length(LayerOrder) + 1);
  LayerOrder[High(LayerOrder)] := L;
end;

{ Remove da ordem as camadas sem objetos e acrescenta as que faltam }
procedure TLADocument.SyncLayerOrder;
var
  I, N: Integer;
  Keep: array of Integer;
begin
  SetLength(Keep, 0);
  for I := 0 to High(LayerOrder) do
    if LayerUsed(LayerOrder[I]) then
    begin
      N := Length(Keep);
      SetLength(Keep, N + 1);
      Keep[N] := LayerOrder[I];
    end;
  LayerOrder := Keep;
  for I := 0 to FShapes.Count - 1 do
    EnsureLayerInOrder(TLAShape(FShapes[I]).Layer);
end;

procedure TLADocument.MoveLayer(L, Delta: Integer);
var
  I, J, T: Integer;
begin
  for I := 0 to High(LayerOrder) do
    if LayerOrder[I] = L then
    begin
      J := I + Delta;
      if (J < 0) or (J > High(LayerOrder)) then Exit;
      T := LayerOrder[I];
      LayerOrder[I] := LayerOrder[J];
      LayerOrder[J] := T;
      Exit;
    end;
end;

{ ---------------------------------------------------------------------------- }
{ JSON                                                                         }

function PathsToJSON(const P: TLAPaths): TJSONArray;
var
  I, J: Integer;
  O: TJSONObject;
  A: TJSONArray;
begin
  Result := TJSONArray.Create;
  for I := 0 to High(P) do
  begin
    O := TJSONObject.Create;
    O.Add('closed', P[I].Closed);
    A := TJSONArray.Create;
    for J := 0 to High(P[I].Pts) do
    begin
      A.Add(RoundTo(P[I].Pts[J].X, -4));
      A.Add(RoundTo(P[I].Pts[J].Y, -4));
    end;
    O.Add('pts', A);
    Result.Add(O);
  end;
end;

function PathsFromJSON(A: TJSONArray): TLAPaths;
var
  I, J: Integer;
  O: TJSONObject;
  Pts: TJSONArray;
begin
  SetLength(Result, 0);
  if A = nil then Exit;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
  begin
    O := A.Objects[I];
    Result[I].Closed := O.Get('closed', False);
    Pts := O.Get('pts', TJSONArray(nil));
    if Pts = nil then Continue;
    SetLength(Result[I].Pts, Pts.Count div 2);
    for J := 0 to Pts.Count div 2 - 1 do
    begin
      Result[I].Pts[J].X := Pts.Floats[J * 2];
      Result[I].Pts[J].Y := Pts.Floats[J * 2 + 1];
    end;
  end;
end;

function TLADocument.ToJSON: string;
var
  Root, O: TJSONObject;
  A: TJSONArray;
  I: Integer;
  S: TLAShape;
  L: TLALayer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', 'laserart');
    Root.Add('version', 1);
    Root.Add('name', Name);
    Root.Add('bed_w', BedW);
    Root.Add('bed_h', BedH);
    Root.Add('start_from', Ord(StartFrom));
    Root.Add('job_origin', JobOrigin);
    Root.Add('user_origin_x', UserOriginX);
    Root.Add('user_origin_y', UserOriginY);
    Root.Add('s_max', SMax);
    Root.Add('use_m3', UseM3);
    Root.Add('rapid_speed', RapidSpeed);
    Root.Add('optimize', Optimize);

    A := TJSONArray.Create;
    for I := 0 to High(LayerOrder) do
      A.Add(LayerOrder[I]);
    Root.Add('layer_order', A);

    A := TJSONArray.Create;
    for I := 0 to LA_LAYER_COUNT - 1 do
    begin
      L := Layers[I];
      O := TJSONObject.Create;
      O.Add('index', I);
      O.Add('mode', Ord(L.Mode));
      O.Add('speed', L.Speed);
      O.Add('power_max', L.PowerMax);
      O.Add('power_min', L.PowerMin);
      O.Add('passes', L.Passes);
      O.Add('interval', L.Interval);
      O.Add('air', L.AirAssist);
      O.Add('output', L.Output);
      O.Add('show', L.Show);
      A.Add(O);
    end;
    Root.Add('layers', A);

    A := TJSONArray.Create;
    for I := 0 to Count - 1 do
    begin
      S := Shape(I);
      O := TJSONObject.Create;
      O.Add('kind', Ord(S.Kind));
      O.Add('layer', S.Layer);
      O.Add('name', S.Name);
      O.Add('x', S.X); O.Add('y', S.Y); O.Add('w', S.W); O.Add('h', S.H);
      O.Add('angle', S.Angle);
      O.Add('mirror_x', S.MirrorX); O.Add('mirror_y', S.MirrorY);
      O.Add('locked', S.Locked);
      O.Add('sides', S.Sides);
      O.Add('corner', S.CornerRadius);
      if Length(S.Local) > 0 then
      begin
        O.Add('local', PathsToJSON(S.Local));
        O.Add('local_w', S.LocalW);
        O.Add('local_h', S.LocalH);
      end;
      if S.Kind = skText then
      begin
        O.Add('text', S.Text); O.Add('font', S.FontName);
        O.Add('bold', S.Bold); O.Add('italic', S.Italic);
      end;
      if S.Kind = skImage then
      begin
        O.Add('image', S.ImageFile);
        O.Add('dither', Ord(S.Dither));
        O.Add('brightness', S.Brightness);
        O.Add('contrast', S.Contrast);
        O.Add('invert', S.Invert);
      end;
      A.Add(O);
    end;
    Root.Add('shapes', A);
    Result := Root.FormatJSON;
  finally
    Root.Free;
  end;
end;

procedure TLADocument.FromJSON(const S: string);
var
  D: TJSONData;
  Root, O: TJSONObject;
  A: TJSONArray;
  I, Idx: Integer;
  Sh: TLAShape;
  L: TLALayer;
begin
  D := GetJSON(S);
  try
    if not (D is TJSONObject) then
      raise Exception.Create('Arquivo LaserArt invalido');
    Root := TJSONObject(D);
    if Root.Get('format', '') <> 'laserart' then
      raise Exception.Create('Arquivo nao e um documento LaserArt');
    Clear;
    Name := Root.Get('name', 'Nova arte');
    BedW := Root.Get('bed_w', 400.0);
    BedH := Root.Get('bed_h', 400.0);
    StartFrom := TLAStartFrom(EnsureRange(Root.Get('start_from', 0), 0, Ord(High(TLAStartFrom))));
    JobOrigin := EnsureRange(Root.Get('job_origin', 6), 0, 8);
    UserOriginX := Root.Get('user_origin_x', 0.0);
    UserOriginY := Root.Get('user_origin_y', 0.0);
    SMax := Root.Get('s_max', 1000.0);
    UseM3 := Root.Get('use_m3', False);
    RapidSpeed := Root.Get('rapid_speed', 6000.0);
    Optimize := Root.Get('optimize', True);

    A := Root.Get('layers', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        Idx := O.Get('index', -1);
        if (Idx < 0) or (Idx >= LA_LAYER_COUNT) then Continue;
        L := Layers[Idx];
        L.Mode := TLALayerMode(EnsureRange(O.Get('mode', 0), 0, Ord(High(TLALayerMode))));
        L.Speed := O.Get('speed', 0.0);
        L.PowerMax := O.Get('power_max', 0.0);
        L.PowerMin := O.Get('power_min', 0.0);
        L.Passes := Max(1, O.Get('passes', 1));
        L.Interval := O.Get('interval', 0.1);
        L.AirAssist := O.Get('air', False);
        L.Output := O.Get('output', True);
        L.Show := O.Get('show', True);
      end;

    A := Root.Get('shapes', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        Sh := TLAShape.Create(TLAShapeKind(EnsureRange(O.Get('kind', 0), 0, Ord(High(TLAShapeKind)))));
        Sh.Layer := EnsureRange(O.Get('layer', 0), 0, LA_LAYER_COUNT - 1);
        Sh.Name := O.Get('name', '');
        Sh.X := O.Get('x', 0.0); Sh.Y := O.Get('y', 0.0);
        Sh.W := O.Get('w', 10.0); Sh.H := O.Get('h', 10.0);
        Sh.Angle := O.Get('angle', 0.0);
        Sh.MirrorX := O.Get('mirror_x', False); Sh.MirrorY := O.Get('mirror_y', False);
        Sh.Locked := O.Get('locked', False);
        Sh.Sides := O.Get('sides', 6);
        Sh.CornerRadius := O.Get('corner', 0.0);
        Sh.Local := PathsFromJSON(O.Get('local', TJSONArray(nil)));
        Sh.LocalW := O.Get('local_w', 0.0);
        Sh.LocalH := O.Get('local_h', 0.0);
        Sh.Text := O.Get('text', '');
        Sh.FontName := O.Get('font', 'Arial');
        Sh.Bold := O.Get('bold', False);
        Sh.Italic := O.Get('italic', False);
        Sh.ImageFile := O.Get('image', '');
        Sh.Dither := TLADither(EnsureRange(O.Get('dither', 1), 0, Ord(High(TLADither))));
        Sh.Brightness := O.Get('brightness', 0);
        Sh.Contrast := O.Get('contrast', 0);
        Sh.Invert := O.Get('invert', False);
        FShapes.Add(Sh);
      end;

    SetLength(LayerOrder, 0);
    A := Root.Get('layer_order', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
        EnsureLayerInOrder(EnsureRange(A.Integers[I], 0, LA_LAYER_COUNT - 1));
    SyncLayerOrder;
  finally
    D.Free;
  end;
end;

procedure TLADocument.SaveToFile(const FN: string);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ToJSON;
    SL.SaveToFile(FN);
    FileName := FN;
  finally
    SL.Free;
  end;
end;

procedure TLADocument.LoadFromFile(const FN: string);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FN);
    FromJSON(SL.Text);
    FileName := FN;
  finally
    SL.Free;
  end;
end;

end.
