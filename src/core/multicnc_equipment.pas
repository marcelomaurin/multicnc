unit multicnc_equipment;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, fpjson, jsonparser, multicnc_types;

type
  TEquipmentProfile = record
    Name: string;
    MachineType: TMachineType;
    ProtocolIndex, ConnectionMode: Integer;
    Brand, Model, SerialPort, Host: string;
    BaudRate, TCPPort: Integer;
    WorkX, WorkY, WorkZ: Double;
    LaserManufacturer, LaserModelName: string;
    LaserOpticalPowerW: Double;
    LaserWavelengthNM: Integer;
    LaserHasHoming: Boolean;
  end;
  TEquipmentProfiles = array of TEquipmentProfile;

  TEquipmentStore = class
  private
    FFileName: string;
    FItems: TEquipmentProfiles;
    FLoadFailed: Boolean;
    procedure WriteFile;
    function GetCount: Integer;
  public
    constructor Create(const AFileName: string);
    procedure Load;
    function Find(const AName: string): Integer;
    function Item(Index: Integer): TEquipmentProfile;
    procedure Put(const Profile: TEquipmentProfile);
    procedure Remove(Index: Integer);
    property Count: Integer read GetCount;
    property FileName: string read FFileName;
    property LoadFailed: Boolean read FLoadFailed;
  end;

function EquipmentFileName: string;
function DefaultEquipmentProfile: TEquipmentProfile;
procedure ValidateEquipment(const Profile: TEquipmentProfile);

implementation

function EquipmentFileName: string;
var Base: string;
begin
  { Permite isolar os testes sem tocar nos equipamentos do operador. }
  Result := GetEnvironmentVariable('MULTICNC_EQUIPMENT_FILE');
  if Result <> '' then Exit(ExpandFileName(Result));
  Base := GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then Base := GetAppConfigDir(False)
  else Base := IncludeTrailingPathDelimiter(Base) + 'Maurinsoft' + PathDelim + 'MultiCNC';
  Result := IncludeTrailingPathDelimiter(Base) + 'multicnc.json';
end;

function DefaultEquipmentProfile: TEquipmentProfile;
begin
  Result := Default(TEquipmentProfile);
  Result.MachineType := mtRouter;
  Result.BaudRate := 115200;
  Result.Host := '127.0.0.1';
  Result.TCPPort := 9000;
end;

procedure ValidateEquipment(const Profile: TEquipmentProfile);
var I: Integer;
  function ValidTravel(Value: Double): Boolean;
  begin
    Result := not IsNan(Value) and not IsInfinite(Value) and (Value >= 0) and (Value <= 3000);
  end;
begin
  if (Trim(Profile.Name) = '') or (Length(Profile.Name) > 240) then
    raise Exception.Create('Informe um nome para o equipamento (ate 240 caracteres).');
  for I := 1 to Length(Profile.Name) do
    if Ord(Profile.Name[I]) < 32 then raise Exception.Create('O nome contem caracteres invalidos.');
  if not (Ord(Profile.MachineType) in [0..2]) or
     not (Profile.ProtocolIndex in [0..1]) or not (Profile.ConnectionMode in [0..2]) then
    raise Exception.Create('Tipo de maquina, protocolo ou conexao invalido.');
  if (Profile.BaudRate < 1) or (Profile.BaudRate > 4000000) then
    raise Exception.Create('Velocidade serial invalida.');
  if (Profile.ConnectionMode = 0) and (Trim(Profile.SerialPort) = '') then
    raise Exception.Create('Selecione a porta serial do equipamento.');
  if (Profile.ConnectionMode = 1) and
     ((Trim(Profile.Host) = '') or (Profile.TCPPort < 1) or (Profile.TCPPort > 65535)) then
    raise Exception.Create('Informe o endereco e uma porta TCP entre 1 e 65535.');
  if not ValidTravel(Profile.WorkX) or not ValidTravel(Profile.WorkY) or
     not ValidTravel(Profile.WorkZ) then raise Exception.Create('Curso da maquina invalido.');
  if (Profile.MachineType = mtLaser) and SameText(Profile.Brand, 'CUSTOM') then
  begin
    if (Profile.WorkX <= 0) or (Profile.WorkY <= 0) then
      raise Exception.Create('Informe a area X/Y do laser CUSTOM em mm.');
    if IsNan(Profile.LaserOpticalPowerW) or IsInfinite(Profile.LaserOpticalPowerW) or
       (Profile.LaserOpticalPowerW <= 0) or (Profile.LaserOpticalPowerW > 1000) then
      raise Exception.Create('Informe a potencia optica do laser CUSTOM em watts (maior que zero, ate 1000 W).');
    if (Profile.LaserWavelengthNM < 0) or (Profile.LaserWavelengthNM > 20000) then
      raise Exception.Create('Comprimento de onda invalido (0 = nao informado).');
    if (Length(Profile.LaserManufacturer) > 120) or (Length(Profile.LaserModelName) > 120) then
      raise Exception.Create('Fabricante e modelo devem ter ate 120 caracteres.');
  end;
