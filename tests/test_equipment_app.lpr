program test_equipment_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, Classes, SysUtils,
  mainform, multicnc_equipment, multicnc_types, multisuite_controls;
procedure Check(Condition: Boolean; const Msg: string);
begin if not Condition then raise Exception.Create(Msg); end;
var F: TMainForm; Store: TEquipmentStore; FN: string; I: Integer;
 Saved,Kind,Brand,Model,Port,Baud,Mode,PrinterBrand,PrinterModel: TComboBox;
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
  Mode.ItemIndex:=1; Mode.OnChange(Mode); Host.Text:='192.168.1.60'; NetPort.Text:='23';
  EquipmentName.Text:='Laser'; Save.Click;
  Check(Saved.Items.Count=2,'Save laser');
  Kind.ItemIndex:=2; Kind.OnChange(Kind);
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
  Saved.ItemIndex:=Saved.Items.IndexOf('Router da oficina'); Saved.OnChange(Saved);
  Check(Baud.Text='57600','Updated baud restored');
  Connect.Click; Check(not Saved.Enabled,'Prevent switching while connected');
  Connect.Click; Check(Saved.Enabled,'Allow switching after disconnect');
  FreeAndNil(F);
  Store:=TEquipmentStore.Create(FN); Store.Load;
  Check((Store.Count=3) and (Store.Item(Store.Find('Router da oficina')).BaudRate=57600),'Saved configuration');
  Writeln('Equipment GUI OK');
 finally
  F.Free; Store.Free; DeleteFile(FN); DeleteFile(FN+'.bak');
 end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.