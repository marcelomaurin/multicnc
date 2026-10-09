unit multipcb_gerber;
{$mode objfpc}{$H+}
{ Compatibilidade: exporta o cobre Top em Gerber X2 a partir do projeto.
  Para o conjunto completo (cobre, mascara, perfil, furacao e job file) use
  TFabricationExporter.ExportAll (multipcb_fabrication). }
interface
uses Classes,SysUtils,multipcb_model,multipcb_board,multipcb_fabrication;
type TGerberExporter=class public class procedure ExportBoard(P:TPCBProject;const FN:string);end;
implementation
class procedure TGerberExporter.ExportBoard(P:TPCBProject;const FN:string);
var S:TStringList;B:TBoard;
begin S:=TStringList.Create;B:=TBoard.Create(P);try TFabricationExporter.BuildGerber(P,B,nil,flTopCopper,TFabricationExporter.DefaultOptions,S);S.SaveToFile(FN);finally B.Free;S.Free;end;end;
end.
