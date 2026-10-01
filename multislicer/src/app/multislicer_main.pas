unit multislicer_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,Dialogs,multislicer_mesh,multislicer_stl,multislicer_engine,multislicer_types,multislicer_profile,multislicer_gcode,multislicer_pipeline;
type TMultiSlicerForm=class(TForm)
 private M:TMesh;Layers:TList;Profile:TPrinterProfile;Log:TMemo;LayerEdit:TEdit;OpenBtn,SliceBtn,ExportBtn:TButton;
  procedure OpenClick(Sender:TObject);procedure SliceClick(Sender:TObject);procedure ExportClick(Sender:TObject);procedure ClearLayers;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;procedure OpenFile(const FN:string);
 end;
implementation
constructor TMultiSlicerForm.Create(AOwner:TComponent);
begin inherited Create(AOwner);Caption:='MultiSlicer - 3D Printer';Width:=900;Height:=600;M:=TMesh.Create;Layers:=TList.Create;Profile:=DefaultPrinterProfile;
 OpenBtn:=TButton.Create(Self);OpenBtn.Parent:=Self;OpenBtn.Align:=alTop;OpenBtn.Caption:='Abrir STL (binario ou ASCII)';OpenBtn.OnClick:=@OpenClick;
 LayerEdit:=TEdit.Create(Self);LayerEdit.Parent:=Self;LayerEdit.Align:=alTop;LayerEdit.Text:='0.20';LayerEdit.TextHint:='Altura de camada (mm)';
 SliceBtn:=TButton.Create(Self);SliceBtn.Parent:=Self;SliceBtn.Align:=alTop;SliceBtn.Caption:='Fatiar';SliceBtn.OnClick:=@SliceClick;
 ExportBtn:=TButton.Create(Self);ExportBtn.Parent:=Self;ExportBtn.Align:=alTop;ExportBtn.Caption:='Exportar G-code';ExportBtn.OnClick:=@ExportClick;
 Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.Lines.Add('Abra um STL para iniciar. Exportacao usa o pipeline moderno (perimetros, gyroid, topo/fundo solidos, M73).');end;
procedure TMultiSlicerForm.ClearLayers;var I:Integer;begin for I:=0 to Layers.Count-1 do TObject(Layers[I]).Free;Layers.Clear;end;
destructor TMultiSlicerForm.Destroy;begin ClearLayers;Layers.Free;M.Free;inherited;end;
procedure TMultiSlicerForm.OpenFile(const FN:string);begin if(FN='')or(not FileExists(FN))then Exit;if TSTLImporter.Load(FN,M)then Log.Lines.Add(Format('Aberto pelo MultiSuite: %s | %d triangulos',[FN,M.Count]))else Log.Lines.Add('Arquivo recebido pelo MultiSuite nao e STL valido: '+FN);end;
procedure TMultiSlicerForm.OpenClick(Sender:TObject);var D:TOpenDialog;begin D:=TOpenDialog.Create(Self);try D.Filter:='STL|*.stl';if D.Execute then OpenFile(D.FileName);finally D.Free;end;end;
procedure TMultiSlicerForm.SliceClick(Sender:TObject);var S:TSlicer;H:Double;begin if M.Count=0 then Exit;H:=StrToFloatDef(LayerEdit.Text,0.2);ClearLayers;S:=TSlicer.Create;try S.Slice(M,H,Layers);finally S.Free;end;Profile.LayerHeight:=H;Log.Lines.Add(Format('Fatiado: %d camadas',[Layers.Count]));end;
procedure TMultiSlicerForm.ExportClick(Sender:TObject);
var D:TSaveDialog;S:TModernSlicer;Cfg:TSliceSettings;G:TStringList;R:TSliceReport;
begin
 if M.Count=0 then Exit;
 D:=TSaveDialog.Create(Self);S:=TModernSlicer.Create;G:=TStringList.Create;
 try
  D.Filter:='G-code|*.gcode';
  if not D.Execute then Exit;
  Cfg:=DefaultSliceSettings;Cfg.Printer:=Profile;Cfg.LayerHeight:=StrToFloatDef(LayerEdit.Text,0.2);
  R:=S.Slice(M,Cfg,G);G.SaveToFile(D.FileName);
  Log.Lines.Add(Format('Gerado: %s | %d camadas | %.1f g | %d min',[D.FileName,R.Layers,R.FilamentGrams,Round(R.EstimatedSeconds/60)]));
  if R.Warnings<>'' then Log.Lines.Add('Avisos: '+R.Warnings);
 finally G.Free;S.Free;D.Free;end;
end;
end.
