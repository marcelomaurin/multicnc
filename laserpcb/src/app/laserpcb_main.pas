unit laserpcb_main;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, laserpcb_project, laserpcb_preview, laserpcb_layout,
  laserpcb_types, multisuite_controls, multisuite_icons;
type
  TLaserPCBForm = class(TForm)
  private
    P: TLaserPCBProject;
    View: TLaserPCBPreview;
    LayerList: TListBox;
    Pages: TPageControl;
    Nav: array[0..3] of TSuiteButton;
    State: TSuiteBadge;
    Info, Summary, Status: TLabel;
    Log: TMemo;
    ModeBox, SideBox, RoleBox: TComboBox;
    Mirror, Copper, Holes, Paths, Locked: TCheckBox;
    Power, Feed, Spot, Passes, SMax, Res, Overlap: TEdit;
    BedW, BedH, Margin, Spacing, PosX, PosY, Rotation, ScaleX, ScaleY: TEdit;
    ExportButton, SendButton, ValidateButton: TSuiteButton;
    FooterPanel: TPanel;
    FUpdating: Boolean;
    FExportedFile: string;
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
    procedure BedClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure GenerateClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure SaveProfileClick(Sender: TObject);
    procedure LoadProfileClick(Sender: TObject);
    procedure AlignClick(Sender: TObject);
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
  laserpcb_geom, laserpcb_alignment, multisuite_numfmt, multisuite_registry,
  multisuite_launcher, multisuite_types, multisuite_context;

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
  LabelAt(ParentControl,AText,16,Y,260,18);
  Result := TEdit.Create(Self); Result.Parent := ParentControl;
  Result.SetBounds(16,Y+20,260,28); Result.Text := Value; Result.OnChange := @SettingsChanged;
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
const Names: array[0..3] of string = ('1  Importar','2  Posicionar','3  Processo','4  Validar');
  Icons: array[0..3] of TSuiteIconKind = (sikLayers,sikMove,sikGear,sikTests);
