unit laserpcb_svg;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,StrUtils,laserpcb_job;
type TSVGImporter=class public class function ImportFile(const FN:string;J:TLaserPCBJob):Boolean;end;
implementation
class function TSVGImporter.ImportFile(const FN:string;J:TLaserPCBJob):Boolean;
var S:TStringList;T,Tag:string;P,Q,E:Integer;X1,Y1,X2,Y2:Double;
 function Attr(const N:string;D:Double):Double;var A,B:Integer;V:string;begin Result:=D;A:=Pos(' '+N+'="',Tag);if A=0 then Exit;Inc(A,Length(N)+3);B:=A;while(B<=Length(Tag))and(Tag[B]<>'"')do Inc(B);V:=Copy(Tag,A,B-A);TryParseFloat(V,Result);end;
begin
 Result:=FileExists(FN);if not Result then Exit;J.Clear;S:=TStringList.Create;
 try
  S.LoadFromFile(FN);T:=S.Text;P:=1;
  { Cada <line .../> vira um deslocamento (laser desligado) e um corte. }
  repeat
   Q:=PosEx('<line',T,P);if Q=0 then Break;
   E:=PosEx('>',T,Q);if E=0 then Break;
   Tag:=Copy(T,Q,E-Q+1);Tag:=StringReplace(StringReplace(StringReplace(Tag,#13,' ',[rfReplaceAll]),#10,' ',[rfReplaceAll]),#9,' ',[rfReplaceAll]);
   X1:=Attr('x1',0);Y1:=Attr('y1',0);X2:=Attr('x2',0);Y2:=Attr('y2',0);
   J.AddPoint(X1,Y1,False);J.AddPoint(X2,Y2,True);
   P:=E+1;
  until False;
 finally S.Free;end;
 Result:=J.Count>0;
end;
end.
