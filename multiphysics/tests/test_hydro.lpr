program test_hydro;

{ Fase 8: atmosfera ISA contra a tabela padrao, Mach, volume submerso pela
  malha e flutuacao de um casco em caixa (calado e altura metacentrica
  GM = KB + BM - KG, BM = B^2 / (12 T)). }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, multiphysics_vector, multiphysics_geometry, multiphysics_mesh,
  multiphysics_hydro, multiphysics_check;

var
  A: TAtmosphere;
  M: TFEMMesh;
  S: TSubmerged;
  F: TFlotation;
  L, B, H, Rho, Mass, T, GMRef: Double;

begin
  Section('Atmosfera ISA');
  A := ISAAtmosphere(0);
  CheckNear(A.Temperature, 288.15, 1e-9, 'nivel do mar: 288,15 K');
  CheckNear(A.Pressure, 101325, 1e-9, 'nivel do mar: 101325 Pa');
  CheckNear(A.Density, 1.2250, 0.001, 'nivel do mar: 1,225 kg/m3');
  CheckNear(A.SoundSpeed, 340.29, 0.001, 'nivel do mar: 340,3 m/s');
  CheckNear(A.Viscosity, 1.789e-5, 0.01, 'nivel do mar: viscosidade 1,79e-5 Pa s');
  A := ISAAtmosphere(5000);
  CheckNear(A.Pressure, 54019.9, 0.001, '5 km: 54020 Pa');
  CheckNear(A.Density, 0.73612, 0.002, '5 km: 0,736 kg/m3');
  A := ISAAtmosphere(11000);
  CheckNear(A.Temperature, 216.65, 1e-9, '11 km: 216,65 K');
  CheckNear(A.Pressure, 22632, 0.002, '11 km: 22632 Pa');
  A := ISAAtmosphere(20000);
  CheckNear(A.Pressure, 5474.9, 0.002, '20 km: 5475 Pa');
  CheckNear(A.Density, 0.088035, 0.003, '20 km: 0,0880 kg/m3');
  CheckNear(MachNumber(170.145, 340.29), 0.5, 1e-6, 'Mach = v / a');
  Check(CompressibilityWarning(0.2) = '', 'Mach 0,2: incompressivel vale');
  Check(CompressibilityWarning(0.5) <> '', 'Mach 0,5: aviso de compressibilidade');

  Section('Volume submerso e flutuacao de um casco em caixa');
  L := 1.0; B := 0.4; H := 0.3;
  M := TFEMMesh.Create;
  try
    M.AddPart('CASCO');
    M.AddPrimitive(0, BoxPrim('b', V3(0, -B / 2, 0), V3(L, B, H)), IdentityTransform, 0.05);
    M.Finalize;
    S := SubmergedVolume(M, 0.1);
    CheckNear(S.Volume, L * B * 0.1, 1e-9, 'volume abaixo de z = 0,1 m');
    CheckNear(S.Center.Z, 0.05, 1e-9, 'centro de empuxo a meia altura do volume submerso');
    S := SubmergedVolumeRotated(M, 0.1, 10, V3(0.5, 0, 0.15));
    CheckNear(S.Volume, SubmergedVolumeRotated(M, 0.1, 10, V3(0.5, 0, 0.15)).Volume, 1e-12, 'corte deterministico');
    { madeira 600 kg/m3 em agua: calado = 0,6 H }
    Rho := 1000;
    Mass := 600 * L * B * H;
    F := SolveFlotation(M, Mass, Rho, V3(L / 2, 0, H / 2), 2);
    Check(F.Ok, F.Message);
    T := 0.6 * H;
    CheckNear(F.Draft, T, 1e-6, 'calado = (rho_corpo / rho_agua) H');
    CheckNear(F.CenterOfBuoyancy.Z, T / 2, 1e-6, 'KB = T / 2');
    GMRef := T / 2 + B * B / (12 * T) - H / 2;
    CheckNear(F.GM, GMRef, 0.03, Format('GM = KB + BM - KG = %.4f m', [GMRef]));
    { centro de gravidade alto: instavel }
    F := SolveFlotation(M, Mass, Rho, V3(L / 2, 0, 0.3), 2);
    Check(F.Ok and (F.GM < 0), 'centro de gravidade no topo: GM negativo (instavel)');
    { mais pesado que a agua: afunda }
    F := SolveFlotation(M, 1200 * L * B * H, Rho, V3(L / 2, 0, H / 2), 2);
    Check(not F.Ok and (Pos('Afunda', F.Message) = 1), 'mais denso que a agua: afunda');
  finally
    M.Free;
  end;
  Finish('atmosfera e flutuacao');
end.
