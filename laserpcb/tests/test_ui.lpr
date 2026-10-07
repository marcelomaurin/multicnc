program test_ui;
{$mode objfpc}{$H+}
uses Types, Interfaces, Forms, Controls, StdCtrls, SysUtils, Graphics, laserpcb_main, multisuite_controls;
var F:TLaserPCBForm; DataDir:string;
procedure Check(Ok:Boolean; const Msg:string);
begin if not Ok then raise Exception.Create(Msg);end;
function FindButton(C:TWinControl; const Text:string):TSuiteButton;
var I:Integer; R:TSuiteButton;
begin
  Result:=nil;
  for I:=0 to C.ControlCount-1 do
  begin
    if (C.Controls[I] is TSuiteButton) and (TSuiteButton(C.Controls[I]).Caption=Text) then Exit(TSuiteButton(C.Controls[I]));
    if C.Controls[I] is TWinControl then
    begin R:=FindButton(TWinControl(C.Controls[I]),Text);if R<>nil then Exit(R);end;
  end;
end;
procedure Click(const Text:string);
var B:TSuiteButton;
begin B:=FindButton(F,Text);Check(B<>nil,'Button missing: '+Text);B.Click;Application.ProcessMessages;end;
procedure SetField(const LabelText,Value:string);
var I,J:Integer; L:TLabel; Edit:TEdit;
begin
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TLabel then
  begin
    L:=TLabel(F.Components[I]);if L.Caption<>LabelText then Continue;
    for J:=0 to L.Parent.ControlCount-1 do if L.Parent.Controls[J] is TEdit then
    begin
      Edit:=TEdit(L.Parent.Controls[J]);
      if Edit.Top=L.Top+20 then begin Edit.Text:=Value;Exit;end;
    end;
  end;
  raise Exception.Create('Field missing: '+LabelText);
end;
function FindCombo(const Item:string):TComboBox;
var I:Integer;
begin
  Result:=nil;
  for I:=0 to F.ComponentCount-1 do
    if (F.Components[I] is TComboBox) and (TComboBox(F.Components[I]).Items.IndexOf(Item)>=0) then
      Exit(TComboBox(F.Components[I]));
end;
function FindCheck(const Text:string):TCheckBox;
var I:Integer;
begin
  for I:=0 to F.ComponentCount-1 do
    if (F.Components[I] is TCheckBox) and (TCheckBox(F.Components[I]).Caption=Text) then Exit(TCheckBox(F.Components[I]));
  raise Exception.Create('Check missing: '+Text);
end;
function LabelStarting(const Prefix:string):Boolean;
var I:Integer;
begin
  Result:=False;
  for I:=0 to F.ComponentCount-1 do
    if (F.Components[I] is TLabel) and (Pos(Prefix,TLabel(F.Components[I]).Caption)=1) then Exit(True);
end;
function Badge:string;
var I:Integer;
begin
  Result:='';
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TSuiteBadge then Exit(TSuiteBadge(F.Components[I]).Caption);
end;
procedure Snapshot(const Name:string);
var B:TBitmap; OutDir:string;
begin
  if ParamCount=0 then Exit;
  OutDir:=IncludeTrailingPathDelimiter(ParamStr(1));ForceDirectories(OutDir);
  Application.ProcessMessages;B:=F.GetFormImage;
  try B.SaveToFile(OutDir+Name+'.bmp');finally B.Free;end;
end;
procedure CheckCopperRendering;
var Image:TBitmap; Origin:TPoint; X,Y,Count:Integer;
begin
  Application.ProcessMessages; Image:=F.GetFormImage;
  try
    Origin:=F.ScreenToClient(F.Preview.ClientToScreen(Point(0,0))); Count:=0;
    Y:=Origin.Y+8;
    while Y<Origin.Y+F.Preview.ClientHeight-8 do
    begin
      X:=Origin.X+8;
      while X<Origin.X+F.Preview.ClientWidth-8 do
      begin
        if ColorToRGB(Image.Canvas.Pixels[X,Y])=RGBToColor(190,124,55) then Inc(Count);
        Inc(X,8);
      end;
      Inc(Y,8);
    end;
    Check(Count>100,'Copper bitmap pixel layout is incorrect');
  finally Image.Free;end;
