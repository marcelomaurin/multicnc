program test_circuit_netlist;

{ Netlist SPICE: sufixos, divisor DC, diodo, carga RC (B9) e erros. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, multisuite_numfmt, multiphysics_netlist, multiphysics_check;

var
  R: TNetlistResult;
  V, Tau, Expected: Double;
  K, Idx: Integer;
  Ok: Boolean;

begin
  Section('Valores com sufixo');
  Check(ParseSpiceValue('4k7', V) and SameValue(V, 4000), '4k7 le a parte numerica 4 com sufixo k (SPICE)');
  Check(ParseSpiceValue('10u', V) and SameValue(V, 10e-6), '10u = 10e-6');
  Check(ParseSpiceValue('2.2meg', V) and SameValue(V, 2.2e6), '2.2meg = 2,2e6');
  Check(ParseSpiceValue('1e-3', V) and SameValue(V, 1e-3), '1e-3 sem sufixo');
  Check(not ParseSpiceValue('abc', V), 'texto invalido recusado');

  Section('Divisor e diodo (DC)');
  R := RunNetlist('* divisor'#10'V1 in 0 10'#10'R1 in mid 1k'#10'R2 mid 0 1k'#10);
  Check(R.Ok, 'resolve: ' + R.Message);
  if R.Ok then CheckNear(StrToFloat(R.DCNodes.Values['mid'], InvariantFS), 5, 1e-9, 'Vmid = 5 V');
  FreeNetlistResult(R);
  R := RunNetlist('V1 a 0 5'#10'R1 a k 1k'#10'D1 k 0'#10);
  Check(R.Ok, 'diodo resolve: ' + R.Message);
  if R.Ok then
  begin
    V := StrToFloat(R.DCNodes.Values['k'], InvariantFS);
    Check((V > 0.55) and (V < 0.8), Format('queda no diodo %.3f V (0,55 a 0,8)', [V]));
  end;
  FreeNetlistResult(R);

  Section('B9 carga RC: v(t) = V (1 - exp(-t/RC))');
  R := RunNetlist('V1 in 0 10'#10'R1 in out 1k'#10'C1 out 0 1u'#10'.tran 10u 5m'#10'.probe out'#10);
  Check(R.Ok and R.HasTran, 'transitorio resolve: ' + R.Message);
  if R.Ok then
  begin
    Tau := 1e3 * 1e-6;
    Ok := True;
    for K := 1 to 5 do
    begin
      Idx := Round(K * Tau / 10e-6);
      Expected := 10 * (1 - Exp(-R.Times[Idx] / Tau));
      if Abs(R.Values[Idx][0] - Expected) > 0.005 * 10 then
      begin
        Ok := False;
        Writeln(Format('        t=%g v=%g esperado %g', [R.Times[Idx], R.Values[Idx][0], Expected]));
      end;
    end;
    Check(Ok, 'v(t) em t = tau..5 tau dentro de 0,5% do fundo de escala');
  end;
  FreeNetlistResult(R);

  Section('Erros');
  R := RunNetlist('R1 a 0 0'#10);
  Check(not R.Ok and (Pos('resistencia', R.Message) > 0), 'resistencia zero recusada: ' + R.Message);
  FreeNetlistResult(R);
  R := RunNetlist('X1 a 0 1'#10);
  Check(not R.Ok and (Pos('desconhecido', R.Message) > 0), 'elemento desconhecido recusado');
  FreeNetlistResult(R);
  Finish('netlist e circuitos');
end.
