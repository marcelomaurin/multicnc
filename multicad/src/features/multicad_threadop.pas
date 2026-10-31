unit multicad_threadop;

{ MultiCAD - Rosca (rosca real modelada em helice).

  Recebe uma face cilindrica do modelo ("face:<nome>"): eixo/pino = rosca
  externa (parafuso); furo = rosca interna (porca). O tipo vem da face.
  Medida:
  - Size = ''      automatica: externa pelo diametro do cilindro, interna
                   pela broca do furo (tabela ISO de multicad_threads);
  - Size = 'M8'    da tabela, passo normal ou fino;
  - Size = 'custom' diametro nominal e passo digitados.
  Comprimento 0 = a face inteira. O inicio fica na ponta de cima do eixo
  da face (FlipStart = ponta oposta), com Offset a partir dela.
  Folga radial para pecas impressas: a externa encolhe e a interna cresce
  (0,1 a 0,2 mm costuma servir numa impressora FDM). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, multicad_types, multicad_feature, multicad_threads;

const
  CAD_THREAD_CUSTOM = 'custom';

type
  TCadModelThread = class(TCadFeature)
  public
    FaceRef: string;
    Size: string;
    Fine: Boolean;
    Diameter: Double;    { personalizada }
    Pitch: Double;       { personalizada }
    Length: Double;      { 0 = face inteira }
    Offset: Double;
    FlipStart: Boolean;
    LeftHand: Boolean;
    Clearance: Double;
    { preenchido na reconstrucao (nao vai para o arquivo) }
    Summary: string;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
  end;

{ Medida da tabela mais proxima: externa pelo diametro nominal, interna pela
  broca (normal ou fina). False se nenhuma ficar a menos de Tol. }
function CadThreadForDiameter(ADiam: Double; AInternal: Boolean; out T: TCadThread;
  out AFine: Boolean; Tol: Double = 0.6): Boolean;

implementation

constructor TCadModelThread.Create;
begin
  inherited Create;
  SetKind(cfThread);
  Size := '';
  Fine := False;
  Diameter := 8;
  Pitch := 1.25;
  Length := 0;
  Offset := 0;
  Clearance := 0;
end;

procedure TCadModelThread.SaveParams(O: TJSONObject);
begin
  O.Add('face', FaceRef);
  O.Add('size', Size);
  O.Add('fine', Fine);
  if Size = CAD_THREAD_CUSTOM then
  begin
    O.Add('diameter', Diameter);
    O.Add('pitch', Pitch);
  end;
  O.Add('length', Length);
  O.Add('offset', Offset);
  O.Add('flip_start', FlipStart);
  O.Add('left_hand', LeftHand);
  O.Add('clearance', Clearance);
end;

procedure TCadModelThread.LoadParams(O: TJSONObject);
begin
  FaceRef := JStr(O, 'face', '');
  Size := JStr(O, 'size', '');
  Fine := JBool(O, 'fine', False);
  Diameter := JNum(O, 'diameter', 8);
  Pitch := JNum(O, 'pitch', 1.25);
  Length := JNum(O, 'length', 0);
  Offset := JNum(O, 'offset', 0);
  FlipStart := JBool(O, 'flip_start', False);
  LeftHand := JBool(O, 'left_hand', False);
  Clearance := JNum(O, 'clearance', 0);
end;

function TCadModelThread.Validate: string;
var
  T: TCadThread;
begin
  Result := '';
  if Pos('face:', FaceRef) <> 1 then
    Exit('Clique na face cilíndrica que vai receber a rosca (eixo ou furo)');
  if (Size <> '') and (Size <> CAD_THREAD_CUSTOM) and not CadFindThread(Size, T) then
    Exit('Medida de rosca desconhecida: ' + Size);
  if Size = CAD_THREAD_CUSTOM then
  begin
    if Diameter <= 0 then
      Exit('Diâmetro nominal deve ser maior que zero');
    if Pitch < 0.1 then
      Exit('Passo deve ser de pelo menos 0,1 mm');
  end;
  if Length < 0 then
    Exit('Comprimento não pode ser negativo (0 = face inteira)');
  if Offset < 0 then
    Exit('Deslocamento do início não pode ser negativo');
  if (Clearance < 0) or (Clearance > 1) then
    Exit('Folga deve ficar entre 0 e 1 mm');
end;

function CadThreadForDiameter(ADiam: Double; AInternal: Boolean; out T: TCadThread;
  out AFine: Boolean; Tol: Double): Boolean;
var
  I: Integer;
  C: TCadThread;
  D, Best: Double;
  F: Boolean;
begin
  Best := MaxDouble;
  AFine := False;
  Result := False;
  for I := 0 to CadThreadCount - 1 do
  begin
    C := CadThread(I);
    for F := False to True do
    begin
      if not AInternal and F then
        Continue;   { externa: o diametro nao diz o passo; fica o normal }
      if AInternal then
        D := Abs(CadTapDrill(C, F) - ADiam)
      else
        D := Abs(C.D - ADiam);
      if D < Best - 1E-9 then
      begin
        Best := D;
        T := C;
        AFine := F;
      end;
    end;
  end;
  Result := Best <= Tol;
end;

initialization
  RegisterCadFeature(cfThread, TCadModelThread);

end.
