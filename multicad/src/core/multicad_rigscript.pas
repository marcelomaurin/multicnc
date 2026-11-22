unit multicad_rigscript;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, SysUtils, multicad_rig, multicad_motion;

function CompileCadMotion(const Source: string; Rig: TCadRig; out Motion: TCadMotion;
  out Error: string): Boolean;
function CadMotionScriptExample(const SegmentID: string): string;

implementation

uses uPSCompiler, uPSRuntime, uPSUtils;

const
  Declarations: array[0..10] of string = (
    'procedure DefinirAngulo(Segmento: string; Graus: Double);',
    'procedure MoverSegmento(Segmento: string; Graus: Double; DuracaoMS: Integer);',
    'procedure Esperar(DuracaoMS: Integer);',
    'function Angulo(Segmento: string): Double;',
    'function TotalSegmentos: Integer;',
    'function Segmento(Indice: Integer): string;',
    'procedure IniciarSimultaneo;',
    'procedure FinalizarSimultaneo;',
    'procedure MoverArticulacao(Osso: string; Eixo: string; Graus: Double; DuracaoMS: Integer);',
    'procedure DefinirArticulacao(Osso: string; Eixo: string; Graus: Double);',
    'procedure MoverDeslocamento(Osso: string; Eixo: string; Milimetros: Double; DuracaoMS: Integer);');
  Names: array[0..10] of string = ('DefinirAngulo','MoverSegmento','Esperar','Angulo','TotalSegmentos','Segmento','IniciarSimultaneo','FinalizarSimultaneo','MoverArticulacao','DefinirArticulacao','MoverDeslocamento');

type
  {$M+}
  TCadMotionAPI = class
  public
    Rig: TCadRig;
    Motion: TCadMotion;
    TimeMS, GroupEnd: Integer;
    Parallel: Boolean;
    GroupMoved: TStringList;
    function Resolve(const Bone, Axis: string; Kind: TCadJointKind): string;
  published
    procedure DefinirAngulo(Segmento: string; Graus: Double);
    procedure MoverSegmento(Segmento: string; Graus: Double; DuracaoMS: Integer);
    procedure IniciarSimultaneo;
    procedure FinalizarSimultaneo;
    procedure MoverArticulacao(Osso: string; Eixo: string; Graus: Double; DuracaoMS: Integer);
    procedure DefinirArticulacao(Osso: string; Eixo: string; Graus: Double);
    procedure MoverDeslocamento(Osso: string; Eixo: string; Milimetros: Double; DuracaoMS: Integer);
    procedure Esperar(DuracaoMS: Integer);
    function Angulo(Segmento: string): Double;
    function TotalSegmentos: Integer;
    function Segmento(Indice: Integer): string;
  end;
  {$M-}

threadvar Budget: Integer; Deadline: QWord;

function UsesAPI(Sender: TPSPascalCompiler; const Name: tbtString): Boolean;
var D: string;
begin
  Result:=Name='SYSTEM';
  if Result then for D in Declarations do Sender.AddDelphiFunction(D);
end;

procedure CountLine(Sender: TPSExec);
begin
  Dec(Budget);
  if (Budget<=0) or (GetTickCount64>Deadline) then begin Budget:=0; Sender.Stop; end;
end;

procedure TCadMotionAPI.DefinirAngulo(Segmento: string; Graus: Double);
var I: Integer; Previous: Double;
begin
  Previous:=Angulo(Segmento);
  Rig.SetAngle(Segmento,Graus); I:=Rig.IndexOf(Segmento);
  Motion.AddStep(Rig[I].ID,Rig[I].Axis,TimeMS,Previous,Graus,Rig[I].Kind);
end;

procedure TCadMotionAPI.MoverSegmento(Segmento: string; Graus: Double; DuracaoMS: Integer);
var I,EndMS: Integer; A: Double;
begin
  if (DuracaoMS<1) or (DuracaoMS>CadMotionMaxDuration-TimeMS) then
    raise Exception.Create('Duração fora do limite de 10 minutos.');
  I:=Rig.IndexOf(Segmento);
  if I<0 then raise Exception.Create('Segmento inexistente: '+Segmento);
  if Parallel then begin
    if GroupMoved.IndexOf(Rig[I].ID)>=0 then raise Exception.Create('Mova cada canal uma vez por grupo simultâneo.');
    GroupMoved.Add(Rig[I].ID);
  end;
  A:=Rig[I].Angle;Rig.SetAngle(Segmento,Graus);EndMS:=TimeMS+DuracaoMS;
  Motion.AddKey(Rig[I].ID,Rig[I].Axis,TimeMS,A,Rig[I].Kind);
  Motion.AddKey(Rig[I].ID,Rig[I].Axis,EndMS,Graus,Rig[I].Kind);
  if Parallel then begin if EndMS>GroupEnd then GroupEnd:=EndMS;end else TimeMS:=EndMS;
end;

procedure TCadMotionAPI.Esperar(DuracaoMS: Integer);
var I: Integer;
begin
  if Parallel then raise Exception.Create('Finalize o grupo simultâneo antes de Esperar.');
  if (DuracaoMS<0) or (DuracaoMS>CadMotionMaxDuration-TimeMS) then
    raise Exception.Create('Duração fora do limite de 10 minutos.');
  for I:=0 to Rig.Count-1 do Motion.AddKey(Rig[I].ID,Rig[I].Axis,TimeMS,Rig[I].Angle,Rig[I].Kind);
  Inc(TimeMS,DuracaoMS);
  for I:=0 to Rig.Count-1 do Motion.AddKey(Rig[I].ID,Rig[I].Axis,TimeMS,Rig[I].Angle,Rig[I].Kind);
