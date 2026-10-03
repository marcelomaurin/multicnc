unit multicnc_visualizer;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils;
type TToolPoint=record X,Y,Z:Double;Rapid:Boolean;end;
 PToolPoint=^TToolPoint;
 TToolPath=class
 private F:TToolPoint;FP:TList;
 public constructor Create;destructor Destroy;override;procedure Clear;procedure ParseLine(const S:string);function Count:Integer;function Point(I:Integer):TToolPoint;
 end;
implementation
constructor TToolPath.Create;begin FP:=TList.Create;end;
destructor TToolPath.Destroy;begin Clear;FP.Free;inherited;end;
procedure TToolPath.Clear;var I:Integer;begin for I:=0 to FP.Count-1 do Dispose(PToolPoint(FP[I]));FP.Clear;FillChar(F,SizeOf(F),0);end;
procedure TToolPath.ParseLine(const S:string);
var P:PToolPoint;U:string;function V(C:Char;D:Double):Double;var i,j:Integer;t:string;begin Result:=D;i:=Pos(C,U);if i=0 then Exit;Inc(i);j:=i;while(j<=Length(U))and(U[j] in ['0'..'9','-','+','.'])do Inc(j);t:=Copy(U,i,j-i);if t<>'' then TryParseFloat(t,Result);end;
begin U:=UpperCase(Trim(S));if(Pos('G0 ',U)=0)and(Pos('G1 ',U)=0)then Exit;F.X:=V('X',F.X);F.Y:=V('Y',F.Y);F.Z:=V('Z',F.Z);F.Rapid:=Pos('G0 ',U)>0;New(P);P^:=F;FP.Add(P);end;
function TToolPath.Count:Integer;begin Result:=FP.Count;end;
function TToolPath.Point(I:Integer):TToolPoint;begin Result:=PToolPoint(FP[I])^;end;
end.
