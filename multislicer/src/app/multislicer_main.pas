unit multislicer_main;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Spin,
  Dialogs, multislicer_mesh, multislicer_stl, multislicer_types, multislicer_profile,
  multislicer_pipeline, multislicer_layerpreview;
type
  TMultiSlicerForm = class(TForm)
  private
    M: TMesh;
    Engine: TModernSlicer;
    Code: TStringList;
    Report: TSliceReport;
    Ready: Boolean;
    SourceFile: string;
    Log: TMemo;
    Preview: TSlicerLayerPreview;
    LayerChoice: TSpinEdit;
    LayerHeight, Nozzle, BedX, BedY, BedZ, Speed: TFloatSpinEdit;
    Walls, Density, Hotend, BedTemp: TSpinEdit;
    PatternChoice, FlavorChoice: TComboBox;
    Adaptive: TCheckBox;
    SliceBtn, ExportBtn: TButton;
    procedure OpenClick(Sender: TObject);
    procedure SliceClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SettingsChanged(Sender: TObject);
    procedure LayerChanged(Sender: TObject);
    function Settings: TSliceSettings;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FN: string);
    procedure GenerateProgram;
    procedure ExportProgram(const FN: string);
    property SliceReport: TSliceReport read Report;
    property ProgramReady: Boolean read Ready;
  end;
implementation

constructor TMultiSlicerForm.Create(AOwner: TComponent);
var Bar, LayerBar: TPanel; Options: TScrollBox; Pages: TPageControl; ViewTab, CodeTab: TTabSheet;
  B: TButton; L: TLabel; Row: Integer;
  procedure Title(const S: string);
  begin
    L := TLabel.Create(Self); L.Parent := Options; L.SetBounds(12, Row, 218, 20); L.Caption := S; Inc(Row, 22);
  end;
  function FloatField(const Caption, AName: string; Value, MinValue, MaxValue: Double): TFloatSpinEdit;
  begin
    Title(Caption); Result := TFloatSpinEdit.Create(Self); Result.Parent := Options; Result.Name := AName;
    Result.SetBounds(12, Row, 218, 28); Result.MinValue := MinValue; Result.MaxValue := MaxValue;
    Result.DecimalPlaces := 3; Result.Increment := 0.05; Result.Value := Value;
    Result.OnChange := @SettingsChanged; Inc(Row, 36);
  end;
  function IntField(const Caption, AName: string; Value, MinValue, MaxValue: Integer): TSpinEdit;
  begin
    Title(Caption); Result := TSpinEdit.Create(Self); Result.Parent := Options; Result.Name := AName;
    Result.SetBounds(12, Row, 218, 28); Result.MinValue := MinValue; Result.MaxValue := MaxValue;
    Result.Value := Value; Result.OnChange := @SettingsChanged; Inc(Row, 36);
  end;
