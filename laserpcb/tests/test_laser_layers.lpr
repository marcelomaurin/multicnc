program test_laser_layers;
{$mode objfpc}{$H+}
uses Interfaces,Forms,Controls,StdCtrls,ComCtrls,Classes,SysUtils,Math,
  laserpcb_main,laserpcb_layertable,laserpcb_types,laserpcb_project,
  laserpcb_drill,laserpcb_profile,laserpcb_referenceform,multisuite_controls,multisuite_numfmt;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
var Main:TLaserPCBForm; Table:TLPLayerTable; I,N:Integer; FN:string;
    Profile:TLaserProfile; Process:TComboBox; Ref:TLaserReferenceForm; List:TListView;
function Edit(const Name:string):TEdit;
begin Result:=TEdit(Main.FindComponent(Name));Check(Result<>nil,'Field '+Name);end;
function Button(const Caption:string):TSuiteButton;
var K:Integer;
begin
 Result:=nil;
 for K:=0 to Main.ComponentCount-1 do
  if (Main.Components[K] is TSuiteButton) and
   (TSuiteButton(Main.Components[K]).Caption=Caption) then Exit(TSuiteButton(Main.Components[K]));
end;
procedure Near(A,B:Double;const Msg:string);
begin Check(Abs(A-B)<1e-6,Msg);end;
begin
 try
  Application.Initialize;Main:=TLaserPCBForm.Create(nil);Ref:=nil;
  FN:=GetTempFileName(GetTempDir,'las');
  try
    Main.HandleNeeded;Main.Realign;
    Table:=nil;
    for I:=0 to Main.ComponentCount-1 do
      if Main.Components[I] is TLPLayerTable then Table:=TLPLayerTable(Main.Components[I]);
    Check(Table<>nil,'Layer table');
    Main.OpenFile(ExtractFilePath(ParamStr(0))+'data'+PathDelim+'demo-F_Cu.gtl');
    Main.OpenFile(ExtractFilePath(ParamStr(0))+'data'+PathDelim+'demo-Edge_Cuts.gm1');
    Process:=TComboBox(Main.FindComponent('LaserProcess'));Check(Process<>nil,'Per layer treatment');
    Edit('LaserOpticalPower').Text:='5';
    Edit('LaserPowerPercent').Text:='40';
    Near(Main.Project.Operation(0).Power,400,'Percent to S');
    Near(StrToFloat(Edit('LaserTargetWatts').Text,InvariantFS),2,'Five watt laser nominal output');
    Edit('LaserTargetWatts').Text:='1';
    Near(Main.Project.Operation(0).Power,200,'Watts to S for 5W laser');
    Process.ItemIndex:=1;Process.OnChange(Process);
    Check(Main.Project.Operation(0).Process=lpDirectAblation,'Direct copper process stored per layer');
    N:=Main.Project.OperationCount;
    Button('Marcar centros a laser').Click;
    Check(Main.Project.OperationCount=N+1,'Laser hole operation created');
    Check((Main.Project.Operation(N).Mode=cmDrillMarks) and
      (Main.Project.Operation(N).MarkKind=mkCenter),'Laser marks, no router drilling');
    Check(Main.Project.Operation(N).Process=lpMarking,'Hole marking process');
    Check(Main.Project.Operation(0).Process=lpDirectAblation,'Other layer treatment unchanged');
    Edit('LaserOpticalPower').Text:='10';Edit('LaserTargetWatts').Text:='1';
    Near(Main.Project.Operation(N).Power,100,'Same nominal watt target on 10W laser');
    Near(StrToFloat(Edit('LaserPowerPercent').Text,InvariantFS),10,'Nominal watt target to percent');
    Table.Selected:=0;Table.OnSelectLayer(Table,0);
    Check(Process.ItemIndex=1,'Treatment restored on layer selection');
    Check(Button('Gerar furacao (Router)')=nil,'No Router export in laser UI');
    Profile:=Main.Project.Profile;Profile.OpticalPowerW:=10;
    TLaserProfileIO.Save(Profile,FN);Profile:=TLaserProfileIO.Load(FN);
    Near(Profile.OpticalPowerW,10,'Optical watts profile persistence');
    Ref:=TLaserReferenceForm.Create(nil);Ref.HandleNeeded;Ref.Configure(10);
    List:=TListView(Ref.FindComponent('LaserReferences'));List.HandleNeeded;
    Check(List.Items.Count=5,'Web reference table');
    Check(TSuiteButton(Ref.FindComponent('ApplyReference')).Enabled,'Complete watt reference can apply');
    Near(Ref.PowerW,1,'Published wattage');Near(Ref.Feed,125,'Published speed');
    List.Items[2].Selected:=True;Application.ProcessMessages;
    Check(not TSuiteButton(Ref.FindComponent('ApplyReference')).Enabled,'Missing watts cannot apply');
    List.Items[4].Selected:=True;Application.ProcessMessages;
    Check(not TSuiteButton(Ref.FindComponent('ApplyReference')).Enabled,'Industrial UV entry reference only');
    Ref.Configure(0);
    Check(not TSuiteButton(Ref.FindComponent('ApplyReference')).Enabled,'Unknown laser watts cannot apply');
    WriteLn('PASS: laser treatments, hole operations, watts/percent/S conversion, profile and sourced reference table');
  finally Ref.Free;Main.Free;DeleteFile(FN);end;
 except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;
 end;
end.
