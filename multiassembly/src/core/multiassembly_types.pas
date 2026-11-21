unit multiassembly_types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  TAssemblyVec3 = record
    X, Y, Z: Double;
  end;

  TAssemblyComponentKind = (
    ackMechanicalPart,
    ackMotor,
    ackSpindle,
    ackLeadScrew,
    ackLinearGuide,
    ackBearing,
    ackPulley,
    ackBelt,
    ackController,
    ackDriver,
    ackPowerSupply,
    ackVFD,
    ackRelay,
    ackSensor,
    ackEndStop,
    ackEStop,
    ackConnector,
    ackPCB,
    ackFastenerScrew,
    ackFastenerNut,
    ackFastenerWasher,
    ackFastenerRivet,
    ackPinSpacer,
    ackOther
  );

  TAssemblyPortKind = (
    apkMechanical,
    apkPower,
    apkGround,
    apkDigitalInput,
    apkDigitalOutput,
    apkAnalogInput,
    apkAnalogOutput,
    apkStep,
    apkDir,
    apkEnable,
    apkPWM,
    apkCommunication
  );

  TAssemblyPort = record
    Name: string;
    Kind: TAssemblyPortKind;
    Voltage: Double;
  end;

  { Geometria 3D realista de um componente (mm, sistema local da peca, canto
    minimo em 0,0,0). Ver models/components/README.md.
    Eixo das primitivas (ciclico): 'z' u->X v->Y w->Z | 'x' u->Y v->Z w->X |
    'y' u->Z v->X w->Y. }
  TAssemblyPrimitiveKind = (
    agpBox,      // caixa: At = canto minimo, Size = dimensoes
    agpCylinder, // cilindro/tubo/cone/setor: At = centro da base
    agpPrism,    // poligono (u,v) extrudado ao longo do eixo
    agpDisk      // decalque plano (furo, LED, etiqueta)
  );

  TAssemblyUV = record
    U, V: Double;
  end;

  TAssemblyPrimitive = record
    Kind: TAssemblyPrimitiveKind;
    Axis: Char;           // 'x', 'y' ou 'z'
    At: TAssemblyVec3;
    Size: TAssemblyVec3;  // agpBox
    R, R2, Ri, H: Double; // raio base, raio topo (cone), raio interno, altura
    Segments: Integer;
    RotDeg: Double;       // fase angular inicial
    HasArc: Boolean;
    ArcStart, ArcEnd: Double;
    Caps: Boolean;
    Poly: array of TAssemblyUV;
    Color: LongInt;       // TColor (BGR)
  end;

  TAssemblyGeometry = array of TAssemblyPrimitive;

  TAssemblyComponent = record
    ID: string;
    Name: string;
    Model: string;
    SourceRef: string;
    Category: string;
    Material: string;
    Kind: TAssemblyComponentKind;
    Position: TAssemblyVec3;
    Rotation: TAssemblyVec3;
    Size: TAssemblyVec3;
    Ports: array of TAssemblyPort;
    Fixed: Boolean;
    Color: LongInt;
    Geometry: TAssemblyGeometry; // vazio = forma gerada pelo tipo (Kind)
  end;

  TElectricalConnection = record
    FromComponent: string;
    FromPort: string;
    ToComponent: string;
    ToPort: string;
    Caption: string;
  end;

  TMechanicalRelationKind = (
    mrFixed,
    mrAxis,
    mrCoupled,
    mrBelt,
    mrLeadScrew,
    mrCoincident,
    mrConcentric,
    mrParallel,
    mrDistance,
    mrSlider,
    mrHinge,
    mrGear,
    mrInsert     // concentrico + coincidente (parafuso no furo, motor no suporte)
  );

  { Referencia geometrica de uma uniao: face plana e/ou eixo de um componente,
    no sistema local do componente (caixa 0..Size, antes da rotacao). }
  TMateFeature = record
    Valid: Boolean;
    HasPlane: Boolean;
    PlanePoint, PlaneNormal: TAssemblyVec3;
    HasAxis: Boolean;
    AxisPoint, AxisDir: TAssemblyVec3;
    Radius: Double;
    Prim, Part: Integer; // primitiva e parte de origem (informativo)
  end;

  TMechanicalRelation = record
    A, B: string;
    Kind: TMechanicalRelationKind;
    Axis: TAssemblyVec3;
    Ratio: Double;
    PitchMM: Double;
    Distance: Double;
    MinLimit: Double;
    MaxLimit: Double;
    CurrentValue: Double;
    Offset: TAssemblyVec3;
    Flipped: Boolean;
    // Uniao por referencia (faces/furos/eixos escolhidos na vista 3D)
    HasRefs: Boolean;
    RefA, RefB: TMateFeature; // RefA pertence a A (peca movida), RefB a B (referencia)
    SpinDeg: Double;          // giro em torno do eixo/normal da uniao
  end;

  TAssemblyDOFStatus = (
    adsFixed,        // (f) Componente fixo (base)
    adsUnderdefined, // (-) Possui graus de liberdade livres
    adsFullyDefined, // ( ) Totalmente definido por juncoes (0 GL)
    adsOverdefined   // (+) Conflito / excesso de restricoes
  );

  TComponentDOF = record
    Tx, Ty, Tz: Boolean; // Translacoes livres
    Rx, Ry, Rz: Boolean; // Rotacoes livres
    FreeCount: Integer;  // Quantidade de graus de liberdade livres (0..6)
    Status: TAssemblyDOFStatus;
    StatusText: string;  // Ex: '(-) 1 GL (Linear X)'
  end;

  TManualStep = record
    ID: string;
    Order: Integer;
    Title: string;
    Instructions: string;
    Tools: string;
    Checks: string;
    ComponentIDs: array of string;
  end;