end;

constructor TEquipmentStore.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := ExpandFileName(AFileName);
end;

function TEquipmentStore.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TEquipmentStore.Find(const AName: string): Integer;
var I: Integer;
begin
  for I := 0 to High(FItems) do
    if SameText(FItems[I].Name, Trim(AName)) then Exit(I);
  Result := -1;
end;

function TEquipmentStore.Item(Index: Integer): TEquipmentProfile;
begin
  if (Index < 0) or (Index >= Count) then raise Exception.Create('Equipamento nao encontrado.');
  Result := FItems[Index];
end;

procedure TEquipmentStore.Load;
var Root, Entry: TJSONData; Items: TJSONArray; Obj: TJSONObject;
    Source: TStringList; Loaded: TEquipmentProfiles; P: TEquipmentProfile;
    I, J, Kind: Integer; ReadPath: string;
begin
  FLoadFailed := False;
  ReadPath := FFileName;
  if not FileExists(ReadPath) and FileExists(FFileName + '.bak') then ReadPath := FFileName + '.bak';
  if not FileExists(ReadPath) then begin SetLength(FItems, 0); Exit; end;
  Root := nil; Source := TStringList.Create;
  try
    try
      Source.LoadFromFile(ReadPath);
      if Length(Source.Text) > 5 * 1024 * 1024 then raise Exception.Create('Arquivo de equipamentos muito grande.');
      Root := GetJSON(Source.Text);
      if not (Root is TJSONObject) then raise Exception.Create('Formato de cadastro invalido.');
      Obj := TJSONObject(Root);
      if Obj.Get('version', 0) <> 1 then raise Exception.Create('Versao de cadastro nao suportada.');
      Entry := Obj.Find('equipment');
      if not (Entry is TJSONArray) then raise Exception.Create('Lista de equipamentos ausente.');
      Items := TJSONArray(Entry);
      if Items.Count > 1000 then raise Exception.Create('Limite de 1000 equipamentos excedido.');
      SetLength(Loaded, Items.Count);
      for I := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[I] is TJSONObject) then raise Exception.Create('Equipamento invalido.');
        Obj := TJSONObject(Items.Items[I]);
        P := DefaultEquipmentProfile;
        P.Name := Trim(Obj.Get('name', ''));
        Kind := Obj.Get('machine_type', -1);
        if not (Kind in [0..2]) then raise Exception.Create('Tipo de equipamento invalido.');
        P.MachineType := TMachineType(Kind);
        P.ProtocolIndex := Obj.Get('protocol', -1);
        P.ConnectionMode := Obj.Get('connection', -1);
        P.Brand := Obj.Get('brand', '');
        P.Model := Obj.Get('model', '');
        P.SerialPort := Obj.Get('serial_port', '');
        P.BaudRate := Obj.Get('baud_rate', 115200);
        P.Host := Obj.Get('host', '127.0.0.1');
        P.TCPPort := Obj.Get('tcp_port', 9000);
        P.WorkX := Obj.Get('work_x', 0.0);
        P.WorkY := Obj.Get('work_y', 0.0);
        P.WorkZ := Obj.Get('work_z', 0.0);
        P.LaserManufacturer := Obj.Get('laser_manufacturer', '');
        P.LaserModelName := Obj.Get('laser_model_name', '');
        P.LaserOpticalPowerW := Obj.Get('laser_optical_power_w', 0.0);
        P.LaserWavelengthNM := Obj.Get('laser_wavelength_nm', 0);
        P.LaserHasHoming := Obj.Get('laser_has_homing', False);
        ValidateEquipment(P);
        for J := 0 to I - 1 do
          if SameText(Loaded[J].Name, P.Name) then raise Exception.Create('Nome de equipamento duplicado.');
        Loaded[I] := P;
      end;
      FItems := Loaded;
    except
      FLoadFailed := True;
      raise;
    end;
  finally
    Root.Free; Source.Free;
  end;
