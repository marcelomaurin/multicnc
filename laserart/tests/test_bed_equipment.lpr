program test_bed_equipment;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Classes, {$IFDEF MSWINDOWS}Windows,{$ENDIF} SysUtils,
  laserart_bedform, laserart_main, laserart_editor, multicnc_equipment, multicnc_types,
  multisuite_controls;
{$IFDEF UNIX}
function c_setenv(Name, Value: PChar; Overwrite: Integer): Integer; cdecl; external 'c' name 'setenv';
function c_unsetenv(Name: PChar): Integer; cdecl; external 'c' name 'unsetenv';
{$ENDIF}
procedure SetEquipmentFile(const Value: string);
begin
  {$IFDEF MSWINDOWS}
  if Value = '' then Windows.SetEnvironmentVariable('MULTICNC_EQUIPMENT_FILE',nil)
  else Windows.SetEnvironmentVariable('MULTICNC_EQUIPMENT_FILE',PChar(Value));
  {$ELSE}
  if Value = '' then c_unsetenv('MULTICNC_EQUIPMENT_FILE')
  else c_setenv('MULTICNC_EQUIPMENT_FILE',PChar(Value),1);
  {$ENDIF}
end;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
type
  TDriver = class
    Timer: TTimer;
    Failure: string;
    procedure ApplySaved(Sender: TObject);
  end;
procedure TDriver.ApplySaved(Sender: TObject);
var I: Integer; F: TLaserBedForm; C: TComboBox;
begin
  Timer.Enabled := False;
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I] is TLaserBedForm then
    begin
      F := TLaserBedForm(Screen.Forms[I]);
      try
        C := TComboBox(F.FindComponent('BedEquipment'));
        C.ItemIndex := C.Items.IndexOf('Laser Custom'); C.OnChange(C);
        TSuiteButton(F.FindComponent('ApplyBed')).Click;
      except
        on E: Exception do begin Failure := E.Message; F.ModalResult := mrCancel; end;
      end;
      Exit;
    end;
  Failure := 'Mesa dialog not opened';
end;
var FN: string; Store: TEquipmentStore; P: TEquipmentProfile; F: TLaserBedForm;
    C: TComboBox; Main: TLaserArtForm; Driver: TDriver;
    Editor: TLAEditor; Mesa: TSuiteButton; I: Integer; TextFile: TStringList;
    OldOverride: string;
begin
 try
  Application.Initialize;
  FN := GetTempFileName(GetTempDir, 'bed'); DeleteFile(FN);
  Store := TEquipmentStore.Create(FN); F := nil; Main := nil; Driver := nil;
  OldOverride := GetEnvironmentVariable('MULTICNC_EQUIPMENT_FILE');
  try
    P := DefaultEquipmentProfile; P.Name := 'Router'; P.ConnectionMode := 2;
    P.WorkX := 300; P.WorkY := 180; Store.Put(P);
    P.MachineType := mtLaser; P.Name := 'Laser Glypho'; P.Brand := 'GLYPHO'; P.Model := 'S1 5W';
    P.WorkX := 130; P.WorkY := 130; Store.Put(P);
    P.Name := 'Laser Custom'; P.Brand := 'CUSTOM'; P.Model := 'CUSTOM Laser';
    P.WorkX := 220.5; P.WorkY := 180.25; P.LaserOpticalPowerW := 10; Store.Put(P);
    P := DefaultEquipmentProfile; P.MachineType := mtLaser; P.ConnectionMode := 2;
    P.Name := 'Legacy sem area'; Store.Put(P);
    F := TLaserBedForm.Create(nil); F.HandleNeeded; F.Configure(400, 300, 1234, FN);
    C := TComboBox(F.FindComponent('BedEquipment'));
    Check((C.Items.Count=3) and (C.Items.IndexOf('Router')<0) and
      (C.Items.IndexOf('Legacy sem area')<0),'Only lasers with valid area');
    C.ItemIndex:=C.Items.IndexOf('Laser Glypho'); C.OnChange(C);
    Check((F.WidthMM=130) and (F.HeightMM=130) and (F.SMax=1234),'GLYPHO dimensions and preserved S');
    C.ItemIndex:=C.Items.IndexOf('Laser Custom'); C.OnChange(C);
    Check((F.WidthMM=220.5) and (F.HeightMM=180.25),'CUSTOM decimal area');
    TSuiteButton(F.FindComponent('ApplyBed')).Click;
    Check(F.ModalResult=mrOK,'Apply accepts selected area');
    C.ItemIndex:=0; C.OnChange(C);
    Check((F.WidthMM=400) and (F.HeightMM=300),'Manual restores original dimensions');
    TSuiteButton(F.FindComponent('CancelBed')).Click; Check(F.ModalResult=mrCancel,'Cancel');
    F.Configure(400,300,1234,FN+'.missing');
    Check(C.Items.Count=1,'Missing store supports manual mode');
    FreeAndNil(F);
    SetEquipmentFile(FN);
    Main:=TLaserArtForm.Create(nil); Main.HandleNeeded; Main.Realign;
    Editor:=nil; Mesa:=nil;
    for I:=0 to Main.ComponentCount-1 do
    begin
      if Main.Components[I] is TLAEditor then Editor:=TLAEditor(Main.Components[I]);
      if (Main.Components[I] is TSuiteButton) and
        (TSuiteButton(Main.Components[I]).Caption='Mesa') then Mesa:=TSuiteButton(Main.Components[I]);
    end;
    Check(Assigned(Editor) and Assigned(Mesa),'Editor and Mesa button');
    Driver:=TDriver.Create; Driver.Timer:=TTimer.Create(nil);
    Driver.Timer.Interval:=100; Driver.Timer.OnTimer:=@Driver.ApplySaved; Driver.Timer.Enabled:=True;
    Mesa.Click;
    Check(Driver.Failure='',Driver.Failure);
    Check((Editor.Document.BedW=220.5) and (Editor.Document.BedH=180.25),'Mesa button updates real drawing dimensions');
    Store.Load; Check(Store.Count=4,'Reading does not rewrite MultiCNC equipment');
    TextFile:=TStringList.Create;
    try TextFile.Text:='{broken'; TextFile.SaveToFile(FN); finally TextFile.Free; end;
    F:=TLaserBedForm.Create(nil); F.Configure(150,160,1000,FN);
    Check((TComboBox(F.FindComponent('BedEquipment')).Items.Count=1) and
      (F.WidthMM=150) and (F.HeightMM=160),'Corrupt store preserves manual dimensions');
    Writeln('PASS: Mesa combobox, saved lasers, CUSTOM, manual/cancel, drawing resized, missing/corrupt store');
  finally
    SetEquipmentFile(OldOverride);
    if Assigned(Driver) then begin Driver.Timer.Free; Driver.Free; end;
    Main.Free; F.Free; Store.Free; DeleteFile(FN); DeleteFile(FN+'.bak');
  end;
 except on E:Exception do begin Writeln('FAIL: ',E.Message); Halt(1); end; end;
end.
