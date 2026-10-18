unit laserpcb_powerform;
{$mode objfpc}{$H+}{$codepage utf8}
{ Janela "Estimar pela potência do laser" da etapa Camadas e laser. }
interface
uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ComCtrls, Dialogs,
  multisuite_controls, multisuite_icons, multisuite_numfmt, laserpcb_powerest;
type
  TLaserPowerForm=class(TForm)
  private
    SourceBox,CopperBox:TComboBox;
    WattsEdit,SpotEdit,BoardEdit,MaxFeedEdit:TEdit;
    Table:TListView;
    Details:TMemo;
    FInput:TLPEstimateInput;
    FValid:Boolean;
    FResults:array[TLPEstimateKind] of TLPEstimate;
    FHighlight:TLPEstimateKind;
    function Edit(const ACaption,Value:string;X,Y,W:Integer):TEdit;
    procedure InputChanged(Sender:TObject);
    procedure Selected(Sender:TObject;Item:TListItem;IsSelected:Boolean);
    procedure ApplyOneClick(Sender:TObject);
    procedure ApplyAllClick(Sender:TObject);
    procedure CloseClick(Sender:TObject);
    procedure Recalculate;
  public
    constructor Create(AOwner:TComponent);override;
    procedure Configure(const AInput:TLPEstimateInput;Highlight:TLPEstimateKind);
    function Estimate(Kind:TLPEstimateKind):TLPEstimate;
    property Input:TLPEstimateInput read FInput;
  end;
const
  { espessuras usuais de cobre: 0,5 / 1 / 2 / 3 oz }
  COPPER_UM:array[0..3] of Double=(18,35,70,105);
implementation

function TLaserPowerForm.Edit(const ACaption,Value:string;X,Y,W:Integer):TEdit;
var L:TLabel;
begin
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(X,Y,W,18);L.Caption:=ACaption;L.Font.Color:=clSuiteMuted;
  Result:=TEdit.Create(Self);Result.Parent:=Self;Result.SetBounds(X,Y+20,W,28);
  Result.Text:=Value;Result.OnChange:=@InputChanged;
end;

constructor TLaserPowerForm.Create(AOwner:TComponent);
var H:TSuiteHeader;L:TLabel;S:TLPLaserSource;I:Integer;
  procedure Button(const AName,ACaption:string;X,W:Integer;Icon:TSuiteIconKind;Handler:TNotifyEvent);
  var B:TSuiteButton;
  begin
    B:=TSuiteButton.Create(Self);B.Parent:=Self;B.Name:=AName;
    B.SetBounds(X,560,W,34);B.Caption:=ACaption;
    B.SetLook(sbsSoft,clSuitePrimary,Icon);B.OnClick:=Handler;
  end;
