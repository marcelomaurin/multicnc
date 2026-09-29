unit multislicer_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,Dialogs,multislicer_mesh,multislicer_stl,multislicer_engine,multislicer_types,multislicer_profile,multislicer_gcode;
type TMultiSlicerForm=class(TForm)
 private M:TMesh;Layers:TList;Profile:TPrinterProfile;Log:TMemo;LayerEdit:TEdit;OpenBtn,SliceBtn,ExportBtn:TButton;
  procedure OpenClick(Sender:TObject);procedure SliceClick(Sender:TObject);procedure ExportClick(Sender:TObject);procedure ClearLayers;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
constructor TMultiSlicerForm.Create(AOwner:TComponent);
begin inherited Create(AOwner);Caption:='MultiSlicer - 3D Printer';Width:=900;Height:=600;M:=TMesh.Create;Layers:=TList.Create;Profile:=DefaultPrinterProfile;
 OpenBtn:=TButton.Create(Self);OpenBtn.Parent:=Self;OpenBtn.Align:=alTop;OpenBtn.Caption:='Abrir STL ASCII';OpenBtn.OnClick:=@OpenClick;
 LayerEdit:=TEdit.Create(Self);LayerEdit.Parent:=Self;LayerEdit.Align:=alTop;LayerEdit.Text:='0.20';LayerEdit.TextHint:='Altura de camada (mm)';
 SliceBtn:=TButton.Create(Self);SliceBtn.Parent:=Self;SliceBtn.Align:=alTop;SliceBtn.Caption:='Fatiar';SliceBtn.OnClick:=@SliceClick;
 ExportBtn:=TButton.Create(Self);ExportBtn.Parent:=Self;ExportBtn.Align:=alTop;ExportBtn.Caption:='Exportar G-code';ExportBtn.OnClick:=@ExportClick;
 Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.Lines.Add('Abra um STL ASCII para iniciar.');end;
procedure TMultiSlicerForm.ClearLayers;var I:Integer;begin for I:=0 to Layers.Count-1 do TObject(Layers[I]).Free;Layers.Clear;end;
destructor TMultiSlicerForm.Destroy;begin ClearLayers;Layers.Free;M.Free;inherited;end;
procedure TMultiSlicerForm.OpenClick(Sender:TObject);var D:TOpenDialog;begin D:=TOpenDialog.Create(Self);try D.Filter:='STL|*.stl';if D.Execute then if TSTLImporter.LoadASCII(D.FileName,M)then Log.Lines.Add(Format('Malha: %d triangulos; Z %.3f..%.3f',[M.Count,M.MinZ,M.MaxZ]))else Log.Lines.Add('Falha/arquivo nao ASCII');finally D.Free;end;end;
procedure TMultiSlicerForm.SliceClick(Sender:TObject);var S:TSlicer;H:Double;begin if M.Count=0 then Exit;H:=StrToFloatDef(LayerEdit.Text,0.2);ClearLayers;S:=TSlicer.Create;try S.Slice(M,H,Layers);finally S.Free;end;Profile.LayerHeight:=H;Log.Lines.Add(Format('Fatiado: %d camadas',[Layers.Count]));end;
procedure TMultiSlicerForm.ExportClick(Sender:TObject);var D:TSaveDialog;begin if Layers.Count=0 then Exit;D:=TSaveDialog.Create(Self);try D.Filter:='G-code|*.gcode';if D.Execute then begin TSlicerGCode.ExportLayers(Layers,Profile,D.FileName);Log.Lines.Add('Gerado: '+D.FileName);end;finally D.Free;end;end;
end.
