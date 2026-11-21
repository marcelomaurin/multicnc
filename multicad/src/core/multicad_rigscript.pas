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
  Declarations: array[0..5] of string = (
    'procedure DefinirAngulo(Segmento: string; Graus: Double);',
    'procedure MoverSegmento(Segmento: string; Graus: Double; DuracaoMS: Integer);',
    'procedure Esperar(DuracaoMS: Integer);',
    'function Angulo(Segmento: string): Double;',
    'function TotalSegmentos: Integer;',
    'function Segmento(Indice: Integer): string;');
  Names: array[0..5] of string = ('DefinirAngulo','MoverSegmento','Esperar','Angulo','TotalSegmentos','Segmento');

type
  {$M+}
  TCadMotionAPI = class
  public
    Rig: TCadRig;
    Motion: TCadMotion;
    TimeMS: Integer;
  published
    procedure DefinirAngulo(Segmento: string; Graus: Double);
    procedure MoverSegmento(Segmento: string; Graus: Double; DuracaoMS: Integer);
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
  Motion.AddStep(Rig[I].ID,Rig[I].Axis,TimeMS,Previous,Graus);
end;

procedure TCadMotionAPI.MoverSegmento(Segmento: string; Graus: Double; DuracaoMS: Integer);
var I: Integer; A: Double;
begin
  if (DuracaoMS<1) or (DuracaoMS>CadMotionMaxDuration-TimeMS) then
    raise Exception.Create('Duração fora do limite de 10 minutos.');
  I:=Rig.IndexOf(Segmento);
  if I<0 then raise Exception.Create('Segmento inexistente: '+Segmento);
  A:=Rig[I].Angle; Rig.SetAngle(Segmento,Graus);
  Motion.AddKey(Rig[I].ID,Rig[I].Axis,TimeMS,A);
  Inc(TimeMS,DuracaoMS);
  Motion.AddKey(Rig[I].ID,Rig[I].Axis,TimeMS,Graus);
end;

procedure TCadMotionAPI.Esperar(DuracaoMS: Integer);
var I: Integer;
begin
  if (DuracaoMS<0) or (DuracaoMS>CadMotionMaxDuration-TimeMS) then
    raise Exception.Create('Duração fora do limite de 10 minutos.');
  for I:=0 to Rig.Count-1 do Motion.AddKey(Rig[I].ID,Rig[I].Axis,TimeMS,Rig[I].Angle);
  Inc(TimeMS,DuracaoMS);
  for I:=0 to Rig.Count-1 do Motion.AddKey(Rig[I].ID,Rig[I].Axis,TimeMS,Rig[I].Angle);
end;

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
      API.Motion.Name:='Script Pascal';
      E:=TPSExec.Create; E.OnRunLine:=@CountLine;
      for I:=0 to High(Names) do E.RegisterDelphiMethod(API,API.MethodAddress(Names[I]),Names[I],cdRegister);
      if not E.LoadData(Code) then raise Exception.Create('Não foi possível carregar o script Pascal.');
      Budget:=25000; Deadline:=GetTickCount64+2000;
      if not E.RunScript then
        raise Exception.Create('Erro no script: '+TIFErrorToString(E.ExceptionCode,E.ExceptionString));
      if Budget<=0 then raise Exception.Create('Script interrompido: limite de instruções/tempo excedido.');
      API.Motion.Validate(Rig);
      Motion:=API.Motion; API.Motion:=nil; Result:=True;
    except on X: Exception do Error:=X.Message; end;
  finally
    E.Free; C.Free;
    if API<>nil then begin API.Motion.Free; API.Rig.Free; API.Free; end;
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
