program test_equipment_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, Classes, SysUtils, Spin, ExtCtrls,
  mainform, multicnc_equipment, multicnc_types, multisuite_controls;
procedure Check(Condition: Boolean; const Msg: string);
begin if not Condition then raise Exception.Create(Msg); end;
var F: TMainForm; Store: TEquipmentStore; FN: string; I: Integer;
 Legacy:TEquipmentProfile;
 Saved,Kind,Brand,Model,Port,Baud,Mode,PrinterBrand,PrinterModel,LaserBrand,LaserModel: TComboBox;
 LaserX,LaserY:TFloatSpinEdit;
 EquipmentName,Host,NetPort: TEdit; Save,Connect: TSuiteButton; Badge:TControl;
procedure Bind;
begin
 Saved:=TComboBox(F.FindComponent('SavedEquipment'));
 Kind:=TComboBox(F.FindComponent('MachineType'));
 Brand:=TComboBox(F.FindComponent('RouterBrand'));
 Model:=TComboBox(F.FindComponent('RouterModel'));
 Port:=TComboBox(F.FindComponent('SerialPort'));
 Baud:=TComboBox(F.FindComponent('BaudRate'));
 Mode:=TComboBox(F.FindComponent('CommunicationMode'));
 EquipmentName:=TEdit(F.FindComponent('EquipmentName'));
 Host:=TEdit(F.FindComponent('TCPHost')); NetPort:=TEdit(F.FindComponent('TCPPort'));
 PrinterBrand:=TComboBox(F.FindComponent('PrinterBrand')); PrinterModel:=TComboBox(F.FindComponent('PrinterModel'));
 LaserBrand:=TComboBox(F.FindComponent('LaserBrand')); LaserModel:=TComboBox(F.FindComponent('LaserModel'));
 LaserX:=TFloatSpinEdit(F.FindComponent('LaserWorkX')); LaserY:=TFloatSpinEdit(F.FindComponent('LaserWorkY'));
 Save:=TSuiteButton(F.FindComponent('SaveEquipment'));
 Badge:=TControl(F.FindComponent('ConnectionState'));
 Connect:=nil;
 for I:=0 to F.ComponentCount-1 do
   if (F.Components[I] is TSuiteButton) and (TSuiteButton(F.Components[I]).Caption='Connect Device') then
     Connect:=TSuiteButton(F.Components[I]);
 Check(Assigned(Saved) and Assigned(Connect) and Assigned(Save),'Controls found');
