unit laserpcb_boardform;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin,
  laserpcb_project, multisuite_controls, multisuite_icons;
type
  TPCBBoardForm = class(TForm)
  private
    Model: TComboBox;
    CountField: TSpinEdit;
    WidthField, HeightField: TFloatSpinEdit;
    Stack, PreviewStack: TListBox;
    Summary, PreviewInfo: TLabel;
    PreviousButton, NextButton, CreateButton: TSuiteButton;
    FUpdating: Boolean;
    Reviewed: array of Boolean;
    procedure RebuildPreview;
    procedure PreviewChanged(Sender: TObject);
    procedure PreviousClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    function GetSingleBottom: Boolean;
    procedure ModelChanged(Sender: TObject);
    procedure CountChanged(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    function GetWidth: Double;
    function GetHeight: Double;
    function GetLayers: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Configure(Project: TLaserPCBProject);
    property BoardWidth: Double read GetWidth;
    property BoardHeight: Double read GetHeight;
    property LayerCount: Integer read GetLayers;
    property SingleBottom: Boolean read GetSingleBottom;
  end;
implementation
constructor TPCBBoardForm.Create(AOwner: TComponent);
var H: TSuiteHeader; L: TLabel; B: TSuiteButton;
  function LabelAt(const Text: string; X,Y,W: Integer): TLabel;
  begin
    Result:=TLabel.Create(Self); Result.Parent:=Self;
    Result.SetBounds(X,Y,W,22); Result.Caption:=Text;
    Result.Font.Color:=clSuiteMuted;
  end;
  function SizeField(const AName: string; X: Integer): TFloatSpinEdit;
  begin
    Result:=TFloatSpinEdit.Create(Self); Result.Parent:=Self; Result.Name:=AName;
    Result.SetBounds(X,272,180,30); Result.MinValue:=0.01;
    Result.MaxValue:=100000; Result.DecimalPlaces:=2; Result.Value:=100;
  end;
  procedure AddButton(const AName,Text: string; X,W: Integer; Handler:TNotifyEvent);
  begin
    B:=TSuiteButton.Create(Self); B.Parent:=Self; B.Name:=AName;
    B.SetBounds(X,590,W,34); B.Caption:=Text;
    B.SetLook(sbsSoft,clSuitePrimary,sikFrame); B.OnClick:=Handler;
  end;
begin
  inherited CreateNew(AOwner);
  Caption:='LaserPCB - Placas'; ClientWidth:=620; ClientHeight:=640;
  BorderStyle:=bsDialog; Position:=poOwnerFormCenter;
  Font.Name:='Segoe UI'; Font.Size:=9; Color:=clSuiteSurface;
  H:=TSuiteHeader.Create(Self); H.Parent:=Self; H.Align:=alTop; H.Height:=60;
  H.Setup('Placas','Dimensões e camadas de cobre',sikLayers);
  Summary:=LabelAt('',20,76,580); Summary.Name:='CurrentLayers';
  Stack:=TListBox.Create(Self); Stack.Parent:=Self; Stack.Name:='CurrentStack';
  Stack.SetBounds(20,104,580,74);
  LabelAt('Modelo da nova placa',20,190,380);
  Model:=TComboBox.Create(Self); Model.Parent:=Self; Model.Name:='BoardModel';
  Model.SetBounds(20,214,380,30); Model.Style:=csDropDownList;
  Model.Items.Add('Face simples — cobre Top (em cima)');
  Model.Items.Add('Face simples — cobre Bottom (embaixo)');
  Model.Items.Add('Face dupla — cobre Top / Bottom');
  Model.Items.Add('Personalizada — N camadas');
  Model.ItemIndex:=0; Model.OnChange:=@ModelChanged;
  LabelAt('Camadas de cobre (N)',420,190,180);
  CountField:=TSpinEdit.Create(Self); CountField.Parent:=Self;
  CountField.Name:='BoardLayers'; CountField.SetBounds(420,214,180,30);
  CountField.MinValue:=1; CountField.MaxValue:=64; CountField.Value:=1;
  CountField.OnChange:=@CountChanged;
  LabelAt('Largura (mm)',20,250,180);
  LabelAt('Altura (mm)',220,250,180);
  WidthField:=SizeField('BoardWidth',20); HeightField:=SizeField('BoardHeight',220);
  LabelAt('Prévia das camadas da nova placa',20,318,580);
  PreviewStack:=TListBox.Create(Self); PreviewStack.Parent:=Self;
  PreviewStack.Name:='PreviewStack'; PreviewStack.SetBounds(20,344,580,96);
  PreviewStack.OnClick:=@PreviewChanged;
  PreviewInfo:=LabelAt('',20,450,580); PreviewInfo.Name:='LayerPreviewInfo';
  PreviewInfo.AutoSize:=False; PreviewInfo.WordWrap:=True; PreviewInfo.Height:=38;
  AddButton('PreviousLayer','Anterior',20,130,@PreviousClick);
  PreviousButton:=B; PreviousButton.Top:=492;
  AddButton('NextLayer','Próxima',160,130,@NextClick);
  NextButton:=B; NextButton.Top:=492;
  L:=LabelAt('Criar placa substitui o trabalho atual. Na opção personalizada, percorra cada camada da prévia. Importe depois a geometria de cada camada.',20,536,580);
  L.AutoSize:=False; L.WordWrap:=True; L.Height:=44;
  AddButton('FitBoards','Ajustar zoom',20,145,@FitClick);
  AddButton('CreateBoard','Criar placa',330,130,@CreateClick);
  CreateButton:=B;
  AddButton('CancelBoard','Cancelar',470,130,@CancelClick);
  ModelChanged(nil);
end;
procedure TPCBBoardForm.Configure(Project: TLaserPCBProject);
var I: Integer;
begin
  Summary.Caption:=Format('%d camadas de cobre | %d operações de gravação',
    [Project.CopperLayerCount,Project.OperationCount]);
  Stack.Items.Clear;
  for I:=1 to Project.CopperLayerCount do Stack.Items.Add(Project.CopperLayerName(I));
  if Project.CopperLayerCount=0 then Stack.Items.Add('Nenhuma camada de cobre configurada.');
  if Project.Width>0 then WidthField.Value:=Project.Width;
  if Project.Height>0 then HeightField.Value:=Project.Height;
end;
procedure TPCBBoardForm.ModelChanged(Sender:TObject);
begin
  if FUpdating then Exit;
  FUpdating:=True;
  try
    if Model.ItemIndex in [0,1] then CountField.Value:=1
    else if Model.ItemIndex=2 then CountField.Value:=2
    else if CountField.Value<3 then CountField.Value:=4;
    CountField.Enabled:=Model.ItemIndex=3;
  finally FUpdating:=False; end;
  RebuildPreview;
end;
procedure TPCBBoardForm.CountChanged(Sender:TObject);
begin
  if FUpdating then Exit;
  RebuildPreview;
end;
procedure TPCBBoardForm.RebuildPreview;
var I,N:Integer; LayerName:string;
begin
  N:=CountField.Value;
  PreviewStack.Items.Clear;
  SetLength(Reviewed,0); SetLength(Reviewed,N);
  for I:=1 to N do
  begin
    if (N=1) and not SingleBottom then LayerName:='Top'
    else if I=N then LayerName:='Bottom (espelhada em X)'
    else if I=1 then LayerName:='Top'
    else LayerName:='Inner '+IntToStr(I-1);
    PreviewStack.Items.Add(Format('%d — %s',[I,LayerName]));
  end;
  PreviewStack.ItemIndex:=0;
  PreviewChanged(nil);
end;
procedure TPCBBoardForm.PreviewChanged(Sender:TObject);
var I,K,Seen:Integer; Detail:string;
begin
  I:=PreviewStack.ItemIndex;
  if (I<0) or (I>=Length(Reviewed)) then Exit;
  Reviewed[I]:=True; Seen:=0;
  for K:=0 to High(Reviewed) do if Reviewed[K] then Inc(Seen);
  if (I=High(Reviewed)) and ((Length(Reviewed)>1) or SingleBottom) then
    Detail:='Bottom: cobre inferior, espelhado em X.'
  else if I=0 then Detail:='Top: cobre superior, sem espelhamento.'
  else Detail:='Camada interna de cobre, sem espelhamento.';
  PreviewInfo.Caption:=Format('Camada %d de %d — %s  Revisadas: %d/%d',
    [I+1,Length(Reviewed),Detail,Seen,Length(Reviewed)]);
  PreviousButton.Enabled:=I>0;
  NextButton.Enabled:=I<High(Reviewed);
  CreateButton.Enabled:=(Model.ItemIndex<>3) or (Seen=Length(Reviewed));
end;
procedure TPCBBoardForm.PreviousClick(Sender:TObject);
begin
  if PreviewStack.ItemIndex>0 then
  begin PreviewStack.ItemIndex:=PreviewStack.ItemIndex-1; PreviewChanged(nil); end;
end;
procedure TPCBBoardForm.NextClick(Sender:TObject);
begin
  if PreviewStack.ItemIndex<PreviewStack.Items.Count-1 then
  begin PreviewStack.ItemIndex:=PreviewStack.ItemIndex+1; PreviewChanged(nil); end;
end;
procedure TPCBBoardForm.CreateClick(Sender:TObject);
begin
  if CreateButton.Enabled then ModalResult:=mrOK;
end;
function TPCBBoardForm.GetSingleBottom:Boolean;
begin Result:=Model.ItemIndex=1; end;
procedure TPCBBoardForm.CancelClick(Sender:TObject);
begin ModalResult:=mrCancel; end;
procedure TPCBBoardForm.FitClick(Sender:TObject);
begin ModalResult:=mrIgnore; end;
function TPCBBoardForm.GetWidth:Double;
begin Result:=WidthField.Value; end;
function TPCBBoardForm.GetHeight:Double;
begin Result:=HeightField.Value; end;
function TPCBBoardForm.GetLayers:Integer;
begin Result:=CountField.Value; end;
end.
