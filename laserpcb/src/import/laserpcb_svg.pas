unit laserpcb_svg;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,laserpcb_job;
type TSVGImporter=class public class function ImportFile(const FN:string;J:TLaserPCBJob):Boolean;end;
implementation
class function TSVGImporter.ImportFile(const FN:string;J:TLaserPCBJob):Boolean;
var S:TStringList;T:string;P:Integer;
 function Attr(const N:string;D:Double):Double;var A,B:Integer;V:string;begin Result:=D;A:=Pos(N+'="',T);if A=0 then Exit;Inc(A,Length(N)+2);B:=A;while(B<=Length(T))and(T[B]<>'"')do Inc(B);V:=Copy(T,A,B-A);TryStrToFloat(V,Result);end;
var X1,Y1,X2,Y2:Double;
begin Result:=FileExists(FN);if not Result then Exit;J.Clear;S:=TStringList.Create;try S.LoadFromFile(FN);T:=StringReplace(S.Text,',','.',[rfReplaceAll]);P:=1;while P<=Length(T)do begin P:=Pos('<line ',Copy(T,P,MaxInt))+P-1;if P<=0 then Break;T:=Copy(T,P,MaxInt);X1:=Attr('x1',0);Y1:=Attr('y1',0);X2:=Attr('x2',0);Y2:=Attr('y2',0);J.AddPoint(X1,Y1,False);J.AddPoint(X2,Y2,True);P:=Pos('>',T)+1;if P<=1 then Break;end;finally S.Free;end;Result:=J.Count>0;end;
end.
