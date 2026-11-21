unit multiphysics_hydro;

{ Ambiente e flutuacao (Fase 8), sempre ESTIMATIVA (nao e CFD):
  - atmosfera padrao ISA de 0 a 20 km (troposfera e baixa estratosfera);
  - numero de Mach e aviso de compressibilidade (M > 0,3);
  - volume submerso e centro de empuxo pela malha: cada tetraedro cortado
    pelo plano da linha d'agua (exato para faces planas);
  - calado de equilibrio (empuxo = peso) por bissecao;
  - altura metacentrica GM por inclinacao pequena: GZ / sen(phi), com o
    calado reajustado para manter o deslocamento. Coordenadas em m, Z para
    cima. }

{$mode objfpc}{$H+}

interface

uses SysUtils, Math, StrUtils, multiphysics_vector, multiphysics_geometry, multiphysics_mesh;

type
  TAtmosphere = record
    Altitude, Temperature, Pressure, Density, Viscosity, SoundSpeed: Double;   { m, K, Pa, kg/m3, Pa s, m/s }
  end;

  TSubmerged = record
    Volume: Double;
    Center: TVector3;
  end;

  TFlotation = record
    Ok: Boolean;
    Message: string;
    WaterlineZ, Draft: Double;       { cota da linha d'agua e calado (abaixo do ponto mais baixo) }
    Displacement: Double;            { m3 }
    CenterOfBuoyancy: TVector3;
    GM: Double;                      { altura metacentrica (m); > 0 = estavel }
  end;

function ISAAtmosphere(Altitude: Double): TAtmosphere;
function MachNumber(Speed, SoundSpeed: Double): Double;
function CompressibilityWarning(Mach: Double): string;   { '' se incompressivel vale }
{ volume abaixo do plano z = WaterZ (nos rodados por Rot em torno de Pivot) }
function SubmergedVolume(M: TFEMMesh; WaterZ: Double): TSubmerged;
function SubmergedVolumeRotated(M: TFEMMesh; WaterZ, HeelDeg: Double; const Pivot: TVector3): TSubmerged;
{ equilibrio em fluido de densidade Rho para massa total Mass e centro de
  gravidade G; GM pela inclinacao HeelDeg em torno do eixo X }
function SolveFlotation(M: TFEMMesh; Mass, Rho: Double; const G: TVector3; HeelDeg: Double = 2): TFlotation;

implementation

const
  R_AIR = 287.053;
  G0 = 9.80665;

function ISAAtmosphere(Altitude: Double): TAtmosphere;
var
  H: Double;
begin
  H := EnsureRange(Altitude, 0, 20000);
  Result.Altitude := H;
  if H <= 11000 then
  begin
    Result.Temperature := 288.15 - 0.0065 * H;
    Result.Pressure := 101325 * Power(Result.Temperature / 288.15, G0 / (0.0065 * R_AIR));
  end
  else
  begin
    Result.Temperature := 216.65;
    Result.Pressure := 22632.06 * Exp(-G0 * (H - 11000) / (R_AIR * 216.65));
  end;
  Result.Density := Result.Pressure / (R_AIR * Result.Temperature);
  Result.SoundSpeed := Sqrt(1.4 * R_AIR * Result.Temperature);
  { Sutherland }
  Result.Viscosity := 1.458e-6 * Power(Result.Temperature, 1.5) / (Result.Temperature + 110.4);
end;

function MachNumber(Speed, SoundSpeed: Double): Double;
begin
  if SoundSpeed <= 0 then Exit(0);
  Result := Abs(Speed) / SoundSpeed;
end;

function CompressibilityWarning(Mach: Double): string;
begin
  if Mach > 1 then Result := Format('Mach %.2f: escoamento supersonico, ha ondas de choque; a estimativa incompressivel nao vale', [Mach])
  else if Mach > 0.3 then Result := Format('Mach %.2f: acima de 0,3 a hipotese incompressivel nao vale como resultado final', [Mach])
  else Result := '';
end;

function TetVol(const A, B, C, D: TVector3): Double; inline;
begin
  Result := Abs(VDot(VSub(B, A), VCross(VSub(C, A), VSub(D, A)))) / 6;
end;

procedure AddTet(var S: TSubmerged; var Moment: TVector3; const A, B, C, D: TVector3);
var
  V: Double;
begin
  V := TetVol(A, B, C, D);
  S.Volume := S.Volume + V;
  Moment := VAdd(Moment, VScale(VAdd(VAdd(A, B), VAdd(C, D)), V / 4));
end;

function Cut(const P, Q: TVector3; Z: Double): TVector3; inline;
var
  T: Double;
begin
  T := (Z - P.Z) / (Q.Z - P.Z);
  Result := VAdd(P, VScale(VSub(Q, P), T));
end;

{ parte de um tetraedro abaixo do plano z = Z }
procedure ClipTet(const V: array of TVector3; Z: Double; var S: TSubmerged; var Moment: TVector3);
var
  Below, Above: array[0..3] of Integer;
  NB, NA, I: Integer;
  A, B, C, D: TVector3;
begin
  NB := 0; NA := 0;
  for I := 0 to 3 do
    if V[I].Z < Z then begin Below[NB] := I; Inc(NB); end
    else begin Above[NA] := I; Inc(NA); end;
  case NB of
    0: ;
    4: AddTet(S, Moment, V[0], V[1], V[2], V[3]);
    1:
      begin
        A := V[Below[0]];
        AddTet(S, Moment, A, Cut(A, V[Above[0]], Z), Cut(A, V[Above[1]], Z), Cut(A, V[Above[2]], Z));
      end;
    3:
      begin
        { inteiro menos o tetraedro acima }
        AddTet(S, Moment, V[0], V[1], V[2], V[3]);
        D := V[Above[0]];
        A := Cut(D, V[Below[0]], Z); B := Cut(D, V[Below[1]], Z); C := Cut(D, V[Below[2]], Z);
        S.Volume := S.Volume - TetVol(D, A, B, C);
        Moment := VSub(Moment, VScale(VAdd(VAdd(D, A), VAdd(B, C)), TetVol(D, A, B, C) / 4));
      end;
    2:
      begin
        { cunha com faces (a, pac, pad) e (b, pbc, pbd): 3 tetraedros }
        A := V[Below[0]]; B := V[Below[1]];
        C := V[Above[0]]; D := V[Above[1]];
        AddTet(S, Moment, A, Cut(A, C, Z), Cut(A, D, Z), B);
        AddTet(S, Moment, Cut(A, C, Z), Cut(A, D, Z), B, Cut(B, D, Z));
        AddTet(S, Moment, Cut(A, C, Z), B, Cut(B, C, Z), Cut(B, D, Z));
      end;
  end;
end;

function SubmergedVolumeRotated(M: TFEMMesh; WaterZ, HeelDeg: Double; const Pivot: TVector3): TSubmerged;
var
  E, K: Integer;
  V: array[0..3] of TVector3;
  Moment: TVector3;
  C, S, Y, Zr: Double;
begin
  Result.Volume := 0;
  Result.Center := V3(0, 0, 0);
  Moment := V3(0, 0, 0);
  SinCos(DegToRad(HeelDeg), S, C);
  for E := 0 to M.ElemCount - 1 do
  begin
    for K := 0 to 3 do
    begin
      V[K] := M.Nodes[M.Elems[E].N[K]];
      if HeelDeg <> 0 then
      begin
        { gira em torno do eixo X passando pelo pivo }
        Y := V[K].Y - Pivot.Y; Zr := V[K].Z - Pivot.Z;
        V[K].Y := Pivot.Y + C * Y - S * Zr;
        V[K].Z := Pivot.Z + S * Y + C * Zr;
      end;
    end;
    ClipTet(V, WaterZ, Result, Moment);
  end;
  if Result.Volume > 0 then Result.Center := VScale(Moment, 1 / Result.Volume);
end;

function SubmergedVolume(M: TFEMMesh; WaterZ: Double): TSubmerged;
begin
  Result := SubmergedVolumeRotated(M, WaterZ, 0, V3(0, 0, 0));
end;

{ cota da linha d'agua que submerge o volume Target (bissecao) }
function WaterlineFor(M: TFEMMesh; Target, HeelDeg: Double; const Pivot: TVector3; ZLo, ZHi: Double): Double;
var
  I: Integer;
  Mid: Double;
begin
  for I := 1 to 80 do
  begin
    Mid := (ZLo + ZHi) / 2;
    if SubmergedVolumeRotated(M, Mid, HeelDeg, Pivot).Volume < Target then ZLo := Mid else ZHi := Mid;
  end;
  Result := (ZLo + ZHi) / 2;
end;

function SolveFlotation(M: TFEMMesh; Mass, Rho: Double; const G: TVector3; HeelDeg: Double): TFlotation;
var
  I: Integer;
  ZMin, ZMax, Target, Zw, C, S, GZ: Double;
  Full, Heeled: TSubmerged;
  GRot: TVector3;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (M.NodeCount = 0) or (Rho <= 0) or (Mass <= 0) then
  begin
    Result.Message := 'Sem malha, massa ou densidade do fluido';
    Exit;
  end;
  ZMin := M.Nodes[0].Z; ZMax := ZMin;
  for I := 1 to M.NodeCount - 1 do
  begin
    ZMin := Min(ZMin, M.Nodes[I].Z);
    ZMax := Max(ZMax, M.Nodes[I].Z);
  end;
  Target := Mass / Rho;
  Full := SubmergedVolume(M, ZMax + 1);
  if Full.Volume < Target then
  begin
    Result.Message := Format('Afunda: empuxo maximo %.1f N < peso %.1f N', [Full.Volume * Rho * G0, Mass * G0]);
    Result.Displacement := Full.Volume;
    Exit;
  end;
  Zw := WaterlineFor(M, Target, 0, G, ZMin, ZMax);
  Result.WaterlineZ := Zw;
  Result.Draft := Zw - ZMin;
  Full := SubmergedVolume(M, Zw);
  Result.Displacement := Full.Volume;
  Result.CenterOfBuoyancy := Full.Center;
  { inclinacao pequena em torno do eixo X pelo centro de gravidade; o calado
    e reajustado para o mesmo deslocamento }
  Zw := WaterlineFor(M, Target, HeelDeg, G, ZMin - (ZMax - ZMin), ZMax + (ZMax - ZMin));
  Heeled := SubmergedVolumeRotated(M, Zw, HeelDeg, G);
  SinCos(DegToRad(HeelDeg), S, C);
  GRot := G;   { G esta no pivo: nao se move com a rotacao }
  { braco de endireitamento: distancia horizontal de B' a G (positivo = endireita) }
  GZ := GRot.Y - Heeled.Center.Y;
  Result.GM := GZ / S;
  Result.Ok := True;
  Result.Message := Format('Flutua com calado %.4f m; GM = %.4f m (%s)',
    [Result.Draft, Result.GM, IfThen(Result.GM > 0, 'estavel', 'instavel')]);
end;

end.
