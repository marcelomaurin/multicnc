unit multisuite_gcode_writer;

{ Emissor de G-code comum da suite (contrato em docs/CONTRATO_GCODE.md).

  - Zero virtual: o programa so conhece o ponto de zero da peca; quem amarra
    esse zero a mesa e o MultiCNC (Zero Workpiece + Frame).
  - Cabecalho: linha 1 "; <Origem> -> MultiCNC (CNC Router)" e linhas
    "; MS-..." legiveis por maquina (CONTRACT, MACHINE, DATUM, STOCK, BOUNDS,
    TOOL, STAGE).
  - So G21 G90 G94, G0, G1, G4, M0, M2, M3, M5. Ponto decimal sempre, linhas
    de no maximo 127 caracteres. Avanco (F) so quando muda.
  - SuiteCheckGCode confere um programa contra essas regras (usado nos testes
    e antes de gravar).

  Sem LCL: pode ser usado por qualquer ferramenta e pelos testes. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

const
  SUITE_GCODE_CONTRACT = 1;
  SUITE_GCODE_MAXLINE = 127;

type
  TSuiteGCodeHeader = record
    Origin: string;        { 'MakeRouter', 'RouterPCB' ... }
    Machine: string;       { 'router' | 'laser' }
    DatumXY: string;       { BL BC BR ML C MR TL TC TR }
    DatumZ: string;        { TOP | TABLE }
    StockW, StockH, StockT: Double;
    ToolNumber: Integer;
    ToolName: string;
    ToolDiameter: Double;
    StageIndex, StageCount: Integer;
    StageName: string;
    Title: string;
    ZeroText: string;      { frase para o operador }
  end;

  TSuiteBounds = record
    X0, X1, Y0, Y1, Z0, Z1: Double;
    Valid: Boolean;
  end;

  TSuiteGCodeWriter = class
  private
    FBody: TStringList;
    FX, FY, FZ, FF: Double;
    FHasXY, FHasZ: Boolean;
    FBounds: TSuiteBounds;
    FCutLength, FRapidLength, FSeconds: Double;
    FRapidFeed: Double;
    procedure Track(X, Y, Z: Double);
    procedure Emit(const S: string);
  public
    SafeZ: Double;
    constructor Create(ASafeZ: Double; ARapidFeed: Double = 3000);
    destructor Destroy; override;
    procedure Comment(const S: string);
    procedure RapidZ(Z: Double);
    procedure Rapid(X, Y: Double);
    procedure Feed(X, Y, Z, F: Double);
    procedure FeedZ(Z, F: Double);
    procedure Dwell(Seconds: Double);
    procedure SpindleOn(RPM: Double; SpinUpSeconds: Double);
    procedure SpindleOff;
    procedure Pause(const Msg: string);
    { programa completo: cabecalho + G21 G90 G94 + corpo + fim (Z seguro, M5,
      X0 Y0, M2). O chamador libera a lista. }
    function Build(const H: TSuiteGCodeHeader): TStringList;
    property Bounds: TSuiteBounds read FBounds;
    property CutLength: Double read FCutLength;
    property RapidLength: Double read FRapidLength;
    { tempo estimado (sem aceleracao), em segundos }
    property Seconds: Double read FSeconds;
    property X: Double read FX;
    property Y: Double read FY;
    property Z: Double read FZ;
  end;

function SuiteFmt(V: Double): string;
function SuiteEmptyHeader: TSuiteGCodeHeader;
{ confere as regras do contrato; True se tudo certo }
function SuiteCheckGCode(Lines: TStrings; Errors: TStrings): Boolean;
{ le as linhas "; MS-..." do inicio do programa (o que nao achar fica vazio) }
function SuiteParseHeader(Lines: TStrings; out H: TSuiteGCodeHeader; out B: TSuiteBounds): Boolean;

implementation

var
  InvFS: TFormatSettings;

function SuiteFmt(V: Double): string;
begin
  if Abs(V) < 0.0005 then V := 0;
  Result := FormatFloat('0.###', V, InvFS);
end;

function SuiteEmptyHeader: TSuiteGCodeHeader;
begin
  Result := Default(TSuiteGCodeHeader);
  Result.Machine := 'router';
  Result.DatumXY := 'BL';
  Result.DatumZ := 'TOP';
end;

{ ---------------- TSuiteGCodeWriter ---------------- }

constructor TSuiteGCodeWriter.Create(ASafeZ: Double; ARapidFeed: Double);
begin
  inherited Create;
  FBody := TStringList.Create;
  SafeZ := ASafeZ;
  FRapidFeed := Max(1, ARapidFeed);
  FF := -1;
  FBounds.Valid := False;
end;

destructor TSuiteGCodeWriter.Destroy;
begin
  FBody.Free;
  inherited Destroy;
end;

procedure TSuiteGCodeWriter.Emit(const S: string);
begin
  FBody.Add(S);
end;

procedure TSuiteGCodeWriter.Track(X, Y, Z: Double);
begin
  if not FBounds.Valid then
  begin
    FBounds.X0 := X; FBounds.X1 := X; FBounds.Y0 := Y; FBounds.Y1 := Y;
    FBounds.Z0 := Z; FBounds.Z1 := Z; FBounds.Valid := True;
  end
  else
  begin
    FBounds.X0 := Min(FBounds.X0, X); FBounds.X1 := Max(FBounds.X1, X);
    FBounds.Y0 := Min(FBounds.Y0, Y); FBounds.Y1 := Max(FBounds.Y1, Y);
    FBounds.Z0 := Min(FBounds.Z0, Z); FBounds.Z1 := Max(FBounds.Z1, Z);
  end;
end;

procedure TSuiteGCodeWriter.Comment(const S: string);
begin
  Emit('; ' + Copy(S, 1, SUITE_GCODE_MAXLINE - 2));
end;

procedure TSuiteGCodeWriter.RapidZ(Z: Double);
begin
  if FHasZ and (Abs(Z - FZ) < 1e-6) then Exit;
  if FHasZ then
  begin
    FRapidLength := FRapidLength + Abs(Z - FZ);
    FSeconds := FSeconds + Abs(Z - FZ) / FRapidFeed * 60;
  end;
  Emit('G0 Z' + SuiteFmt(Z));
  FZ := Z; FHasZ := True;
  if FHasXY then Track(FX, FY, FZ);
end;

procedure TSuiteGCodeWriter.Rapid(X, Y: Double);
var D: Double;
begin
  if FHasXY and (Abs(X - FX) < 1e-6) and (Abs(Y - FY) < 1e-6) then Exit;
  if FHasXY then
  begin
    D := Hypot(X - FX, Y - FY);
    FRapidLength := FRapidLength + D;
    FSeconds := FSeconds + D / FRapidFeed * 60;
  end;
  Emit('G0 X' + SuiteFmt(X) + ' Y' + SuiteFmt(Y));
  FX := X; FY := Y; FHasXY := True;
  if FHasZ then Track(FX, FY, FZ);
end;

procedure TSuiteGCodeWriter.Feed(X, Y, Z, F: Double);
var S: string; D: Double;
begin
  if FHasXY and FHasZ and (Abs(X - FX) < 1e-6) and (Abs(Y - FY) < 1e-6) and (Abs(Z - FZ) < 1e-6) then Exit;
  S := 'G1';
  if not FHasXY or (Abs(X - FX) >= 1e-6) then S := S + ' X' + SuiteFmt(X);
  if not FHasXY or (Abs(Y - FY) >= 1e-6) then S := S + ' Y' + SuiteFmt(Y);
  if not FHasZ or (Abs(Z - FZ) >= 1e-6) then S := S + ' Z' + SuiteFmt(Z);
  if Abs(F - FF) > 1e-6 then begin S := S + ' F' + SuiteFmt(F); FF := F; end;
  if FHasXY and FHasZ then
  begin
    D := Sqrt(Sqr(X - FX) + Sqr(Y - FY) + Sqr(Z - FZ));
    FCutLength := FCutLength + D;
    if F > 0 then FSeconds := FSeconds + D / F * 60;
  end;
  Emit(S);
  FX := X; FY := Y; FZ := Z; FHasXY := True; FHasZ := True;
  Track(FX, FY, FZ);
end;

procedure TSuiteGCodeWriter.FeedZ(Z, F: Double);
begin
  if not FHasXY then raise Exception.Create('FeedZ sem posicao XY');
  Feed(FX, FY, Z, F);
end;

procedure TSuiteGCodeWriter.Dwell(Seconds: Double);
begin
  if Seconds <= 0 then Exit;
  Emit('G4 P' + SuiteFmt(Seconds));
  FSeconds := FSeconds + Seconds;
end;

procedure TSuiteGCodeWriter.SpindleOn(RPM: Double; SpinUpSeconds: Double);
begin
  if RPM > 0 then Emit('M3 S' + SuiteFmt(RPM)) else Emit('M3');
  Dwell(SpinUpSeconds);
end;

procedure TSuiteGCodeWriter.SpindleOff;
begin
  Emit('M5');
end;

procedure TSuiteGCodeWriter.Pause(const Msg: string);
begin
  if Msg <> '' then Comment(Msg);
  Emit('M0');
end;

function TSuiteGCodeWriter.Build(const H: TSuiteGCodeHeader): TStringList;
var R, B: Double;
begin
  Result := TStringList.Create;
  try
    Result.Add('; ' + H.Origin + ' -> MultiCNC (CNC Router)');
    Result.Add('; MS-CONTRACT: ' + IntToStr(SUITE_GCODE_CONTRACT));
    Result.Add('; MS-MACHINE: ' + H.Machine);
    Result.Add('; MS-DATUM: XY=' + H.DatumXY + ' Z=' + H.DatumZ);
    if (H.StockW > 0) and (H.StockH > 0) then
      Result.Add('; MS-STOCK: W=' + SuiteFmt(H.StockW) + ' H=' + SuiteFmt(H.StockH) +
        ' T=' + SuiteFmt(H.StockT));
    if FBounds.Valid then
    begin
      R := Max(0, H.ToolDiameter / 2);
      B := Max(SafeZ, FBounds.Z1);
      Result.Add('; MS-BOUNDS: X0=' + SuiteFmt(FBounds.X0 - R) + ' X1=' + SuiteFmt(FBounds.X1 + R) +
        ' Y0=' + SuiteFmt(FBounds.Y0 - R) + ' Y1=' + SuiteFmt(FBounds.Y1 + R) +
        ' Z0=' + SuiteFmt(FBounds.Z0) + ' Z1=' + SuiteFmt(B));
    end;
    if H.ToolName <> '' then
      Result.Add(Copy('; MS-TOOL: T' + IntToStr(Max(1, H.ToolNumber)) + ' "' +
        StringReplace(H.ToolName, '"', '''', [rfReplaceAll]) + '" D=' + SuiteFmt(H.ToolDiameter),
        1, SUITE_GCODE_MAXLINE));
    if H.StageCount > 0 then
      Result.Add(Copy('; MS-STAGE: ' + IntToStr(H.StageIndex) + '/' + IntToStr(H.StageCount) +
        ' ' + H.StageName, 1, SUITE_GCODE_MAXLINE));
    if H.Title <> '' then Result.Add(Copy('; ' + H.Title, 1, SUITE_GCODE_MAXLINE));
    if H.ZeroText <> '' then Result.Add(Copy('; Zero: ' + H.ZeroText, 1, SUITE_GCODE_MAXLINE));
    Result.Add('G21');
    Result.Add('G90');
    Result.Add('G94');
    Result.Add('G0 Z' + SuiteFmt(SafeZ));
    Result.AddStrings(FBody);
    Result.Add('G0 Z' + SuiteFmt(SafeZ));
    Result.Add('M5');
    Result.Add('G0 X0 Y0');
    Result.Add('M2');
  except
    Result.Free;
    raise;
  end;
end;

{ ---------------- verificacao ---------------- }

function SuiteCheckGCode(Lines: TStrings; Errors: TStrings): Boolean;
const
  Allowed: array[0..9] of string = ('G0', 'G1', 'G4', 'G21', 'G90', 'G94', 'M0', 'M2', 'M3', 'M5');
var
  I, K, P: Integer;
  L, W, U: string;
  Ok: Boolean;
  Parts: TStringList;
  procedure Bad(const Msg: string);
  begin
    Errors.Add(Format('Linha %d: %s (%s)', [I + 1, Msg, Copy(Lines[I], 1, 40)]));
  end;
begin
  Result := True;
  if (Lines.Count = 0) or (Pos('-> MultiCNC', Lines[0]) = 0) then
  begin
    Errors.Add('Primeira linha sem "-> MultiCNC"');
    Result := False;
  end;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' '; Parts.StrictDelimiter := True;
    for I := 0 to Lines.Count - 1 do
    begin
      L := Lines[I];
      if Length(L) > SUITE_GCODE_MAXLINE then begin Bad('linha longa'); Result := False; end;
      for K := 1 to Length(L) do
        if L[K] < ' ' then begin Bad('caractere de controle'); Result := False; Break; end;
      if (L = '') or (L[1] = ';') then Continue;
      if Pos(',', L) > 0 then begin Bad('virgula'); Result := False; end;
      Parts.DelimitedText := Trim(L);
      for K := 0 to Parts.Count - 1 do
      begin
        W := UpperCase(Parts[K]);
        if W = '' then Continue;
        if W[1] in ['G', 'M'] then
        begin
          U := W;
          Ok := False;
          for P := 0 to High(Allowed) do if U = Allowed[P] then Ok := True;
          if not Ok then begin Bad('codigo nao permitido ' + U); Result := False; end;
        end
        else if not (W[1] in ['X', 'Y', 'Z', 'F', 'S', 'P']) then
        begin
          Bad('palavra desconhecida ' + W); Result := False;
        end;
      end;
    end;
  finally
    Parts.Free;
  end;
end;

function ValueOf(const S, Key: string; out V: string): Boolean;
var P, E: Integer;
begin
  P := Pos(Key + '=', S);
  Result := P > 0;
  if not Result then Exit;
  P := P + Length(Key) + 1;
  E := P;
  while (E <= Length(S)) and (S[E] <> ' ') do Inc(E);
  V := Copy(S, P, E - P);
end;

function NumOf(const S, Key: string; var D: Double): Boolean;
var V: string;
begin
  Result := ValueOf(S, Key, V) and TryStrToFloat(V, D, InvFS);
end;

function SuiteParseHeader(Lines: TStrings; out H: TSuiteGCodeHeader; out B: TSuiteBounds): Boolean;
var I: Integer; L, V: string;
begin
  H := SuiteEmptyHeader;
  H.Machine := '';
  B := Default(TSuiteBounds);
  Result := False;
  for I := 0 to Min(Lines.Count, 40) - 1 do
  begin
    L := Trim(Lines[I]);
    if (L = '') or (L[1] <> ';') then Break;
    if (I = 0) and (Pos(' -> MultiCNC', L) > 0) then
      H.Origin := Trim(Copy(L, 2, Pos(' -> MultiCNC', L) - 2));
    if Pos('; MS-CONTRACT:', L) = 1 then Result := True
    else if Pos('; MS-MACHINE:', L) = 1 then H.Machine := Trim(Copy(L, 14, MaxInt))
    else if Pos('; MS-DATUM:', L) = 1 then
    begin
      if ValueOf(L, 'XY', V) then H.DatumXY := V;
      if ValueOf(L, 'Z', V) then H.DatumZ := V;
    end
    else if Pos('; MS-STOCK:', L) = 1 then
    begin
      NumOf(L, 'W', H.StockW); NumOf(L, 'H', H.StockH); NumOf(L, 'T', H.StockT);
    end
    else if Pos('; MS-BOUNDS:', L) = 1 then
      B.Valid := NumOf(L, 'X0', B.X0) and NumOf(L, 'X1', B.X1) and NumOf(L, 'Y0', B.Y0) and
        NumOf(L, 'Y1', B.Y1) and NumOf(L, 'Z0', B.Z0) and NumOf(L, 'Z1', B.Z1);
  end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
  InvFS.ThousandSeparator := #0;
end.
