unit multicnc_grbl_status;

{$mode objfpc}{$H+}

{ Interpretacao das respostas da familia GRBL (Grbl 1.1, grblHAL, FluidNC).

  Cobre:
  - relatorio de status em tempo real: <Idle|MPos:..|WPos:..|WCO:..|Bf:..|
    Ln:..|FS:..|F:..|Ov:..|A:..|Pn:..>
  - ok / error:N / ALARM:N com texto explicativo em portugues;
  - banner de boas-vindas com deteccao de firmware e versao;
  - mensagens [MSG:..], [GC:..], [PRB:..] e configuracoes $N=V.

  A WPos e reconstruida a partir de MPos - WCO quando o firmware envia
  apenas uma delas (comportamento padrao do GRBL com $10). }

interface

uses
  SysUtils, multicnc_types;

type
  TGrblFirmware = (gfUnknown, gfGrbl, gfGrblHAL, gfFluidNC);

  TGrblMachineState = (gsUnknown, gsIdle, gsRun, gsHold, gsJog, gsAlarm,
    gsDoor, gsCheck, gsHome, gsSleep, gsTool);

  TGrblResponseKind = (grkNone, grkOk, grkError, grkAlarm, grkStatus,
    grkWelcome, grkMessage, grkFeedback, grkSetting, grkOther);

  TGrblResponse = record
    Kind: TGrblResponseKind;
    Code: Integer;
    Text: string;
  end;

  TGrblStatus = record
    State: TGrblMachineState;
    SubState: Integer;
    MPos, WPos, WCO: TMachinePosition;
    HasMPos, HasWPos, HasWCO: Boolean;
    Feed, Spindle: Double;
    PlannerFree, RxFree: Integer;    // -1 = nao informado
    LineNumber: Integer;             // -1 = nao informado
    FeedOverride, RapidOverride, SpindleOverride: Integer;
    Pins: string;                    // ex.: 'XYZP' (limites/probe ativos)
    Accessories: string;             // ex.: 'SFM' (spindle, flood, mist)
  end;

  TGrblStatusParser = class
  private
    FStatus: TGrblStatus;
    FFirmware: TGrblFirmware;
    FVersion: string;
    FLastAlarm, FLastError: Integer;
    procedure ParseStatus(const Body: string);
  public
    constructor Create;
    procedure Reset;
    function ParseLine(const ALine: string): TGrblResponse;
    property Status: TGrblStatus read FStatus;
    property Firmware: TGrblFirmware read FFirmware;
    property Version: string read FVersion;
    property LastAlarm: Integer read FLastAlarm;
    property LastError: Integer read FLastError;
  end;

function GrblStateFromText(const S: string): TGrblMachineState;
function GrblStateToMachineState(S: TGrblMachineState): TMachineState;
function GrblErrorText(Code: Integer): string;
function GrblAlarmText(Code: Integer): string;
function GrblFirmwareName(F: TGrblFirmware): string;
function ParseAxisList(const S: string; out P: TMachinePosition): Boolean;

implementation

function InvariantFloat(const S: string; Default: Double): Double;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(Trim(S), Result, FS) then Result := Default;
end;

function ParseAxisList(const S: string; out P: TMachinePosition): Boolean;
var Parts: TStringArray; V: array[0..3] of Double; I: Integer;
begin
  P := EmptyPosition;
  Parts := S.Split([',']);
  Result := Length(Parts) >= 3;
  if not Result then Exit;
  FillChar(V, SizeOf(V), 0);
  for I := 0 to High(Parts) do
    if I <= High(V) then V[I] := InvariantFloat(Parts[I], 0);
  P.X := V[0]; P.Y := V[1]; P.Z := V[2]; P.A := V[3];
end;

function GrblStateFromText(const S: string): TGrblMachineState;
var U: string;
begin
  U := LowerCase(S);
  if U = 'idle' then Result := gsIdle
  else if U = 'run' then Result := gsRun
  else if U = 'hold' then Result := gsHold
  else if U = 'jog' then Result := gsJog
  else if U = 'alarm' then Result := gsAlarm
  else if U = 'door' then Result := gsDoor
  else if U = 'check' then Result := gsCheck
  else if U = 'home' then Result := gsHome
  else if U = 'sleep' then Result := gsSleep
  else if U = 'tool' then Result := gsTool
  else Result := gsUnknown;
end;

function GrblStateToMachineState(S: TGrblMachineState): TMachineState;
begin
  case S of
    gsIdle, gsCheck, gsSleep: Result := msIdle;
    gsRun, gsJog, gsHome: Result := msRunning;
    gsHold, gsDoor, gsTool: Result := msPaused;
    gsAlarm: Result := msAlarm;
  else
    Result := msError;
  end;
end;

function GrblFirmwareName(F: TGrblFirmware): string;
begin
  case F of
    gfGrbl: Result := 'Grbl';
    gfGrblHAL: Result := 'grblHAL';
    gfFluidNC: Result := 'FluidNC';
  else
    Result := 'Desconhecido';
  end;
end;