begin
  inherited CreateNew(AOwner,1);
  Caption := 'LaserPCB • MultiSuite'; Width := 1240; Height := 850;
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
  for I := 0 to 3 do
  begin
    Nav[I] := Button(Sidebar,Names[I],12,16+I*44,190,Icons[I],@NavClick); Nav[I].Tag := I;
  end;
  Button(Sidebar,'Importar arquivos',12,208,190,sikImport,@OpenClick);
  Button(Sidebar,'Novo trabalho',12,250,190,sikNew,@NewClick);
  LabelAt(Sidebar,'CAMADAS E FUROS',16,304,180,20);
  LayerList := TListBox.Create(Self); LayerList.Parent := Sidebar;
  LayerList.SetBounds(12,330,190,Height-540); LayerList.Anchors := [akLeft,akTop,akRight,akBottom];
  LayerList.OnClick := @LayerClick;
  Info := LabelAt(Sidebar,'Nenhuma placa importada',16,Sidebar.Height-132,184,88);
  Info.Align := alBottom; Info.BorderSpacing.Around := 12;
  Right := TPageControl.Create(Self); Right.Parent := Self; Right.Align := alRight;
  Right.Width := 306; Right.ShowTabs := False; Pages := Right;
  for I := 0 to 3 do
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
        RoleBox.SetBounds(16,206,260,30); RoleBox.Style := csDropDownList;
        for Role := Low(TLPLayerRole) to High(TLPLayerRole) do RoleBox.Items.Add(LayerRoleName(Role));
        RoleBox.ItemIndex := 0; RoleBox.OnChange := @RoleChanged;
        LabelAt(Scroll,'Confira a funcao dos Gerbers sem atributo X2. O CAM precisa de um contorno fechado.',
          16,256,260,84);
        Button(Scroll,'Abrir arquivos...',16,354,260,sikFolder,@OpenClick);
      end;
      1:
      begin
        BedW := Field(Scroll,'Mesa: largura (mm)','400',58);
        BedH := Field(Scroll,'Mesa: altura (mm)','400',114);
        Margin := Field(Scroll,'Margem da mesa (mm)','5',170);
        Spacing := Field(Scroll,'Espaco entre placas (mm)','2',226);
        Button(Scroll,'Duplicar',16,288,124,sikCopy,@CopyClick);
        Button(Scroll,'Excluir',152,288,124,sikTrash,@RemoveClick);
        Button(Scroll,'Distribuir placas',16,330,260,sikMove,@NestClick);
        PosX := Field(Scroll,'Placa selecionada: X (mm)','5',386);
        PosY := Field(Scroll,'Placa selecionada: Y (mm)','5',442);
        Rotation := Field(Scroll,'Rotacao (graus)','0',498);
        ScaleX := Field(Scroll,'Escala X','1',554);
        ScaleY := Field(Scroll,'Escala Y','1',610);
        Locked := Check(Scroll,'Travar placa',16,670,False); Locked.OnChange := @SettingsChanged;
        Button(Scroll,'Aplicar posicao',16,710,260,sikTarget,@ApplyClick);
        Button(Scroll,'Girar 90 graus',16,752,260,sikMove,@RotateClick);
        Button(Scroll,'Adicionar zona proibida',16,794,260,sikRect,@KeepOutClick);
        Button(Scroll,'Alinhar 2 fiduciais',16,836,260,sikTarget,@AlignClick);
        LabelAt(Scroll,'Camera nao configurada. Informe as coordenadas medidas dos fiduciais.',
          16,886,260,70);
      end;
      2:
      begin
        LabelAt(Scroll,'Processo',16,58,260,20);
        ModeBox := TComboBox.Create(Self); ModeBox.Parent := Scroll; ModeBox.SetBounds(16,82,260,30);
        ModeBox.Style := csDropDownList;
        ModeBox.Items.Add('Vetores SVG'); ModeBox.Items.Add('Isolacao do cobre');
        ModeBox.Items.Add('Remocao de cobre'); ModeBox.Items.Add('Preencher camada selecionada');
        ModeBox.ItemIndex := Ord(P.Mode); ModeBox.OnChange := @SettingsChanged;
        Mirror := Check(Scroll,'Espelhar Bottom',16,128,True); Mirror.OnChange := @SettingsChanged;
        Spot := Field(Scroll,'Diametro calibrado do feixe (mm)','0.1',168);
        Power := Field(Scroll,'Potencia calibrada (S)','0',224);
        SMax := Field(Scroll,'S-max da maquina ($30)','1000',280);
        Feed := Field(Scroll,'Velocidade calibrada (mm/min)','0',336);
        Passes := Field(Scroll,'Passadas / aneis na isolacao','1',392);
        Overlap := Field(Scroll,'Sobreposicao (%)','20',448);
        Res := Field(Scroll,'Resolucao raster (mm/pixel)','0.05',504);
        LabelAt(Scroll,'Na isolacao, passadas sao aneis. Nos outros processos, o G-code repete o percurso.',
          16,568,260,68);
        Button(Scroll,'Atualizar trajetorias',16,646,260,sikFlame,@GenerateClick);
        Button(Scroll,'Salvar perfil',16,692,124,sikSave,@SaveProfileClick);
        Button(Scroll,'Carregar',152,692,124,sikFolder,@LoadProfileClick);
      end;
      3:
      begin
        State := TSuiteBadge.Create(Self); State.Parent := Scroll; State.SetBounds(16,60,260,32);
        State.Caption := 'Aguardando validacao'; State.DotColor := clSuiteWarning;
        Summary := LabelAt(Scroll,'Confira os parametros e gere a previa.',16,112,260,100);
        Log := TMemo.Create(Self); Log.Parent := Scroll; Log.SetBounds(16,228,260,250);
        Log.ReadOnly := True; Log.ScrollBars := ssAutoVertical;
        LabelAt(Scroll,'A conexao, o enquadramento e a execucao ficam no MultiCNC.',16,504,260,60);
        Button(Scroll,'Validar agora',16,580,260,sikTests,@ValidateClick);
      end;
    end;
  end;
  Work := TPanel.Create(Self); Work.Parent := Self; Work.Align := alClient;
  Work.BevelOuter := bvNone; Work.Color := clSuiteSurface;
  Bar := TPanel.Create(Self); Bar.Parent := Work; Bar.Align := alTop; Bar.Height := 84; Bar.BevelOuter := bvNone;
  LabelAt(Bar,'Lado da placa',12,4,150,18);
  SideBox := TComboBox.Create(Self); SideBox.Parent := Bar; SideBox.SetBounds(12,26,120,30);
  SideBox.Style := csDropDownList; SideBox.Items.Add('Top'); SideBox.Items.Add('Bottom');
  SideBox.ItemIndex := 0; SideBox.OnChange := @SettingsChanged;
  Button(Bar,'Placas',142,22,100,sikFit,@FitClick);
  Button(Bar,'Mesa',250,22,90,sikFrame,@BedClick);
  Button(Bar,'',348,22,42,sikZoomIn,@ZoomInClick).Hint := 'Ampliar';
  Button(Bar,'',396,22,42,sikZoomOut,@ZoomOutClick).Hint := 'Reduzir';
  Copper := Check(Bar,'Cobre',12,58,True); Copper.Width := 92;
  Holes := Check(Bar,'Furos',106,58,True); Holes.Width := 88;
  Paths := Check(Bar,'Trajetorias',200,58,True); Paths.Width := 128;
  Copper.OnChange := @ViewsChanged; Holes.OnChange := @ViewsChanged; Paths.OnChange := @ViewsChanged;
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
  BW,BH,M,S,R,O,X,Y,Angle,SX,SY: Double;
