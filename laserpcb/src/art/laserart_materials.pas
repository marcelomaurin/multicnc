unit laserart_materials;

{ Biblioteca de materiais do LaserArt.

  Cada preset guarda os parametros de uma camada (modo, velocidade,
  potencia, passadas, intervalo, ar) para um material/espessura.
  Arquivo JSON por usuario: <config>/laserart_materials.json.

  A biblioteca comeca vazia: valores de potencia/velocidade dependem da
  maquina e devem vir de teste de material (Teste de material). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, laserart_model;

type
  TLAMaterial = class
  public
    Name, Material, Notes: string;
    Thickness: Double;
    Mode: TLALayerMode;
    Speed, PowerMax, PowerMin, Interval: Double;
    Passes: Integer;
    AirAssist: Boolean;
    procedure FromLayer(L: TLALayer);
    procedure ToLayer(L: TLALayer);
    function Summary: string;
  end;

  TLAMaterialLibrary = class
  private
    FItems: TList;
    FFileName: string;
  public
    constructor Create(const AFileName: string = '');
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function Item(I: Integer): TLAMaterial;
    function Add(const AName: string): TLAMaterial;
    procedure Delete(I: Integer);
    procedure Load;
    procedure Save;
    property FileName: string read FFileName;
  end;

function DefaultMaterialFile: string;

implementation

function DefaultMaterialFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'laserart_materials.json';
end;

procedure TLAMaterial.FromLayer(L: TLALayer);
begin
  Mode := L.Mode;
  Speed := L.Speed;
  PowerMax := L.PowerMax;
  PowerMin := L.PowerMin;
  Passes := L.Passes;
  Interval := L.Interval;
  AirAssist := L.AirAssist;
end;

procedure TLAMaterial.ToLayer(L: TLALayer);
begin
  L.Mode := Mode;
  L.Speed := Speed;
  L.PowerMax := PowerMax;
  L.PowerMin := PowerMin;
  L.Passes := Max(1, Passes);
  L.Interval := Interval;
  L.AirAssist := AirAssist;
end;

function TLAMaterial.Summary: string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := Format('%s | %.0f mm/min | %.0f%% | %dx', [LayerModeName(Mode), Speed, PowerMax, Passes], FS);
  if Mode <> lmLine then
    Result := Result + Format(' | %.3f mm', [Interval], FS);
end;

constructor TLAMaterialLibrary.Create(const AFileName: string);
begin
  inherited Create;
  FItems := TList.Create;
  if AFileName = '' then
    FFileName := DefaultMaterialFile
  else
    FFileName := AFileName;
end;

destructor TLAMaterialLibrary.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TLAMaterialLibrary.Clear;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    TObject(FItems[I]).Free;
  FItems.Clear;
end;

function TLAMaterialLibrary.Count: Integer;
begin
  Result := FItems.Count;
end;

function TLAMaterialLibrary.Item(I: Integer): TLAMaterial;
begin
  Result := TLAMaterial(FItems[I]);
end;

function TLAMaterialLibrary.Add(const AName: string): TLAMaterial;
begin
  Result := TLAMaterial.Create;
  Result.Name := AName;
  Result.Passes := 1;
  Result.Interval := 0.1;
  FItems.Add(Result);
end;

procedure TLAMaterialLibrary.Delete(I: Integer);
begin
  TObject(FItems[I]).Free;
  FItems.Delete(I);
end;

procedure TLAMaterialLibrary.Load;
var
  SL: TStringList;
  D: TJSONData;
  A: TJSONArray;
  O: TJSONObject;
  I: Integer;
  M: TLAMaterial;
begin
  Clear;
  if not FileExists(FFileName) then Exit;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FFileName);
    D := GetJSON(SL.Text);
    try
      if not (D is TJSONObject) then Exit;
      A := TJSONObject(D).Get('materials', TJSONArray(nil));
      if A = nil then Exit;
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        M := Add(O.Get('name', 'Material'));
        M.Material := O.Get('material', '');
        M.Notes := O.Get('notes', '');
        M.Thickness := O.Get('thickness', 0.0);
        M.Mode := TLALayerMode(EnsureRange(O.Get('mode', 0), 0, Ord(High(TLALayerMode))));
        M.Speed := O.Get('speed', 0.0);
        M.PowerMax := O.Get('power_max', 0.0);
        M.PowerMin := O.Get('power_min', 0.0);
        M.Interval := O.Get('interval', 0.1);
        M.Passes := Max(1, O.Get('passes', 1));
        M.AirAssist := O.Get('air', False);
      end;
    finally
      D.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TLAMaterialLibrary.Save;
var
  Root, O: TJSONObject;
  A: TJSONArray;
  I: Integer;
  M: TLAMaterial;
  SL: TStringList;
begin
  ForceDirectories(ExtractFileDir(FFileName));
  Root := TJSONObject.Create;
  SL := TStringList.Create;
  try
    A := TJSONArray.Create;
    for I := 0 to Count - 1 do
    begin
      M := Item(I);
      O := TJSONObject.Create;
      O.Add('name', M.Name);
      O.Add('material', M.Material);
      O.Add('notes', M.Notes);
      O.Add('thickness', M.Thickness);
      O.Add('mode', Ord(M.Mode));
      O.Add('speed', M.Speed);
      O.Add('power_max', M.PowerMax);
      O.Add('power_min', M.PowerMin);
      O.Add('interval', M.Interval);
      O.Add('passes', M.Passes);
      O.Add('air', M.AirAssist);
      A.Add(O);
    end;
    Root.Add('format', 'laserart-materials');
    Root.Add('materials', A);
    SL.Text := Root.FormatJSON;
    SL.SaveToFile(FFileName);
  finally
    SL.Free;
    Root.Free;
  end;
end;

end.