function Vec3(AX, AY, AZ: Double): TAssemblyVec3;
function Vec3Dist(const A, B: TAssemblyVec3): Double;
function Vec3Add(const A, B: TAssemblyVec3): TAssemblyVec3;
function Vec3Sub(const A, B: TAssemblyVec3): TAssemblyVec3;
function Vec3Mul(const A: TAssemblyVec3; S: Double): TAssemblyVec3;
function Vec3Dot(const A, B: TAssemblyVec3): Double;
function Vec3Len(const A: TAssemblyVec3): Double;
function Vec3Normalize(const A: TAssemblyVec3): TAssemblyVec3;

implementation

function Vec3(AX, AY, AZ: Double): TAssemblyVec3;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function Vec3Dist(const A, B: TAssemblyVec3): Double;
var
  DX, DY, DZ: Double;
begin
  DX := A.X - B.X;
  DY := A.Y - B.Y;
  DZ := A.Z - B.Z;
  Result := Sqrt(DX * DX + DY * DY + DZ * DZ);
end;

function Vec3Add(const A, B: TAssemblyVec3): TAssemblyVec3;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
  Result.Z := A.Z + B.Z;
end;

function Vec3Sub(const A, B: TAssemblyVec3): TAssemblyVec3;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
  Result.Z := A.Z - B.Z;
end;

function Vec3Mul(const A: TAssemblyVec3; S: Double): TAssemblyVec3;
begin
  Result.X := A.X * S;
  Result.Y := A.Y * S;
  Result.Z := A.Z * S;
end;

function Vec3Dot(const A, B: TAssemblyVec3): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function Vec3Len(const A: TAssemblyVec3): Double;
begin
  Result := Sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z);
end;

function Vec3Normalize(const A: TAssemblyVec3): TAssemblyVec3;
var
  L: Double;
begin
  L := Vec3Len(A);
  if L > 1e-9 then
    Result := Vec3Mul(A, 1.0 / L)
  else
    Result := Vec3(0, 0, 0);
end;

end.
