unit multislicer_stl;
{$mode objfpc}{$H+}
{ Importacao de STL.
  - LoadASCII: STL texto (agora com ponto decimal invariante - antes falhava
    em sistemas com virgula decimal, como pt-BR);
  - LoadBinary: STL binario (formato usado pela grande maioria dos CADs e
    repositorios de modelos);
  - Load: detecta o formato automaticamente pelo tamanho/cabecalho. }
interface
uses Classes,SysUtils,multislicer_types,multislicer_mesh;
type TSTLImporter=class
 public
  class function LoadASCII(const FN:string;M:TMesh):Boolean;
  class function LoadBinary(const FN:string;M:TMesh):Boolean;
  class function Load(const FN:string;M:TMesh):Boolean;
  class function IsBinary(const FN:string):Boolean;
  class procedure SaveBinary(M:TMesh;const FN:string);
 end;
implementation
function InvFloat(const S:string):Double;
var FS:TFormatSettings;
begin FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';Result:=StrToFloatDef(S,0,FS);end;

class function TSTLImporter.LoadASCII(const FN:string;M:TMesh):Boolean;
var S:TStringList;I,N:Integer;L:string;V:TVec3;T:TTriangle;P:TStringList;
begin Result:=False;if not FileExists(FN)then Exit;M.Clear;S:=TStringList.Create;P:=TStringList.Create;try P.Delimiter:=' ';P.StrictDelimiter:=False;N:=0;S.LoadFromFile(FN);for I:=0 to S.Count-1 do begin L:=Trim(S[I]);if Pos('vertex ',LowerCase(L))=1 then begin P.DelimitedText:=L;if P.Count>=4 then begin V.X:=InvFloat(P[1]);V.Y:=InvFloat(P[2]);V.Z:=InvFloat(P[3]);case N of 0:T.A:=V;1:T.B:=V;2:begin T.C:=V;M.Add(T);end;end;N:=(N+1) mod 3;end;end;end;Result:=M.Count>0;finally P.Free;S.Free;end;end;

class function TSTLImporter.IsBinary(const FN:string):Boolean;
var F:TFileStream;Count:LongWord;Head:array[0..4]of Char;H:string;
begin
 Result:=False;
 if not FileExists(FN)then Exit;
 F:=TFileStream.Create(FN,fmOpenRead or fmShareDenyWrite);
 try
  if F.Size<84 then Exit;
  F.ReadBuffer(Head,5);
  F.Position:=80;
  F.ReadBuffer(Count,4);
  Count:=LEtoN(Count);
  // tamanho exato confirma binario mesmo se o cabecalho comecar com "solid"
  SetString(H,PChar(@Head[0]),5);
  Result:=(Int64(84)+Int64(Count)*50=F.Size)or(LowerCase(H)<>'solid');
 finally F.Free;end;
end;

class function TSTLImporter.LoadBinary(const FN:string;M:TMesh):Boolean;
var F:TFileStream;Count,I:LongWord;Rec:packed record N,A,B,C:array[0..2]of Single;Attr:Word;end;T:TTriangle;
 function V(const A:array of Single):TVec3;
 var X,Y,Z:Single;
 begin
  X:=A[0];Y:=A[1];Z:=A[2];
  {$ifdef ENDIAN_BIG}X:=LEtoN(X);Y:=LEtoN(Y);Z:=LEtoN(Z);{$endif}
  Result.X:=X;Result.Y:=Y;Result.Z:=Z;
 end;
begin
 Result:=False;
 if not FileExists(FN)then Exit;
 M.Clear;
 F:=TFileStream.Create(FN,fmOpenRead or fmShareDenyWrite);
 try
  if F.Size<84 then Exit;
  F.Position:=80;
  F.ReadBuffer(Count,4);Count:=LEtoN(Count);
  if Int64(84)+Int64(Count)*50>F.Size then Exit;
  for I:=1 to Count do begin
   F.ReadBuffer(Rec,50);
   T.A:=V(Rec.A);T.B:=V(Rec.B);T.C:=V(Rec.C);
   M.Add(T);
  end;
  Result:=M.Count>0;
 finally F.Free;end;
end;

class function TSTLImporter.Load(const FN:string;M:TMesh):Boolean;
begin
 if IsBinary(FN)then Result:=LoadBinary(FN,M) else Result:=LoadASCII(FN,M);
end;

class procedure TSTLImporter.SaveBinary(M:TMesh;const FN:string);
var F:TFileStream;Head:array[0..79]of Char;Count,I:LongWord;T:TTriangle;Rec:packed record N,A,B,C:array[0..2]of Single;Attr:Word;end;
 procedure Put(var D:array of Single;const P:TVec3);begin D[0]:=P.X;D[1]:=P.Y;D[2]:=P.Z;end;
 var UX,UY,UZ,VX,VY,VZ,NX,NY,NZ,L:Double;
begin
 F:=TFileStream.Create(FN,fmCreate);
 try
  FillChar(Head,SizeOf(Head),0);
  Move(PChar('MultiSuite binary STL')^,Head,21);
  F.WriteBuffer(Head,80);
  Count:=NtoLE(LongWord(M.Count));F.WriteBuffer(Count,4);
  for I:=0 to M.Count-1 do begin
   T:=M.Triangle(I);
   UX:=T.B.X-T.A.X;UY:=T.B.Y-T.A.Y;UZ:=T.B.Z-T.A.Z;VX:=T.C.X-T.A.X;VY:=T.C.Y-T.A.Y;VZ:=T.C.Z-T.A.Z;
   NX:=UY*VZ-UZ*VY;NY:=UZ*VX-UX*VZ;NZ:=UX*VY-UY*VX;L:=Sqrt(NX*NX+NY*NY+NZ*NZ);if L>0 then begin NX:=NX/L;NY:=NY/L;NZ:=NZ/L;end;
   Rec.N[0]:=NX;Rec.N[1]:=NY;Rec.N[2]:=NZ;Put(Rec.A,T.A);Put(Rec.B,T.B);Put(Rec.C,T.C);Rec.Attr:=0;
   F.WriteBuffer(Rec,50);
  end;
 finally F.Free;end;
end;
end.
