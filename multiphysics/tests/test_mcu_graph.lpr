program test_mcu_graph;

{ MCU por eventos (MP-7.9) e validacao do grafo (MP-7.2): trem de pulsos
  STEP com frequencia exata, resolucao do PWM por perfil, ADC, e erros e
  avisos do grafo (porta inexistente, tipo diferente, componente solto). }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, multiphysics_mcu, multiphysics_mcu_program, multiphysics_graph,
  multiphysics_component_library, multiphysics_graph_runtime, multiphysics_check;

var
  M: TMCU;
  P: TMCUProgram;
  I: Integer;
  G: TSimulationGraph;
  Log: TStringList;
  Ok: Boolean;
  C: TSimComponent;

begin
  Section('MCU por eventos');
  M := TMCU.Create(mfESP32);
  P := TMCUProgram.Create;
  try
    P.AddAt(0, moPinModeOut, 18);
    P.AddPulseTrain(0.001, 1000, 200, 18);       { 200 pulsos a 1 kHz a partir de 1 ms }
    for I := 1 to 3000 do P.Step(M, 0.0001);      { 0,3 s }
    Check(P.PulseCount(18) = 200, Format('200 pulsos STEP (%d)', [P.PulseCount(18)]));
    Check(not M.DigitalRead(18), 'pulso de um passo: pino volta a 0');
    M.PWMWrite(5, 0.3333);
    CheckNear(M.PWMRead(5), Round(0.3333 * 1023) / 1023, 1e-12, 'ESP32: PWM com 10 bits');
    M.AnalogInput(4, 1.65);
    Check(Abs(M.AnalogRead(4, 3.3) - 2048) <= 1, 'ESP32: ADC 12 bits, meia escala = 2048');
  finally
    P.Free; M.Free;
  end;
  M := TMCU.Create(mfATmega328P);
  try
    M.PWMWrite(3, 0.5);
    CheckNear(M.PWMRead(3), 128 / 255, 1e-12, 'ATmega328P: PWM com 8 bits (128/255)');
  finally
    M.Free;
  end;

  Section('Validacao do grafo');
  Log := TStringList.Create;
  G := BuildDemoMachine;
  try
    Ok := G.Validate(Log);
    Check(Ok and (Pos('Grafo valido', Log.Text) > 0), 'maquina demo valida');
    Log.Clear;
    G.AddComponent(NewSpeedSensor('S2'));
    Ok := G.Validate(Log);
    Check(Ok and (Pos('sem ligacao: S2', Log.Text) > 0), 'componente solto gera aviso');
    Check(not G.Connect('PSU1', 'V+', 'S2', 'OUT', ptElectrical), 'ligacao com tipo de porta diferente recusada');
    Log.Clear;
    C := G.Find('S2');
    C.AddPort('X', ptElectrical);
    Check(G.Connect('PSU1', 'V+', 'S2', 'X', ptElectrical), 'ligacao eletrica aceita');
    C.Parameters.Values['dummy'] := '1';
    Ok := G.Validate(Log);
    Check(Ok, 'grafo continua valido');
  finally
    G.Free; Log.Free;
  end;
  Finish('MCU por eventos e grafo');
end.
