unit makepcb_library;

{ Biblioteca de footprints do MakePCB (galeria de componentes).

  Familias no estilo do PCB Wizard: resistores, capacitores, diodos/LEDs,
  transistores, circuitos integrados, conectores, diversos e pads/vias.
  Medidas em mm; passo padrao de 0,1 pol (2,54 mm). A origem de cada
  footprint e o centro dos pads, para girar no proprio lugar.

  Pads de furo passante: redondo 1,8 mm / furo 0,8 mm; pino 1 de CIs e
  conectores e quadrado. Os pads ficam com folga para isolacao a laser. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, makepcb_model;

type
  TMPLibrary = class
  private
    FItems: TList;
    FCategories: TStringList;
    function Add(const AName, ACategory, ADesc, APrefix, AValue: string): TMPFootprint;
    procedure Build;
    procedure Axial(const AName, ADesc: string; PitchIn: Double; Kind: TMPBodyKind;
      BodyL, BodyD: Double; Color: LongWord; const Prefix, Value, Category: string);
    procedure Radial(const AName, ADesc: string; Pitch, BodyD: Double; Kind: TMPBodyKind;
      Color: LongWord; const Prefix, Value, Category: string; Polarized: Boolean);
    procedure DIL(Pins: Integer; RowIn: Double);
    procedure Header(Cols, Rows: Integer);
    procedure Terminal(Ways: Integer);
    procedure SILPack(Pins: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    function Item(I: Integer): TMPFootprint;
    function Find(const AName: string): TMPFootprint;
    { para TMPDocument.LoadFromFile }
    function Resolve(const AName: string): TMPFootprint;
    property Categories: TStringList read FCategories;
    { footprints de uma categoria, na ordem da galeria }
    procedure ListCategory(const ACategory: string; Into: TList);
  end;

const
  MP_PAD = 1.8;
  MP_DRILL = 0.8;
  MP_PITCH = 2.54;

function MakePCBLibrary: TMPLibrary;

implementation

var
  GLibrary: TMPLibrary = nil;

function MakePCBLibrary: TMPLibrary;
begin
  if GLibrary = nil then GLibrary := TMPLibrary.Create;
  Result := GLibrary;
end;

constructor TMPLibrary.Create;
begin
  inherited Create;
  FItems := TList.Create;
  FCategories := TStringList.Create;
  Build;
end;

destructor TMPLibrary.Destroy;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do TObject(FItems[I]).Free;
  FItems.Free;
  FCategories.Free;
  inherited Destroy;
end;

function TMPLibrary.Count: Integer;
begin
  Result := FItems.Count;
end;

function TMPLibrary.Item(I: Integer): TMPFootprint;
begin
  Result := TMPFootprint(FItems[I]);
end;

function TMPLibrary.Find(const AName: string): TMPFootprint;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if SameText(Item(I).Name, AName) then Exit(Item(I));
  Result := nil;
end;

function TMPLibrary.Resolve(const AName: string): TMPFootprint;
begin
  Result := Find(AName);
end;

procedure TMPLibrary.ListCategory(const ACategory: string; Into: TList);
var
  I: Integer;
begin
  Into.Clear;
  for I := 0 to Count - 1 do
    if SameText(Item(I).Category, ACategory) then Into.Add(Item(I));
end;

function TMPLibrary.Add(const AName, ACategory, ADesc, APrefix, AValue: string): TMPFootprint;
begin
  if Find(AName) <> nil then raise Exception.Create('Footprint repetido: ' + AName);
  Result := TMPFootprint.Create;
  Result.Name := AName;
  Result.Category := ACategory;
  Result.Description := ADesc;
  Result.RefPrefix := APrefix;
  Result.DefaultValue := AValue;
  FItems.Add(Result);
  if FCategories.IndexOf(ACategory) < 0 then FCategories.Add(ACategory);
end;

{ ---- construtores de familias ---- }

procedure TMPLibrary.Axial(const AName, ADesc: string; PitchIn: Double; Kind: TMPBodyKind;
  BodyL, BodyD: Double; Color: LongWord; const Prefix, Value, Category: string);
var
  F: TMPFootprint;
  H: Double;
begin
  F := Add(AName, Category, ADesc, Prefix, Value);
  H := PitchIn * MP_INCH / 2;
  if Kind in [bkDiode] then
    F.AddPad('1', -H, 0, psSquare, MP_PAD, MP_PAD, MP_DRILL)   { catodo quadrado }
  else
    F.AddPad('1', -H, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', H, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddRect(-BodyL / 2, -BodyD / 2, BodyL / 2, BodyD / 2);
  F.AddLine(-H + 1.2, 0, -BodyL / 2, 0);
  F.AddLine(BodyL / 2, 0, H - 1.2, 0);
  if Kind = bkDiode then F.AddLine(-BodyL / 2 + 0.8, -BodyD / 2, -BodyL / 2 + 0.8, BodyD / 2);
  F.SetBody(Kind, -BodyL / 2, -BodyD / 2, BodyL / 2, BodyD / 2, Color);
end;

procedure TMPLibrary.Radial(const AName, ADesc: string; Pitch, BodyD: Double; Kind: TMPBodyKind;
  Color: LongWord; const Prefix, Value, Category: string; Polarized: Boolean);
var
  F: TMPFootprint;
begin
  F := Add(AName, Category, ADesc, Prefix, Value);
  if Polarized then
    F.AddPad('1', -Pitch / 2, 0, psSquare, MP_PAD, MP_PAD, MP_DRILL)
  else
    F.AddPad('1', -Pitch / 2, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', Pitch / 2, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddCircle(0, 0, BodyD / 2);
  if Polarized then
  begin
    { sinal + ao lado do pad 1 }
    F.AddLine(-BodyD / 2 - 1.6, 1.2, -BodyD / 2 - 0.4, 1.2);
    F.AddLine(-BodyD / 2 - 1.0, 0.6, -BodyD / 2 - 1.0, 1.8);
  end;
  F.SetBody(Kind, -BodyD / 2, -BodyD / 2, BodyD / 2, BodyD / 2, Color);
end;

procedure TMPLibrary.DIL(Pins: Integer; RowIn: Double);
var
  F: TMPFootprint;
  N, I: Integer;
  Row, X0, X, L: Double;
  Shape: TMPPadShape;
begin
  N := Pins div 2;
  Row := RowIn * MP_INCH;
  F := Add('DIL-' + IntToStr(Pins) + ' 0.' + IntToStr(Round(RowIn * 10)),
    'Circuitos integrados', Format('%d pinos, fileiras a %.1f pol', [Pins, RowIn]), 'IC', '');
  X0 := -(N - 1) * MP_PITCH / 2;
  { pinos 1..N embaixo (esq->dir), N+1..2N em cima (dir->esq) }
  for I := 0 to N - 1 do
  begin
    X := X0 + I * MP_PITCH;
    if I = 0 then Shape := psSquare else Shape := psOblong;
    F.AddPad(IntToStr(I + 1), X, -Row / 2, Shape, 1.5, 2.2, MP_DRILL);
  end;
  for I := 0 to N - 1 do
  begin
    X := X0 + (N - 1 - I) * MP_PITCH;
    F.AddPad(IntToStr(N + I + 1), X, Row / 2, psOblong, 1.5, 2.2, MP_DRILL);
  end;
  L := N * MP_PITCH;
  F.AddRect(-L / 2, -Row / 2 + 1.6, L / 2, Row / 2 - 1.6);
  F.AddCircle(-L / 2, 0, 0.9);   { chanfro do pino 1 }
  F.SetBody(bkIC, -L / 2, -Row / 2 + 1.6, L / 2, Row / 2 - 1.6, $2D2D2D);
end;

procedure TMPLibrary.Header(Cols, Rows: Integer);
var
  F: TMPFootprint;
  C, R, K: Integer;
  X0, Y0: Double;
  Shape: TMPPadShape;
begin
  if Rows = 1 then
    F := Add(Format('Barra 1x%d', [Cols]), 'Conectores', Format('%d pinos, passo 0,1 pol', [Cols]), 'J', '')
  else
    F := Add(Format('Barra %dx%d', [Rows, Cols]), 'Conectores', Format('%d pinos (IDC), passo 0,1 pol', [Cols * Rows]), 'J', '');
  X0 := -(Cols - 1) * MP_PITCH / 2;
  Y0 := -(Rows - 1) * MP_PITCH / 2;
  K := 0;
  for C := 0 to Cols - 1 do
    for R := 0 to Rows - 1 do
    begin
      Inc(K);
      if K = 1 then Shape := psSquare else Shape := psRound;
      F.AddPad(IntToStr(K), X0 + C * MP_PITCH, Y0 + R * MP_PITCH, Shape, 1.7, 1.7, 1.0);
    end;
  F.AddRect(X0 - 1.27, Y0 - 1.27, -X0 + 1.27, -Y0 + 1.27);
  F.SetBody(bkHeader, X0 - 1.27, Y0 - 1.27, -X0 + 1.27, -Y0 + 1.27, $1E1E1E);
end;

procedure TMPLibrary.Terminal(Ways: Integer);
var
  F: TMPFootprint;
  I: Integer;
  X0, P: Double;
  Shape: TMPPadShape;
begin
  P := 5.08;
  F := Add(Format('Borne %d vias', [Ways]), 'Conectores', 'Borne de parafuso, passo 5,08 mm', 'TB', '');
  X0 := -(Ways - 1) * P / 2;
  for I := 0 to Ways - 1 do
  begin
    if I = 0 then Shape := psSquare else Shape := psRound;
    F.AddPad(IntToStr(I + 1), X0 + I * P, 0, Shape, 2.6, 2.6, 1.3);
  end;
  F.AddRect(X0 - 2.54, -3.8, -X0 + 2.54, 3.8);
  F.SetBody(bkTerminal, X0 - 2.54, -3.8, -X0 + 2.54, 3.8, $2E7D32);
end;

procedure TMPLibrary.SILPack(Pins: Integer);
var
  F: TMPFootprint;
  I: Integer;
  X0: Double;
  Shape: TMPPadShape;
begin
  F := Add(Format('Rede SIL-%d', [Pins]), 'Resistores',
    Format('Rede de resistores, %d pinos em linha', [Pins]), 'RN', '10K');
  X0 := -(Pins - 1) * MP_PITCH / 2;
  for I := 0 to Pins - 1 do
  begin
    if I = 0 then Shape := psSquare else Shape := psRound;
    F.AddPad(IntToStr(I + 1), X0 + I * MP_PITCH, 0, Shape, MP_PAD, MP_PAD, MP_DRILL);
  end;
  F.AddRect(X0 - 1.27, -1.3, -X0 + 1.27, 1.3);
  F.SetBody(bkIC, X0 - 1.27, -1.3, -X0 + 1.27, 1.3, $243B7A);
end;

procedure TMPLibrary.Build;
var
  F: TMPFootprint;
  I: Integer;
begin
  { ---------- Resistores ---------- }
  Axial('Resistor 0.3 pol', 'Resistor 1/8 W, 7,6 mm', 0.3, bkResistor, 3.6, 1.8, $D9C28F, 'R', '1K', 'Resistores');
  Axial('Resistor 0.4 pol', 'Resistor 1/4 W, 10,2 mm', 0.4, bkResistor, 6.3, 2.4, $D9C28F, 'R', '1K', 'Resistores');
  Axial('Resistor 0.5 pol', 'Resistor 1/2 W, 12,7 mm', 0.5, bkResistor, 9.0, 3.2, $D9C28F, 'R', '1K', 'Resistores');
  F := Add('Resistor vertical', 'Resistores', 'Resistor em pe, 2,54 mm', 'R', '1K');
  F.AddPad('1', -1.27, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', 1.27, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddCircle(-1.27, 0, 1.6);
  F.SetBody(bkResistor, -2.9, -1.4, 0.4, 1.4, $D9C28F);
  F := Add('Potenciometro', 'Resistores', 'Potenciometro, 3 pinos a 5,08 mm', 'VR', '10K');
  F.AddPad('1', -5.08, 0, psRound, 2.0, 2.0, 1.0);
  F.AddPad('2', 0, 0, psRound, 2.0, 2.0, 1.0);
  F.AddPad('3', 5.08, 0, psRound, 2.0, 2.0, 1.0);
  F.AddRect(-7.5, -2.5, 7.5, 7.5);
  F.AddCircle(0, 3.5, 3.0);
  F.SetBody(bkPot, -7.5, -2.5, 7.5, 7.5, $1E5AA8);
  F := Add('Trimpot', 'Resistores', 'Trimpot horizontal, 3 pinos', 'VR', '10K');
  F.AddPad('1', -2.54, -2.54, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', 0, 2.54, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('3', 2.54, -2.54, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddCircle(0, 0, 4.6);
  F.SetBody(bkPot, -4.6, -4.6, 4.6, 4.6, $F2F2F2);
  F := Add('LDR', 'Resistores', 'Fotoresistor (ORP12), 5,08 mm', 'LDR', '');
  F.AddPad('1', -2.54, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', 2.54, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddCircle(0, 0, 4.4);
  F.SetBody(bkLDR, -4.4, -4.4, 4.4, 4.4, $C8A15A);
  SILPack(8);
  SILPack(9);

  { ---------- Capacitores ---------- }
  Radial('Ceramico 0.1 pol', 'Capacitor ceramico, 2,54 mm', 2.54, 4.0, bkCapCeramic, $E0892C, 'C', '100nF', 'Capacitores', False);
  Radial('Ceramico 0.2 pol', 'Capacitor ceramico, 5,08 mm', 5.08, 5.5, bkCapCeramic, $E0892C, 'C', '100nF', 'Capacitores', False);
  F := Add('Poliester 0.2 pol', 'Capacitores', 'Capacitor de poliester, 5,08 mm', 'C', '100nF');
  F.AddPad('1', -2.54, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', 2.54, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddRect(-3.6, -1.8, 3.6, 1.8);
  F.SetBody(bkCapFilm, -3.6, -1.8, 3.6, 1.8, $B71C1C);
  F := Add('Poliester 0.4 pol', 'Capacitores', 'Capacitor de poliester, 10,16 mm', 'C', '1uF');
  F.AddPad('1', -5.08, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', 5.08, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddRect(-6.5, -2.5, 6.5, 2.5);
  F.SetBody(bkCapFilm, -6.5, -2.5, 6.5, 2.5, $B71C1C);
  Radial('Eletrolitico 5 mm', 'Eletrolitico radial, D5 mm, passo 2,0 mm', 2.0, 5.0, bkCapElectrolytic, $1F4E9A, 'C', '10uF', 'Capacitores', True);
  Radial('Eletrolitico 6.3 mm', 'Eletrolitico radial, D6,3 mm, passo 2,5 mm', 2.5, 6.3, bkCapElectrolytic, $1F4E9A, 'C', '47uF', 'Capacitores', True);
  Radial('Eletrolitico 8 mm', 'Eletrolitico radial, D8 mm, passo 3,5 mm', 3.5, 8.0, bkCapElectrolytic, $1F4E9A, 'C', '100uF', 'Capacitores', True);
  Radial('Eletrolitico 10 mm', 'Eletrolitico radial, D10 mm, passo 5,0 mm', 5.0, 10.0, bkCapElectrolytic, $1F4E9A, 'C', '470uF', 'Capacitores', True);
  Axial('Eletrolitico axial', 'Eletrolitico axial, 15,2 mm', 0.6, bkCapElectrolytic, 10.0, 5.0, $1F4E9A, 'C', '100uF', 'Capacitores');

  { ---------- Diodos e LEDs ---------- }
  Axial('Diodo 0.3 pol', 'Diodo de sinal (1N4148), 7,6 mm', 0.3, bkDiode, 3.6, 1.8, $C9341F, 'D', '1N4148', 'Diodos e LEDs');
  Axial('Diodo 0.4 pol', 'Diodo retificador (1N4007), 10,2 mm', 0.4, bkDiode, 5.0, 2.7, $222222, 'D', '1N4007', 'Diodos e LEDs');
  Axial('Diodo 0.5 pol', 'Diodo de potencia (1N5408), 12,7 mm', 0.5, bkDiode, 7.5, 5.0, $222222, 'D', '1N5408', 'Diodos e LEDs');
  Radial('LED 3 mm', 'LED 3 mm, passo 2,54 mm (catodo quadrado)', 2.54, 3.0, bkLED, $E53935, 'D', 'Vermelho', 'Diodos e LEDs', True);
  Radial('LED 5 mm', 'LED 5 mm, passo 2,54 mm (catodo quadrado)', 2.54, 5.0, bkLED, $43A047, 'D', 'Verde', 'Diodos e LEDs', True);
  F := Add('Ponte retificadora', 'Diodos e LEDs', 'Ponte DIL 4 pinos (W04)', 'BR', 'W04');
  F.AddPad('+', -2.54, -2.54, psSquare, MP_PAD, MP_PAD, 1.0);
  F.AddPad('~', 2.54, -2.54, psRound, MP_PAD, MP_PAD, 1.0);
  F.AddPad('-', 2.54, 2.54, psRound, MP_PAD, MP_PAD, 1.0);
  F.AddPad('~', -2.54, 2.54, psRound, MP_PAD, MP_PAD, 1.0);
  F.AddCircle(0, 0, 4.6);
  F.SetBody(bkPower, -4.6, -4.6, 4.6, 4.6, $2B2B2B);

  { ---------- Transistores ---------- }
  F := Add('TO-92', 'Transistores', 'Transistor TO-92 (E B C), passo 2,54 mm', 'Q', 'BC548');
  F.AddPad('E', -2.54, 0, psOblong, 1.4, 2.0, MP_DRILL);
  F.AddPad('B', 0, 0, psOblong, 1.4, 2.0, MP_DRILL);
  F.AddPad('C', 2.54, 0, psOblong, 1.4, 2.0, MP_DRILL);
  F.AddLine(-2.4, -1.6, 2.4, -1.6);
  F.AddCircle(0, 0.6, 2.5);
  F.SetBody(bkTransistor, -2.5, -1.6, 2.5, 3.1, $222222);
  F := Add('TO-126', 'Transistores', 'Transistor TO-126 (E C B), passo 2,29 mm', 'Q', 'BD139');
  F.AddPad('E', -2.29, 0, psOblong, 1.5, 2.2, 1.0);
  F.AddPad('C', 0, 0, psOblong, 1.5, 2.2, 1.0);
  F.AddPad('B', 2.29, 0, psOblong, 1.5, 2.2, 1.0);
  F.AddRect(-4.0, -1.3, 4.0, 1.5);
  F.SetBody(bkTransistor, -4.0, -1.3, 4.0, 1.5, $2A2A2A);
  F := Add('TO-220', 'Transistores', 'TO-220 deitado/em pe, passo 2,54 mm (7805, TIP120)', 'Q', '7805');
  F.AddPad('1', -2.54, 0, psOblong, 1.8, 2.6, 1.1);
  F.AddPad('2', 0, 0, psOblong, 1.8, 2.6, 1.1);
  F.AddPad('3', 2.54, 0, psOblong, 1.8, 2.6, 1.1);
  F.AddRect(-5.2, -1.6, 5.2, 3.0);
  F.AddLine(-5.2, 1.9, 5.2, 1.9);
  F.SetBody(bkPower, -5.2, -1.6, 5.2, 3.0, $2A2A2A);

  { ---------- Circuitos integrados ---------- }
  DIL(8, 0.3);
  DIL(14, 0.3);
  DIL(16, 0.3);
  DIL(18, 0.3);
  DIL(20, 0.3);
  DIL(24, 0.6);
  DIL(28, 0.3);
  DIL(28, 0.6);
  DIL(40, 0.6);

  { ---------- Conectores ---------- }
  for I := 2 to 10 do Header(I, 1);
  Header(5, 2);
  Terminal(2);
  Terminal(3);
  F := Add('Bateria 9 V', 'Conectores', 'Clip de bateria (fios), 2 pads', 'B', '9V');
  F.AddPad('+', -2.54, 0, psSquare, 2.2, 2.2, 1.0);
  F.AddPad('-', 2.54, 0, psRound, 2.2, 2.2, 1.0);
  F.AddLine(-4.4, 2.0, -3.4, 2.0);
  F.AddLine(-3.9, 1.5, -3.9, 2.5);
  F.SetBody(bkTerminal, -4.0, -1.6, 4.0, 1.6, $B71C1C);

  { ---------- Diversos ---------- }
  F := Add('Cristal HC-49', 'Diversos', 'Cristal HC-49/US, passo 4,88 mm', 'X', '16MHz');
  F.AddPad('1', -2.44, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('2', 2.44, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddRect(-5.6, -2.3, 5.6, 2.3);
  F.SetBody(bkCrystal, -5.6, -2.3, 5.6, 2.3, $B0BEC5);
  F := Add('Botao 6x6', 'Diversos', 'Chave tactil 6 x 6 mm, 4 pinos', 'SW', '');
  F.AddPad('1', -3.25, -2.25, psRound, MP_PAD, MP_PAD, 1.0);
  F.AddPad('2', 3.25, -2.25, psRound, MP_PAD, MP_PAD, 1.0);
  F.AddPad('3', -3.25, 2.25, psRound, MP_PAD, MP_PAD, 1.0);
  F.AddPad('4', 3.25, 2.25, psRound, MP_PAD, MP_PAD, 1.0);
  F.AddRect(-3.0, -3.0, 3.0, 3.0);
  F.AddCircle(0, 0, 1.75);
  F.SetBody(bkSwitch, -3.0, -3.0, 3.0, 3.0, $3A3A3A);
  F := Add('Buzzer 12 mm', 'Diversos', 'Buzzer/LS, D12 mm, passo 7,6 mm', 'LS', '');
  F.AddPad('+', -3.8, 0, psSquare, MP_PAD, MP_PAD, MP_DRILL);
  F.AddPad('-', 3.8, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.AddCircle(0, 0, 6.0);
  F.SetBody(bkBuzzer, -6.0, -6.0, 6.0, 6.0, $1A1A1A);
  F := Add('Furo de fixacao M3', 'Diversos', 'Furo nao metalizado 3,2 mm', 'H', '');
  F.AddPad('1', 0, 0, psRound, 3.2, 3.2, 3.2, False);
  F.AddCircle(0, 0, 3.0);
  F.SetBody(bkPad, -1.6, -1.6, 1.6, 1.6, $9E9E9E);

  { ---------- Pads e vias ---------- }
  F := Add('Pad redondo', 'Pads e vias', 'Pad avulso 1,8 mm / furo 0,8 mm', '', '');
  F.AddPad('1', 0, 0, psRound, MP_PAD, MP_PAD, MP_DRILL);
  F.SetBody(bkPad, -0.9, -0.9, 0.9, 0.9, 0);
  F := Add('Pad grande', 'Pads e vias', 'Pad avulso 2,5 mm / furo 1,0 mm (fios)', '', '');
  F.AddPad('1', 0, 0, psRound, 2.5, 2.5, 1.0);
  F.SetBody(bkPad, -1.25, -1.25, 1.25, 1.25, 0);
  F := Add('Pad quadrado', 'Pads e vias', 'Pad avulso quadrado 1,8 mm', '', '');
  F.AddPad('1', 0, 0, psSquare, MP_PAD, MP_PAD, MP_DRILL);
  F.SetBody(bkPad, -0.9, -0.9, 0.9, 0.9, 0);
  F := Add('Via', 'Pads e vias', 'Via 1,2 mm / furo 0,6 mm (dupla face)', '', '');
  F.AddPad('1', 0, 0, psRound, 1.2, 1.2, 0.6);
  F.SetBody(bkPad, -0.6, -0.6, 0.6, 0.6, 0);
end;

finalization
  FreeAndNil(GLibrary);
end.
