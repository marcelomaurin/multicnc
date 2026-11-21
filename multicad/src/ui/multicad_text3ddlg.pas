unit multicad_text3ddlg;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, multicad_generatedmesh, multicad_aiconfig;

function GenerateCadMesh(Owner: TComponent; var Config: TCadAIConfig): TCadGeneratedMesh;

implementation

uses SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin, Dialogs, LazUTF8, LCLIntf,
  multicad_text3d, multicad_document, multicad_rebuild, multicad_view3d,
  multicad_camera, multicad_feature, multicad_log;

type
  TCadText3DDialog = class(TForm)
  private
    FPrompt: TMemo;
    FConfig: TCadAIConfig;
    FNotice: TLabel;
    FProvider, FModel: TComboBox;
    FImage: TButton;
    FSize: TFloatSpinEdit;
    FStatus: TLabel;
    FGenerate, FCancel, FConfigure, FOpenLog, FInsert: TButton;
    FTimer: TTimer;
    FJob: TCadText3DJob;
    FResult: TCadGeneratedMesh;
    FClosing: Boolean;
    FPreview: TCadView3D;
    FPreviewDoc: TCadDocument;
    FPreviewRebuild: TCadRebuilder;
    procedure GenerateClick(Sender: TObject);
    procedure GenerateImageClick(Sender: TObject);
    procedure StartGeneration(const ImageFile: string);
    procedure ProviderChanged(Sender: TObject);
    procedure ModelChanged(Sender: TObject);
    procedure ShowPreview;
    procedure ConfigureClick(Sender: TObject);
    procedure OpenLogClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure CheckJob(Sender: TObject);
    procedure CanClose(Sender: TObject; var Allow: Boolean);
    procedure SetRunning(Running: Boolean);
  public
    constructor Create(AOwner: TComponent; const Config: TCadAIConfig); reintroduce;
    destructor Destroy; override;
  end;