end;
begin
  DataDir:='laserpcb/tests/data/';
  if not FileExists(DataDir+'demo-F_Cu.gtl') then
    DataDir:=IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+'data'+PathDelim;
  Application.Initialize;
  F:=TLaserPCBForm.Create(Application);
  try
    F.Show;Application.ProcessMessages;
    F.OpenFile(DataDir+'demo-F_Cu.gtl');F.OpenFile(DataDir+'demo-B_Cu.gbl');
    F.OpenFile(DataDir+'demo-Edge_Cuts.gm1');F.OpenFile(DataDir+'demo-F_Mask.gts');
    F.OpenFile(DataDir+'demo-F_Silkscreen.gto');F.OpenFile(DataDir+'demo-PTH.drl');
    F.OpenFile(DataDir+'demo-NPTH-slot.drl');
    SetField('Potencia calibrada (S)','250');SetField('Velocidade calibrada (mm/min)','600');
    SetField('Diametro calibrado do feixe (mm)','0.2');
    Click('3  Processo');Click('Atualizar trajetorias');
    Check(Length(F.Project.Paths)>0,'UI CAM not generated');
    Check(F.Project.CopperMask.CountSet>0,'UI copper preview empty');CheckCopperRendering;
    Snapshot('process');
    Click('Validar');Check(Badge='Trabalho valido','UI validation: '+Badge);Snapshot('validated');
    Click('2  Posicionar');Click('Duplicar');Click('Distribuir placas');
    Check(F.Project.Layout.Count=2,'UI copies');
    Click('Girar 90 graus');Check(F.Project.Layout.Item(1).Rotation=90,'UI rotate');
    SetField('Escala X','0');Click('Aplicar posicao');
    Check(F.Project.Layout.Item(1).ScaleX=1,'invalid scale mutated model');
    SetField('Escala X','1');Snapshot('position');
    Click('5  Furar');SetField('Profundidade (mm, negativa)','-1.6');Click('Conferir furacao');
    Check(LabelStarting('20 furos, 2 rasgos'),'UI drill summary');
    FindCheck('Furar pinos de registro').Checked:=True;Application.ProcessMessages;
    Check(F.Project.RegistrationPins,'UI registration pins');Snapshot('drill');
    FindCheck('Furar pinos de registro').Checked:=False;
    SetField('Profundidade (mm, negativa)','1');Click('Conferir furacao');
    Check(Badge='Corrigir a furacao','UI accepted positive drill depth');
    SetField('Profundidade (mm, negativa)','-1.6');
    Click('3  Processo');FindCombo('Marcar furos (laser)').ItemIndex:=4;
    Click('Atualizar trajetorias');Check(Length(F.Project.Paths)=F.Project.Drills.HoleCount,'UI drill marks');
    Snapshot('marks');FindCombo('Marcar furos (laser)').ItemIndex:=1;
    F.Width:=1040;F.Height:=680;Application.ProcessMessages;
    Check(FindButton(F,'Gerar G-code').Left>=0,'export button offscreen');
    Check(FindButton(F,'Abrir no MultiCNC').BoundsRect.Right<=FindButton(F,'Abrir no MultiCNC').Parent.ClientWidth,'send button offscreen');
    Snapshot('minimum');
    SetField('Velocidade calibrada (mm/min)','0');Click('Validar');
    Check(Badge<>'Trabalho valido','UI accepted uncalibrated speed');
    Writeln('PASS: native UI import, CAM, preview, validation, copies, rotation, drilling, marks, invalid parameters, minimum size');
  finally F.Free;end;
end.