function GrblErrorText(Code: Integer): string;
begin
  case Code of
    1: Result := 'Palavra G-code sem letra';
    2: Result := 'Valor numerico ausente ou invalido';
    3: Result := 'Comando $ nao reconhecido';
    4: Result := 'Valor negativo onde se esperava positivo';
    5: Result := 'Homing nao habilitado ($22)';
    6: Result := 'Pulso de passo minimo deve ser maior que 3 us';
    7: Result := 'Falha de leitura da EEPROM; padroes restaurados';
    8: Result := 'Comando $ exige estado Idle';
    9: Result := 'G-code bloqueado em alarme ou jog';
    10: Result := 'Soft limits exigem homing habilitado';
    11: Result := 'Linha excede o tamanho maximo';
    12: Result := 'Valor excede a taxa maxima de passos';
    13: Result := 'Porta de seguranca aberta';
    14: Result := 'Linha de inicializacao/build info muito longa';
    15: Result := 'Destino do jog excede o curso da maquina';
    16: Result := 'Comando de jog invalido';
    17: Result := 'Modo laser requer saida PWM';
    20: Result := 'Comando G-code nao suportado';
    21: Result := 'Dois comandos do mesmo grupo modal no bloco';
    22: Result := 'Avanco (F) nao definido';
    23: Result := 'Comando exige valor inteiro';
    24: Result := 'Dois comandos que usam eixos no mesmo bloco';
    25: Result := 'Palavra G-code repetida no bloco';
    26: Result := 'Comando exige palavras de eixo';
    27: Result := 'Numero de linha N fora do intervalo';
    28: Result := 'Faltam palavras P ou L';
    29: Result := 'Sistema de coordenadas nao suportado';
    30: Result := 'G53 exige G0 ou G1 ativo';
    31: Result := 'Palavras de eixo sem uso com G80 ativo';
    32: Result := 'Arco sem eixos no plano selecionado';
    33: Result := 'Destino de movimento invalido';
    34: Result := 'Erro de geometria do raio do arco';
    35: Result := 'Offsets IJK do arco ausentes no plano';
    36: Result := 'Palavras de valor sem uso no bloco';
    37: Result := 'Compensacao dinamica de ferramenta em eixo invalido';
    38: Result := 'Numero de ferramenta acima do suportado';
  else
    Result := 'Erro ' + IntToStr(Code);
  end;
end;

function GrblAlarmText(Code: Integer): string;
begin
  case Code of
    1: Result := 'Fim de curso (hard limit) acionado; reposicao perdida';
    2: Result := 'Movimento excede o curso (soft limit)';
    3: Result := 'Reset durante movimento; reposicao perdida';
    4: Result := 'Probe ja acionado antes do ciclo';
    5: Result := 'Probe nao tocou a peca';
    6: Result := 'Homing interrompido por reset';
    7: Result := 'Homing interrompido por porta aberta';
    8: Result := 'Homing nao conseguiu liberar o fim de curso';
    9: Result := 'Homing nao encontrou o fim de curso';
    10: Result := 'Parada de emergencia / homing de eixo duplo falhou';
  else
    Result := 'Alarme ' + IntToStr(Code);
  end;
end;

constructor TGrblStatusParser.Create;
begin
  inherited Create;
  Reset;
end;

procedure TGrblStatusParser.Reset;
begin
  FillChar(FStatus, SizeOf(FStatus), 0);
  FStatus.State := gsUnknown;
  FStatus.PlannerFree := -1;
  FStatus.RxFree := -1;
  FStatus.LineNumber := -1;
  FStatus.FeedOverride := 100;
  FStatus.RapidOverride := 100;
  FStatus.SpindleOverride := 100;
  FLastAlarm := 0;
  FLastError := 0;
end;

procedure TGrblStatusParser.ParseStatus(const Body: string);
var Fields, Pair: TStringArray; I, P: Integer; Key, Value, StateText: string;
  Pos3: TMachinePosition;
