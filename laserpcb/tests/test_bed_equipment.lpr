program test_bed_equipment;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Spin, Classes,
  {$IFDEF MSWINDOWS}Windows,{$ENDIF} SysUtils,
  laserpcb_main, laserart_bedform, multicnc_equipment, multicnc_types,
  multisuite_controls;
{$IFDEF UNIX}
function c_setenv(Name,Value:PChar;Overwrite:Integer):Integer;cdecl;external 'c' name 'setenv';
function c_unsetenv(Name:PChar):Integer;cdecl;external 'c' name 'unsetenv';
{$ENDIF}
procedure SetEquipmentFile(const Value: string);
begin
  {$IFDEF MSWINDOWS}
  if Value='' then Windows.SetEnvironmentVariable('MULTICNC_EQUIPMENT_FILE',nil)
  else Windows.SetEnvironmentVariable('MULTICNC_EQUIPMENT_FILE',PChar(Value));
  {$ELSE}
  if Value='' then c_unsetenv('MULTICNC_EQUIPMENT_FILE')
  else c_setenv('MULTICNC_EQUIPMENT_FILE',PChar(Value),1);
  {$ENDIF}
end;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
type
  TDriver = class
    Timer: TTimer;
    Selected, Failure: string;
    Cancel: Boolean;
    NewS: Double;
    procedure Choose(Sender: TObject);
  end;
procedure TDriver.Choose(Sender: TObject);
var I: Integer; F: TLaserBedForm; C: TComboBox;
begin
  Timer.Enabled := False;
  for I := 0 to Screen.FormCount-1 do
    if Screen.Forms[I] is TLaserBedForm then
    begin
      F := TLaserBedForm(Screen.Forms[I]);
      try
        Check(F.Caption='LaserPCB - Mesa','Dialog title');
        C := TComboBox(F.FindComponent('BedEquipment'));
        Check((C.Items.Count=3) and (C.Items.IndexOf('Router')<0),'Only saved lasers');
        C.ItemIndex := C.Items.IndexOf(Selected);
        Check(C.ItemIndex>0,'Saved laser selectable');
        C.OnChange(C);
        if NewS>0 then TFloatSpinEdit(F.FindComponent('BedSMax')).Value:=NewS;
        if Cancel then TSuiteButton(F.FindComponent('CancelBed')).Click
        else TSuiteButton(F.FindComponent('ApplyBed')).Click;
      except on E: Exception do
        begin Failure:=E.Message; F.ModalResult:=mrCancel; end;
      end;
      Exit;
    end;
  Failure:='Mesa dialog not opened';
end;
var FN, OldOverride: string; Store: TEquipmentStore; P: TEquipmentProfile;
    Main: TLaserPCBForm; Mesa: TSuiteButton; D: TDriver; I: Integer;
procedure RunDialog(const Selected: string; Cancel: Boolean; NewS: Double);
begin
  D.Selected:=Selected; D.Cancel:=Cancel; D.NewS:=NewS; D.Failure:='';
  D.Timer.Enabled:=True; Mesa.Click;
  Check(D.Failure='',D.Failure);
end;
begin
 try
  Application.Initialize;
  FN:=GetTempFileName(GetTempDir,'pcb'); DeleteFile(FN);
  OldOverride:=GetEnvironmentVariable('MULTICNC_EQUIPMENT_FILE');
  Store:=TEquipmentStore.Create(FN); Main:=nil; D:=nil;
  try
    P:=DefaultEquipmentProfile; P.Name:='Router'; P.ConnectionMode:=2;
    P.WorkX:=300; P.WorkY:=180; Store.Put(P);
    P.MachineType:=mtLaser; P.Name:='Glypho'; P.Brand:='GLYPHO';
    P.Model:='S1'; P.WorkX:=130; P.WorkY:=130; Store.Put(P);
    P.Name:='CUSTOM'; P.Brand:='CUSTOM'; P.Model:='CUSTOM Laser';
    P.WorkX:=220.5; P.WorkY:=180.25; P.LaserOpticalPowerW:=10; Store.Put(P);
    SetEquipmentFile(FN);
    Main:=TLaserPCBForm.Create(nil); Main.HandleNeeded; Main.Realign;
    Mesa:=nil;
    for I:=0 to Main.ComponentCount-1 do
      if (Main.Components[I] is TSuiteButton) and
        (TSuiteButton(Main.Components[I]).Caption='Mesa') then
        Mesa:=TSuiteButton(Main.Components[I]);
    Check(Mesa<>nil,'Mesa button');
    D:=TDriver.Create; D.Timer:=TTimer.Create(nil);
    D.Timer.Enabled:=False; D.Timer.Interval:=50; D.Timer.OnTimer:=@D.Choose;
    RunDialog('Glypho',False,0);
    Check((Main.Project.Layout.BedWidth=130) and
      (Main.Project.Layout.BedHeight=130),'Glypho changes actual bed');
    Check(Main.Project.Profile.SMax=1000,'Preserves manual S max');
    RunDialog('CUSTOM',False,1200);
    Check((Main.Project.Layout.BedWidth=220.5) and
      (Main.Project.Layout.BedHeight=180.25),'CUSTOM decimal bed');
    Check(Main.Project.Profile.SMax=1200,'Applies manual S max');
    Check(Main.Project.Profile.OpticalPowerW=10,'Loads optical watts from saved CUSTOM laser');
    Check(Main.Preview.Zoom>0,'Bed zoom adjusted');
    RunDialog('Glypho',True,900);
    Check((Main.Project.Layout.BedWidth=220.5) and
      (Main.Project.Layout.BedHeight=180.25) and
      (Main.Project.Profile.SMax=1200),'Cancel preserves bed and S max');
    RunDialog('Glypho',False,0.5);
    Check((Main.Project.Layout.BedWidth=220.5) and
      (Main.Project.Profile.SMax=1200),'Invalid S leaves bed unchanged');
    Store.Load; Check(Store.Count=3,'Equipment file remains unchanged');
    WriteLn('PASS: LaserPCB Mesa saved lasers, CUSTOM, S max, cancel and validation');
  finally
    if D<>nil then begin D.Timer.Free; D.Free; end;
    Main.Free; Store.Free;
    SetEquipmentFile(OldOverride);
    DeleteFile(FN);
  end;
 except on E: Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end;
 end;
end.