begin
  { Ler e verificar tudo antes de alterar a geometria mostrada na tela. }
  Profile := P.Profile;
  Profile.SpotMM := Number(Spot,'Feixe'); Profile.Power := Number(Power,'Potencia');
  Profile.Feed := Number(Feed,'Velocidade'); Profile.SMax := Number(SMax,'S-max');
  if not TryStrToInt(Passes.Text,N) or (N < 1) or (N > 1000) then raise Exception.Create('Passadas: use 1 a 1000');
  Profile.Passes := N;
  R := Number(Res,'Resolucao'); O := Number(Overlap,'Sobreposicao')/100;
  BW := Number(BedW,'Largura da mesa'); BH := Number(BedH,'Altura da mesa');
  M := Number(Margin,'Margem'); S := Number(Spacing,'Espacamento');
  if (Profile.SpotMM <= 0) or (Profile.Power < 0) or (Profile.Feed < 0) or
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
  P.Side := TPCBLayerSide(SideBox.ItemIndex); P.MirrorBottom := Mirror.Checked;
  P.Mode := TLPCamMode(ModeBox.ItemIndex);
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
  for I := 0 to 3 do if I = N then Nav[I].SetLook(sbsSolid,clSuitePrimary)
  else Nav[I].SetLook(sbsSoft,clSuitePrimary);
end;
procedure TLaserPCBForm.RefreshSources;
var I: Integer;
begin
  LayerList.Items.Clear;
  if P.HasSVG then LayerList.Items.Add(ExtractFileName(P.SVGFile)+' [SVG]');
  for I := 0 to P.SourceCount-1 do LayerList.Items.Add(LayerRoleName(P.Source(I).Role)+' | '+ExtractFileName(P.Source(I).FileName));
  for I := 0 to P.DrillFiles.Count-1 do LayerList.Items.Add('Furos | '+ExtractFileName(P.DrillFiles[I]));
  if P.SelectedLayer >= 0 then LayerList.ItemIndex := P.SelectedLayer;
  Info.Caption := Format('Placa %.2f x %.2f mm'+#10+'%d copias  •  %d furos',
    [P.Width,P.Height,P.Layout.Count,P.Drills.HoleCount],InvariantFS);
  FUpdating := True;
  try
    ModeBox.ItemIndex := Ord(P.Mode);
    if P.SelectedLayer >= 0 then RoleBox.ItemIndex := Ord(P.Source(P.SelectedLayer).Role);
  finally FUpdating := False; end;
  FExportedFile := ''; SendButton.Enabled := False;
  View.SelectedIndex := 0; View.FitBoards;
end;
procedure TLaserPCBForm.NewClick(Sender: TObject);
begin P.Clear; View.SelectedIndex := -1; RefreshSources; Log.Clear; View.FitBed; Status.Caption := 'Novo trabalho. Importe os arquivos da placa.'; end;
procedure TLaserPCBForm.OpenFile(const FN: string);
begin
  try
    P.ImportFile(FN); RefreshSources;
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
procedure TLaserPCBForm.FitClick(Sender: TObject);
begin View.FitBoards; end;
procedure TLaserPCBForm.BedClick(Sender: TObject);
begin View.FitBed; end;
procedure TLaserPCBForm.ZoomInClick(Sender: TObject);
begin View.ZoomIn; end;
procedure TLaserPCBForm.ZoomOutClick(Sender: TObject);
begin View.ZoomOut; end;
procedure TLaserPCBForm.Prepared;
begin
  ReadSettings; P.Generate; View.Invalidate;
  Summary.Caption := Format('%d trajetorias'+#10+'%.2f mm por placa'+#10+'%d copias',
    [Length(P.Paths),LPPathsLength(P.Paths),P.Layout.Count],InvariantFS);
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
    if P.Validate(Log.Lines,True) then
    begin Log.Lines.Add('Pronto para gerar G-code.'); State.Caption := 'Trabalho valido'; State.DotColor := clSuiteSuccess; Status.Caption := 'Geometria e parametros validados.'; end
    else begin State.Caption := 'Corrigir antes de exportar'; State.DotColor := clSuiteDanger; Status.Caption := Log.Lines[0]; end;
  except on E: Exception do ShowError(E); end;
end;
procedure TLaserPCBForm.ExportClick(Sender: TObject);
var D: TSaveDialog; Job: TLaserPCBJob;
begin
  try
    Prepared;
    if not P.Validate(Log.Lines,True) then begin FocusPage(3); raise Exception.Create(Log.Lines.Text); end;
    D := TSaveDialog.Create(Self);
    try
      D.Filter := 'G-code|*.gcode'; D.DefaultExt := 'gcode'; D.Options := D.Options+[ofOverwritePrompt];
      if D.Execute then
      begin
        Job := P.BuildJob;
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
        Spot.Text := FloatToStr(Profile.SpotMM,InvariantFS); SMax.Text := FloatToStr(Profile.SMax,InvariantFS);
        Passes.Text := IntToStr(Profile.Passes);
      finally FUpdating := False; end;
      SettingsChanged(Sender);
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
procedure TLaserPCBForm.ShowError(E: Exception);
begin
  Status.Caption := E.Message; Log.Lines.Add(E.Message);
  State.Caption := 'Verifique o trabalho'; State.DotColor := clSuiteDanger;
end;
end.