end;

procedure TCadMotionAPI.IniciarSimultaneo;
begin
  if Parallel then raise Exception.Create('Grupos simultâneos não podem ser aninhados.');
  Parallel:=True;GroupEnd:=TimeMS;GroupMoved.Clear;
end;
procedure TCadMotionAPI.FinalizarSimultaneo;
begin
  if not Parallel then raise Exception.Create('Nenhum grupo simultâneo aberto.');
  Parallel:=False;TimeMS:=GroupEnd;
end;
function TCadMotionAPI.Resolve(const Bone, Axis: string; Kind: TCadJointKind): string;
var I: Integer;
begin
  I:=Rig.ChannelIndex(Bone,CadJointAxis(LowerCase(Axis)),Kind);
  if I<0 then raise Exception.Create('Osso/eixo/canal inexistente: '+Bone+'/'+Axis);
  Result:=Rig[I].ID;
end;
procedure TCadMotionAPI.MoverArticulacao(Osso: string; Eixo: string; Graus: Double; DuracaoMS: Integer);
begin MoverSegmento(Resolve(Osso,Eixo,jkRotation),Graus,DuracaoMS);end;
procedure TCadMotionAPI.DefinirArticulacao(Osso: string; Eixo: string; Graus: Double);
begin DefinirAngulo(Resolve(Osso,Eixo,jkRotation),Graus);end;
procedure TCadMotionAPI.MoverDeslocamento(Osso: string; Eixo: string; Milimetros: Double; DuracaoMS: Integer);
begin MoverSegmento(Resolve(Osso,Eixo,jkTranslation),Milimetros,DuracaoMS);end;

function TCadMotionAPI.Angulo(Segmento: string): Double;
var I: Integer;
begin
  I:=Rig.IndexOf(Segmento);
  if I<0 then raise Exception.Create('Segmento inexistente: '+Segmento);
  Result:=Rig[I].Angle;
end;

function TCadMotionAPI.TotalSegmentos: Integer;
begin Result:=Rig.Count; end;

function TCadMotionAPI.Segmento(Indice: Integer): string;
begin
  if (Indice<0) or (Indice>=Rig.Count) then raise Exception.Create('Índice de segmento inválido.');
  Result:=Rig[Indice].ID;
end;

function CompileCadMotion(const Source: string; Rig: TCadRig; out Motion: TCadMotion;
  out Error: string): Boolean;
var C: TPSPascalCompiler; E: TPSExec; API: TCadMotionAPI; Code: tbtString; I: Integer;
begin
  Result:=False; Motion:=nil; Error:='';
  C:=nil; E:=nil; API:=nil;
  try
    try
      Rig.Validate;
      if (Rig.Count=0) or (Length(Source)>65536) then raise Exception.Create('Crie segmentos e use um script de até 64 KB.');
      C:=TPSPascalCompiler.Create; C.OnUses:=@UsesAPI;
      if not C.Compile(Source) or not C.GetOutput(Code) then
      begin
        for I:=0 to C.MsgCount-1 do
          Error:=Error+Format('%d:%d: %s',[C.Msg[I].Row,C.Msg[I].Col,C.Msg[I].ShortMessageToString])+LineEnding;
        Exit;
      end;
      API:=TCadMotionAPI.Create; API.Rig:=Rig.Clone; API.Motion:=TCadMotion.Create;
      API.Motion.Name:='Script Pascal';API.GroupMoved:=TStringList.Create;
      E:=TPSExec.Create; E.OnRunLine:=@CountLine;
      for I:=0 to High(Names) do E.RegisterDelphiMethod(API,API.MethodAddress(Names[I]),Names[I],cdRegister);
      if not E.LoadData(Code) then raise Exception.Create('Não foi possível carregar o script Pascal.');
      Budget:=25000; Deadline:=GetTickCount64+2000;
      if not E.RunScript then
        raise Exception.Create('Erro no script: '+TIFErrorToString(E.ExceptionCode,E.ExceptionString));
      if Budget<=0 then raise Exception.Create('Script interrompido: limite de instruções/tempo excedido.');
      if API.Parallel then raise Exception.Create('Falta FinalizarSimultaneo no script.');
      API.Motion.Validate(Rig);
      Motion:=API.Motion; API.Motion:=nil; Result:=True;
    except on X: Exception do Error:=X.Message; end;
  finally
    E.Free; C.Free;
    if API<>nil then begin API.Motion.Free; API.Rig.Free; API.GroupMoved.Free; API.Free; end;
  end;
end;

function CadMotionScriptExample(const SegmentID: string): string;
var ID: string;
begin
  ID:=StringReplace(SegmentID,'''','''''',[rfReplaceAll]);
  Result:='begin'+LineEnding+
    '  MoverSegmento('''+ID+''', 30, 600);'+LineEnding+
    '  Esperar(300);'+LineEnding+
    '  MoverSegmento('''+ID+''', 0, 600);'+LineEnding+'end.';
end;

end.