begin
  inherited CreateNew(AOwner); Caption := 'MultiSlicer | Preparacao para impressao 3D';
  Position := poScreenCenter; Width := 1100; Height := 760; Constraints.MinWidth := 850; Constraints.MinHeight := 620;
  M := TMesh.Create; Engine := TModernSlicer.Create; Code := TStringList.Create;
  Bar := TPanel.Create(Self); Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 48;
  B := TButton.Create(Self); B.Parent := Bar; B.SetBounds(8, 8, 140, 32); B.Caption := 'Abrir STL...'; B.OnClick := @OpenClick;
  SliceBtn := TButton.Create(Self); SliceBtn.Name := 'Slice'; SliceBtn.Parent := Bar;
  SliceBtn.SetBounds(158, 8, 140, 32); SliceBtn.Caption := 'Fatiar e visualizar'; SliceBtn.OnClick := @SliceClick; SliceBtn.Enabled := False;
  ExportBtn := TButton.Create(Self); ExportBtn.Name := 'Export'; ExportBtn.Parent := Bar;
  ExportBtn.SetBounds(308, 8, 140, 32); ExportBtn.Caption := 'Exportar G-code...'; ExportBtn.OnClick := @ExportClick; ExportBtn.Enabled := False;
  Options := TScrollBox.Create(Self); Options.Parent := Self; Options.Align := alLeft; Options.Width := 252; Row := 10;
  LayerHeight := FloatField('Altura de camada (mm)', 'LayerHeight', 0.2, 0.01, 1);
  Nozzle := FloatField('Bico (mm)', 'Nozzle', 0.4, 0.1, 5);
  Walls := IntField('Numero de paredes', 'Walls', 2, 1, 20);
  Density := IntField('Preenchimento (%)', 'InfillDensity', 20, 0, 100);
  Title('Padrao de preenchimento'); PatternChoice := TComboBox.Create(Self); PatternChoice.Parent := Options;
  PatternChoice.SetBounds(12, Row, 218, 28); PatternChoice.Style := csDropDownList;
  PatternChoice.Items.Add('Gyroid'); PatternChoice.Items.Add('Retilineo'); PatternChoice.ItemIndex := 0;
  PatternChoice.OnChange := @SettingsChanged; Inc(Row, 36);
  Title('Firmware de impressao'); FlavorChoice := TComboBox.Create(Self); FlavorChoice.Parent := Options;
  FlavorChoice.SetBounds(12, Row, 218, 28); FlavorChoice.Style := csDropDownList;
  FlavorChoice.Items.Add('Marlin'); FlavorChoice.Items.Add('Klipper'); FlavorChoice.ItemIndex := 0;
  FlavorChoice.OnChange := @SettingsChanged; Inc(Row, 36);
  BedX := FloatField('Mesa X (mm)', 'BedX', 220, 1, 2000);
  BedY := FloatField('Mesa Y (mm)', 'BedY', 220, 1, 2000);
  BedZ := FloatField('Altura maxima Z (mm)', 'BedZ', 250, 1, 2000);
  Speed := FloatField('Impressao (mm/s)', 'PrintSpeed', 50, 1, 500);
  Hotend := IntField('Temperatura do bico (C)', 'HotendTemperature', 200, 0, 400);
  BedTemp := IntField('Temperatura da mesa (C)', 'BedTemperature', 60, 0, 150);
  Adaptive := TCheckBox.Create(Self); Adaptive.Parent := Options; Adaptive.SetBounds(12, Row, 218, 30);
  Adaptive.Caption := 'Altura adaptativa'; Adaptive.OnChange := @SettingsChanged;
  Pages := TPageControl.Create(Self); Pages.Parent := Self; Pages.Align := alClient;
  ViewTab := TTabSheet.Create(Self); ViewTab.PageControl := Pages; ViewTab.Caption := 'Camadas';
  LayerBar := TPanel.Create(Self); LayerBar.Parent := ViewTab; LayerBar.Align := alTop; LayerBar.Height := 45;
  L := TLabel.Create(Self); L.Parent := LayerBar; L.SetBounds(10, 12, 70, 20); L.Caption := 'Camada';
  LayerChoice := TSpinEdit.Create(Self); LayerChoice.Parent := LayerBar; LayerChoice.SetBounds(90, 8, 130, 30);
  LayerChoice.MinValue := 1; LayerChoice.MaxValue := 1; LayerChoice.Value := 1; LayerChoice.OnChange := @LayerChanged;
  Preview := TSlicerLayerPreview.Create(Self); Preview.Parent := ViewTab; Preview.Align := alClient;
  CodeTab := TTabSheet.Create(Self); CodeTab.PageControl := Pages; CodeTab.Caption := 'G-code e relatorio';
  Log := TMemo.Create(Self); Log.Name := 'SliceOutput'; Log.Parent := CodeTab; Log.Align := alClient;
  Log.ReadOnly := True; Log.WordWrap := False; Log.ScrollBars := ssAutoBoth;
  Log.Lines.Add('Abra um STL. A previa e a exportacao usam o mesmo pipeline de fatiamento.');
end;
destructor TMultiSlicerForm.Destroy;
begin Code.Free; Engine.Free; M.Free; inherited; end;

procedure TMultiSlicerForm.SettingsChanged(Sender: TObject);
begin
  Ready := False;
  if Assigned(Code) then Code.Clear;
  if Assigned(Preview) then Preview.SetSlice(nil, 0);
  if Assigned(Log) and (M.Count > 0) then Log.Text := 'Configuracao alterada. Fatie novamente para atualizar a previa.';
end;