constructor TCadText3DDialog.Create(AOwner: TComponent; const Config: TCadAIConfig);

  function LabelAt(const Text: string; Y: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.Left := 16;
    Result.Top := Y;
    Result.Caption := Text;
  end;

  function ButtonAt(const Text: string; X: Integer; Handler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Self;
    Result.Caption := Text;
    Result.SetBounds(X, 388, 123, 30);
    Result.OnClick := Handler;
  end;

begin
  inherited CreateNew(AOwner);
  Caption := 'MultiCAD · Modelar peça por IA';
  BorderStyle := bsDialog;
  Position := poOwnerFormCenter;
  ClientWidth := 850;
  ClientHeight := 434;
  FConfig := Config;
  OnCloseQuery := @CanClose;

  LabelAt('Descreva a peça', 14);
  FPrompt := TMemo.Create(Self);
  FPrompt.Parent := Self;
  FPrompt.SetBounds(16, 35, 392, 88);
  FPrompt.ScrollBars := ssAutoVertical;

  LabelAt('Provedor', 132);
  FProvider := TComboBox.Create(Self);
  FProvider.Parent := Self;
  FProvider.SetBounds(16, 153, 145, 26);
  FProvider.Style := csDropDownList;
  FProvider.Items.Add(CadAIProviderNames[capMeshy]);
  FProvider.Items.Add(CadAIProviderNames[capTripo]);
  FProvider.ItemIndex := Ord(FConfig.Provider);
  FProvider.OnChange := @ProviderChanged;
  LabelAt('Modelo', 132).Left := 176;
  FModel := TComboBox.Create(Self);
  FModel.Parent := Self;
  FModel.SetBounds(176, 153, 232, 26);
  FModel.Style := csDropDownList;
  FModel.OnChange := @ModelChanged;
  LabelAt('Maior dimensão da peça (mm)', 196);
  FSize := TFloatSpinEdit.Create(Self);
  FSize.Parent := Self;
  FSize.SetBounds(16, 217, 175, 26);
  FSize.DecimalPlaces := 1;
  FSize.MinValue := 0.1;
  FSize.MaxValue := 100000;
  FSize.Value := 100;

  FGenerate := ButtonAt('Gerar por texto', 16, @GenerateClick);
  FGenerate.Top := 260;
  FImage := ButtonAt('Gerar por imagem', 147, @GenerateImageClick);
  FImage.Top := 260;
  FNotice := LabelAt('', 302);
  FNotice.SetBounds(16, 302, 392, 34);
  FNotice.AutoSize := False;
  FNotice.WordWrap := True;
  FStatus := LabelAt('', 344);
  FStatus.AutoSize := False;
  FStatus.Width := 392;
  FStatus.Height := 40;
  FStatus.WordWrap := True;
  FConfigure := ButtonAt('Configurar IA', 16, @ConfigureClick);
  FOpenLog := ButtonAt('Abrir log', 147, @OpenLogClick);
  FCancel := ButtonAt('Cancelar', 573, @CancelClick);
  FCancel.Cancel := True;
  FInsert := ButtonAt('Inserir peça', 704, nil);
  FInsert.ModalResult := mrOk;
  FInsert.Enabled := False;

  FPreviewDoc := TCadDocument.Create;
  FPreviewDoc.NewPart;
  FPreviewRebuild := TCadRebuilder.Create(FPreviewDoc);
  FPreview := TCadView3D.Create(Self);
  FPreview.Parent := Self;
  FPreview.SetBounds(427, 35, 400, 337);
  FPreview.SetView(svIso);
  LabelAt('Prévia 3D', 14).Left := 427;
  ProviderChanged(nil);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 200;
  FTimer.OnTimer := @CheckJob;
  ActiveControl := FPrompt;
end;

destructor TCadText3DDialog.Destroy;
begin
  if FTimer <> nil then FTimer.Enabled := False;
  FJob.Free;
  FPreview.Free;
  FPreviewRebuild.Free;
  FPreviewDoc.Free;
  FResult.Free;
  inherited Destroy;
end;

procedure TCadText3DDialog.SetRunning(Running: Boolean);
begin
  FPrompt.Enabled := not Running;
  FSize.Enabled := not Running;
  FGenerate.Enabled := not Running;
  FProvider.Enabled := not Running;
  FModel.Enabled := not Running;
  FConfigure.Enabled := not Running;
  FImage.Enabled := not Running and (FProvider.ItemIndex = Ord(capTripo));
  FInsert.Enabled := not Running and (FResult <> nil);
  FTimer.Enabled := Running;
end;

procedure TCadText3DDialog.ProviderChanged(Sender: TObject);
var
  Provider: TCadAIProvider;
  I: Integer;
  SelectedModel: string;
begin
  if FProvider.ItemIndex < 0 then Exit;
  Provider := TCadAIProvider(FProvider.ItemIndex);
  SelectedModel := CadAINormalizeModel(Provider, FConfig.Models[Provider]);
  FConfig.Models[Provider] := SelectedModel;
  FModel.Items.BeginUpdate;
  try
    FModel.Items.Clear;
    for I := 0 to CadAIModelCount(Provider) - 1 do
      FModel.Items.Add(CadAIModelAt(Provider, I));
    FModel.ItemIndex := FModel.Items.IndexOf(SelectedModel);
    if (FModel.ItemIndex < 0) and (FModel.Items.Count > 0) then
      FModel.ItemIndex := 0;
  finally
    FModel.Items.EndUpdate;
  end;
  if Provider = capTripo then
    FNotice.Caption := 'A Tripo recebe o texto ou a imagem. A geração e a conversão podem consumir créditos.'
  else
    FNotice.Caption := 'A Meshy recebe o texto. A geração pode consumir créditos.';
  FImage.Enabled := Provider = capTripo;
end;

procedure TCadText3DDialog.ModelChanged(Sender: TObject);
var Provider: TCadAIProvider;
begin
  if (FProvider.ItemIndex < 0) or (FModel.ItemIndex < 0) then Exit;
  Provider := TCadAIProvider(FProvider.ItemIndex);
  FConfig.Models[Provider] := CadAINormalizeModel(Provider, FModel.Text);
end;

procedure TCadText3DDialog.GenerateClick(Sender: TObject);
begin
  StartGeneration('');
end;

procedure TCadText3DDialog.GenerateImageClick(Sender: TObject);
var Picker: TOpenDialog;
begin
  if (FJob <> nil) or (FProvider.ItemIndex <> Ord(capTripo)) then Exit;
  Picker := TOpenDialog.Create(Self);
  try
    Picker.Title := 'Escolher imagem de referência para a Tripo';
    Picker.Filter := 'Imagens PNG e JPEG|*.png;*.jpg;*.jpeg';
    Picker.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
    if Picker.Execute then StartGeneration(Picker.FileName);
  finally
    Picker.Free;
  end;
end;

procedure TCadText3DDialog.StartGeneration(const ImageFile: string);
var Prompt, Key, Model, ProviderName: string; Provider: TCadAIProvider;
begin
  if FJob <> nil then Exit;
  Provider := TCadAIProvider(FProvider.ItemIndex);
  ProviderName := CadAIProviderNames[Provider];
  Prompt := Trim(FPrompt.Text);
  Model := Trim(FModel.Text);
  if Model = '' then Model := FConfig.Models[Provider];
  Key := FConfig.Keys[Provider];
  if Key = '' then Key := Trim(GetEnvironmentVariableUTF8(CadAIKeyVariables[Provider]));
  if (ImageFile = '') and ((Prompt = '') or (UTF8Length(Prompt) > 800)) then
    FStatus.Caption := 'Informe uma descrição de até 800 caracteres.'
  else if (Key = '') or (Pos(#10, Key) > 0) or (Pos(#13, Key) > 0) or (Pos(#0, Key) > 0) then
    FStatus.Caption := 'Abra Configurar IA e informe a chave de ' + ProviderName + '.'
  else if not CadAIModelCompatible(Provider, Model) then
    FStatus.Caption := 'Selecione um modelo compatível com ' + ProviderName + '.'
  else
  begin
    FConfig.Models[Provider] := CadAINormalizeModel(Provider, Model);
    CadLog('AI.UI.START', Format('provider=%s model=%s key_len=%d size_mm=%.2f image=%s',
      [ProviderName, FConfig.Models[Provider], Length(Key), FSize.Value, BoolToStr(ImageFile <> '', True)]));
    if ImageFile <> '' then Prompt := '';
    FJob := TCadText3DJob.Create(Prompt, Key, FConfig.Models[Provider], FSize.Value, Provider, ImageFile);
    FStatus.Caption := 'Iniciando geração em ' + ProviderName + '…';
    FJob.Start;
    SetRunning(True);
  end;
end;

procedure TCadText3DDialog.ConfigureClick(Sender: TObject);
begin
  if FJob <> nil then Exit;
  if EditCadAIConfig(Self, FConfig) then
  begin
    FProvider.ItemIndex := Ord(FConfig.Provider);
    ProviderChanged(nil);
    FStatus.Caption := '';
  end;
end;

procedure TCadText3DDialog.OpenLogClick(Sender: TObject);
var LogFile: string;
begin
  LogFile := CadLogPath;
  if (LogFile = '') or not FileExists(LogFile) then
    FStatus.Caption := 'Arquivo de log ainda não encontrado.'
  else if not OpenDocument(LogFile) then
    FStatus.Caption := 'Não foi possível abrir o log: ' + LogFile;
end;

procedure TCadText3DDialog.CancelClick(Sender: TObject);
begin
  if FJob = nil then
    ModalResult := mrCancel
  else
  begin
    FClosing := True;
    FCancel.Enabled := False;
    FJob.Cancel;
    FStatus.Caption := 'Encerrando a espera local pela tarefa…';
  end;
end;

procedure TCadText3DDialog.CanClose(Sender: TObject; var Allow: Boolean);
begin
  Allow := FJob = nil;
  if not Allow then CancelClick(Sender);
end;

procedure TCadText3DDialog.ShowPreview;
var Candidate: TCadGeneratedMesh;
begin
  FPreview.SetModel(nil, nil);
  FPreviewRebuild.Invalidate;
  FPreviewDoc.NewPart;
  Candidate := FResult.CopyForPreview;
  try
    FPreviewDoc.AddFeature(Candidate);
  except
    Candidate.Free;
    raise;
  end;
  if FPreviewRebuild.Rebuild <> 0 then
    raise Exception.Create(Candidate.Message);
  FPreview.SetModel(FPreviewDoc, FPreviewRebuild);
  FPreview.FitAll;
  if Candidate.Message <> '' then FStatus.Caption := Candidate.Message
  else FStatus.Caption := 'Confira a prévia e clique em Inserir peça.';
end;

procedure TCadText3DDialog.CheckJob(Sender: TObject);
var Candidate: TCadGeneratedMesh;
begin
  if FJob.Finished then
  begin
    FJob.WaitFor;
    if not FClosing then
    begin
      FStatus.Caption := FJob.ErrorMessage;
      Candidate := FJob.TakeFeature;
      if Candidate <> nil then
      begin
        FreeAndNil(FResult);
        FResult := Candidate;
        try
          ShowPreview;
        except
          on E: Exception do
          begin
            FreeAndNil(FResult);
            FStatus.Caption := E.Message;
          end;
        end;
      end;
    end;
    FreeAndNil(FJob);
    SetRunning(False);
    if FClosing then ModalResult := mrCancel;
    Exit;
  end;
  if FClosing then Exit;
  case FJob.Stage of
    2: FStatus.Caption := 'Gerando a malha 3D…';
    3: FStatus.Caption := 'Baixando e conferindo a malha…';
    4: FStatus.Caption := 'Enviando a imagem à Tripo…';
    5: FStatus.Caption := 'Convertendo a malha para STL…';
  end;
end;

function GenerateCadMesh(Owner: TComponent; var Config: TCadAIConfig): TCadGeneratedMesh;
var Dialog: TCadText3DDialog;
begin
  Result := nil;
  Dialog := TCadText3DDialog.Create(Owner, Config);
  try
    if Dialog.ShowModal = mrOk then
    begin
      Result := Dialog.FResult;
      Dialog.FResult := nil;
    end;
    Config := Dialog.FConfig;
  finally
    Dialog.Free;
  end;
end;

end.
