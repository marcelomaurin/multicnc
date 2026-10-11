unit laserpcb_main;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, laserpcb_project, laserpcb_preview, laserpcb_layout,
  laserpcb_types, laserpcb_layertable, laserpcb_roles, laserart_widgets, multisuite_controls, multisuite_icons;
type
  TLaserPCBForm = class(TForm)
  private
    P: TLaserPCBProject;
    View: TLaserPCBPreview;
    LayerList: TListBox;
    Pages: TPageControl;
    Nav: array[0..4] of TSuiteButton;
    State: TSuiteBadge;
    Info, Summary, Status: TLabel;
    Log: TMemo;
    ModeBox, SideBox, RoleBox, MarkKindBox, SourceBox, ProcessBox: TComboBox;
    Layers: TLPLayerTable;
    Palette: TLAPalette;
    LayerName: TEdit;
    LayerTitle, Estimate: TLabel;
    Mirror, Copper, Holes, Paths, Locked: TCheckBox;
    Power, Feed, Spot, Passes, SMax, Res, Overlap: TEdit;
    OpticalPower, PowerPercent, TargetWatts: TEdit;
    LaserPowerInfo, LayerPowerInfo: TLabel;
    BedW, BedH, Margin, Spacing, PosX, PosY, Rotation, ScaleX, ScaleY: TEdit;
    DrillMin, DrillMax, MarkDia: TEdit;
    DrillPTH, DrillNPTH: TCheckBox;
    ExportButton, SendButton, ValidateButton: TSuiteButton;
    FooterPanel: TPanel;
    FUpdating: Boolean;
    FExportedFile: string;
    FEditOp: TLPOperation;   { camada mostrada no editor }
    procedure LaserPowerChanged(Sender: TObject);
    procedure UpdateLaserPower;
    procedure AddHoleLayerClick(Sender: TObject);
    procedure LaserReferencesClick(Sender: TObject);
    function Button(ParentControl: TWinControl; const AText: string; X,Y,W: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function LabelAt(ParentControl: TWinControl; const AText: string; X,Y,W,H: Integer): TLabel;
    function Field(ParentControl: TWinControl; const AText, Value: string; Y: Integer): TEdit;
    function Check(ParentControl: TWinControl; const AText: string; X,Y: Integer; Value: Boolean): TCheckBox;
    function Number(Edit: TEdit; const What: string): Double;
    procedure ReadSettings;
    procedure RefreshSources;
    procedure RefreshSelection(Sender: TObject);
    procedure SettingsChanged(Sender: TObject);
    procedure PlacementChanged(Sender: TObject);
    procedure ViewsChanged(Sender: TObject);
    procedure NavClick(Sender: TObject);
    procedure FocusPage(N: Integer);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure LayerClick(Sender: TObject);
    procedure RoleChanged(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure NestClick(Sender: TObject);
    procedure RotateClick(Sender: TObject);
    procedure KeepOutClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure CopperSideChanged(Sender: TObject);
    procedure RefreshCopperSides;
    procedure BedClick(Sender: TObject);
    procedure ComponentsClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure GenerateClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure SaveProfileClick(Sender: TObject);
    procedure LoadProfileClick(Sender: TObject);
    procedure AlignClick(Sender: TObject);
    procedure DrillChanged(Sender: TObject);
    procedure LayerSelected(Sender: TObject; Index: Integer);
    procedure LayerToggled(Sender: TObject; Index: Integer);
    procedure PalettePicked(Sender: TObject; Index: Integer);
    procedure AddLayerClick(Sender: TObject);
    procedure DeleteLayerClick(Sender: TObject);
    procedure LayerUpClick(Sender: TObject);
    procedure LayerDownClick(Sender: TObject);
    procedure LoadLayerEditor;
    procedure CommitLayerEditor;
    procedure RefreshLayerSources;
    function SelectedOperation: TLPOperation;
    function DrillField(ParentControl: TWinControl; const AText, Value: string; Y: Integer): TEdit;
    procedure ShowError(E: Exception);
    procedure ResizeUI(Sender: TObject);
    procedure ShowUI(Sender: TObject);
    procedure Prepared;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FN: string);
    property Project: TLaserPCBProject read P;
    property Preview: TLaserPCBPreview read View;
  end;
implementation
uses laserpcb_job, laserpcb_gcode, laserpcb_profile, laserpcb_nesting,
  laserpcb_geom, laserpcb_alignment, laserpcb_drill, multisuite_numfmt, multisuite_registry,
  multisuite_launcher, multisuite_types, multisuite_context, laserart_bedform, laserpcb_boardform, laserpcb_referenceform, laserpcb_componentsform;

function TLaserPCBForm.Button(ParentControl: TWinControl; const AText: string;
  X,Y,W: Integer; AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self); Result.Parent := ParentControl;
  Result.SetBounds(X,Y,W,34); Result.Caption := AText;
  Result.SetLook(sbsSoft,clSuitePrimary,AIcon); Result.OnClick := Handler;
end;
function TLaserPCBForm.LabelAt(ParentControl: TWinControl; const AText: string;
  X,Y,W,H: Integer): TLabel;
begin
  Result := TLabel.Create(Self); Result.Parent := ParentControl;
  Result.AutoSize := False; Result.SetBounds(X,Y,W,H); Result.WordWrap := True;
  Result.Caption := AText; Result.Font.Color := clSuiteMuted;
end;
function TLaserPCBForm.Field(ParentControl: TWinControl; const AText, Value: string; Y: Integer): TEdit;
begin
  LabelAt(ParentControl,AText,16,Y,290,18);
  Result := TEdit.Create(Self); Result.Parent := ParentControl;
  Result.SetBounds(16,Y+20,290,28); Result.Text := Value; Result.OnChange := @SettingsChanged;
end;
function TLaserPCBForm.Check(ParentControl: TWinControl; const AText: string;
  X,Y: Integer; Value: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(Self); Result.Parent := ParentControl;
  Result.SetBounds(X,Y,260,24); Result.Caption := AText; Result.Checked := Value;
end;
constructor TLaserPCBForm.Create(AOwner: TComponent);
var Header: TSuiteHeader; Sidebar, Work, Bar, Footer: TPanel; Right: TPageControl;
  Page: TTabSheet; Scroll: TScrollBox; I: Integer; B: TSuiteButton; Role: TLPLayerRole;
const Names: array[0..4] of string = ('1  Importar','2  Posicionar','3  Camadas','4  Saida','5  Furos laser');
  Icons: array[0..4] of TSuiteIconKind = (sikLayers,sikMove,sikGear,sikTests,sikFlame);
begin
  inherited CreateNew(AOwner,1);
  Caption := 'LaserPCB - MultiSuite'; Width := 1240; Height := 850;
  Constraints.MinWidth := 1040; Constraints.MinHeight := 680; Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10; Color := clSuiteSurface;
  P := TLaserPCBProject.Create; FUpdating := True;
  Header := TSuiteHeader.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('LaserPCB','Preparacao de placas  /  MultiSuite',sikLaserPCB);
  Footer := TPanel.Create(Self); Footer.Parent := Self; Footer.Align := alBottom;
  Footer.Height := 66; Footer.BevelOuter := bvNone; Footer.Color := clSuiteCard;
  FooterPanel := Footer;
  Status := LabelAt(Footer,'Importe SVG ou um conjunto Gerber + Excellon.',18,12,380,44);
  B := Button(Footer,'Validar',Width-550,15,130,sikTests,@ValidateClick);
  ValidateButton := B;
  B.Anchors := [akTop,akRight];
  ExportButton := Button(Footer,'Gerar G-code',Width-410,15,160,sikExport,@ExportClick);
  ExportButton.Anchors := [akTop,akRight]; ExportButton.SetLook(sbsSolid,clSuitePrimary,sikExport);
  SendButton := Button(Footer,'Abrir no MultiCNC',Width-240,15,222,sikSend,@SendClick);
  SendButton.Anchors := [akTop,akRight]; SendButton.Enabled := False;
  Sidebar := TPanel.Create(Self); Sidebar.Parent := Self; Sidebar.Align := alLeft;
  Sidebar.Width := 214; Sidebar.BevelOuter := bvNone; Sidebar.Color := clSuiteCard;
  for I := 0 to 4 do
  begin
    Nav[I] := Button(Sidebar,Names[I],12,16+I*44,190,Icons[I],@NavClick); Nav[I].Tag := I;
  end;
  Button(Sidebar,'Importar arquivos',12,252,190,sikImport,@OpenClick);
  Button(Sidebar,'Novo trabalho',12,294,190,sikNew,@NewClick);
  LabelAt(Sidebar,'CAMADAS E FUROS',16,348,180,20);
  LayerList := TListBox.Create(Self); LayerList.Parent := Sidebar;
  LayerList.SetBounds(12,374,190,Height-584); LayerList.Anchors := [akLeft,akTop,akRight,akBottom];
  LayerList.OnClick := @LayerClick;
  Info := LabelAt(Sidebar,'Nenhuma placa importada',16,Sidebar.Height-132,184,88);
  Info.Align := alBottom; Info.BorderSpacing.Around := 12;
  Right := TPageControl.Create(Self); Right.Parent := Self; Right.Align := alRight;
  Right.Width := 336; Right.ShowTabs := False; Pages := Right;
  for I := 0 to 4 do
  begin
    Page := TTabSheet.Create(Self); Page.PageControl := Pages; Page.Caption := Names[I];
    Scroll := TScrollBox.Create(Self); Scroll.Parent := Page; Scroll.Align := alClient;
    Scroll.BorderStyle := bsNone; Scroll.Color := clSuiteCard;
    Scroll.HorzScrollBar.Visible := False;
    LabelAt(Scroll,Names[I],16,16,260,30).Font.Style := [fsBold];
    case I of
      0:
      begin
        LabelAt(Scroll,'SVG: vetores em mm.'+#10+'Gerber: cobre, contorno, mascara e serigrafia.'+#10+
          'Excellon: furos e rasgos como referencia.',16,58,260,110);
        LabelAt(Scroll,'Funcao da camada selecionada',16,180,260,20);
        RoleBox := TComboBox.Create(Self); RoleBox.Parent := Scroll;
        RoleBox.SetBounds(16,206,290,30); RoleBox.Style := csDropDownList;
        for Role := Low(TLPLayerRole) to High(TLPLayerRole) do RoleBox.Items.Add(LayerRoleName(Role));
        RoleBox.ItemIndex := 0; RoleBox.OnChange := @RoleChanged;
        LabelAt(Scroll,'Confira a funcao dos Gerbers sem atributo X2. O CAM precisa de um contorno fechado.',
          16,256,260,84);
        Button(Scroll,'Abrir arquivos...',16,354,290,sikFolder,@OpenClick);
      end;
      1:
      begin
        BedW := Field(Scroll,'Mesa: largura (mm)','400',58);
        BedH := Field(Scroll,'Mesa: altura (mm)','400',114);
        Margin := Field(Scroll,'Margem da mesa (mm)','5',170);
        Spacing := Field(Scroll,'Espaco entre placas (mm)','2',226);
        Button(Scroll,'Duplicar',16,288,124,sikCopy,@CopyClick);
        Button(Scroll,'Excluir',152,288,124,sikTrash,@RemoveClick);
        Button(Scroll,'Distribuir placas',16,330,290,sikMove,@NestClick);
        PosX := Field(Scroll,'Placa selecionada: X (mm)','5',386);
        PosY := Field(Scroll,'Placa selecionada: Y (mm)','5',442);
        Rotation := Field(Scroll,'Rotacao (graus)','0',498);
        ScaleX := Field(Scroll,'Escala X','1',554);
        ScaleY := Field(Scroll,'Escala Y','1',610);
        Locked := Check(Scroll,'Travar placa',16,670,False); Locked.OnChange := @SettingsChanged;
        Button(Scroll,'Aplicar posicao',16,710,290,sikTarget,@ApplyClick);
        Button(Scroll,'Girar 90 graus',16,752,290,sikMove,@RotateClick);
        Button(Scroll,'Adicionar zona proibida',16,794,290,sikRect,@KeepOutClick);
        Button(Scroll,'Alinhar 2 fiduciais',16,836,290,sikTarget,@AlignClick);
        LabelAt(Scroll,'Camera nao configurada. Informe as coordenadas medidas dos fiduciais.',
          16,886,260,70);
      end;
      2:
      begin
        { "Cortes / Camadas": cada camada e um processo do mesmo trabalho }
        Layers := TLPLayerTable.Create(Self); Layers.Parent := Scroll;
        Layers.SetBounds(12,52,296,200); Layers.Project := P;
        Layers.OnSelectLayer := @LayerSelected; Layers.OnToggle := @LayerToggled;
        Button(Scroll,'Nova camada',12,260,145,sikNew,@AddLayerClick);
        Button(Scroll,'Excluir camada',163,260,145,sikTrash,@DeleteLayerClick);
        Button(Scroll,'Subir',12,300,145,sikArrowUp,@LayerUpClick);
        Button(Scroll,'Descer',163,300,145,sikArrowDown,@LayerDownClick);
        LayerTitle := LabelAt(Scroll,'CAMADA SELECIONADA',16,348,260,18); LayerTitle.Font.Style := [fsBold];
        LayerName := Field(Scroll,'Nome da camada','',372);
        LabelAt(Scroll,'Processo',16,428,260,20);
        ModeBox := TComboBox.Create(Self); ModeBox.Parent := Scroll; ModeBox.SetBounds(16,448,290,30);
        ModeBox.Style := csDropDownList;
        ModeBox.Items.Add('Vetores SVG'); ModeBox.Items.Add('Isolacao do cobre');
        ModeBox.Items.Add('Retirada de material a laser'); ModeBox.Items.Add('Preencher camada');
        ModeBox.Items.Add('Marcar furos (laser)'); ModeBox.Items.Add('Contorno da placa (linha)');
        ModeBox.ItemIndex := Ord(P.Mode); ModeBox.OnChange := @SettingsChanged;
        LabelAt(Scroll,'Tratamento desta camada',16,486,260,20);
        ProcessBox:=TComboBox.Create(Self); ProcessBox.Parent:=Scroll; ProcessBox.Name:='LaserProcess';
        ProcessBox.SetBounds(16,506,290,30); ProcessBox.Style:=csDropDownList;
        ProcessBox.Items.Add('Remover tinta / verniz sobre o cobre');
        ProcessBox.Items.Add('Remover cobre diretamente');
        ProcessBox.Items.Add('Marcacao a laser');
        ProcessBox.ItemIndex:=0; ProcessBox.OnChange:=@SettingsChanged;
        LabelAt(Scroll,'Camada a preencher',16,542,260,20);
        SourceBox := TComboBox.Create(Self); SourceBox.Parent := Scroll; SourceBox.SetBounds(16,562,290,30);
        SourceBox.Style := csDropDownList; SourceBox.OnChange := @SettingsChanged;
        Power := Field(Scroll,'Potencia calibrada (S)','0',602);
        Power.ReadOnly:=True;
        LabelAt(Scroll,'Potencia laser (%)',16,658,140,18);
        PowerPercent:=TEdit.Create(Self); PowerPercent.Parent:=Scroll;
        PowerPercent.Name:='LaserPowerPercent'; PowerPercent.SetBounds(16,678,135,28);
        PowerPercent.Text:='0'; PowerPercent.OnChange:=@LaserPowerChanged;
        LabelAt(Scroll,'Potencia nominal (W)',166,658,140,18);
        TargetWatts:=TEdit.Create(Self); TargetWatts.Parent:=Scroll;
        TargetWatts.Name:='LaserTargetWatts'; TargetWatts.SetBounds(166,678,140,28);
        TargetWatts.Text:='0'; TargetWatts.OnChange:=@LaserPowerChanged;
        Feed := Field(Scroll,'Velocidade calibrada (mm/min)','0',714);
        Passes := Field(Scroll,'Passadas / aneis na isolacao','1',770);
        Overlap := Field(Scroll,'Sobreposicao (%)','20',826);
        LabelAt(Scroll,'Marcacao de furos',16,884,260,18);
        MarkKindBox := TComboBox.Create(Self); MarkKindBox.Parent := Scroll;
        MarkKindBox.SetBounds(16,904,290,30); MarkKindBox.Style := csDropDownList;
        MarkKindBox.Items.Add('Marcar centro a laser'); MarkKindBox.Items.Add('Contorno do furo');
        MarkKindBox.Items.Add('Cortar o furo (aneis)');
        MarkKindBox.ItemIndex := Ord(P.MarkKind); MarkKindBox.OnChange := @SettingsChanged;
        MarkDia := Field(Scroll,'Diametro da marca de centro (mm)','0.4',944);
        LabelAt(Scroll,'MAQUINA',16,1010,260,18).Font.Style := [fsBold];
        Spot := Field(Scroll,'Diametro calibrado do feixe (mm)','0.1',1034);
        SMax := Field(Scroll,'S-max da maquina ($30)','1000',1090);
        OpticalPower:=Field(Scroll,'Potencia optica nominal (W)','0',1146);
        OpticalPower.Name:='LaserOpticalPower'; OpticalPower.OnChange:=@LaserPowerChanged;
        SMax.OnChange:=@LaserPowerChanged;
        Res := Field(Scroll,'Resolucao raster (mm/pixel)','0.05',1202);
        Mirror := Check(Scroll,'Espelhar Bottom',16,1262,True); Mirror.OnChange := @SettingsChanged;
        LabelAt(Scroll,'Calibre cada processo no material. Potencia em W e nominal; nao confirma remocao de cobre ou corte do substrato.',
          16,1292,260,54);
        Button(Scroll,'Atualizar trajetorias',16,1354,290,sikFlame,@GenerateClick);
        Button(Scroll,'Salvar perfil',16,1400,140,sikSave,@SaveProfileClick);
        Button(Scroll,'Carregar',166,1400,140,sikFolder,@LoadProfileClick);
        Button(Scroll,'Tabela de referencias (web)',16,1446,290,sikTests,@LaserReferencesClick);
        LayerPowerInfo:=LabelAt(Scroll,'',16,1494,280,120);
        LayerPowerInfo.Name:='LayerPowerInfo';
      end;
      3:
      begin
        State := TSuiteBadge.Create(Self); State.Parent := Scroll; State.SetBounds(16,60,260,32);
        State.Caption := 'Aguardando validacao'; State.DotColor := clSuiteWarning;
        LabelAt(Scroll,'CAMADAS COM SAIDA',16,104,260,18).Font.Style := [fsBold];
        Summary := LabelAt(Scroll,'Atualize as trajetorias para ver o resumo.',16,126,260,130);
        Estimate := LabelAt(Scroll,'',16,262,260,40); Estimate.Font.Style := [fsBold];
        Log := TMemo.Create(Self); Log.Parent := Scroll; Log.SetBounds(16,308,260,190);
        Log.ReadOnly := True; Log.ScrollBars := ssAutoVertical;
        LabelAt(Scroll,'A conexao, o enquadramento e a execucao ficam no MultiCNC. G-code em coordenadas absolutas da mesa.',
          16,510,260,60);
        Button(Scroll,'Validar agora',16,580,290,sikTests,@ValidateClick);
        Button(Scroll,'Salvar G-code...',16,622,290,sikSave,@ExportClick);
      end;
      4:
      begin
        LabelAt(Scroll,'FUROS COM CNC LASER',16,58,280,20).Font.Style:=[fsBold];
        LabelAt(Scroll,'Use o Excellon para marcar centros, percorrer contornos ou gerar aneis de corte. Potencia, velocidade e passadas sao da camada laser.',16,88,280,88);
        DrillMin:=DrillField(Scroll,'Diametro minimo (mm, 0 = todos)','0',184);
        DrillMax:=DrillField(Scroll,'Diametro maximo (mm, 0 = todos)','0',240);
        DrillPTH:=Check(Scroll,'Metalizados (PTH)',16,302,True); DrillPTH.OnChange:=@DrillChanged;
        DrillNPTH:=Check(Scroll,'Nao metalizados (NPTH)',16,330,True); DrillNPTH.OnChange:=@DrillChanged;
        Button(Scroll,'Marcar centros a laser',16,380,290,sikTarget,@AddHoleLayerClick).Tag:=0;
        Button(Scroll,'Contornos dos furos',16,424,290,sikFlame,@AddHoleLayerClick).Tag:=1;
        Button(Scroll,'Aneis para corte a laser',16,468,290,sikFlame,@AddHoleLayerClick).Tag:=2;
        LaserPowerInfo:=LabelAt(Scroll,'Selecione o laser no botao Mesa ou informe a potencia optica em Camadas.',16,532,280,160);
        LaserPowerInfo.Name:='LaserPowerInfo';
      end;
    end;
  end;
  Work := TPanel.Create(Self); Work.Parent := Self; Work.Align := alClient;
  Work.BevelOuter := bvNone; Work.Color := clSuiteSurface;
  Bar := TPanel.Create(Self); Bar.Parent := Work; Bar.Align := alTop; Bar.Height := 84; Bar.BevelOuter := bvNone;
  LabelAt(Bar,'Camada da placa',12,4,150,18);
  SideBox := TComboBox.Create(Self); SideBox.Parent := Bar; SideBox.SetBounds(12,26,120,30);
  SideBox.Style := csDropDownList; SideBox.Items.Add('Top'); SideBox.Items.Add('Bottom');
  SideBox.ItemIndex := 0; SideBox.OnChange := @CopperSideChanged;
  Button(Bar,'Placas',142,22,100,sikFit,@FitClick);
  Button(Bar,'Mesa',250,22,90,sikFrame,@BedClick);
  Button(Bar,'Componentes',348,22,140,sikLayers,@ComponentsClick).Name:='ComponentsButton';
  Button(Bar,'',496,22,42,sikZoomIn,@ZoomInClick).Hint := 'Ampliar';
  Button(Bar,'',544,22,42,sikZoomOut,@ZoomOutClick).Hint := 'Reduzir';
  Copper := Check(Bar,'Cobre',12,58,True); Copper.Width := 92;
  Holes := Check(Bar,'Furos',106,58,True); Holes.Width := 88;
  Paths := Check(Bar,'Trajetorias',200,58,True); Paths.Width := 128;
  Copper.OnChange := @ViewsChanged; Holes.OnChange := @ViewsChanged; Paths.OnChange := @ViewsChanged;
  Palette := TLAPalette.Create(Self); Palette.Parent := Work; Palette.Align := alBottom;
  Palette.Height := 34; Palette.Color := clSuiteCard; Palette.OnPick := @PalettePicked;
  Palette.Hint := 'Cor da camada selecionada'; Palette.ShowHint := True;
  View := TLaserPCBPreview.Create(Self); View.Parent := Work; View.Align := alClient;
  View.Project := P; View.Layout := P.Layout; View.OnSelectionChanged := @RefreshSelection;
  View.OnLayoutChanged := @PlacementChanged;
  Pages.ActivePageIndex := 0; Nav[0].SetLook(sbsSolid,clSuitePrimary,sikLayers);
  FUpdating := False;
  OnResize := @ResizeUI; OnShow := @ShowUI;
end;
procedure TLaserPCBForm.ResizeUI(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  SendButton.Left := FooterPanel.ClientWidth-SendButton.Width-18;
  ExportButton.Left := SendButton.Left-ExportButton.Width-10;
  ValidateButton.Left := ExportButton.Left-ValidateButton.Width-10;
  Status.Width := Max(120,ValidateButton.Left-30);
  LayerList.Height := Max(60,LayerList.Parent.ClientHeight-LayerList.Top-116);
end;
procedure TLaserPCBForm.ShowUI(Sender: TObject);
begin ResizeUI(Sender); View.FitBoards; end;
destructor TLaserPCBForm.Destroy;
begin View.Project := nil; View.Layout := nil; P.Free; inherited Destroy; end;
function TLaserPCBForm.Number(Edit: TEdit; const What: string): Double;
begin
  if not TryParseFloat(Edit.Text,Result) or not FiniteNumber(Result) or (Abs(Result) > 1e9) then
    raise Exception.Create(What+': informe um numero valido');
end;
procedure TLaserPCBForm.ReadSettings;
var Item: TLaserLayoutItem; N: Integer; Profile: TLaserProfile;
  BW,BH,M,S,R,O,X,Y,Angle,SX,SY,MarkD: Double; Filter: TLPDrillFilter;
  Op: TLPOperation;
begin
  { Ler e verificar tudo antes de alterar a geometria mostrada na tela. }
  Profile := P.Profile;
  Profile.SpotMM := Number(Spot,'Feixe'); Profile.Power := Number(Power,'Potencia');
  Profile.Feed := Number(Feed,'Velocidade'); Profile.SMax := Number(SMax,'S-max');
  Profile.OpticalPowerW:=Number(OpticalPower,'Potencia optica');
  Profile.Process:=TLaserProcess(ProcessBox.ItemIndex);
  if (Number(PowerPercent,'Potencia percentual')<0) or
    (Number(PowerPercent,'Potencia percentual')>100) then
    raise Exception.Create('Potencia laser deve estar entre 0 e 100%.');
  if (Profile.OpticalPowerW>0) and
    ((Number(TargetWatts,'Potencia em W')<0) or
     (Number(TargetWatts,'Potencia em W')>Profile.OpticalPowerW)) then
    raise Exception.Create('Potencia nominal deve estar entre zero e os W do laser.');
  if not TryStrToInt(Passes.Text,N) or (N < 1) or (N > 1000) then raise Exception.Create('Passadas: use 1 a 1000');
  Profile.Passes := N;
  R := Number(Res,'Resolucao'); O := Number(Overlap,'Sobreposicao')/100;
  BW := Number(BedW,'Largura da mesa'); BH := Number(BedH,'Altura da mesa');
  M := Number(Margin,'Margem'); S := Number(Spacing,'Espacamento');
  MarkD := Number(MarkDia,'Diametro da marca');
  if MarkD <= 0 then raise Exception.Create('Diametro da marca deve ser positivo');
  Filter := LPDefaultDrillFilter;
  Filter.MinDiameter := Number(DrillMin,'Diametro minimo'); Filter.MaxDiameter := Number(DrillMax,'Diametro maximo');
  Filter.IncludePlated := DrillPTH.Checked; Filter.IncludeNonPlated := DrillNPTH.Checked;
  if (Profile.OpticalPowerW<0) or (Profile.SpotMM <= 0) or (Profile.Power < 0) or (Profile.Feed < 0) or
    (Profile.SMax < 1) or (Profile.Power > Profile.SMax) or
    (R < 0.001) or (O < 0) or (O > 0.9) then raise Exception.Create('Parametros do processo invalidos');
  if (BW <= 0) or (BH <= 0) or (BW > 1000000) or (BH > 1000000) or
    (M < 0) or (S < 0) or (2*M >= Min(BW,BH)) then raise Exception.Create('Mesa, margem ou espacamento invalidos');
  Item := nil;
  if (View.SelectedIndex >= 0) and (View.SelectedIndex < P.Layout.Count) then
  begin
    Item := P.Layout.Item(View.SelectedIndex);
    X := Number(PosX,'X'); Y := Number(PosY,'Y'); Angle := Number(Rotation,'Rotacao');
    SX := Number(ScaleX,'Escala X'); SY := Number(ScaleY,'Escala Y');
    if (Abs(SX) < 1e-9) or (Abs(SY) < 1e-9) or (Abs(SX) > 100) or (Abs(SY) > 100) or
      (Abs(X) > 1000000) or (Abs(Y) > 1000000) or (Abs(Angle) > 1000000) then
      raise Exception.Create('Posicao, rotacao ou escala fora dos limites');
    if Item.Locked and Locked.Checked then
    begin
      if (Abs(X-Item.X)>0.000501) or (Abs(Y-Item.Y)>0.000501) or
        (Abs(Angle-Item.Rotation)>0.000501) or (Abs(SX-Item.ScaleX)>0.000051) or
        (Abs(SY-Item.ScaleY)>0.000051) then
        raise Exception.Create('Destrave a placa antes de alterar sua posicao');
      X:=Item.X; Y:=Item.Y; Angle:=Item.Rotation; SX:=Item.ScaleX; SY:=Item.ScaleY;
    end;
  end;
  P.Profile := Profile; P.Resolution := R; P.Overlap := O;
  if P.CopperLayerCount>0 then
    P.SelectCopperLayer(SideBox.ItemIndex+1)
  else P.Side := TPCBLayerSide(SideBox.ItemIndex);
  P.MirrorBottom := Mirror.Checked;
  P.Mode := TLPCamMode(ModeBox.ItemIndex);
  { o editor mostra sempre a camada selecionada: grava nela }
  Op := SelectedOperation;
  if (Op <> nil) and (Op = FEditOp) then
  begin
    Op.Name := Trim(LayerName.Text); if Op.Name = '' then Op.Name := CamModeName(Op.Mode);
    Op.Mode := P.Mode; Op.Process:=Profile.Process; Op.Power := Profile.Power; Op.Feed := Profile.Feed;
    Op.Passes := Profile.Passes; Op.Overlap := O; Op.MarkKind := TLPMarkKind(MarkKindBox.ItemIndex);
    Op.MarkDiameter := MarkD; Op.SourceLayer := SourceBox.ItemIndex;
    Layers.Invalidate;
  end;
  P.MarkKind := TLPMarkKind(MarkKindBox.ItemIndex); P.MarkDiameter := MarkD;
  P.DrillFilter := Filter;
  P.Layout.BedWidth := BW; P.Layout.BedHeight := BH; P.Layout.Margin := M; P.Layout.Spacing := S;
  if Item <> nil then
  begin
    Item.X := X; Item.Y := Y; Item.Rotation := Angle; Item.ScaleX := SX; Item.ScaleY := SY;
    Item.Locked := Locked.Checked;
  end;
end;
procedure TLaserPCBForm.SettingsChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  CommitLayerEditor;
  UpdateLaserPower;
  FExportedFile := ''; SendButton.Enabled := False; P.InvalidateCAM; View.Invalidate;
  State.Caption := 'Alteracoes pendentes'; State.DotColor := clSuiteWarning;
  Status.Caption := 'Atualize as trajetorias e valide as alteracoes.';
end;
procedure TLaserPCBForm.PlacementChanged(Sender: TObject);
begin
  FExportedFile := ''; SendButton.Enabled := False;
  RefreshSelection(Sender); State.Caption := 'Posicao alterada'; State.DotColor := clSuiteWarning;
end;
procedure TLaserPCBForm.RefreshSelection(Sender: TObject);
var Item: TLaserLayoutItem;
begin
  if (View.SelectedIndex < 0) or (View.SelectedIndex >= P.Layout.Count) then Exit;
  Item := P.Layout.Item(View.SelectedIndex); FUpdating := True;
  try
    PosX.Text := Format('%.3f',[Item.X],InvariantFS); PosY.Text := Format('%.3f',[Item.Y],InvariantFS);
    Rotation.Text := Format('%.3f',[Item.Rotation],InvariantFS);
    ScaleX.Text := Format('%.4f',[Item.ScaleX],InvariantFS); ScaleY.Text := Format('%.4f',[Item.ScaleY],InvariantFS);
    Locked.Checked := Item.Locked;
  finally FUpdating := False; end;
end;
procedure TLaserPCBForm.ViewsChanged(Sender: TObject);
begin View.ShowCopper := Copper.Checked; View.ShowDrills := Holes.Checked; View.ShowPaths := Paths.Checked; View.Invalidate; end;
procedure TLaserPCBForm.NavClick(Sender: TObject);
begin
  FocusPage(TSuiteButton(Sender).Tag);
end;
procedure TLaserPCBForm.FocusPage(N: Integer);
var I: Integer;
begin
  Pages.ActivePageIndex := N;
  for I := 0 to 4 do if I = N then Nav[I].SetLook(sbsSolid,clSuitePrimary)
  else Nav[I].SetLook(sbsSoft,clSuitePrimary);
end;
procedure TLaserPCBForm.RefreshSources;
var I: Integer;
begin
  RefreshCopperSides;
  LayerList.Items.Clear;
  if P.HasSVG then LayerList.Items.Add(ExtractFileName(P.SVGFile)+' [SVG]');
  for I := 0 to P.SourceCount-1 do
    if P.Source(I).ComponentGeometry then LayerList.Items.Add(P.Source(I).FileName)
    else if P.Source(I).CopperIndex>0 then
      LayerList.Items.Add('Cobre '+P.CopperLayerName(P.Source(I).CopperIndex)+' | '+ExtractFileName(P.Source(I).FileName))
    else LayerList.Items.Add(LayerRoleName(P.Source(I).Role)+' | '+ExtractFileName(P.Source(I).FileName));
  for I := 0 to P.DrillFiles.Count-1 do LayerList.Items.Add('Furos | '+ExtractFileName(P.DrillFiles[I]));
  if P.SelectedLayer >= 0 then LayerList.ItemIndex := P.SelectedLayer;
  Info.Caption := Format('Placa %.2f x %.2f mm'+#10+'%d copias  |  %d furos',
    [P.Width,P.Height,P.Layout.Count,P.Drills.HoleCount],InvariantFS);
  FUpdating := True;
  try
    if P.SelectedLayer >= 0 then begin RoleBox.ItemIndex := Ord(P.Source(P.SelectedLayer).Role);
      RoleBox.Enabled:=not P.Source(P.SelectedLayer).ComponentGeometry;end else RoleBox.Enabled:=True;
  finally FUpdating := False; end;
  try P.CreateDefaultOperations; except on E: Exception do Status.Caption := E.Message; end;
  RefreshLayerSources;
  if (Layers.Selected < 0) and (P.OperationCount > 0) then Layers.Selected := 0
  else Layers.Selected := Layers.Selected;
  LoadLayerEditor;
  FExportedFile := ''; SendButton.Enabled := False;
  View.SelectedIndex := 0; View.FitBoards;
end;
procedure TLaserPCBForm.NewClick(Sender: TObject);
begin FEditOp := nil; P.Clear; View.SelectedIndex := -1; RefreshSources; Log.Clear; View.FitBed; Status.Caption := 'Novo trabalho. Importe os arquivos da placa.'; end;
procedure TLaserPCBForm.OpenFile(const FN: string);
begin
  try
    FEditOp := nil;
    if DirectoryExists(FN) then
    begin
      P.ImportFolder(FN);
      FUpdating := True;
      try SideBox.ItemIndex := Ord(P.Side); finally FUpdating := False; end;
      Status.Caption := 'Pasta importada: ' + IntToStr(P.SourceCount) + ' camadas e ' +
        IntToStr(P.DrillFiles.Count) + ' arquivos de furos.';
    end
    else P.ImportFile(FN);
    RefreshSources;
    if not P.HasSVG then
      try P.RebuildMasks; except on E:Exception do Status.Caption := E.Message; end;
    Log.Lines.Assign(P.Warnings); View.Invalidate;
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.OpenClick(Sender: TObject);
var D: TOpenDialog; I: Integer;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Options := D.Options+[ofAllowMultiSelect,ofFileMustExist];
    D.Filter := 'PCB (SVG, Gerber, Excellon)|*.svg;*.gbr;*.ger;*.gtl;*.gbl;*.gts;*.gbs;*.gto;*.gbo;*.gm1;*.gko;*.drl;*.xln;*.exc|Todos os arquivos|*';
    if D.Execute then for I := 0 to D.Files.Count-1 do OpenFile(D.Files[I]);
  finally D.Free; end;
end;
procedure TLaserPCBForm.LayerClick(Sender: TObject);
begin
  if (LayerList.ItemIndex < 0) or (LayerList.ItemIndex >= P.SourceCount) or P.HasSVG then Exit;
  P.SelectedLayer := LayerList.ItemIndex;
  FUpdating := True; try RoleBox.ItemIndex := Ord(P.Source(P.SelectedLayer).Role); finally FUpdating := False; end;
  SettingsChanged(Sender);
end;
procedure TLaserPCBForm.RoleChanged(Sender: TObject);
begin
  if (P.SelectedLayer>=0) and(P.SelectedLayer<P.SourceCount) and P.Source(P.SelectedLayer).ComponentGeometry then Exit;
  if FUpdating or (P.SelectedLayer < 0) then Exit;
  try P.SetLayerRole(P.SelectedLayer,TLPLayerRole(RoleBox.ItemIndex)); RefreshSources;
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.ApplyClick(Sender: TObject);
begin try ReadSettings; View.Invalidate; PlacementChanged(Sender); except on E: Exception do ShowError(E); end; end;
procedure TLaserPCBForm.CopyClick(Sender: TObject);
begin try ReadSettings; P.AddCopy; RefreshSources; View.SelectedIndex := P.Layout.Count-1;
  except on E: Exception do ShowError(E); end; end;
procedure TLaserPCBForm.RemoveClick(Sender: TObject);
begin
  if View.SelectedIndex < 0 then Exit;
  P.Layout.RemoveItem(View.SelectedIndex); View.SelectedIndex := -1;
  RefreshSources; PlacementChanged(Sender);
end;
procedure TLaserPCBForm.NestClick(Sender: TObject);
begin
  try
    ReadSettings;
    if not TLaserNesting.ArrangeRows(P.Layout) then raise Exception.Create('Nao foi possivel distribuir todas as placas. Posicoes preservadas.');
    RefreshSelection(Sender); View.FitBoards; PlacementChanged(Sender);
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.RotateClick(Sender: TObject);
begin try ReadSettings; View.RotateSelected90; except on E: Exception do ShowError(E); end; end;
procedure TLaserPCBForm.KeepOutClick(Sender: TObject);
var S: string; Parts: TStringList; V: array[0..3] of Double; I: Integer;
begin
  S := '10;10;20;20';
  if not InputQuery('Zona proibida','X; Y; largura; altura (mm)',S) then Exit;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ';'; Parts.StrictDelimiter := True; Parts.DelimitedText := S;
    if Parts.Count <> 4 then raise Exception.Create('Informe quatro valores separados por ponto e virgula');
    for I := 0 to 3 do if not TryParseFloat(Parts[I],V[I]) then raise Exception.Create('Valor invalido');
    P.Layout.AddKeepOut(V[0],V[1],V[2],V[3]); PlacementChanged(Sender); View.Invalidate;
  except on E: Exception do ShowError(E); end;
  Parts.Free;
end;
procedure TLaserPCBForm.RefreshCopperSides;
var I, Selected: Integer;
begin
  FUpdating := True;
  try
    SideBox.Items.Clear;
    if P.CopperLayerCount>0 then
    begin
      for I:=1 to P.CopperLayerCount do SideBox.Items.Add(P.CopperLayerName(I));
      Selected:=P.ActiveCopperIndex-1;
      if Selected<0 then
      begin
        Selected:=0;
        for I:=1 to P.CopperLayerCount do
          if ((P.Side=lsBottom) and (P.CopperSource(I).Role=lrBottomCopper)) or
             ((P.Side=lsTop) and (P.CopperSource(I).Role=lrTopCopper)) then Selected:=I-1;
      end;
      SideBox.ItemIndex:=Selected;
      P.SelectCopperLayer(Selected+1);
    end
    else
    begin SideBox.Items.Add('Top'); SideBox.Items.Add('Bottom'); SideBox.ItemIndex:=Ord(P.Side); end;
  finally FUpdating:=False; end;
end;
procedure TLaserPCBForm.CopperSideChanged(Sender:TObject);
begin
  if FUpdating then Exit;
  if P.CopperLayerCount>0 then P.SelectCopperLayer(SideBox.ItemIndex+1)
  else begin P.Side:=TPCBLayerSide(SideBox.ItemIndex); P.InvalidateCAM; end;
  P.MirrorBottom:=Mirror.Checked;
  FExportedFile:=''; SendButton.Enabled:=False; View.Invalidate;
  State.Caption:='Alteracoes pendentes'; State.DotColor:=clSuiteWarning;
  Status.Caption:='Camada selecionada. Gere novamente as trajetorias desta face.';
end;
procedure TLaserPCBForm.FitClick(Sender: TObject);
var F: TPCBBoardForm; Choice: Integer;
begin
  F:=TPCBBoardForm.Create(Self);
  try
    try
      F.Configure(P);
      Choice:=F.ShowModal;
      if Choice=mrIgnore then begin View.FitBoards; Exit; end;
      if Choice<>mrOK then Exit;
      { Validate before replacing any geometry or clearing the active editor. }
      if (F.BoardWidth>P.Layout.BedWidth-2*P.Layout.Margin) or
         (F.BoardHeight>P.Layout.BedHeight-2*P.Layout.Margin) then
        raise Exception.Create('A placa deve caber na area util da mesa.');
      FEditOp:=nil;
      P.CreateBoard(F.BoardWidth,F.BoardHeight,F.LayerCount,F.SingleBottom);
      FUpdating:=True;
      try Mirror.Checked:=True; finally FUpdating:=False; end;
      RefreshSources; RefreshSelection(Sender); View.FitBoards; View.Invalidate;
      State.Caption:='Placa criada'; State.DotColor:=clSuiteWarning;
      Status.Caption:=Format('Placa %.2f x %.2f mm, %d camadas de cobre. Importe a geometria de cada camada.',
        [P.Width,P.Height,P.CopperLayerCount],InvariantFS);
    except on E:Exception do ShowError(E); end;
  finally F.Free; end;
end;
procedure TLaserPCBForm.ComponentsClick(Sender:TObject);
var F:TLPComponentsForm;
begin
  if P.HasSVG or(P.Width<=0) then begin Status.Caption:='Crie uma placa no botao Placas ou importe Gerber antes dos componentes.';Exit;end;
  F:=nil;
  try
    F:=TLPComponentsForm.CreateFor(Self,P);
    if F.ShowModal=mrOK then begin FEditOp:=nil;RefreshSources;P.RebuildMasks;View.Invalidate;
      Status.Caption:='Componentes aplicados: confira as camadas e calibre os parametros do laser.';end;
  except on E:Exception do ShowError(E);end;
  F.Free;
end;
procedure TLaserPCBForm.BedClick(Sender: TObject);
var F: TLaserBedForm; M: Double;
begin
  F := nil;
  try
    try
      F := TLaserBedForm.Create(Self);
      F.Caption := 'LaserPCB - Mesa';
      F.Configure(Number(BedW,'Largura da mesa'),Number(BedH,'Altura da mesa'),
        Number(SMax,'S maximo'));
      if F.ShowModal <> mrOK then Exit;
      M := Number(Margin,'Margem');
      if (M < 0) or (2*Max(P.Layout.Margin,M) >= Min(F.WidthMM,F.HeightMM)) then
        raise Exception.Create('A mesa deve ser maior que duas vezes a margem.');
      if F.SMax < 1 then
        raise Exception.Create('S maximo deve ser maior ou igual a 1.');
      FUpdating := True;
      try
        BedW.Text := FloatToStr(F.WidthMM,InvariantFS);
        BedH.Text := FloatToStr(F.HeightMM,InvariantFS);
        SMax.Text := FloatToStr(F.SMax,InvariantFS);
        P.Layout.BedWidth := F.WidthMM;
        P.Layout.BedHeight := F.HeightMM;
        P.Profile.SMax := F.SMax;
        if F.OpticalPowerW>0 then
        begin
          P.Profile.OpticalPowerW:=F.OpticalPowerW;
          OpticalPower.Text:=FloatToStr(F.OpticalPowerW,InvariantFS);
        end;
      finally
        FUpdating := False;
      end;
      FExportedFile := '';
      SendButton.Enabled := False;
      P.InvalidateCAM;
      UpdateLaserPower;
      View.FitBed;
      View.Invalidate;
      State.Caption := 'Alteracoes pendentes';
      State.DotColor := clSuiteWarning;
      Status.Caption := 'Mesa atualizada. Gere as trajetorias e valide as alteracoes.';
    except
      on E: Exception do ShowError(E);
    end;
  finally
    F.Free;
  end;
end;
procedure TLaserPCBForm.ZoomInClick(Sender: TObject);
begin View.ZoomIn; end;
procedure TLaserPCBForm.ZoomOutClick(Sender: TObject);
begin View.ZoomOut; end;
procedure TLaserPCBForm.Prepared;
var I: Integer; Op: TLPOperation; S: string; Cut, Travel, Secs: Double;
begin
  ReadSettings; P.GenerateOperations; View.Invalidate; Layers.Invalidate;
  S := '';
  for I := 0 to P.OperationCount-1 do
  begin
    Op := P.Operation(I);
    if not Op.Output then Continue;
    if S <> '' then S := S+#10;
    S := S+Format('%s %s: %.0f mm, %dx',[Op.Caption,Op.Name,Op.CutLength,Max(1,Op.Passes)],InvariantFS);
  end;
  if S = '' then S := 'Nenhuma camada com Saida ligada.';
  Summary.Caption := S;
  P.EstimateOperations(3000,Cut,Travel,Secs);
  Estimate.Caption := Format('Tempo estimado %d:%.2d'+#10+'Corte %.0f mm  |  deslocamento %.0f mm',
    [Trunc(Secs) div 60,Trunc(Secs) mod 60,Cut,Travel],InvariantFS);
end;
procedure TLaserPCBForm.GenerateClick(Sender: TObject);
begin
  try Prepared; Status.Caption := 'Trajetorias atualizadas. Confira a previa e valide o trabalho.';
    State.Caption := 'Previa atualizada'; State.DotColor := clSuiteInfo;
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.ValidateClick(Sender: TObject);
begin
  FocusPage(3);
  try
    Prepared;
    if P.ValidateOperations(Log.Lines,True) then
    begin Log.Lines.Add('Pronto para gerar G-code.'); State.Caption := 'Trabalho valido'; State.DotColor := clSuiteSuccess; Status.Caption := 'Geometria e parametros validados.'; end
    else begin State.Caption := 'Corrigir antes de exportar'; State.DotColor := clSuiteDanger; Status.Caption := Log.Lines[0]; end;
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.ExportClick(Sender: TObject);
var D: TSaveDialog; Job: TLaserPCBJob;
begin
  try
    Prepared;
    if not P.ValidateOperations(Log.Lines,True) then begin FocusPage(3); raise Exception.Create(Log.Lines.Text); end;
    D := TSaveDialog.Create(Self);
    try
      D.Filter := 'G-code|*.gcode'; D.DefaultExt := 'gcode'; D.Options := D.Options+[ofOverwritePrompt];
      if D.Execute then
      begin
        Job := P.BuildOperationsJob;
        try TLaserGCodeExporter.ExportJob(Job,D.FileName); finally Job.Free; end;
        FExportedFile := ExpandFileName(D.FileName); SendButton.Enabled := True;
        State.Caption := 'G-code gerado'; State.DotColor := clSuiteSuccess;
        Status.Caption := 'Gerado: '+ExtractFileName(D.FileName);
      end;
    finally D.Free; end;
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.SendClick(Sender: TObject);
var Registry: TSuiteRegistry; Root,Err,Candidate: string; C: TSuiteContext; I: Integer;
begin
  if (FExportedFile = '') or not FileExists(FExportedFile) then Exit;
  Registry := TSuiteRegistry.Create;
  try
    C := ReadSuiteContext; Root := ExtractFilePath(ParamStr(0)); Candidate := Root;
    for I := 0 to 5 do
    begin
      if DirectoryExists(IncludeTrailingPathDelimiter(Candidate)+'multisuite') then begin Root := Candidate; Break; end;
      Candidate := ExtractFileDir(ExcludeTrailingPathDelimiter(Candidate));
    end;
    if not TSuiteLauncher.LaunchArtifact(Registry.Tool(Registry.Find(stiMultiCNC)),Root,C.ProjectRoot,FExportedFile,Err) then
      raise Exception.Create(Err);
    Status.Caption := 'Programa aberto no MultiCNC.';
  except on E: Exception do ShowError(E); end;
  Registry.Free;
end;
procedure TLaserPCBForm.SaveProfileClick(Sender: TObject);
var D: TSaveDialog;
begin
  try
    ReadSettings; D := TSaveDialog.Create(Self);
    try
      D.Filter := 'Perfil laser|*.json'; D.DefaultExt := 'json'; D.Options := D.Options+[ofOverwritePrompt];
      if D.Execute then TLaserProfileIO.Save(P.Profile,D.FileName);
    finally D.Free; end;
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.LoadProfileClick(Sender: TObject);
var D: TOpenDialog; Profile: TLaserProfile;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Perfil laser|*.json';
    if D.Execute then
    begin
      Profile := TLaserProfileIO.Load(D.FileName); P.Profile := Profile; FUpdating := True;
      try
        Power.Text := FloatToStr(Profile.Power,InvariantFS); Feed.Text := FloatToStr(Profile.Feed,InvariantFS);
        OpticalPower.Text:=FloatToStr(Profile.OpticalPowerW,InvariantFS);
        ProcessBox.ItemIndex:=Ord(Profile.Process);
        Spot.Text := FloatToStr(Profile.SpotMM,InvariantFS); SMax.Text := FloatToStr(Profile.SMax,InvariantFS);
        Passes.Text := IntToStr(Profile.Passes);
      finally FUpdating := False; end;
      SettingsChanged(Sender); UpdateLaserPower;
    end;
  except on E: Exception do ShowError(E); end;
  D.Free;
end;
procedure TLaserPCBForm.AlignClick(Sender: TObject);
var S: string; Values: TStringList; V: array[0..7] of Double; I: Integer;
  A,B: TFiducial; T: TAlignment2D; Item: TLaserLayoutItem; OX,OY: Double;
begin
  if View.SelectedIndex < 0 then Exit;
  S := '0;0;10;10;20;0;30;10';
  if not InputQuery('Alinhar 2 fiduciais','Projeto X1;Y1;medido X1;Y1;projeto X2;Y2;medido X2;Y2 (mm)',S) then Exit;
  Values := TStringList.Create;
  try
    Values.Delimiter := ';'; Values.StrictDelimiter := True; Values.DelimitedText := S;
    if Values.Count <> 8 then raise Exception.Create('Informe oito coordenadas');
    for I := 0 to 7 do if not TryParseFloat(Values[I],V[I]) or not FiniteNumber(V[I]) then raise Exception.Create('Coordenada invalida');
    A.DesignX := V[0]; A.DesignY := V[1]; A.MachineX := V[2]; A.MachineY := V[3];
    B.DesignX := V[4]; B.DesignY := V[5]; B.MachineX := V[6]; B.MachineY := V[7];
    A.DesignX := A.DesignX-P.OriginX; A.DesignY := A.DesignY-P.OriginY;
    B.DesignX := B.DesignX-P.OriginX; B.DesignY := B.DesignY-P.OriginY;
    if (P.Side = lsBottom) and P.MirrorBottom then
    begin A.DesignX := P.Width-A.DesignX; B.DesignX := P.Width-B.DesignX; end;
    T := TAlignmentSolver.Solve2(A,B); if not T.Valid then raise Exception.Create('Os fiduciais precisam ser distintos');
    Item := P.Layout.Item(View.SelectedIndex); if Item.Locked then raise Exception.Create('Destrave a placa para alinhar');
    Item.MirrorX := False; Item.MirrorY := False;
    Item.ScaleX := T.Scale; Item.ScaleY := T.Scale; Item.Rotation := T.RotationDeg;
    P.InvalidateCAM;
    Item.RotationOrigin(OX,OY); Item.X := T.OffsetX+OX; Item.Y := T.OffsetY+OY;
    PlacementChanged(Sender); View.FitBoards;
  except on E: Exception do ShowError(E); end;
  Values.Free;
end;
function TLaserPCBForm.SelectedOperation: TLPOperation;
begin
  if (Layers <> nil) and (Layers.Selected >= 0) and (Layers.Selected < P.OperationCount) then
    Result := P.Operation(Layers.Selected)
  else Result := nil;
end;
procedure TLaserPCBForm.CommitLayerEditor;
var Op: TLPOperation; V: Double; N: Integer;
begin
  { grava o que for valido; campos incompletos ficam para o ReadSettings }
  Op := FEditOp;
  if (Op = nil) or (P.OperationCount = 0) or (Op <> SelectedOperation) then Exit;
  if Trim(LayerName.Text) <> '' then Op.Name := Trim(LayerName.Text);
  if ProcessBox.ItemIndex>=0 then Op.Process:=TLaserProcess(ProcessBox.ItemIndex);
  if ModeBox.ItemIndex >= 0 then Op.Mode := TLPCamMode(ModeBox.ItemIndex);
  if SourceBox.ItemIndex >= 0 then Op.SourceLayer := SourceBox.ItemIndex;
  if MarkKindBox.ItemIndex >= 0 then Op.MarkKind := TLPMarkKind(MarkKindBox.ItemIndex);
  if TryParseFloat(Power.Text,V) and FiniteNumber(V) and (V >= 0) then Op.Power := V;
  if TryParseFloat(Feed.Text,V) and FiniteNumber(V) and (V >= 0) then Op.Feed := V;
  if TryStrToInt(Passes.Text,N) and (N >= 1) and (N <= 1000) then Op.Passes := N;
  if TryParseFloat(Overlap.Text,V) and FiniteNumber(V) and (V >= 0) and (V <= 90) then Op.Overlap := V/100;
  if TryParseFloat(MarkDia.Text,V) and FiniteNumber(V) and (V > 0) then Op.MarkDiameter := V;
  LayerTitle.Caption := 'CAMADA '+Op.Caption+'  -  '+CamModeName(Op.Mode);
  SourceBox.Enabled := Op.Mode = cmLayerHatch;
  MarkKindBox.Enabled := Op.Mode = cmDrillMarks; MarkDia.Enabled := MarkKindBox.Enabled;
  Layers.Invalidate;
end;
procedure TLaserPCBForm.RefreshLayerSources;
var I, Keep: Integer;
begin
  Keep := SourceBox.ItemIndex;
  SourceBox.Items.Clear;
  for I := 0 to P.SourceCount-1 do
    if P.Source(I).ComponentGeometry then LayerList.Items.Add(P.Source(I).FileName)
    else if P.Source(I).CopperIndex>0 then
      SourceBox.Items.Add('Cobre '+P.CopperLayerName(P.Source(I).CopperIndex)+' | '+ExtractFileName(P.Source(I).FileName))
    else SourceBox.Items.Add(LayerRoleName(P.Source(I).Role)+' | '+ExtractFileName(P.Source(I).FileName));
  if Keep < SourceBox.Items.Count then SourceBox.ItemIndex := Keep;
end;
procedure TLaserPCBForm.LoadLayerEditor;
var Op: TLPOperation;
begin
  Op := SelectedOperation; FEditOp := Op;
  FUpdating := True;
  try
    if Op = nil then
    begin
      LayerTitle.Caption := 'CAMADA SELECIONADA'; Palette.Current := -1; Palette.Invalidate; Exit;
    end;
    LayerTitle.Caption := 'CAMADA '+Op.Caption+'  -  '+CamModeName(Op.Mode);
    LayerName.Text := Op.Name; ModeBox.ItemIndex := Ord(Op.Mode);
    ProcessBox.ItemIndex:=Ord(Op.Process);
    if Op.SourceLayer < SourceBox.Items.Count then SourceBox.ItemIndex := Op.SourceLayer;
    SourceBox.Enabled := Op.Mode = cmLayerHatch;
    Power.Text := FloatToStr(Op.Power,InvariantFS); Feed.Text := FloatToStr(Op.Feed,InvariantFS);
    Passes.Text := IntToStr(Op.Passes); Overlap.Text := FloatToStr(Round(Op.Overlap*1000)/10,InvariantFS);
    MarkKindBox.ItemIndex := Ord(Op.MarkKind); MarkKindBox.Enabled := Op.Mode = cmDrillMarks;
    MarkDia.Text := FloatToStr(Op.MarkDiameter,InvariantFS); MarkDia.Enabled := Op.Mode = cmDrillMarks;
    Palette.Current := Op.ColorIndex; Palette.Invalidate;
  finally FUpdating := False; end;
  UpdateLaserPower;
end;
procedure TLaserPCBForm.LayerSelected(Sender: TObject; Index: Integer);
begin
  LoadLayerEditor;
  if Pages.ActivePageIndex <> 2 then FocusPage(2);
end;
procedure TLaserPCBForm.LayerToggled(Sender: TObject; Index: Integer);
begin
  FExportedFile := ''; SendButton.Enabled := False; View.Invalidate;
  State.Caption := 'Camadas alteradas'; State.DotColor := clSuiteWarning;
  Status.Caption := 'Saida/Mostrar alterado. Atualize as trajetorias e valide.';
end;
procedure TLaserPCBForm.PalettePicked(Sender: TObject; Index: Integer);
var Op: TLPOperation;
begin
  Op := SelectedOperation;
  if Op = nil then begin Status.Caption := 'Selecione uma camada para mudar a cor.'; Exit; end;
  Op.ColorIndex := Index; LoadLayerEditor; Layers.Invalidate; View.Invalidate;
end;
procedure TLaserPCBForm.AddLayerClick(Sender: TObject);
var Op: TLPOperation; I, C: Integer; Used: Boolean;
begin
  try
    ReadSettings;
    { primeira cor da paleta ainda sem camada }
    for C := 0 to 29 do
    begin
      Used := False;
      for I := 0 to P.OperationCount-1 do if P.Operation(I).ColorIndex = C then Used := True;
      if not Used then Break;
    end;
    if P.HasSVG then Op := P.AddOperation(cmVectors,'Nova camada',C)
    else Op := P.AddOperation(cmIsolation,'Nova camada',C);
    Layers.Selected := P.OperationCount-1; LoadLayerEditor; SettingsChanged(Sender);
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.DeleteLayerClick(Sender: TObject);
var I: Integer;
begin
  I := Layers.Selected; if I < 0 then Exit;
  FEditOp := nil; P.DeleteOperation(I); Layers.Selected := Min(I,P.OperationCount-1);
  LoadLayerEditor; SettingsChanged(Sender);
end;
procedure TLaserPCBForm.LayerUpClick(Sender: TObject);
var I: Integer;
begin
  I := Layers.Selected; if I <= 0 then Exit;
  P.MoveOperation(I,-1); Layers.Selected := I-1; LoadLayerEditor; SettingsChanged(Sender);
end;
procedure TLaserPCBForm.LayerDownClick(Sender: TObject);
var I: Integer;
begin
  I := Layers.Selected; if (I < 0) or (I >= P.OperationCount-1) then Exit;
  P.MoveOperation(I,1); Layers.Selected := I+1; LoadLayerEditor; SettingsChanged(Sender);
end;
function TLaserPCBForm.DrillField(ParentControl: TWinControl; const AText, Value: string; Y: Integer): TEdit;
begin
  Result := Field(ParentControl,AText,Value,Y); Result.OnChange := @DrillChanged;
end;
procedure TLaserPCBForm.DrillChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  SettingsChanged(Sender);
end;
procedure TLaserPCBForm.AddHoleLayerClick(Sender:TObject);
var Op:TLPOperation;
begin
  CommitLayerEditor;
  Op:=P.AddOperation(cmDrillMarks,'Furos a laser',6);
  Op.MarkKind:=TLPMarkKind(TSuiteButton(Sender).Tag);
  Op.Process:=lpMarking;
  case Op.MarkKind of
    mkCenter: Op.Name:='Marcacao dos centros';
    mkOutline: Op.Name:='Marcacao dos contornos dos furos';
    mkCutHole: Op.Name:='Aneis de corte dos furos';
  end;
  Layers.Selected:=P.OperationCount-1; LoadLayerEditor;
  SettingsChanged(Sender); FocusPage(2);
end;
procedure TLaserPCBForm.LaserReferencesClick(Sender:TObject);
var F:TLaserReferenceForm; W:Double;
begin
  try
    W:=Number(OpticalPower,'Potencia optica');
    F:=TLaserReferenceForm.Create(Self);
    try
      F.Configure(W);
      if F.ShowModal<>mrOK then Exit;
      FUpdating:=True;
      try
        Power.Text:=FloatToStr(F.PowerW/W*Number(SMax,'S-max'),InvariantFS);
        Feed.Text:=FloatToStr(F.Feed,InvariantFS);
        ProcessBox.ItemIndex:=Ord(lpMarking);
      finally FUpdating:=False; end;
      SettingsChanged(Sender); UpdateLaserPower;
      Status.Caption:='Referencia aplicada a esta camada. Calibre no seu material antes de usar.';
    finally F.Free; end;
  except on E:Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.UpdateLaserPower;
var SLimit,SValue,W,F,Percent:Double; PowerSummary:string; WasUpdating:Boolean;
begin
  if not TryParseFloat(SMax.Text,SLimit) or (SLimit<=0) or not FiniteNumber(SLimit) then Exit;
  if not TryParseFloat(Power.Text,SValue) or not FiniteNumber(SValue) then Exit;
  if not TryParseFloat(OpticalPower.Text,W) or (W<0) or not FiniteNumber(W) then Exit;
  Percent:=100*SValue/SLimit;
  WasUpdating:=FUpdating; FUpdating:=True;
  try
    PowerPercent.Text:=FloatToStr(Percent,InvariantFS);
    TargetWatts.Enabled:=W>0;
    if W>0 then TargetWatts.Text:=FloatToStr(W*Percent/100,InvariantFS) else TargetWatts.Text:='';
  finally FUpdating:=WasUpdating; end;
  PowerSummary:=Format('Laser %.2f W | %.1f%% = S%.0f | potencia nominal %.2f W',
    [W,Percent,SValue,W*Percent/100],InvariantFS);
  if W=0 then PowerSummary:='Potencia optica desconhecida. Informe os W do laser ou selecione o equipamento em Mesa.';
  if (W>0) and TryParseFloat(Feed.Text,F) and FiniteNumber(F) and (F>0) then
    PowerSummary:=PowerSummary+#10+Format('Energia nominal por passada: %.3f J/mm',[W*Percent/100*60/F],InvariantFS);
  LaserPowerInfo.Caption:=PowerSummary+#10+'Use parametros testados para cada tratamento e material.';
  LayerPowerInfo.Caption:=LaserPowerInfo.Caption;
  P.Profile.OpticalPowerW:=W;
end;
procedure TLaserPCBForm.LaserPowerChanged(Sender:TObject);
var W,Value,SLimit:Double; WasUpdating:Boolean;
begin
  if FUpdating then Exit;
  if not TryParseFloat(SMax.Text,SLimit) or not FiniteNumber(SLimit) or (SLimit<1) then Exit;
  if Sender=PowerPercent then
  begin
    if not TryParseFloat(PowerPercent.Text,Value) or not FiniteNumber(Value) or (Value<0) or (Value>100) then Exit;
    Value:=Value*SLimit/100;
  end
  else if Sender=TargetWatts then
  begin
    if not TryParseFloat(OpticalPower.Text,W) or not FiniteNumber(W) or (W<=0) then Exit;
    if not TryParseFloat(TargetWatts.Text,Value) or not FiniteNumber(Value) or (Value<0) or (Value>W) then Exit;
    Value:=Value/W*SLimit;
  end else Value:=-1;
  if Value>=0 then
  begin
    WasUpdating:=FUpdating; FUpdating:=True;
    try Power.Text:=FloatToStr(Value,InvariantFS); finally FUpdating:=WasUpdating; end;
  end;
  SettingsChanged(Sender); UpdateLaserPower;
end;
procedure TLaserPCBForm.ShowError(E: Exception);
begin
  Status.Caption := E.Message; Log.Lines.Add(E.Message);
  State.Caption := 'Verifique o trabalho'; State.DotColor := clSuiteDanger;
end;
end.
