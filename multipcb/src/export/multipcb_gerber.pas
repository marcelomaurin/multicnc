unit multipcb_gerber;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_model;
type TGerberExporter=class public class procedure ExportBoard(P:TPCBProject;const FN:string);end;
implementation
class procedure TGerberExporter.ExportBoard(P:TPCBProject;const FN:string);
var S:TStringList;
begin S:=TStringList.Create;try S.Add('G04 MultiPCB Gerber*');S.Add('%FSLAX46Y46*%');S.Add('%MOMM*%');S.Add('G01*');S.Add('M02*');S.SaveToFile(FN);finally S.Free;end;end;
end.
