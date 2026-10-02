unit laserpcb_gcode;
{$mode objfpc}{$H+}
{ Exportador de jobs LaserArt/LaserPCB.
  - modo laser dinamico (M4) ligado uma vez; a potencia vai como S na
    propria linha G1 (Grbl $32=1, grblHAL, FluidNC e Marlin LASER_FEATURE);
  - deslocamentos com laser apagado em G0;
  - saida modal: so escreve X/Y/S/F quando mudam (arquivos muito menores);
  - ponto decimal invariante;
  - potencia/velocidade nao calibradas continuam gerando erro (seguranca). }
interface
uses Classes,SysUtils,laserpcb_job,laserpcb_types;
type TLaserGCodeExporter=class
 public
  class procedure BuildProgram(J:TLaserPCBJob;Output:TStrings);
  class procedure ExportJob(J:TLaserPCBJob;const FN:string);
 end;
implementation
class procedure TLaserGCodeExporter.BuildProgram(J:TLaserPCBJob;Output:TStrings);
var I,K,LastG:Integer;P:TPathPoint;Power,Feed,CX,CY,CS,CF:Double;Known:Boolean;FS:TFormatSettings;L:string;
 function N(V:Double):string;begin Result:=FormatFloat('0.###',V,FS);end;
begin
 FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';
 Output.Clear;
 Output.Add('; LaserArt/LaserPCB -> MultiCNC');
 Output.Add('G21 G90');
 Output.Add('M5');
 for K:=1 to J.Profile.Passes do begin
  Output.Add(Format('; PASS %d/%d',[K,J.Profile.Passes]));
  Output.Add('M4 S0');
  Known:=False;LastG:=-1;CS:=-1;CF:=-1;CX:=0;CY:=0;
  for I:=0 to J.Count-1 do begin
   P:=J.Point(I);
   L:='';
   if(not Known)or(N(P.X)<>N(CX))then L:=L+' X'+N(P.X);
   if(not Known)or(N(P.Y)<>N(CY))then L:=L+' Y'+N(P.Y);
   if P.LaserOn then begin
    Power:=P.Power;if Power<=0 then Power:=J.Profile.Power;
    Feed:=P.Feed;if Feed<=0 then Feed:=J.Profile.Feed;
    if(Power<=0)or(Feed<=0)then raise Exception.Create('Potencia/velocidade nao calibradas no ponto '+IntToStr(I));
    if L='' then Continue;
    if Round(Power)<>Round(CS)then begin L:=L+' S'+IntToStr(Round(Power));CS:=Power;end;
    if Round(Feed)<>Round(CF)then begin L:=L+' F'+IntToStr(Round(Feed));CF:=Feed;end;
    if LastG<>1 then L:='G1'+L else L:=Trim(L);LastG:=1;
   end else begin
    if L='' then Continue;
    if LastG<>0 then L:='G0'+L else L:=Trim(L);LastG:=0;
   end;
   Output.Add(L);CX:=P.X;CY:=P.Y;Known:=True;
  end;
  Output.Add('M5');
 end;
 Output.Add('M5');
end;
class procedure TLaserGCodeExporter.ExportJob(J:TLaserPCBJob;const FN:string);
var S:TStringList;
begin
 S:=TStringList.Create;
 try BuildProgram(J,S);S.SaveToFile(FN);finally S.Free;end;
end;
end.
