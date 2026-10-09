unit multiassembly_library;
{$mode objfpc}{$H+}
interface
uses multiassembly_types;
type TAssemblyLibrary=class public class function MakeComponent(const ID,Name:string;Kind:TAssemblyComponentKind;X,Y,Z,SX,SY,SZ:Double):TAssemblyComponent;static;class procedure AddPort(var C:TAssemblyComponent;const Name:string;Kind:TAssemblyPortKind;Voltage:Double=0);static;end;
implementation
class function TAssemblyLibrary.MakeComponent(const ID,Name:string;Kind:TAssemblyComponentKind;X,Y,Z,SX,SY,SZ:Double):TAssemblyComponent;begin Result.ID:=ID;Result.Name:=Name;Result.Model:='';Result.SourceRef:='';SetLength(Result.Ports,0);Result.Rotation.X:=0;Result.Rotation.Y:=0;Result.Rotation.Z:=0;Result.Kind:=Kind;Result.Position.X:=X;Result.Position.Y:=Y;Result.Position.Z:=Z;Result.Size.X:=SX;Result.Size.Y:=SY;Result.Size.Z:=SZ;end;
class procedure TAssemblyLibrary.AddPort(var C:TAssemblyComponent;const Name:string;Kind:TAssemblyPortKind;Voltage:Double);var N:Integer;begin N:=Length(C.Ports);SetLength(C.Ports,N+1);C.Ports[N].Name:=Name;C.Ports[N].Kind:=Kind;C.Ports[N].Voltage:=Voltage;end;
end.
