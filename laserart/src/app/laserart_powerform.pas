unit laserart_powerform;
{$mode objfpc}{$H+}{$codepage utf8}
{ Janela "Estimar potência pelo laser" da aba Cortes / Camadas. }
interface
uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, Dialogs,
  multisuite_controls, multisuite_icons, multisuite_numfmt, laserart_powerest;
type
  TLaserArtPowerForm=class(TForm)
  private
    SourceBox,MaterialBox,GoalBox:TComboBox;
    WattsEdit,SpotEdit,MaxFeedEdit,ThickEdit,IntervalEdit:TEdit;
    Details:TMemo;
    FInput:TLAEstimateInput;
    FResult:TLAEstimate;
    function Edit(const ACaption,Value:string;X,Y,W:Integer):TEdit;
    function Combo(const ACaption:string;X,Y,W:Integer):TComboBox;
    procedure InputChanged(Sender:TObject);
    procedure ApplyClick(Sender:TObject);
    procedure CloseClick(Sender:TObject);
    procedure Recalculate;
  public
    constructor Create(AOwner:TComponent);override;
    procedure Configure(const AInput:TLAEstimateInput;const LayerName:string);
    property Input:TLAEstimateInput read FInput;
    property Estimate:TLAEstimate read FResult;
  end;
implementation

function TLaserArtPowerForm.Edit(const ACaption,Value:string;X,Y,W:Integer):TEdit;
var L:TLabel;
begin
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(X,Y,W,18);L.Caption:=ACaption;L.Font.Color:=clSuiteMuted;
  Result:=TEdit.Create(Self);Result.Parent:=Self;Result.SetBounds(X,Y+20,W,28);
  Result.Text:=Value;Result.OnChange:=@InputChanged;
end;

function TLaserArtPowerForm.Combo(const ACaption:string;X,Y,W:Integer):TComboBox;
var L:TLabel;
begin
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(X,Y,W,18);L.Caption:=ACaption;L.Font.Color:=clSuiteMuted;
  Result:=TComboBox.Create(Self);Result.Parent:=Self;Result.SetBounds(X,Y+20,W,28);
  Result.Style:=csDropDownList;Result.OnChange:=@InputChanged;
end;

constructor TLaserArtPowerForm.Create(AOwner:TComponent);
var H:TSuiteHeader;S:TLALaserSource;G:TLAGoal;I:Integer;B:TSuiteButton;
begin
  inherited CreateNew(AOwner);
  Caption:='LaserArt - Estimar potência pelo laser';ClientWidth:=640;ClientHeight:=480;
  BorderStyle:=bsDialog;Position:=poOwnerFormCenter;Font.Name:='Segoe UI';Font.Size:=9;
  Color:=clSuiteSurface;
  H:=TSuiteHeader.Create(Self);H.Parent:=Self;H.Align:=alTop;H.Height:=60;
  H.Setup('Estimativa de potência','Pelos W do laser, feixe, material e espessura - confirme no Teste de material',sikGauge);
  SourceBox:=Combo('Tipo de laser',20,72,300);
  for S:=Low(TLALaserSource) to High(TLALaserSource) do SourceBox.Items.Add(LALaserSourceName(S));
  WattsEdit:=Edit('Potência óptica (W)','0',336,72,130);
  SpotEdit:=Edit('Feixe (mm)','0.1',480,72,140);
  MaterialBox:=Combo('Material',20,128,300);
  for I:=0 to High(LA_MATERIALS) do MaterialBox.Items.Add(LA_MATERIALS[I].Name);
  ThickEdit:=Edit('Espessura (mm)','3',336,128,130);
  MaxFeedEdit:=Edit('Velocidade máx. (mm/min)','6000',480,128,140);
  GoalBox:=Combo('Objetivo da camada',20,184,300);
  for G:=Low(TLAGoal) to High(TLAGoal) do GoalBox.Items.Add(LAGoalName(G));
  IntervalEdit:=Edit('Intervalo (mm, gravação)','0.1',336,184,130);
  Details:=TMemo.Create(Self);Details.Parent:=Self;Details.SetBounds(20,244,600,170);
  Details.ReadOnly:=True;Details.ScrollBars:=ssAutoVertical;
  B:=TSuiteButton.Create(Self);B.Parent:=Self;B.SetBounds(20,428,300,34);
  B.Caption:='Aplicar na camada selecionada';B.SetLook(sbsSolid,clSuitePrimary,sikArrowLeft);B.OnClick:=@ApplyClick;
  B:=TSuiteButton.Create(Self);B.Parent:=Self;B.SetBounds(500,428,120,34);
  B.Caption:='Fechar';B.SetLook(sbsOutline,clSuitePrimary,sikClose);B.OnClick:=@CloseClick;
