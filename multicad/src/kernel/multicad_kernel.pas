unit multicad_kernel;

{ MultiCAD - interface do nucleo geometrico (decisao D1).

  A arvore de operacoes e a tela so falam com ICadKernel. Hoje existe o
  nucleo Pascal (malha rotulada); o adaptador OpenCascade (fase 8)
  implementa a mesma interface. As capacidades dizem o que o nucleo ja
  sabe fazer, para a interface habilitar so os comandos possiveis.

  Fase 0: primitivas e verificacao. Fase 2 acrescenta varredura (extrusao,
  revolucao) e booleanas. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, multicad_types, multicad_mesh;

type
  TCadKernelCap = (kcPrimitives, kcSweep, kcBoolean, kcFillet, kcShell, kcStep);
  TCadKernelCaps = set of TCadKernelCap;

  ICadKernel = interface
    ['{6B1F8E2A-4C1D-4E7B-9A55-3D2C7A1E9B10}']
    function Name: string;
    function Version: string;
    function Capabilities: TCadKernelCaps;
    function Tolerance: Double;
    function MakeBox(const AMin, AMax: TCadVec3; const APrefix: string): TCadMesh;
    function MakeCylinder(const ABase, AAxis: TCadVec3; AR, AH: Double;
      const APrefix: string): TCadMesh;
    { Confere se o resultado e um solido valido (fechado e com volume positivo). }
    function CheckSolid(AMesh: TCadMesh; out AError: string): Boolean;
  end;

  TCadPascalKernel = class(TInterfacedObject, ICadKernel)
  public
    function Name: string;
    function Version: string;
    function Capabilities: TCadKernelCaps;
    function Tolerance: Double;
    function MakeBox(const AMin, AMax: TCadVec3; const APrefix: string): TCadMesh;
    function MakeCylinder(const ABase, AAxis: TCadVec3; AR, AH: Double;
      const APrefix: string): TCadMesh;
    function CheckSolid(AMesh: TCadMesh; out AError: string): Boolean;
  end;

{ Nucleo em uso (hoje sempre o Pascal). }
function CadKernel: ICadKernel;

implementation

var
  GKernel: ICadKernel;

function TCadPascalKernel.Name: string;
begin
  Result := 'MultiCAD Pascal (malha rotulada)';
end;

function TCadPascalKernel.Version: string;
begin
  Result := '0.1';
end;

function TCadPascalKernel.Capabilities: TCadKernelCaps;
begin
  Result := [kcPrimitives];
end;

function TCadPascalKernel.Tolerance: Double;
begin
  Result := CAD_TOL;
end;

function TCadPascalKernel.MakeBox(const AMin, AMax: TCadVec3;
  const APrefix: string): TCadMesh;
begin
  Result := CadMakeBox(AMin, AMax, APrefix);
end;

function TCadPascalKernel.MakeCylinder(const ABase, AAxis: TCadVec3; AR,
  AH: Double; const APrefix: string): TCadMesh;
begin
  Result := CadMakeCylinder(ABase, AAxis, AR, AH, APrefix);
end;

function TCadPascalKernel.CheckSolid(AMesh: TCadMesh; out AError: string): Boolean;
begin
  AError := '';
  if AMesh = nil then
  begin
    AError := 'Sem sólido';
    Exit(False);
  end;
  if not AMesh.CheckClosed(AError) then
    Exit(False);
  if AMesh.Volume <= CAD_TOL * CAD_TOL * CAD_TOL then
  begin
    AError := 'Sólido com volume nulo ou invertido';
    Exit(False);
  end;
  Result := True;
end;

function CadKernel: ICadKernel;
begin
  if GKernel = nil then
    GKernel := TCadPascalKernel.Create;
  Result := GKernel;
end;

finalization
  GKernel := nil;

end.
