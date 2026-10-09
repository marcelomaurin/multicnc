unit multicad_materials;

(* MultiCAD - biblioteca de materiais (decisao D9).

  Valores tipicos de referencia (densidade em kg/m3, modulo de elasticidade
  em GPa, coeficiente de Poisson). Servem para massa e para o MultiPhysics;
  para projeto critico, use o valor do fornecedor.
  A tabela embutida pode ser ampliada por data/materials.json:
    [ {"name": "...", "density": 7850, "e_gpa": 200, "poisson": 0.29}, ... ] *)

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser;

type
  TCadMaterial = record
    Name: string;
    Density: Double;   { kg/m3 }
    EModulus: Double;  { GPa }
    Poisson: Double;
  end;
  TCadMaterialArray = array of TCadMaterial;

function CadMaterialCount: Integer;
function CadMaterial(I: Integer): TCadMaterial;
function CadFindMaterial(const AName: string; out M: TCadMaterial): Boolean;
function CadMaterialIndex(const AName: string): Integer;
{ Junta (ou substitui pelo nome) materiais de um arquivo JSON. }
function CadLoadMaterials(const AFileName: string; out AError: string): Boolean;
{ Massa em kg de um volume em mm3. }
function CadMassKg(const M: TCadMaterial; VolumeMM3: Double): Double;

const
  CAD_DEFAULT_MATERIAL = 'Aço 1020';

implementation

var
  GMaterials: TCadMaterialArray;

function Mat(const N: string; D, E, P: Double): TCadMaterial;
begin
  Result.Name := N;
  Result.Density := D;
  Result.EModulus := E;
  Result.Poisson := P;
end;

procedure InitDefaults;
begin
  SetLength(GMaterials, 0);
  GMaterials := [
    Mat('Aço 1020', 7870, 200, 0.29),
    Mat('Aço 1045', 7850, 205, 0.29),
    Mat('Aço inox 304', 8000, 193, 0.29),
    Mat('Alumínio 6061-T6', 2700, 68.9, 0.33),
    Mat('Latão', 8500, 100, 0.34),
    Mat('Ferro fundido cinzento', 7200, 100, 0.26),
    Mat('Nylon 6', 1140, 2.8, 0.39),
    Mat('POM (acetal)', 1410, 2.9, 0.35),
    Mat('ABS', 1050, 2.2, 0.35),
    Mat('PLA', 1240, 3.5, 0.36),
    Mat('PETG', 1270, 2.1, 0.38),
    Mat('MDF', 750, 4.0, 0.25)
  ];
end;

function CadMaterialCount: Integer;
begin
  Result := Length(GMaterials);
end;

function CadMaterial(I: Integer): TCadMaterial;
begin
  Result := GMaterials[I];
end;

function CadMaterialIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(GMaterials) do
    if SameText(GMaterials[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

function CadFindMaterial(const AName: string; out M: TCadMaterial): Boolean;
var
  I: Integer;
begin
  I := CadMaterialIndex(AName);
  Result := I >= 0;
  if Result then
    M := GMaterials[I]
  else
    M := Mat('', 0, 0, 0);
end;

function CadLoadMaterials(const AFileName: string; out AError: string): Boolean;
var
  SL: TStringList;
  Data: TJSONData;
  Arr: TJSONArray;
  O: TJSONObject;
  I, K: Integer;
  M: TCadMaterial;
  Loaded: TCadMaterialArray;
begin
  Result := False;
  AError := '';
  if not FileExists(AFileName) then
  begin
    AError := 'Arquivo não encontrado: ' + AFileName;
    Exit;
  end;
  SL := TStringList.Create;
  Data := nil;
  try
    try
      SL.LoadFromFile(AFileName);
      Data := GetJSON(SL.Text);
      if not (Data is TJSONArray) then
      begin
        AError := 'O arquivo de materiais deve ser uma lista JSON';
        Exit;
      end;
      Arr := TJSONArray(Data);
      SetLength(Loaded, 0);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then
        begin
          AError := Format('Item %d não é um objeto', [I]);
          Exit;
        end;
        O := TJSONObject(Arr.Items[I]);
        M.Name := Trim(O.Get('name', ''));
        M.Density := O.Get('density', 0.0);
        M.EModulus := O.Get('e_gpa', 0.0);
        M.Poisson := O.Get('poisson', 0.0);
        if (M.Name = '') or (M.Density <= 0) then
        begin
          AError := Format('Item %d sem nome ou densidade', [I]);
          Exit;
        end;
        SetLength(Loaded, Length(Loaded) + 1);
        Loaded[High(Loaded)] := M;
      end;
      { so aplica depois de validar tudo }
      for I := 0 to High(Loaded) do
      begin
        K := CadMaterialIndex(Loaded[I].Name);
        if K >= 0 then
          GMaterials[K] := Loaded[I]
        else
        begin
          SetLength(GMaterials, Length(GMaterials) + 1);
          GMaterials[High(GMaterials)] := Loaded[I];
        end;
      end;
      Result := True;
    except
      on E: Exception do
        AError := E.Message;
    end;
  finally
    Data.Free;
    SL.Free;
  end;
end;

function CadMassKg(const M: TCadMaterial; VolumeMM3: Double): Double;
begin
  Result := VolumeMM3 * 1E-9 * M.Density;
end;

initialization
  InitDefaults;

end.
