unit multicad_text3ddlg;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, multicad_generatedmesh, multicad_aiconfig;

function GenerateCadMeshFromText(Owner: TComponent; var Config: TCadAIConfig): TCadGeneratedMesh;

implementation

uses SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin, LazUTF8, multicad_text3d;

type
  TCadText3DDialog = class(TForm)
  private
    FPrompt: TMemo;
    FConfig: TCadAIConfig;
    FModel: TLabel;
    FSize: TFloatSpinEdit;
    FSizeReference:TComboBox;
    FStatus: TLabel;
    FGenerate, FCancel: TButton;
    FTimer: TTimer;
    FJob: TCadText3DJob;
    FResult: TCadGeneratedMesh;
    FClosing: Boolean;
    procedure GenerateClick(Sender: TObject);
    procedure ConfigureClick(Sender: TObject);
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
    Result.SetBounds(X, 290, 112, 30);
    Result.OnClick := Handler;
  end;

begin
  inherited CreateNew(AOwner);
  Caption := 'MultiCAD · Gerar modelo 3D por texto';
  BorderStyle := bsDialog;
  Position := poOwnerFormCenter;
  ClientWidth := 576;
  ClientHeight := 336;
  FConfig := Config;
  OnCloseQuery := @CanClose;

  LabelAt('Descreva a peça', 14);
  FPrompt := TMemo.Create(Self);
  FPrompt.Parent := Self;
  FPrompt.SetBounds(16, 35, 544, 88);
  FPrompt.ScrollBars := ssAutoVertical;

  FModel := LabelAt('Modelo Meshy   ' + FConfig.Model, 132);
  LabelAt('Medida desejada (mm)', 164);
  FSizeReference:=TComboBox.Create(Self);FSizeReference.Parent:=Self;FSizeReference.SetBounds(210,186,260,26);
  FSizeReference.Style:=csDropDownList;FSizeReference.Items.Text:='Maior dimensão'+LineEnding+'Altura'+LineEnding+'Largura'+LineEnding+'Profundidade';FSizeReference.ItemIndex:=0;
  FSize := TFloatSpinEdit.Create(Self);
  FSize.Parent := Self;
  FSize.SetBounds(16, 186, 175, 26);
  FSize.DecimalPlaces := 1;
  FSize.MinValue := 0.1;
  FSize.MaxValue := 100000;
  FSize.Value := 100;

  LabelAt('O texto será enviado à Meshy. A tarefa pode consumir créditos.', 222);
  FStatus := LabelAt('', 244);
  FStatus.AutoSize := False;
  FStatus.Width := 544;
  FStatus.Height := 42;
  FStatus.WordWrap := True;
  ButtonAt('Configurar IA', 16, @ConfigureClick);
  FCancel := ButtonAt('Cancelar', 330, @CancelClick);
  FCancel.Cancel := True;
  FGenerate := ButtonAt('Gerar', 448, @GenerateClick);
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
  FResult.Free;
  inherited Destroy;
end;

procedure TCadText3DDialog.SetRunning(Running: Boolean);
begin
  FPrompt.Enabled := not Running;
  FSize.Enabled := not Running;FSizeReference.Enabled:=not Running;
  FGenerate.Enabled := not Running;
  FTimer.Enabled := Running;
end;

procedure TCadText3DDialog.GenerateClick(Sender: TObject);
var Prompt, Key, Model: string;
begin
  if FJob <> nil then Exit;
  Prompt := Trim(FPrompt.Text);
  Model := FConfig.Model;
  Key := FConfig.Key;
  if Key = '' then Key := Trim(GetEnvironmentVariableUTF8('MESHY_API_KEY'));
  if (Prompt = '') or (UTF8Length(Prompt) > 800) then
    FStatus.Caption := 'Informe uma descrição de até 800 caracteres.'
  else if (Key = '') or (Pos(#10, Key) > 0) or (Pos(#13, Key) > 0) or (Pos(#0, Key) > 0) then
    FStatus.Caption := 'Abra Configurar IA e informe a chave da Meshy.'
  else if Model = '' then
    FStatus.Caption := 'Abra Configurar IA e informe o modelo Meshy.'
  else
  begin
    FJob := TCadText3DJob.Create(Prompt, Key, Model, FSize.Value);
    FStatus.Caption := 'Enviando descrição à Meshy…';
    FJob.Start;
    SetRunning(True);
  end;
end;

procedure TCadText3DDialog.ConfigureClick(Sender: TObject);
begin
  if FJob <> nil then Exit;
  if EditCadAIConfig(Self, FConfig) then
  begin
    FModel.Caption := 'Modelo Meshy   ' + FConfig.Model;
    FStatus.Caption := '';
  end;
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

procedure TCadText3DDialog.CheckJob(Sender: TObject);
begin
  if FJob.Finished then
  begin
    FJob.WaitFor;
    if not FClosing then
    begin
      FStatus.Caption := FJob.ErrorMessage;
      FResult := FJob.TakeFeature;
      if FResult<>nil then case FSizeReference.ItemIndex of 1:FResult.SizeReference:='height';2:FResult.SizeReference:='width';3:FResult.SizeReference:='depth';else FResult.SizeReference:='max';end;
    end;
    FreeAndNil(FJob);
    SetRunning(False);
    if FClosing then ModalResult := mrCancel
    else if FResult <> nil then ModalResult := mrOk;
    Exit;
  end;
  if FClosing then Exit;
  case FJob.Stage of
    2: FStatus.Caption := 'Gerando a malha 3D na Meshy…';
    3: FStatus.Caption := 'Baixando e conferindo a malha…';
  end;
end;

function GenerateCadMeshFromText(Owner: TComponent; var Config: TCadAIConfig): TCadGeneratedMesh;
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
