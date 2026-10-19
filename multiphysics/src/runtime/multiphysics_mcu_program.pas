unit multiphysics_mcu_program;

{ Programa do MCU virtual (MP-7.9): lista sequencial de instrucoes (com
  Delay) e eventos com hora marcada (AddAt). StepPulse gera um pulso de um
  passo de simulacao (sobe agora, desce no passo seguinte) e conta as bordas
  de subida por pino. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, multiphysics_mcu;

type
  TMCUOp = (moPinModeOut, moDigitalHigh, moDigitalLow, moPWM, moDelay, moStepPulse, moDirHigh, moDirLow);

  TMCUInstruction = record
    Op: TMCUOp;
    Pin: Integer;
    Value: Double;
    Time: Double;       { so eventos com hora marcada }
  end;

  TMCUProgram = class
  private
    FCode, FEvents: array of TMCUInstruction;
    FPC, FNextEvent: Integer;
    FWait: Double;
    FPulseLow: array of Integer;     { pinos que descem no proximo passo }
    FPulses: array of Int64;
    procedure Exec(M: TMCU; const I: TMCUInstruction);
  public
    procedure Add(Op: TMCUOp; Pin: Integer; Value: Double = 0);
    { evento em T segundos (tempo do MCU); eventos fora de ordem sao ordenados }
    procedure AddAt(T: Double; Op: TMCUOp; Pin: Integer; Value: Double = 0);
    { trem de N pulsos com frequencia F a partir de T0 }
    procedure AddPulseTrain(T0, F: Double; N, Pin: Integer);
    procedure Reset;
    procedure Step(M: TMCU; Dt: Double);
    function Count: Integer;
    function PulseCount(Pin: Integer): Int64;
  end;

implementation

procedure TMCUProgram.Add(Op: TMCUOp; Pin: Integer; Value: Double);
var
  N: Integer;
begin
  N := Length(FCode);
  SetLength(FCode, N + 1);
  FCode[N].Op := Op; FCode[N].Pin := Pin; FCode[N].Value := Value; FCode[N].Time := 0;
end;

procedure TMCUProgram.AddAt(T: Double; Op: TMCUOp; Pin: Integer; Value: Double);
var
  N, K: Integer;
begin
  N := Length(FEvents);
  SetLength(FEvents, N + 1);
  K := N;
  while (K > 0) and (FEvents[K - 1].Time > T) do
  begin
    FEvents[K] := FEvents[K - 1];
    Dec(K);
  end;
  FEvents[K].Op := Op; FEvents[K].Pin := Pin; FEvents[K].Value := Value; FEvents[K].Time := T;
end;

procedure TMCUProgram.AddPulseTrain(T0, F: Double; N, Pin: Integer);
var
  I: Integer;
begin
  if F <= 0 then Exit;
  for I := 0 to N - 1 do AddAt(T0 + I / F, moStepPulse, Pin);
end;

procedure TMCUProgram.Reset;
begin
  FPC := 0; FNextEvent := 0; FWait := 0;
  FPulseLow := nil;
  FPulses := nil;
end;

procedure TMCUProgram.Exec(M: TMCU; const I: TMCUInstruction);
var
  N: Integer;
begin
  case I.Op of
    moPinModeOut: M.PinMode(I.Pin, True);
    moDigitalHigh, moDirHigh: M.DigitalWrite(I.Pin, True);
    moDigitalLow, moDirLow: M.DigitalWrite(I.Pin, False);
    moPWM: M.PWMWrite(I.Pin, I.Value);
    moDelay: FWait := I.Value;
    moStepPulse:
      begin
        if not M.DigitalRead(I.Pin) then
        begin
          if I.Pin >= Length(FPulses) then SetLength(FPulses, I.Pin + 1);
          Inc(FPulses[I.Pin]);
        end;
        M.DigitalWrite(I.Pin, True);
        N := Length(FPulseLow);
        SetLength(FPulseLow, N + 1);
        FPulseLow[N] := I.Pin;
      end;
  end;
end;

procedure TMCUProgram.Step(M: TMCU; Dt: Double);
var
  K: Integer;
begin
  { descem os pulsos do passo anterior }
  for K := 0 to High(FPulseLow) do M.DigitalWrite(FPulseLow[K], False);
  FPulseLow := nil;
  M.Step(Dt);
  { eventos com hora marcada vencidos }
  while (FNextEvent < Length(FEvents)) and (FEvents[FNextEvent].Time <= M.Time + 1e-12) do
  begin
    Exec(M, FEvents[FNextEvent]);
    Inc(FNextEvent);
  end;
  { programa sequencial (repete do inicio) }
  if FWait > 0 then
  begin
    FWait := FWait - Dt;
    Exit;
  end;
  if Length(FCode) = 0 then Exit;
  if FPC >= Length(FCode) then FPC := 0;
  Exec(M, FCode[FPC]);
  Inc(FPC);
end;

function TMCUProgram.Count: Integer;
begin
  Result := Length(FCode) + Length(FEvents);
end;

function TMCUProgram.PulseCount(Pin: Integer): Int64;
begin
  if (Pin >= 0) and (Pin < Length(FPulses)) then Result := FPulses[Pin] else Result := 0;
end;

end.
