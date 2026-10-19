unit multiphysics_machine_faults;

{ Falhas injetaveis na maquina virtual (MP-7.6). Cada falha muda o modelo do
  eixo de forma que o efeito aparece na simulacao seguinte:
    circuito aberto  -> motor sem torque e comando desligado: o eixo nao anda
    curto-circuito   -> +10 A: desarme por sobrecorrente
    eixo travado     -> carga infinita: estol, passos perdidos
    sensor falhou    -> leitura de posicao 5 mm errada: o eixo para no lugar errado
    fim de curso preso -> homing zera no lugar errado
    corrosao/oxidacao -> aquecimento I2R 1,6x / 1,3x
    sobrecorrente    -> +6 A: desarme }

{$mode objfpc}{$H+}

interface

uses SysUtils, Math, multiphysics_machine_runtime;

type
  TMachineFault = (mfNone, mfOpenCircuit, mfShortCircuit, mfAxisLocked, mfSensorFailed,
    mfLimitStuck, mfCorrosion, mfOxidation, mfOverCurrent);

procedure InjectAxisFault(A: TAxisRuntime; Fault: TMachineFault);
procedure ClearAxisFaults(A: TAxisRuntime);
function MachineFaultName(F: TMachineFault): string;

implementation

procedure ClearAxisFaults(A: TAxisRuntime);
begin
  A.ExtraCurrent := 0;
  A.ResistanceFactor := 1;
  A.Locked := False;
  A.SensorOffsetMM := 0;
  A.LimitStuck := False;
  A.Motor.LoadTorque := 0;
end;

procedure InjectAxisFault(A: TAxisRuntime; Fault: TMachineFault);
begin
  case Fault of
    mfOpenCircuit:
      begin
        A.Current := 0;
        A.Motor.RunningTorque := 0;
        A.Motor.HoldingTorque := 0;
        A.Motor.LoadTorque := Max(A.Motor.LoadTorque, 1e-6);
        A.Command.Enabled := False;   { driver sem bobina: o comando nao executa }
      end;
    mfShortCircuit: A.ExtraCurrent := A.ExtraCurrent + 10;
    mfAxisLocked: A.Locked := True;
    mfSensorFailed: A.SensorOffsetMM := A.SensorOffsetMM + 5;
    mfLimitStuck:
      begin
        A.LimitStuck := True;
        A.State.AtMin := True;
      end;
    mfCorrosion: A.ResistanceFactor := A.ResistanceFactor * 1.6;
    mfOxidation: A.ResistanceFactor := A.ResistanceFactor * 1.3;
    mfOverCurrent: A.ExtraCurrent := A.ExtraCurrent + 6;
  end;
end;

function MachineFaultName(F: TMachineFault): string;
begin
  case F of
    mfOpenCircuit: Result := 'Circuito aberto';
    mfShortCircuit: Result := 'Curto-circuito';
    mfAxisLocked: Result := 'Eixo travado';
    mfSensorFailed: Result := 'Sensor falhou';
    mfLimitStuck: Result := 'Fim de curso preso';
    mfCorrosion: Result := 'Corrosao';
    mfOxidation: Result := 'Oxidacao';
    mfOverCurrent: Result := 'Sobrecorrente';
    else Result := 'Nenhuma';
  end;
end;

end.
