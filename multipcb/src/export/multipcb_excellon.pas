unit multipcb_excellon;
{$mode objfpc}{$H+}
{ Compatibilidade: Excellon 2 com tabela de ferramentas (antes o arquivo
  saia sem definicao de ferramentas, invalido para fabricantes). }
interface
uses Classes,SysUtils,multipcb_model,multipcb_fabrication;
type TExcellonExporter=class public class procedure ExportDrill(P:TPCBProject;const FN:string);end;
implementation
class procedure TExcellonExporter.ExportDrill(P:TPCBProject;const FN:string);
var S:TStringList;
begin S:=TStringList.Create;try TFabricationExporter.BuildExcellon(P,nil,S);S.SaveToFile(FN);finally S.Free;end;end;
end.
