unit multiphysics_coupling;

{ Acoplamento runtime -> FEM (MP-7.13): grandezas de um instante da
  simulacao de sistema viram cargas da analise de campo.
  - perdas do motor (I2R) -> potencia dissipada na peca do motor (termica);
  - torque do eixo -> forca tangencial equivalente numa face (estrutural).
  As cargas entram como condicoes de contorno do projeto, editaveis. }

{$mode objfpc}{$H+}

interface

uses SysUtils, Math, multiphysics_runtime_types, multiphysics_types, multiphysics_project;

type
  TFieldLoads = record
    Torque, Force, Heat, Temperature, Velocity: Double;
  end;

function RuntimeToFieldLoads(const S: TSimulationSnapshot): TFieldLoads;
{ acrescenta (ou atualiza) a potencia dissipada da peca com o calor do motor;
  devolve o indice da condicao }
function ApplyRuntimeHeat(P: TPhysicsProject; const PartID: string; const S: TSimulationSnapshot): Integer;
{ forca tangencial = torque / raio, na face indicada, na direcao Dir (unitaria) }
function ApplyRuntimeTorque(P: TPhysicsProject; const PartID, Face: string; const S: TSimulationSnapshot;
  Radius, DirX, DirY, DirZ: Double): Integer;

implementation

function RuntimeToFieldLoads(const S: TSimulationSnapshot): TFieldLoads;
begin
  Result.Torque := S.Mechanical.Torque;
  Result.Force := 0;
  Result.Heat := S.Thermal.HeatPower;
  Result.Temperature := S.Thermal.Temperature;
  Result.Velocity := S.Mechanical.Velocity;
end;

function FindBC(P: TPhysicsProject; const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to P.BCCount - 1 do
    if SameText(P.BC(I).Name, Name) then Exit(I);
  Result := -1;
end;

function ApplyRuntimeHeat(P: TPhysicsProject; const PartID: string; const S: TSimulationSnapshot): Integer;
var
  B: TBoundaryCondition;
  Name: string;
begin
  Name := 'Perdas do motor (runtime) ' + PartID;
  B := NewBC(Name, PartID, '', bkHeatPower);
  B.Value := Max(0.0, S.Thermal.HeatPower);
  Result := FindBC(P, Name);
  if Result >= 0 then P.SetBC(Result, B)
  else
  begin
    P.AddBC(B);
    Result := P.BCCount - 1;
  end;
end;

function ApplyRuntimeTorque(P: TPhysicsProject; const PartID, Face: string; const S: TSimulationSnapshot;
  Radius, DirX, DirY, DirZ: Double): Integer;
var
  B: TBoundaryCondition;
  Name: string;
  F: Double;
begin
  Name := 'Torque do eixo (runtime) ' + PartID;
  if Radius > 0 then F := S.Mechanical.Torque / Radius else F := 0;
  B := NewBC(Name, PartID, Face, bkForce);
  B.X := F * DirX; B.Y := F * DirY; B.Z := F * DirZ;
  Result := FindBC(P, Name);
  if Result >= 0 then P.SetBC(Result, B)
  else
  begin
    P.AddBC(B);
    Result := P.BCCount - 1;
  end;
end;

end.