end;

procedure TLaserArtPowerForm.Configure(const AInput:TLAEstimateInput;const LayerName:string);
begin
  FInput:=AInput;
  SourceBox.ItemIndex:=Ord(AInput.Source);
  WattsEdit.Text:=FloatToStr(AInput.OpticalW,InvariantFS);
  SpotEdit.Text:=FloatToStr(AInput.SpotMM,InvariantFS);
  MaxFeedEdit.Text:=FloatToStr(AInput.MaxFeed,InvariantFS);
  MaterialBox.ItemIndex:=EnsureRange(AInput.Material,0,High(LA_MATERIALS));
  ThickEdit.Text:=FloatToStr(AInput.ThicknessMM,InvariantFS);
  IntervalEdit.Text:=FloatToStr(AInput.IntervalMM,InvariantFS);
  GoalBox.ItemIndex:=Ord(AInput.Goal);
  Caption:='LaserArt - Estimar potência - camada '+LayerName;
  Recalculate;
end;

procedure TLaserArtPowerForm.InputChanged(Sender:TObject);
begin Recalculate;end;

procedure TLaserArtPowerForm.Recalculate;
var V:Double;E:TLAEstimate;S:string;
begin
  FInput.Source:=TLALaserSource(Max(0,SourceBox.ItemIndex));
  FInput.Material:=Max(0,MaterialBox.ItemIndex);
  FInput.Goal:=TLAGoal(Max(0,GoalBox.ItemIndex));
  if TryParseFloat(WattsEdit.Text,V) and (V>0) then FInput.OpticalW:=V else FInput.OpticalW:=0;
  if TryParseFloat(SpotEdit.Text,V) and (V>0) then FInput.SpotMM:=V else FInput.SpotMM:=0;
  if TryParseFloat(MaxFeedEdit.Text,V) and (V>=60) then FInput.MaxFeed:=V else FInput.MaxFeed:=0;
  if TryParseFloat(ThickEdit.Text,V) and (V>0) then FInput.ThicknessMM:=V else FInput.ThicknessMM:=0;
  if TryParseFloat(IntervalEdit.Text,V) and (V>0) then FInput.IntervalMM:=V else FInput.IntervalMM:=0;
  ThickEdit.Enabled:=FInput.Goal=lgCut;
  IntervalEdit.Enabled:=FInput.Goal in [lgEngraveLight,lgEngraveMedium,lgEngraveDeep];
  E:=LAEstimate(FInput);FResult:=E;
  if E.Feed>0 then
  begin
    S:=Format('Potência %.0f%% (%.2f W)  |  velocidade %.0f mm/min  |  %d passada(s)',
      [E.Percent,E.Watts,E.Feed,E.Passes],InvariantFS)+#13#10+
      Format('Energia necessária %.3f J/mm (largura %.3f x profundidade %.3f mm); por passada %.3f J/mm.',
      [E.EnergyPerMM,E.KerfMM,E.DepthMM,E.EnergyPerPass],InvariantFS)+#13#10;
    if not E.Feasible then S:=S+'IMPRATICÁVEL com este laser.'+#13#10;
    S:=S+Format('Teste em volta do ponto: %.0f a %.0f mm/min, %.0f%% a %.0f%%.',
      [E.Feed*0.7,E.Feed*1.3,Max(5,E.Percent-15),Min(100,E.Percent+15)],InvariantFS)+#13#10;
  end else S:='Sem estimativa.'+#13#10;
  if E.Note<>'' then S:=S+E.Note+#13#10;
  S:=S+'Estimativa pela potência nominal: confirme com o Teste de material antes do trabalho.';
  Details.Text:=S;
end;

procedure TLaserArtPowerForm.ApplyClick(Sender:TObject);
begin
  if not (FResult.Feed>0) or not FResult.Feasible then
  begin ShowMessage('Não há estimativa viável para aplicar.');Exit;end;
  ModalResult:=mrOK;
end;

procedure TLaserArtPowerForm.CloseClick(Sender:TObject);
begin ModalResult:=mrCancel;end;

end.