end;
begin
 try
 Application.Initialize;
 FN:=GetTempFileName(GetTempDir,'mce'); DeleteFile(FN); F:=nil; Store:=nil;
 try
  F:=TMainForm.CreateWithEquipmentFile(nil,FN); F.HandleNeeded; F.Realign; Bind;
  Saved.Parent.Width:=1180; TSuiteHeader(Saved.Parent).OnResize(Saved.Parent);
  Check((Saved.Parent=Connect.Parent) and (Badge.Left+Badge.Width<=Saved.Left) and
    (Saved.Left+Saved.Width<=Connect.Left),'Header order');
  Brand.ItemIndex:=Brand.Items.IndexOf('TwoTrees'); Brand.OnChange(Brand);
  Model.ItemIndex:=Model.Items.IndexOf('TTC3018'); Model.OnChange(Model);
  Mode.ItemIndex:=2; Mode.OnChange(Mode);
  Port.ItemIndex:=Port.Items.Add('COM9999'); Baud.Text:='230400';
  EquipmentName.Text:='Router da oficina'; Save.Click;
  Check((Saved.Items.Count=1) and FileExists(FN),'Save router');
  Kind.ItemIndex:=1; Kind.OnChange(Kind);
  TControl(F.FindComponent('Outline')).Parent.Parent.Width:=800;
  TPanel(TControl(F.FindComponent('Outline')).Parent).Width:=800;
  TPanel(TControl(F.FindComponent('Outline')).Parent).OnResize(TControl(F.FindComponent('Outline')).Parent);
  Check(TControl(F.FindComponent('Outline')).Visible,'Outline visible for CNC Laser');
  Check(not TControl(F.FindComponent('Outline')).Enabled,'Outline disabled while disconnected');
  for I:=0 to F.ComponentCount-1 do
    if (F.Components[I] is TSuiteButton) and (TSuiteButton(F.Components[I]).Caption='Emergency Stop') then
    begin
      Check((TControl(F.FindComponent('Outline')).Top=TSuiteButton(F.Components[I]).Top) and
        (TControl(F.FindComponent('Outline')).Left+TControl(F.FindComponent('Outline')).Width<
         TSuiteButton(F.Components[I]).Left),'Outline before Emergency Stop');
      Check(TSuiteButton(F.Components[I]).Left+TSuiteButton(F.Components[I]).Width<=
        TSuiteButton(F.Components[I]).Parent.ClientWidth,'Emergency Stop stays inside toolbar');
    end;
  LaserBrand.ItemIndex:=LaserBrand.Items.IndexOf('LONGER'); LaserBrand.OnChange(LaserBrand);
  LaserModel.ItemIndex:=LaserModel.Items.IndexOf('RAY5 20W'); LaserModel.OnChange(LaserModel);
  Check((LaserX.Value=400) and (LaserY.Value=365),'Commercial RAY5 20W area applied');
  Check(Pos('longer3d.com',TLabel(F.FindComponent('LaserSpecs')).Hint)>0,'Manufacturer source exposed');
  LaserBrand.ItemIndex:=LaserBrand.Items.IndexOf('Creality'); LaserBrand.OnChange(LaserBrand);
  LaserModel.ItemIndex:=LaserModel.Items.IndexOf('Falcon2 40W'); LaserModel.OnChange(LaserModel);
  Check((LaserX.Value=400) and (LaserY.Value=415),'Commercial Falcon2 area applied');
  LaserBrand.ItemIndex:=LaserBrand.Items.IndexOf('GLYPHO'); LaserBrand.OnChange(LaserBrand);
  Check(LaserModel.Items.Count=2,'two GLYPHO variants');
  Check(TSpinEdit(F.FindComponent('LaserPowerPercent')).Value=40,'5W suggested power applied');
  LaserModel.ItemIndex:=LaserModel.Items.IndexOf('S1 10W modificado'); LaserModel.OnChange(LaserModel);
  Check((LaserX.Value=130) and (LaserY.Value=130),'GLYPHO area');
  Check((TSpinEdit(F.FindComponent('LaserPowerPercent')).Value=20) and
    (TSpinEdit(F.FindComponent('LaserEngraveFeed')).Value=3000),'10W suggestions applied atomically');
  LaserX.Value:=125;
  Mode.ItemIndex:=1; Mode.OnChange(Mode); Host.Text:='192.168.1.60'; NetPort.Text:='23';
  EquipmentName.Text:='Laser'; Save.Click;
  Check(Saved.Items.Count=2,'Save laser');
  Kind.ItemIndex:=2; Kind.OnChange(Kind);
  Check(not TControl(F.FindComponent('Outline')).Visible,'Outline hidden for printer');
  PrinterBrand.ItemIndex:=PrinterBrand.Items.IndexOf('Creality'); PrinterBrand.OnChange(PrinterBrand);
  PrinterModel.ItemIndex:=PrinterModel.Items.IndexOf('Ender-3 V2'); PrinterModel.OnChange(PrinterModel);
  Mode.ItemIndex:=2; Mode.OnChange(Mode); Baud.Text:='250000';
  EquipmentName.Text:='Impressora'; Save.Click;
  Check(Saved.Items.Count=3,'Save printer');
  FreeAndNil(F); F:=TMainForm.CreateWithEquipmentFile(nil,FN); F.HandleNeeded; F.Realign; Bind;
  Check(Saved.Items.Count=3,'Reload GUI');
  Saved.ItemIndex:=Saved.Items.IndexOf('Router da oficina'); Saved.OnChange(Saved);
  Check((Kind.ItemIndex=0) and (Brand.Text='TwoTrees') and (Model.Text='TTC3018') and
    (Port.Text='COM9999') and (Baud.Text='230400') and (Mode.ItemIndex=2),'Restore router');
  Check(Connect.Caption='Connect Device','Selection does not connect');
  Port.OnDropDown(Port); Check(Port.Text='COM9999','Absent port preserved');
  Baud.Text:='57600'; Save.Click; Check(Saved.Items.Count=3,'Update keeps count');
  Saved.ItemIndex:=Saved.Items.IndexOf('Impressora'); Saved.OnChange(Saved);
  Check((Kind.ItemIndex=2) and (PrinterBrand.Text='Creality') and (PrinterModel.Text='Ender-3 V2') and
    (Baud.Text='250000') and (Mode.ItemIndex=2),'Restore printer');
  Saved.ItemIndex:=Saved.Items.IndexOf('Laser'); Saved.OnChange(Saved);
  Check((Kind.ItemIndex=1) and (Mode.ItemIndex=1) and (Host.Text='192.168.1.60') and (NetPort.Text='23'),'Restore laser');
  Check((LaserBrand.Text='GLYPHO') and (LaserModel.Text='S1 10W modificado') and
    (LaserX.Value=125) and (LaserY.Value=130),'Restore laser brand/model and edited area');
  Saved.ItemIndex:=Saved.Items.IndexOf('Router da oficina'); Saved.OnChange(Saved);
  Check(Baud.Text='57600','Updated baud restored');
  Connect.Click; Check(not Saved.Enabled,'Prevent switching while connected');
  Connect.Click; Check(Saved.Enabled,'Allow switching after disconnect');
  FreeAndNil(F);
  Store:=TEquipmentStore.Create(FN); Store.Load;
  Check((Store.Count=3) and (Store.Item(Store.Find('Router da oficina')).BaudRate=57600),'Saved configuration');
  Check((Store.Item(Store.Find('Laser')).Brand='GLYPHO') and
    (Store.Item(Store.Find('Laser')).Model='S1 10W modificado'),'Laser model persisted');
  Legacy:=DefaultEquipmentProfile; Legacy.Name:='Laser antigo'; Legacy.MachineType:=mtLaser;
  Legacy.ConnectionMode:=2; Legacy.WorkX:=90; Legacy.WorkY:=80;
  Store.Put(Legacy);
  FreeAndNil(Store);
  F:=TMainForm.CreateWithEquipmentFile(nil,FN); F.HandleNeeded; Bind;
  Saved.ItemIndex:=Saved.Items.IndexOf('Laser antigo'); Saved.OnChange(Saved);
  Check((LaserBrand.Text='Generic') and (LaserX.Value=90) and (LaserY.Value=80),'Legacy laser preserved');
  LaserBrand.ItemIndex:=LaserBrand.Items.IndexOf('CUSTOM'); LaserBrand.OnChange(LaserBrand);
  Check(TControl(F.FindComponent('LaserCustomManufacturer')).Visible,'CUSTOM controls visible');
  LaserX.Value:=220; LaserY.Value:=180;
  TEdit(F.FindComponent('LaserCustomManufacturer')).Text:='Oficina';
  TEdit(F.FindComponent('LaserCustomModel')).Text:='Modulo 7.5W';
  TFloatSpinEdit(F.FindComponent('LaserOpticalPowerW')).Value:=7.5;
  TSpinEdit(F.FindComponent('LaserWavelengthNM')).Value:=455;
  TCheckBox(F.FindComponent('LaserHasHoming')).Checked:=True;
  Mode.ItemIndex:=2; Mode.OnChange(Mode);
  EquipmentName.Text:='Custom A'; Save.Click;
  Check(Saved.Items.Count=5,'Save first CUSTOM');
  LaserX.Value:=300; LaserY.Value:=250;
  TFloatSpinEdit(F.FindComponent('LaserOpticalPowerW')).Value:=20;
  TEdit(F.FindComponent('LaserCustomModel')).Text:='Modulo 20W';
  TSpinEdit(F.FindComponent('LaserWavelengthNM')).Value:=0;
  TCheckBox(F.FindComponent('LaserHasHoming')).Checked:=False;
  EquipmentName.Text:='Custom B'; Save.Click;
  Check(Saved.Items.Count=6,'Save second independent CUSTOM');
  FreeAndNil(F); F:=TMainForm.CreateWithEquipmentFile(nil,FN); F.HandleNeeded; Bind;
  Saved.ItemIndex:=Saved.Items.IndexOf('Custom A'); Saved.OnChange(Saved);
  Check(TControl(F.FindComponent('LaserCustomManufacturer')).Parent.Visible,'CUSTOM panel restored');
  Check((LaserModel.Text='CUSTOM Laser') and (LaserBrand.Text='CUSTOM') and (LaserX.Value=220) and (LaserY.Value=180) and
    (TFloatSpinEdit(F.FindComponent('LaserOpticalPowerW')).Value=7.5) and
    (TEdit(F.FindComponent('LaserCustomManufacturer')).Text='Oficina') and
    (TEdit(F.FindComponent('LaserCustomModel')).Text='Modulo 7.5W') and
    (TSpinEdit(F.FindComponent('LaserWavelengthNM')).Value=455) and
    TCheckBox(F.FindComponent('LaserHasHoming')).Checked,'Restore complete CUSTOM A');
  Saved.ItemIndex:=Saved.Items.IndexOf('Custom B'); Saved.OnChange(Saved);
  Check((LaserX.Value=300) and (LaserY.Value=250) and
    (TFloatSpinEdit(F.FindComponent('LaserOpticalPowerW')).Value=20) and
    (TSpinEdit(F.FindComponent('LaserWavelengthNM')).Value=0) and
    not TCheckBox(F.FindComponent('LaserHasHoming')).Checked,'Restore independent CUSTOM B');
  FreeAndNil(F); Store:=TEquipmentStore.Create(FN); Store.Load;
  Legacy:=Store.Item(Store.Find('Custom B')); Legacy.LaserOpticalPowerW:=0;
  try Store.Put(Legacy); Check(False,'Reject zero CUSTOM optical power');
  except on E:Exception do Check(Pos('potencia optica',E.Message)>0,'Validation message'); end;
  Check(Store.Item(Store.Find('Custom B')).LaserOpticalPowerW=20,'Invalid save preserves existing data');
  Writeln('Equipment GUI OK (commercial, legacy and two independent CUSTOM profiles)');
 finally
  F.Free; Store.Free; DeleteFile(FN); DeleteFile(FN+'.bak');
 end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.