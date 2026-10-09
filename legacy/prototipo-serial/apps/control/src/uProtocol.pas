unit uProtocol;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, StrUtils, uDomain;
type
  TLineFramer=class
  private FBuffer:string;
  public procedure Feed(const Chunk:string; Lines:TStrings);
  end;
function ParseGrbl(const Line:string; out State,FrameName:string; out P:TVector):Boolean;
function ParseMarlin(const Line:string; out P:TVector):Boolean;
function PrepareProgram(const Text:string; Lines:TStrings; out Points:TVectors):Boolean;
implementation
procedure TLineFramer.Feed(const Chunk:string;Lines:TStrings);
var I:Integer;C:Char;
begin
  for I:=1 to Length(Chunk) do begin C:=Chunk[I];
    if C in [#10,#13] then begin if FBuffer<>'' then Lines.Add(FBuffer);FBuffer:='';end
    else begin FBuffer:=FBuffer+C;if Length(FBuffer)>8192 then raise Exception.Create('Resposta serial maior que 8192 bytes.');end;
  end;
end;
function Triple(const S:string;out P:TVector):Boolean;
var A:TStringArray;
begin A:=S.Split(',');Result:=(Length(A)>=3);if Result then Result:=DotFloat(A[0],P.X) and DotFloat(A[1],P.Y) and DotFloat(A[2],P.Z);end;
function ParseGrbl(const Line:string;out State,FrameName:string;out P:TVector):Boolean;
var A:TStringArray;S:string;M,W:TVector;HM,HW:Boolean;
begin
  Result:=False;State:='';FrameName:='';if (Length(Line)<3) or (Line[1]<>'<') or (Line[Length(Line)]<>'>') then Exit;
  A:=Copy(Line,2,Length(Line)-2).Split('|');State:=A[0];HM:=False;HW:=False;
  for S in A do begin
    if StartsStr('MPos:',S) then HM:=Triple(Copy(S,6,200),M);
    if StartsStr('WPos:',S) then HW:=Triple(Copy(S,6,200),W);
  end;
  if HW then begin P:=W;FrameName:='Trabalho';Result:=True;end
  else if HM then begin P:=M;FrameName:='Máquina';Result:=True;end;
  // Do not convert MPos using an intermittent/stale WCO: preserve a stable frame.
end;
function ParseMarlin(const Line:string;out P:TVector):Boolean;
var S:string;A:TStringArray;T:string;X,Y,Z:Boolean;V:Double;
begin
  S:=Trim(Line);if not StartsStr('X:',S) then Exit(False);
  if Pos(' Count',S)>0 then S:=Copy(S,1,Pos(' Count',S)-1);
  A:=S.Split(' ');X:=False;Y:=False;Z:=False;
  for T in A do if Length(T)>2 then if DotFloat(Copy(T,3,100),V) then begin
    if StartsStr('X:',T) then begin P.X:=V;X:=True;end;
    if StartsStr('Y:',T) then begin P.Y:=V;Y:=True;end;
    if StartsStr('Z:',T) then begin P.Z:=V;Z:=True;end;
  end;Result:=X and Y and Z;
end;
function PrepareProgram(const Text:string; Lines:TStrings;out Points:TVectors):Boolean;
var Raw:TStringList;S,Clean,Token:string;I,J,K,Start,Code,Motion,AxisMask:Integer;C:Char;V:Double;P:TVector;MM,Absolute,FirstPoint:Boolean;
begin
  Result:=False;Points:=nil;Lines.Clear;
  if Length(Text)>1048576 then raise Exception.Create('Limite de programa: 1 MB.');
  Raw:=TStringList.Create;P:=Vector(0,0,0);MM:=False;Absolute:=False;FirstPoint:=True;Motion:=-1;
  try
    Raw.Text:=Text;
    for I:=0 to Raw.Count-1 do begin
      S:=UpperCase(Raw[I]);Clean:='';J:=1;
      while J<=Length(S) do begin
        if S[J]=';' then Break;
        if S[J]='(' then begin Inc(J);while (J<=Length(S)) and (S[J]<>')') do Inc(J);if J>Length(S) then raise Exception.CreateFmt('Comentário sem fechamento na linha %d.',[I+1]);end
        else if S[J]>' ' then Clean:=Clean+S[J];Inc(J);
      end;
      if Clean='' then Continue;
      if Length(Clean)>79 then raise Exception.CreateFmt('Linha %d excede 79 caracteres.',[I+1]);
      J:=1;AxisMask:=0;
      while J<=Length(Clean) do begin
        C:=Clean[J];Inc(J);Start:=J;while (J<=Length(Clean)) and (Clean[J] in ['0'..'9','-','+','.']) do Inc(J);
        Token:=Copy(Clean,Start,J-Start);if not DotFloat(Token,V) then raise Exception.CreateFmt('Palavra inválida na linha %d.',[I+1]);
        case C of
          'G':begin
            if (V<>Trunc(V)) or (V<0) or (V>100) then raise Exception.Create('G-code não suportado.');Code:=Trunc(V);
            case Code of 0,1:Motion:=Code;21:MM:=True;90:Absolute:=True;17,54,94:;
            else raise Exception.CreateFmt('G%d não suportado. Use trajetórias lineares, G21 e G90.',[Code]);end;
          end;
          'M':begin if (V<>3) and (V<>4) and (V<>5) then raise Exception.Create('Apenas M3, M4 e M5 são suportados.');end;
          'X','Y','Z':begin
            if not MM or not Absolute then raise Exception.Create('Declare G21 e G90 antes das coordenadas.');
            if Abs(V)>100000 then raise Exception.Create('Coordenada fora do intervalo permitido.');
            K:=1;if C='Y' then K:=2;if C='Z' then K:=4;if AxisMask and K<>0 then raise Exception.Create('Eixo duplicado.');AxisMask:=AxisMask or K;
            if C='X' then P.X:=V;if C='Y' then P.Y:=V;if C='Z' then P.Z:=V;
          end;
          'F','S':if (V<0) or (V>1000000) then raise Exception.Create('Avanço/potência fora do intervalo.');
        else raise Exception.CreateFmt('Palavra %s não suportada.',[C]);end;
      end;
      if AxisMask<>0 then begin
        if Motion<0 then raise Exception.Create('Defina G0 ou G1.');
        if FirstPoint and (AxisMask<>7) then raise Exception.Create('Primeiro movimento precisa definir X, Y e Z.');
        FirstPoint:=False;SetLength(Points,Length(Points)+1);Points[High(Points)]:=P;
      end;
      Lines.Add(Clean);
    end;
    if Length(Points)=0 then raise Exception.Create('Programa sem movimentos.');
    if Lines[Lines.Count-1]<>'M5' then raise Exception.Create('Finalize o programa com M5.');
    Result:=True;
  finally Raw.Free;end;
end;
end.