begin
  Fields := Body.Split(['|']);
  if Length(Fields) = 0 then Exit;
  StateText := Fields[0];
  P := Pos(':', StateText);
  if P > 0 then begin
    FStatus.SubState := StrToIntDef(Copy(StateText, P + 1, MaxInt), 0);
    StateText := Copy(StateText, 1, P - 1);
  end else
    FStatus.SubState := 0;
  FStatus.State := GrblStateFromText(StateText);
  FStatus.HasMPos := False;
  FStatus.HasWPos := False;
  FStatus.Pins := '';
  FStatus.Accessories := '';
  for I := 1 to High(Fields) do begin
    P := Pos(':', Fields[I]);
    if P = 0 then Continue;
    Key := Copy(Fields[I], 1, P - 1);
    Value := Copy(Fields[I], P + 1, MaxInt);
    if Key = 'MPos' then begin
      FStatus.HasMPos := ParseAxisList(Value, FStatus.MPos);
    end else if Key = 'WPos' then begin
      FStatus.HasWPos := ParseAxisList(Value, FStatus.WPos);
    end else if Key = 'WCO' then begin
      if ParseAxisList(Value, Pos3) then begin
        FStatus.WCO := Pos3;
        FStatus.HasWCO := True;
      end;
    end else if Key = 'Bf' then begin
      Pair := Value.Split([',']);
      if Length(Pair) >= 2 then begin
        FStatus.PlannerFree := StrToIntDef(Pair[0], -1);
        FStatus.RxFree := StrToIntDef(Pair[1], -1);
      end;
    end else if Key = 'Ln' then
      FStatus.LineNumber := StrToIntDef(Value, -1)
    else if Key = 'FS' then begin
      Pair := Value.Split([',']);
      if Length(Pair) >= 1 then FStatus.Feed := InvariantFloat(Pair[0], 0);
      if Length(Pair) >= 2 then FStatus.Spindle := InvariantFloat(Pair[1], 0);
    end else if Key = 'F' then
      FStatus.Feed := InvariantFloat(Value, 0)
    else if Key = 'Ov' then begin
      Pair := Value.Split([',']);
      if Length(Pair) >= 3 then begin
        FStatus.FeedOverride := StrToIntDef(Pair[0], 100);
        FStatus.RapidOverride := StrToIntDef(Pair[1], 100);
        FStatus.SpindleOverride := StrToIntDef(Pair[2], 100);
      end;
    end else if Key = 'Pn' then
      FStatus.Pins := Value
    else if Key = 'A' then
      FStatus.Accessories := Value;
  end;
  // Reconstroi a coordenada ausente usando o ultimo WCO conhecido.
  if FStatus.HasMPos and not FStatus.HasWPos then begin
    FStatus.WPos.X := FStatus.MPos.X - FStatus.WCO.X;
    FStatus.WPos.Y := FStatus.MPos.Y - FStatus.WCO.Y;
    FStatus.WPos.Z := FStatus.MPos.Z - FStatus.WCO.Z;
    FStatus.WPos.A := FStatus.MPos.A - FStatus.WCO.A;
    FStatus.HasWPos := True;
  end else if FStatus.HasWPos and not FStatus.HasMPos then begin
    FStatus.MPos.X := FStatus.WPos.X + FStatus.WCO.X;
    FStatus.MPos.Y := FStatus.WPos.Y + FStatus.WCO.Y;
    FStatus.MPos.Z := FStatus.WPos.Z + FStatus.WCO.Z;
    FStatus.MPos.A := FStatus.WPos.A + FStatus.WCO.A;
    FStatus.HasMPos := True;
  end;
end;

function TGrblStatusParser.ParseLine(const ALine: string): TGrblResponse;
var L, Low: string; P, Q: Integer;
begin
  Result.Kind := grkNone;
  Result.Code := 0;
  Result.Text := '';
  L := Trim(ALine);
  if L = '' then Exit;
  Result.Text := L;
  Low := LowerCase(L);
  if Low = 'ok' then
    Result.Kind := grkOk
  else if Copy(Low, 1, 6) = 'error:' then begin
    Result.Kind := grkError;
    Result.Code := StrToIntDef(Trim(Copy(L, 7, MaxInt)), 0);
    FLastError := Result.Code;
    Result.Text := GrblErrorText(Result.Code);
  end else if Copy(Low, 1, 6) = 'alarm:' then begin
    Result.Kind := grkAlarm;
    Result.Code := StrToIntDef(Trim(Copy(L, 7, MaxInt)), 0);
    FLastAlarm := Result.Code;
    FStatus.State := gsAlarm;
    Result.Text := GrblAlarmText(Result.Code);
  end else if (L[1] = '<') and (L[Length(L)] = '>') then begin
    Result.Kind := grkStatus;
    ParseStatus(Copy(L, 2, Length(L) - 2));
  end else if Pos('fluidnc', Low) > 0 then begin
    Result.Kind := grkWelcome;
    FFirmware := gfFluidNC;
    P := Pos('fluidnc v', Low);
    if P > 0 then begin
      Q := P + 9;
      while (Q <= Length(L)) and (L[Q] <> ' ') and (L[Q] <> ')') do Inc(Q);
      FVersion := Copy(L, P + 9, Q - P - 9);
    end;
    Reset;
  end else if (Copy(Low, 1, 8) = 'grblhal ') or (Copy(Low, 1, 5) = 'grbl ') then begin
    Result.Kind := grkWelcome;
    if Copy(Low, 1, 8) = 'grblhal ' then begin
      FFirmware := gfGrblHAL;
      P := 9;
    end else begin
      FFirmware := gfGrbl;
      P := 6;
    end;
    Q := P;
    while (Q <= Length(L)) and (L[Q] <> ' ') do Inc(Q);
    FVersion := Copy(L, P, Q - P);
    Reset;
  end else if Copy(L, 1, 5) = '[MSG:' then
    Result.Kind := grkMessage
  else if L[1] = '[' then begin
    Result.Kind := grkFeedback;
    // grblHAL anuncia-se em [FIRMWARE:grblHAL] na resposta de $I
    if Pos('[firmware:grblhal]', Low) > 0 then FFirmware := gfGrblHAL;
  end else if (L[1] = '$') and (Pos('=', L) > 0) then
    Result.Kind := grkSetting
  else
    Result.Kind := grkOther;
end;

end.