end;

procedure TEquipmentStore.WriteFile;
var Root, Obj: TJSONObject; Items: TJSONArray; Source: TStringList;
    I: Integer; P: TEquipmentProfile; TempName, BackupName, Dir: string; HadOriginal: Boolean;
begin
  if FLoadFailed then raise Exception.Create('O cadastro nao foi lido. O arquivo original foi preservado.');
  Dir := ExtractFilePath(FFileName);
  if not ForceDirectories(Dir) then raise Exception.Create('Nao foi possivel criar a pasta do cadastro.');
  TempName := GetTempFileName(Dir, 'eqp');
  BackupName := FFileName + '.bak';
  Root := TJSONObject.Create;
  Source := TStringList.Create;
  try
    Root.Add('version', 1);
    Items := TJSONArray.Create; Root.Add('equipment', Items);
    for I := 0 to High(FItems) do
    begin
      P := FItems[I]; Obj := TJSONObject.Create; Items.Add(Obj);
      Obj.Add('name', P.Name); Obj.Add('machine_type', Ord(P.MachineType));
      Obj.Add('protocol', P.ProtocolIndex); Obj.Add('connection', P.ConnectionMode);
      Obj.Add('brand', P.Brand); Obj.Add('model', P.Model);
      Obj.Add('serial_port', P.SerialPort); Obj.Add('baud_rate', P.BaudRate);
      Obj.Add('host', P.Host); Obj.Add('tcp_port', P.TCPPort);
      Obj.Add('work_x', P.WorkX); Obj.Add('work_y', P.WorkY); Obj.Add('work_z', P.WorkZ);
      if (P.MachineType = mtLaser) and SameText(P.Brand, 'CUSTOM') then
      begin
        Obj.Add('laser_manufacturer', P.LaserManufacturer);
        Obj.Add('laser_model_name', P.LaserModelName);
        Obj.Add('laser_optical_power_w', P.LaserOpticalPowerW);
        Obj.Add('laser_wavelength_nm', P.LaserWavelengthNM);
        Obj.Add('laser_has_homing', P.LaserHasHoming);
      end;
    end;
    Source.Text := Root.FormatJSON;
    Source.SaveToFile(TempName);
    HadOriginal := FileExists(FFileName);
    if HadOriginal then
    begin
      if FileExists(BackupName) and not DeleteFile(BackupName) then
        raise Exception.Create('Nao foi possivel atualizar a copia de seguranca do cadastro.');
      if not RenameFile(FFileName, BackupName) then
        raise Exception.Create('Nao foi possivel atualizar o arquivo de equipamentos.');
    end;
    if not RenameFile(TempName, FFileName) then
    begin
      if HadOriginal then RenameFile(BackupName, FFileName);
      raise Exception.Create('Nao foi possivel salvar os equipamentos.');
    end;
  finally
    if FileExists(TempName) then DeleteFile(TempName);
    Source.Free; Root.Free;
  end;
end;

procedure TEquipmentStore.Put(const Profile: TEquipmentProfile);
var Previous: TEquipmentProfiles; P: TEquipmentProfile; I: Integer;
begin
  P := Profile; P.Name := Trim(P.Name); ValidateEquipment(P);
  Previous := Copy(FItems);
  I := Find(P.Name);
  if I < 0 then
  begin
    if Count >= 1000 then raise Exception.Create('Limite de 1000 equipamentos excedido.');
    I := Count; SetLength(FItems, I + 1);
  end;
  FItems[I] := P;
  try WriteFile; except FItems := Previous; raise; end;
end;

procedure TEquipmentStore.Remove(Index: Integer);
var Previous: TEquipmentProfiles; I: Integer;
begin
  Item(Index);
  Previous := Copy(FItems);
  for I := Index to Count - 2 do FItems[I] := FItems[I + 1];
  SetLength(FItems, Count - 1);
  try WriteFile; except FItems := Previous; raise; end;
end;

end.