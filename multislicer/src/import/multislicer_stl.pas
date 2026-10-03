unit multislicer_stl;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,multislicer_types,multislicer_mesh;
type TSTLImporter=class public class function LoadASCII(const FN:string;M:TMesh):Boolean;end;
implementation
class function TSTLImporter.LoadASCII(const FN:string;M:TMesh):Boolean;
var S:TStringList;I,N:Integer;L:string;V:TVec3;T:TTriangle;P:TStringList;
begin Result:=False;if not FileExists(FN)then Exit;M.Clear;S:=TStringList.Create;P:=TStringList.Create;try P.Delimiter:=' ';P.StrictDelimiter:=False;N:=0;S.LoadFromFile(FN);for I:=0 to S.Count-1 do begin L:=Trim(S[I]);if Pos('vertex ',LowerCase(L))=1 then begin P.DelimitedText:=L;if P.Count>=4 then begin V.X:=ParseFloatDef(P[1],0);V.Y:=ParseFloatDef(P[2],0);V.Z:=ParseFloatDef(P[3],0);case N of 0:T.A:=V;1:T.B:=V;2:begin T.C:=V;M.Add(T);end;end;N:=(N+1) mod 3;end;end;end;Result:=M.Count>0;finally P.Free;S.Free;end;end;
end.