procedure TMultiSlicerForm.OpenFile(const FN: string);
var Candidate: TMesh;
begin
  if not FileExists(FN) then raise EInOutError.Create('Arquivo nao encontrado: ' + FN);
  Candidate := TMesh.Create;
  try
    if not TSTLImporter.Load(FN, Candidate) or (Candidate.Count = 0) then
      raise Exception.Create('STL invalido ou sem triangulos: ' + FN);
    M.Free; M := Candidate; Candidate := nil; SourceFile := ExpandFileName(FN);
    SettingsChanged(nil); SliceBtn.Enabled := True; ExportBtn.Enabled := True;
    Log.Text := Format('Aberto: %s | %d triangulos', [FN, M.Count]);
  finally Candidate.Free; end;
end;
function TMultiSlicerForm.Settings: TSliceSettings;
begin
  Result := DefaultSliceSettings; Result.Printer := DefaultPrinterProfile;
  Result.Printer.BedX := BedX.Value; Result.Printer.BedY := BedY.Value; Result.Printer.MaxZ := BedZ.Value;
  Result.Printer.Nozzle := Nozzle.Value; Result.Printer.HotendTemp := Hotend.Value; Result.Printer.BedTemp := BedTemp.Value;
  Result.LayerHeight := LayerHeight.Value; Result.Printer.LayerHeight := Result.LayerHeight;
  Result.FirstLayerHeight := Result.LayerHeight;
  if Result.LayerHeight > Result.Printer.Nozzle * 0.8 then
    raise Exception.Create('A altura de camada deve ser no maximo 80% do diametro do bico.');
  Result.LineWidth := Result.Printer.Nozzle * 1.125;
  Result.Walls := Walls.Value; Result.InfillDensity := Density.Value / 100;
  Result.InfillPattern := TInfillPattern(PatternChoice.ItemIndex); Result.Flavor := TSlicerFlavor(FlavorChoice.ItemIndex);
  Result.WallSpeed := Speed.Value; Result.OuterWallSpeed := Speed.Value * 0.6; Result.InfillSpeed := Speed.Value;
  Result.Adaptive := Adaptive.Checked;
  Result.AdaptiveMin := Min(0.08, Result.LayerHeight);
  Result.AdaptiveMax := Min(Result.LayerHeight, Result.Printer.Nozzle * 0.8);
  Result.ObjectName := ChangeFileExt(ExtractFileName(SourceFile), '');
end;

procedure TMultiSlicerForm.GenerateProgram;
var Candidate: TModernSlicer; G: TStringList; R: TSliceReport;
begin
  if M.Count = 0 then raise Exception.Create('Abra um STL primeiro.');
  Candidate := TModernSlicer.Create; G := TStringList.Create;
  try
    R := Candidate.Slice(M, Settings, G);
    if (R.Layers = 0) or (G.Count = 0) then raise Exception.Create('O modelo nao gerou camadas imprimiveis.');
    Engine.Free; Engine := Candidate; Candidate := nil; Code.Assign(G); Report := R; Ready := True;
    LayerChoice.MaxValue := R.Layers; LayerChoice.Value := 1; LayerChanged(nil);
    Log.Lines.Clear;
    Log.Lines.Add(Format('; %d camadas | %.2f g | %.1f min | %d retracoes',
      [R.Layers, R.FilamentGrams, R.EstimatedSeconds / 60, R.Retractions]));
    if R.Warnings <> '' then Log.Lines.Add('; Avisos: ' + R.Warnings);
    Log.Lines.AddStrings(Code);
  finally G.Free; Candidate.Free; end;
end;
procedure TMultiSlicerForm.ExportProgram(const FN: string);
begin
  if not Ready then GenerateProgram;
  Code.SaveToFile(FN);
end;
procedure TMultiSlicerForm.LayerChanged(Sender: TObject);
begin if Ready then Preview.SetSlice(Engine, LayerChoice.Value - 1); end;
procedure TMultiSlicerForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'STL binario ou ASCII|*.stl'; D.Options := [ofFileMustExist, ofEnableSizing];
    if D.Execute then try OpenFile(D.FileName); except on E: Exception do ShowMessage(E.Message); end;
  finally D.Free; end;
end;
procedure TMultiSlicerForm.SliceClick(Sender: TObject);
begin try GenerateProgram; except on E: Exception do ShowMessage(E.Message); end; end;
procedure TMultiSlicerForm.ExportClick(Sender: TObject);
var D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'G-code|*.gcode'; D.DefaultExt := 'gcode';
    D.FileName := ChangeFileExt(ExtractFileName(SourceFile), '.gcode');
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if D.Execute then try ExportProgram(D.FileName); except on E: Exception do ShowMessage(E.Message); end;
  finally D.Free; end;
end;
end.