begin
  inherited CreateNew(AOwner);
  Caption:='LaserPCB - Estimar pela potência do laser';ClientWidth:=870;ClientHeight:=610;
  BorderStyle:=bsDialog;Position:=poOwnerFormCenter;Font.Name:='Segoe UI';Font.Size:=9;
  Color:=clSuiteSurface;
  H:=TSuiteHeader.Create(Self);H.Parent:=Self;H.Align:=alTop;H.Height:=60;
  H.Setup('Estimativa de potência','Ponto de partida pelos W do laser, feixe e espessuras - confirme com teste de material',sikFlame);
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(20,74,280,18);L.Caption:='Tipo de laser';L.Font.Color:=clSuiteMuted;
  SourceBox:=TComboBox.Create(Self);SourceBox.Parent:=Self;SourceBox.Name:='LaserSource';
  SourceBox.SetBounds(20,94,280,28);SourceBox.Style:=csDropDownList;
  for S:=Low(TLPLaserSource) to High(TLPLaserSource) do SourceBox.Items.Add(LaserSourceName(S));
  SourceBox.ItemIndex:=0;SourceBox.OnChange:=@InputChanged;
  WattsEdit:=Edit('Potência óptica (W)','0',316,74,120);
  SpotEdit:=Edit('Feixe (mm)','0.1',452,74,120);
  MaxFeedEdit:=Edit('Velocidade máx. (mm/min)','6000',588,74,150);
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(20,132,280,18);L.Caption:='Espessura do cobre';L.Font.Color:=clSuiteMuted;
  CopperBox:=TComboBox.Create(Self);CopperBox.Parent:=Self;CopperBox.Name:='CopperThickness';
  CopperBox.SetBounds(20,152,280,28);CopperBox.Style:=csDropDownList;
  CopperBox.Items.Add('18 um (0,5 oz)');CopperBox.Items.Add('35 um (1 oz)');
  CopperBox.Items.Add('70 um (2 oz)');CopperBox.Items.Add('105 um (3 oz)');
  CopperBox.ItemIndex:=1;CopperBox.OnChange:=@InputChanged;
  BoardEdit:=Edit('Espessura da PCB (mm)','1.6',316,132,120);
  Table:=TListView.Create(Self);Table.Parent:=Self;Table.Name:='PowerEstimates';
  Table.SetBounds(20,196,830,170);Table.ViewStyle:=vsReport;Table.ReadOnly:=True;
  Table.RowSelect:=True;Table.HideSelection:=False;
  for I:=0 to 6 do Table.Columns.Add;
  Table.Columns[0].Caption:='Processo';Table.Columns[0].Width:=240;
  Table.Columns[1].Caption:='Potência';Table.Columns[1].Width:=110;
  Table.Columns[2].Caption:='mm/min';Table.Columns[2].Width:=80;
  Table.Columns[3].Caption:='Passadas';Table.Columns[3].Width:=75;
  Table.Columns[4].Caption:='J/mm total';Table.Columns[4].Width:=85;
  Table.Columns[5].Caption:='Sulco x prof. (mm)';Table.Columns[5].Width:=130;
  Table.Columns[6].Caption:='Situação';Table.Columns[6].Width:=100;
  Table.OnSelectItem:=@Selected;
  Details:=TMemo.Create(Self);Details.Parent:=Self;Details.Name:='PowerEstimateDetails';
  Details.SetBounds(20,380,830,166);Details.ReadOnly:=True;Details.ScrollBars:=ssAutoVertical;
  Button('ApplyEstimate','Aplicar na camada selecionada',20,270,sikTarget,@ApplyOneClick);
  Button('ApplyEstimateAll','Aplicar em todas as camadas',304,270,sikLayers,@ApplyAllClick);
  Button('CloseEstimate','Fechar',670,180,sikArrowLeft,@CloseClick);
end;

procedure TLaserPowerForm.Configure(const AInput:TLPEstimateInput;Highlight:TLPEstimateKind);
var I:Integer;
begin
  FInput:=AInput;FHighlight:=Highlight;
  SourceBox.ItemIndex:=Ord(AInput.Source);
  WattsEdit.Text:=FloatToStr(AInput.OpticalW,InvariantFS);
  SpotEdit.Text:=FloatToStr(AInput.SpotMM,InvariantFS);
  if AInput.BoardMM>0 then BoardEdit.Text:=FloatToStr(AInput.BoardMM,InvariantFS);
  if AInput.MaxFeed>0 then MaxFeedEdit.Text:=FloatToStr(AInput.MaxFeed,InvariantFS);
  for I:=0 to High(COPPER_UM) do if Abs(COPPER_UM[I]-AInput.CopperUM)<0.5 then CopperBox.ItemIndex:=I;
  Recalculate;
end;

procedure TLaserPowerForm.InputChanged(Sender:TObject);
begin Recalculate;end;

