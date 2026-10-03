unit multicnc_safety;

{ Regras aplicadas pelo nucleo a todo comando antes de chegar ao transporte.
  Nao substituem a parada de emergencia fisica nem os limites do firmware
  (no GRBL, habilite soft limits com $20=1 e homing com $22=1). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multicnc_types;

const
  { Linha maior que o buffer de linha do GRBL (80) com folga; acima disso o
    comando e rejeitado em vez de truncado pela controladora. }
  MaxCommandLength = 127;

type
  TWorkEnvelope = record
    X, Y, Z: Double; { curso util por eixo em mm; 0 = desconhecido }
  end;

  TSafetyValidator = class
  public
    class function CanMove(AState: TMachineState; AAxis: TAxis;
      const C: TMachineCapabilities; out Reason: string): Boolean;
    class function CheckJog(AState: TMachineState; AAxis: TAxis; ADistance, AFeed: Double;
      const C: TMachineCapabilities; const E: TWorkEnvelope; out Reason: string): Boolean;
    { Valida uma linha de G-code ou comando de firmware. }
    class function CheckCommand(AState: TMachineState; const ALine: string;
      out Reason: string): Boolean;
    { Comandos aceitos em alarme: desbloqueio, referenciamento, consultas. }
    class function AllowedInAlarm(const ALine: string): Boolean;
    { Detecta "X10,5": virgula decimal gerada por configuracao regional. }
    class function HasDecimalComma(const ALine: string): Boolean;
  end;

implementation

class function TSafetyValidator.CanMove(AState: TMachineState; AAxis: TAxis;
  const C: TMachineCapabilities; out Reason: string): Boolean;
begin
  Reason := '';
  if AState in [msDisconnected, msConnecting, msAlarm, msError] then
  begin
    Reason := 'Estado da maquina nao permite movimento';
    Exit(False);
  end;
  if not (AAxis in C.Axes) then
  begin
    Reason := 'Eixo nao suportado';
    Exit(False);
  end;
  Result := True;
end;

class function TSafetyValidator.CheckJog(AState: TMachineState; AAxis: TAxis;
  ADistance, AFeed: Double; const C: TMachineCapabilities; const E: TWorkEnvelope;
  out Reason: string): Boolean;
var Travel: Double;
begin
  Result := CanMove(AState, AAxis, C, Reason);
  if not Result then Exit;
  if (ADistance = 0) or IsNan(ADistance) or IsInfinite(ADistance) then
  begin
    Reason := 'Distancia invalida';
    Exit(False);
  end;
  if (AFeed <= 0) or IsNan(AFeed) or IsInfinite(AFeed) then
  begin
    Reason := 'Avanco invalido';
    Exit(False);
  end;
  case AAxis of
    axX: Travel := E.X;
    axY: Travel := E.Y;
    axZ: Travel := E.Z;
  else
    Travel := 0;
  end;
  if (Travel > 0) and (Abs(ADistance) > Travel) then
  begin
    Reason := Format('Deslocamento maior que o curso do eixo (%.0f mm)', [Travel]);
    Exit(False);
  end;
end;

class function TSafetyValidator.HasDecimalComma(const ALine: string): Boolean;
var I: Integer; InComment: Boolean;
begin
  Result := False;
  InComment := False;
  for I := 2 to Length(ALine) - 1 do
  begin
    if ALine[I] = '(' then InComment := True
    else if ALine[I] = ')' then InComment := False
    else if ALine[I] = ';' then Exit
    else if (not InComment) and (ALine[I] = ',') and
      (ALine[I - 1] in ['0'..'9']) and (ALine[I + 1] in ['0'..'9']) then
      Exit(True);
  end;
end;

class function TSafetyValidator.AllowedInAlarm(const ALine: string): Boolean;
var U: string;
begin
  U := UpperCase(Trim(ALine));
  Result :=
    ((U <> '') and (U[1] = '$') and (Copy(U, 1, 3) <> '$J=')) or { $X, $H, $$, $#, $I... }
    (U = '?') or (U = 'M999') or (U = 'M112') or (U = 'M410') or
    (U = 'M114') or (U = 'M105') or (U = 'M115') or (U = 'M119') or
    (U = 'M5') or (U = 'M107') or (Copy(U, 1, 7) = 'M104 S0') or (Copy(U, 1, 7) = 'M140 S0');
end;

class function TSafetyValidator.CheckCommand(AState: TMachineState; const ALine: string;
  out Reason: string): Boolean;
var I: Integer; L: string;
begin
  Reason := '';
  Result := False;
  L := Trim(ALine);
  if L = '' then begin Reason := 'Comando vazio'; Exit; end;
  if AState in [msDisconnected, msConnecting] then
  begin
    Reason := 'Maquina desconectada';
    Exit;
  end;
  if Length(L) > MaxCommandLength then
  begin
    Reason := Format('Linha com mais de %d caracteres', [MaxCommandLength]);
    Exit;
  end;
  for I := 1 to Length(L) do
    if (L[I] < ' ') and (L[I] <> #9) then
    begin
      Reason := 'Caractere de controle no comando';
      Exit;
    end;
  if HasDecimalComma(L) then
  begin
    Reason := 'Numero com virgula decimal (use ponto): ' + L;
    Exit;
  end;
  if (AState in [msAlarm, msError]) and not AllowedInAlarm(L) then
  begin
    Reason := 'Maquina em alarme/erro: desbloqueie ou referencie antes de mover';
    Exit;
  end;
  Result := True;
end;

end.