procedure TLaserPowerForm.Recalculate;
var K:TLPEstimateKind;E:TLPEstimate;Item:TListItem;V:Double;Keep:Integer;
begin
  FValid:=False;
  FInput.Source:=TLPLaserSource(Max(0,SourceBox.ItemIndex));
  if CopperBox.ItemIndex>=0 then FInput.CopperUM:=COPPER_UM[CopperBox.ItemIndex];
  if TryParseFloat(WattsEdit.Text,V) and (V>0) and (V<=1000) then FInput.OpticalW:=V else FInput.OpticalW:=0;
  if TryParseFloat(SpotEdit.Text,V) and (V>0) and (V<=5) then FInput.SpotMM:=V else FInput.SpotMM:=0;
  if TryParseFloat(BoardEdit.Text,V) and (V>0) and (V<=10) then FInput.BoardMM:=V else FInput.BoardMM:=0;
  if TryParseFloat(MaxFeedEdit.Text,V) and (V>=60) then FInput.MaxFeed:=V else FInput.MaxFeed:=0;
  if Table.Selected<>nil then Keep:=Table.Selected.Index else Keep:=Ord(FHighlight);
  Table.Items.BeginUpdate;
  try
    Table.Items.Clear;
    for K:=Low(TLPEstimateKind) to High(TLPEstimateKind) do
    begin
      E:=LPEstimate(FInput,K);FResults[K]:=E;
      Item:=Table.Items.Add;Item.Caption:=EstimateKindName(K);
      if E.Feed>0 then
      begin
        Item.SubItems.Add(Format('%.0f%% = %.2f W',[E.Percent,E.Watts],InvariantFS));
        Item.SubItems.Add(Format('%.0f',[E.Feed],InvariantFS));
        Item.SubItems.Add(IntToStr(E.Passes));
        Item.SubItems.Add(Format('%.2f',[E.EnergyPerMM],InvariantFS));
        Item.SubItems.Add(Format('%.3f x %.3f',[E.KerfMM,E.DepthMM],InvariantFS));
        if not E.Feasible then Item.SubItems.Add('Impraticável')
        else if E.Calibrated then Item.SubItems.Add('Aferido')
        else Item.SubItems.Add('Estimado');
      end
      else
      begin
        Item.SubItems.Add('-');Item.SubItems.Add('-');Item.SubItems.Add('-');
        Item.SubItems.Add('-');Item.SubItems.Add('-');Item.SubItems.Add('Indisponível');
      end;
      if E.Feed>0 then FValid:=True;
    end;
  finally Table.Items.EndUpdate;end;
  if (Keep>=0) and (Keep<Table.Items.Count) then
  begin Table.Items[Keep].Selected:=True;Selected(nil,Table.Items[Keep],True);end;
end;

procedure TLaserPowerForm.Selected(Sender:TObject;Item:TListItem;IsSelected:Boolean);
var E:TLPEstimate;S:string;
begin
  if not IsSelected or (Item=nil) then Exit;
  E:=FResults[TLPEstimateKind(Item.Index)];
  S:=EstimateKindName(E.Kind)+#13#10;
  if E.Feed>0 then
  begin
    S:=S+Format('Energia necessária: %.3f J/mm (Ev x sulco x profundidade). Por passada: %.3f J/mm.',
      [E.EnergyPerMM,E.EnergyPerPass],InvariantFS)+#13#10;
    S:=S+Format('Faça uma matriz de teste em volta do ponto: velocidade %.0f a %.0f mm/min, potência %.0f%% a %.0f%%.',
      [E.Feed*0.7,E.Feed*1.3,Max(5,E.Percent-15),Min(100,E.Percent+15)],InvariantFS)+#13#10;
  end;
  if E.Note<>'' then S:=S+E.Note+#13#10;
  S:=S+'Estimativa pela potência nominal; não substitui a calibração. A potência real do driver, o foco, '+
    'o revestimento e o substrato mudam o resultado. Em M4, a saída cai nas acelerações.';
  Details.Text:=S;
end;

function TLaserPowerForm.Estimate(Kind:TLPEstimateKind):TLPEstimate;
begin Result:=FResults[Kind];end;

procedure TLaserPowerForm.ApplyOneClick(Sender:TObject);
begin
  if not FValid then begin ShowMessage('Informe a potência óptica e o feixe.');Exit;end;
  ModalResult:=mrOK;
end;

procedure TLaserPowerForm.ApplyAllClick(Sender:TObject);
begin
  if not FValid then begin ShowMessage('Informe a potência óptica e o feixe.');Exit;end;
  ModalResult:=mrAll;
end;

procedure TLaserPowerForm.CloseClick(Sender:TObject);
begin ModalResult:=mrCancel;end;

end.
