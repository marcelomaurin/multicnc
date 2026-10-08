unit multisuite_main;
{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Dialogs,
  Process, Graphics, multisuite_types, multisuite_registry, multisuite_launcher,
  multisuite_workspace;

const
  SEC_HOME        = 0;
  SEC_PROJECT     = 1;
  SEC_DESIGN      = 2;
  SEC_PREPARE     = 3;
  SEC_SIMULATE    = 4;
  SEC_MANUFACTURE = 5;
  SEC_TOOLS       = 6;
  SEC_SETTINGS    = 7;

type
  TMultiSuiteForm = class(TForm)
  private
    Registry: TSuiteRegistry;
    Workspace: TWorkspace;
    Root: string;

    Sidebar: TPanel;
    NavPanel: TPanel;
    TopBar: TPanel;
    Content: TPanel;
    HeaderTitle: TLabel;
    HeaderSubtitle: TLabel;
    ProjectStatus: TLabel;
    Tree: TTreeView;
    Flow: TListBox;
    Info: TLabel;
    CurrentSection: Integer;

    procedure BuildSidebar;
    procedure BuildTopBar;
    procedure ClearContent;
    procedure ShowSection(ASection: Integer);
    procedure ShowHome;
    procedure ShowProject;
    procedure ShowCategory(ASection: Integer);
    procedure ShowTools;
    procedure ShowSettings;
    procedure Navigate(Sender: TObject);
    procedure SetActiveNavigation;
    procedure AddNavigationHeader(const ACaption: string);
    procedure AddNavigationButton(const ACaption: string; ASection: Integer);
    procedure AddPageHeader(AParent: TWinControl; const ATitle, ASubtitle: string);
    procedure AddToolCard(AParent: TWinControl; AToolIndex: Integer);
    procedure AddSectionTitle(AParent: TWinControl; const ACaption: string);
    function ToolInSection(AID: TSuiteToolID; ASection: Integer): Boolean;
    function ToolIndex(AID: TSuiteToolID): Integer;
    function SuiteColor(R, G, B: Byte): TColor;

    procedure OpenToolCard(Sender: TObject);
    procedure OpenTestCenter(Sender: TObject);
    procedure OpenArtifact(Sender: TObject);
    procedure NewDemo(Sender: TObject);
    procedure RefreshWorkspace;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

function TMultiSuiteForm.SuiteColor(R, G, B: Byte): TColor;
begin
  Result := TColor(R or (G shl 8) or (B shl 16));
end;

constructor TMultiSuiteForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Caption := 'MultiSuite - Central de Projeto e Fabricacao Digital';
  Position := poScreenCenter;
  Width := 1360;
  Height := 820;
  Constraints.MinWidth := 1024;
  Constraints.MinHeight := 650;
  Color := SuiteColor(245, 247, 250);
  DoubleBuffered := True;

  Registry := TSuiteRegistry.Create;
  Workspace := TWorkspace.Create;
  Root := ExpandFileName(
    ExtractFilePath(ParamStr(0)) + '..' + DirectorySeparator + '..' +
    DirectorySeparator + '..' + DirectorySeparator
  );

  Tree := nil;
  Flow := nil;
  Info := nil;
  CurrentSection := SEC_HOME;

  BuildSidebar;
  BuildTopBar;

  Content := TPanel.Create(Self);
  Content.Parent := Self;
  Content.Align := alClient;
  Content.BevelOuter := bvNone;
  Content.Color := SuiteColor(245, 247, 250);

  ShowSection(SEC_HOME);
end;

destructor TMultiSuiteForm.Destroy;
begin
  Workspace.Free;
  Registry.Free;
  inherited Destroy;
end;

procedure TMultiSuiteForm.BuildSidebar;
var
  Brand, Footer: TPanel;
  L: TLabel;
begin
  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self;
  Sidebar.Align := alLeft;
  Sidebar.Width := 238;
  Sidebar.BevelOuter := bvNone;
  Sidebar.Color := SuiteColor(28, 34, 44);

  Brand := TPanel.Create(Sidebar);
  Brand.Parent := Sidebar;
  Brand.Align := alTop;
  Brand.Height := 104;
  Brand.BevelOuter := bvNone;
  Brand.Color := Sidebar.Color;

  L := TLabel.Create(Brand);
  L.Parent := Brand;
  L.Caption := 'MultiSuite';
  L.SetBounds(20, 20, 190, 30);
  L.Font.Size := 19;
  L.Font.Style := [fsBold];
  L.Font.Color := clWhite;

  L := TLabel.Create(Brand);
  L.Parent := Brand;
  L.Caption := 'Projeto e fabricacao digital';
  L.SetBounds(20, 55, 195, 20);
  L.Font.Size := 9;
  L.Font.Color := SuiteColor(176, 186, 201);

  Footer := TPanel.Create(Sidebar);
  Footer.Parent := Sidebar;
  Footer.Align := alBottom;
  Footer.Height := 54;
  Footer.BevelOuter := bvNone;
  Footer.Color := SuiteColor(24, 29, 38);

  L := TLabel.Create(Footer);
  L.Parent := Footer;
  L.AutoSize := False;
  L.Align := alClient;
  L.Alignment := taCenter;
  L.Layout := tlCenter;
  L.Caption := Format('%d ferramentas registradas', [Registry.Count]);
  L.Font.Color := SuiteColor(155, 165, 181);

  NavPanel := TPanel.Create(Sidebar);
  NavPanel.Parent := Sidebar;
  NavPanel.Align := alClient;
  NavPanel.BevelOuter := bvNone;
  NavPanel.Color := Sidebar.Color;

  AddNavigationHeader('INICIO');
  AddNavigationButton('Visao geral', SEC_HOME);
  AddNavigationButton('Projeto atual', SEC_PROJECT);

  AddNavigationHeader('FLUXO');
  AddNavigationButton('Projetar', SEC_DESIGN);
  AddNavigationButton('Preparar', SEC_PREPARE);
  AddNavigationButton('Simular', SEC_SIMULATE);
  AddNavigationButton('Fabricar', SEC_MANUFACTURE);

  AddNavigationHeader('SISTEMA');
  AddNavigationButton('Ferramentas', SEC_TOOLS);
  AddNavigationButton('Configuracoes', SEC_SETTINGS);
end;

procedure TMultiSuiteForm.BuildTopBar;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 72;
  TopBar.BevelOuter := bvNone;
  TopBar.Color := clWhite;

  HeaderTitle := TLabel.Create(TopBar);
  HeaderTitle.Parent := TopBar;
  HeaderTitle.SetBounds(24, 10, 600, 28);
  HeaderTitle.Font.Size := 15;
  HeaderTitle.Font.Style := [fsBold];
  HeaderTitle.Font.Color := SuiteColor(34, 40, 49);

  HeaderSubtitle := TLabel.Create(TopBar);
  HeaderSubtitle.Parent := TopBar;
  HeaderSubtitle.SetBounds(24, 40, 700, 20);
  HeaderSubtitle.Font.Size := 9;
  HeaderSubtitle.Font.Color := SuiteColor(100, 110, 124);

  ProjectStatus := TLabel.Create(TopBar);
  ProjectStatus.Parent := TopBar;
  ProjectStatus.AutoSize := False;
  ProjectStatus.Align := alRight;
  ProjectStatus.Width := 360;
  ProjectStatus.Alignment := taRightJustify;
  ProjectStatus.Layout := tlCenter;
  ProjectStatus.BorderSpacing.Right := 24;
  ProjectStatus.Caption := 'Nenhum projeto aberto';
  ProjectStatus.Font.Size := 9;
  ProjectStatus.Font.Color := SuiteColor(82, 92, 107);
end;

procedure TMultiSuiteForm.AddNavigationHeader(const ACaption: string);
var
  L: TLabel;
begin
  L := TLabel.Create(NavPanel);
  L.Parent := NavPanel;
  L.Align := alTop;
  L.Top := 10000;
  L.AutoSize := False;
  L.Height := 34;
  L.BorderSpacing.Left := 18;
  L.BorderSpacing.Top := 10;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  L.Font.Size := 8;
  L.Font.Style := [fsBold];
  L.Font.Color := SuiteColor(111, 124, 143);
end;

procedure TMultiSuiteForm.AddNavigationButton(const ACaption: string; ASection: Integer);
var
  B: TButton;
begin
  B := TButton.Create(NavPanel);
  B.Parent := NavPanel;
  B.Align := alTop;
  B.Top := 10000;
  B.Height := 42;
  B.BorderSpacing.Left := 12;
  B.BorderSpacing.Right := 12;
  B.BorderSpacing.Bottom := 4;
  B.Caption := ACaption;
  B.Tag := 100 + ASection;
  B.OnClick := @Navigate;
  B.Font.Size := 10;
end;

procedure TMultiSuiteForm.Navigate(Sender: TObject);
begin
  if not (Sender is TButton) then
    Exit;
  ShowSection(TButton(Sender).Tag - 100);
end;

procedure TMultiSuiteForm.SetActiveNavigation;
var
  I, S: Integer;
  B: TButton;
begin
  if NavPanel = nil then
    Exit;

  for I := 0 to NavPanel.ControlCount - 1 do
    if NavPanel.Controls[I] is TButton then
    begin
      B := TButton(NavPanel.Controls[I]);
      S := B.Tag - 100;
      if S = CurrentSection then
        B.Font.Style := [fsBold]
      else
        B.Font.Style := [];
    end;
end;

procedure TMultiSuiteForm.ClearContent;
begin
  Tree := nil;
  Flow := nil;
  Info := nil;

  while Content.ControlCount > 0 do
    Content.Controls[0].Free;
end;

procedure TMultiSuiteForm.ShowSection(ASection: Integer);
begin
  if (ASection < SEC_HOME) or (ASection > SEC_SETTINGS) then
    ASection := SEC_HOME;

  CurrentSection := ASection;
  ClearContent;

  case ASection of
    SEC_HOME:        ShowHome;
    SEC_PROJECT:     ShowProject;
    SEC_DESIGN,
    SEC_PREPARE,
    SEC_SIMULATE,
    SEC_MANUFACTURE: ShowCategory(ASection);
    SEC_TOOLS:       ShowTools;
    SEC_SETTINGS:    ShowSettings;
  end;

  SetActiveNavigation;
  RefreshWorkspace;
end;

procedure TMultiSuiteForm.AddPageHeader(AParent: TWinControl;
  const ATitle, ASubtitle: string);
var
  P: TPanel;
  L: TLabel;
begin
  P := TPanel.Create(AParent);
  P.Parent := AParent;
  P.Align := alTop;
  P.Top := 10000;
  P.Height := 92;
  P.BevelOuter := bvNone;
  P.Color := SuiteColor(245, 247, 250);
  P.BorderSpacing.Left := 22;
  P.BorderSpacing.Right := 22;
  P.BorderSpacing.Top := 16;

  L := TLabel.Create(P);
  L.Parent := P;
  L.Caption := ATitle;
  L.SetBounds(0, 7, 760, 30);
  L.Font.Size := 18;
  L.Font.Style := [fsBold];
  L.Font.Color := SuiteColor(34, 40, 49);

  L := TLabel.Create(P);
  L.Parent := P;
  L.AutoSize := False;
  L.SetBounds(0, 43, 850, 38);
  L.Caption := ASubtitle;
  L.WordWrap := True;
  L.Font.Size := 10;
  L.Font.Color := SuiteColor(95, 106, 121);
end;

procedure TMultiSuiteForm.AddSectionTitle(AParent: TWinControl; const ACaption: string);
var
  L: TLabel;
begin
  L := TLabel.Create(AParent);
  L.Parent := AParent;
  L.Align := alTop;
  L.Top := 10000;
  L.AutoSize := False;
  L.Height := 42;
  L.BorderSpacing.Left := 26;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  L.Font.Size := 11;
  L.Font.Style := [fsBold];
  L.Font.Color := SuiteColor(63, 72, 85);
end;

function TMultiSuiteForm.ToolIndex(AID: TSuiteToolID): Integer;
begin
  Result := Registry.Find(AID);
end;

function TMultiSuiteForm.ToolInSection(AID: TSuiteToolID; ASection: Integer): Boolean;
begin
  Result := False;
  case ASection of
    SEC_DESIGN:
      Result := AID in [stiMultiCAD, stiMultiPCB, stiMakePCB, stiMakeRouter, stiLaserPCB, stiLaserArt];
    SEC_PREPARE:
      Result := AID in [stiMultiCAM, stiRouterPCB, stiMultiSlicer];
    SEC_SIMULATE:
      Result := AID in [stiMultiPhysics, stiMultiAssembly];
    SEC_MANUFACTURE:
      Result := AID = stiMultiCNC;
  end;
end;

procedure TMultiSuiteForm.AddToolCard(AParent: TWinControl; AToolIndex: Integer);
var
  P, ActionPanel: TPanel;
  L: TLabel;
  B: TButton;
  T: TSuiteToolInfo;
begin
  if (AToolIndex < 0) or (AToolIndex >= Registry.Count) then
    Exit;

  T := Registry.Tool(AToolIndex);

  P := TPanel.Create(AParent);
  P.Parent := AParent;
  P.Align := alTop;
  P.Top := 10000;
  P.Height := 94;
  P.BevelOuter := bvNone;
  P.Color := clWhite;
  P.BorderSpacing.Left := 24;
  P.BorderSpacing.Right := 24;
  P.BorderSpacing.Bottom := 9;

  ActionPanel := TPanel.Create(P);
  ActionPanel.Parent := P;
  ActionPanel.Align := alRight;
  ActionPanel.Width := 142;
  ActionPanel.BevelOuter := bvNone;
  ActionPanel.Color := clWhite;

  B := TButton.Create(ActionPanel);
  B.Parent := ActionPanel;
  B.SetBounds(18, 28, 104, 36);
  B.Caption := 'Abrir';
  B.Tag := AToolIndex;
  B.OnClick := @OpenToolCard;
  B.Font.Style := [fsBold];

  L := TLabel.Create(P);
  L.Parent := P;
  L.Caption := T.Name;
  L.SetBounds(20, 16, 420, 26);
  L.Font.Size := 13;
  L.Font.Style := [fsBold];
  L.Font.Color := SuiteColor(38, 46, 58);

  L := TLabel.Create(P);
  L.Parent := P;
  L.AutoSize := False;
  L.SetBounds(20, 45, 650, 32);
  L.Caption := T.Description;
  L.WordWrap := True;
  L.Font.Size := 9;
  L.Font.Color := SuiteColor(103, 113, 128);
end;

procedure TMultiSuiteForm.ShowHome;
var
  Scroll: TScrollBox;
  Hero, FlowPanel, QuickPanel: TPanel;
  L: TLabel;
  B: TButton;
  I, CNCIndex: Integer;
begin
  HeaderTitle.Caption := 'Visao geral';
  HeaderSubtitle.Caption := 'Da ideia a fabricacao em um unico ecossistema.';

  Scroll := TScrollBox.Create(Content);
  Scroll.Parent := Content;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.Color := SuiteColor(245, 247, 250);
  Scroll.VertScrollBar.Tracking := True;

  Hero := TPanel.Create(Scroll);
  Hero.Parent := Scroll;
  Hero.Align := alTop;
  Hero.Top := 10000;
  Hero.Height := 168;
  Hero.BevelOuter := bvNone;
  Hero.Color := SuiteColor(38, 75, 132);
  Hero.BorderSpacing.Left := 24;
  Hero.BorderSpacing.Right := 24;
  Hero.BorderSpacing.Top := 20;
  Hero.BorderSpacing.Bottom := 12;

  L := TLabel.Create(Hero);
  L.Parent := Hero;
  L.Caption := 'MultiCNC Suite';
  L.SetBounds(24, 20, 520, 34);
  L.Font.Size := 22;
  L.Font.Style := [fsBold];
  L.Font.Color := clWhite;

  L := TLabel.Create(Hero);
  L.Parent := Hero;
  L.AutoSize := False;
  L.SetBounds(24, 60, 780, 46);
  L.Caption := 'Projete, simule, prepare e fabrique usando ferramentas especializadas que compartilham o mesmo fluxo de trabalho.';
  L.WordWrap := True;
  L.Font.Size := 11;
  L.Font.Color := SuiteColor(224, 233, 246);

  L := TLabel.Create(Hero);
  L.Parent := Hero;
  L.Caption := 'IDEIA  >  PROJETO  >  SIMULACAO  >  PREPARACAO  >  VALIDACAO  >  FABRICACAO';
  L.SetBounds(24, 124, 820, 24);
  L.Font.Size := 9;
  L.Font.Style := [fsBold];
  L.Font.Color := clWhite;

  QuickPanel := TPanel.Create(Scroll);
  QuickPanel.Parent := Scroll;
  QuickPanel.Align := alTop;
  QuickPanel.Top := 10000;
  QuickPanel.Height := 74;
  QuickPanel.BevelOuter := bvNone;
  QuickPanel.Color := SuiteColor(245, 247, 250);
  QuickPanel.BorderSpacing.Left := 24;
  QuickPanel.BorderSpacing.Right := 24;

  B := TButton.Create(QuickPanel);
  B.Parent := QuickPanel;
  B.SetBounds(0, 16, 210, 38);
  B.Caption := 'Criar projeto demonstracao';
  B.OnClick := @NewDemo;

  CNCIndex := ToolIndex(stiMultiCNC);
  B := TButton.Create(QuickPanel);
  B.Parent := QuickPanel;
  B.SetBounds(224, 16, 150, 38);
  B.Caption := 'Abrir MultiCNC';
  B.Tag := CNCIndex;
  B.OnClick := @OpenToolCard;

  B := TButton.Create(QuickPanel);
  B.Parent := QuickPanel;
  B.SetBounds(388, 16, 160, 38);
  B.Caption := 'Central de testes';
  B.OnClick := @OpenTestCenter;

  FlowPanel := TPanel.Create(Scroll);
  FlowPanel.Parent := Scroll;
  FlowPanel.Align := alTop;
  FlowPanel.Top := 10000;
  FlowPanel.Height := 72;
  FlowPanel.BevelOuter := bvNone;
  FlowPanel.Color := clWhite;
  FlowPanel.BorderSpacing.Left := 24;
  FlowPanel.BorderSpacing.Right := 24;
  FlowPanel.BorderSpacing.Bottom := 10;

  L := TLabel.Create(FlowPanel);
  L.Parent := FlowPanel;
  L.Caption := 'Um ecossistema, varias ferramentas';
  L.SetBounds(18, 13, 450, 24);
  L.Font.Size := 12;
  L.Font.Style := [fsBold];
  L.Font.Color := SuiteColor(45, 54, 67);

  L := TLabel.Create(FlowPanel);
  L.Parent := FlowPanel;
  L.Caption := 'Escolha o que deseja fazer no menu lateral; o MultiSuite encaminha voce para a ferramenta apropriada.';
  L.SetBounds(18, 41, 780, 20);
  L.Font.Size := 9;
  L.Font.Color := SuiteColor(100, 111, 126);

  AddSectionTitle(Scroll, 'Aplicacoes da suite');
  for I := 0 to Registry.Count - 1 do
    AddToolCard(Scroll, I);
end;

procedure TMultiSuiteForm.ShowCategory(ASection: Integer);
var
  Scroll: TScrollBox;
  I: Integer;
  TitleText, SubtitleText: string;
begin
  case ASection of
    SEC_DESIGN:
      begin
        TitleText := 'Projetar';
        SubtitleText := 'Crie geometrias, placas e conteudo para os processos de fabricacao.';
      end;
    SEC_PREPARE:
      begin
        TitleText := 'Preparar';
        SubtitleText := 'Transforme o projeto em trajetorias, camadas e instrucoes prontas para fabricar.';
      end;
    SEC_SIMULATE:
      begin
        TitleText := 'Simular';
        SubtitleText := 'Valide montagem e comportamento fisico antes de chegar a maquina real.';
      end;
    SEC_MANUFACTURE:
      begin
        TitleText := 'Fabricar';
        SubtitleText := 'Conecte-se ao equipamento, posicione a peca e execute o trabalho com o MultiCNC.';
      end;
  else
    TitleText := 'Ferramentas';
    SubtitleText := '';
  end;

  HeaderTitle.Caption := TitleText;
  HeaderSubtitle.Caption := SubtitleText;

  Scroll := TScrollBox.Create(Content);
  Scroll.Parent := Content;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.Color := SuiteColor(245, 247, 250);
  Scroll.VertScrollBar.Tracking := True;

  AddPageHeader(Scroll, TitleText, SubtitleText);
  AddSectionTitle(Scroll, 'Ferramentas recomendadas');

  for I := 0 to Registry.Count - 1 do
    if ToolInSection(Registry.Tool(I).ID, ASection) then
      AddToolCard(Scroll, I);
end;

procedure TMultiSuiteForm.ShowProject;
var
  LeftPanel, RightPanel, TitlePanel: TPanel;
  L: TLabel;
  B: TButton;
begin
  HeaderTitle.Caption := 'Projeto atual';
  HeaderSubtitle.Caption := 'Artefatos e etapas do fluxo de engenharia.';

  RightPanel := TPanel.Create(Content);
  RightPanel.Parent := Content;
  RightPanel.Align := alRight;
  RightPanel.Width := 340;
  RightPanel.BevelOuter := bvNone;
  RightPanel.Color := SuiteColor(245, 247, 250);
  RightPanel.BorderSpacing.Around := 16;

  TitlePanel := TPanel.Create(RightPanel);
  TitlePanel.Parent := RightPanel;
  TitlePanel.Align := alTop;
  TitlePanel.Height := 88;
  TitlePanel.BevelOuter := bvNone;
  TitlePanel.Color := clWhite;

  L := TLabel.Create(TitlePanel);
  L.Parent := TitlePanel;
  L.Caption := 'Fluxo do projeto';
  L.SetBounds(18, 14, 250, 24);
  L.Font.Size := 12;
  L.Font.Style := [fsBold];

  B := TButton.Create(TitlePanel);
  B.Parent := TitlePanel;
  B.SetBounds(18, 47, 190, 30);
  B.Caption := 'Criar projeto demonstracao';
  B.OnClick := @NewDemo;

  Flow := TListBox.Create(RightPanel);
  Flow.Parent := RightPanel;
  Flow.Align := alClient;
  Flow.BorderSpacing.Top := 10;
  Flow.Font.Size := 10;

  LeftPanel := TPanel.Create(Content);
  LeftPanel.Parent := Content;
  LeftPanel.Align := alClient;
  LeftPanel.BevelOuter := bvNone;
  LeftPanel.Color := SuiteColor(245, 247, 250);
  LeftPanel.BorderSpacing.Around := 16;

  Info := TLabel.Create(LeftPanel);
  Info.Parent := LeftPanel;
  Info.Align := alTop;
  Info.AutoSize := False;
  Info.Height := 94;
  Info.BorderSpacing.Bottom := 10;
  Info.Color := clWhite;
  Info.ParentColor := False;
  Info.BorderSpacing.Left := 16;
  Info.Layout := tlCenter;
  Info.Font.Size := 10;
  Info.WordWrap := True;

  Tree := TTreeView.Create(LeftPanel);
  Tree.Parent := LeftPanel;
  Tree.Align := alClient;
  Tree.OnDblClick := @OpenArtifact;
  Tree.Font.Size := 10;
end;

procedure TMultiSuiteForm.ShowTools;
var
  Scroll: TScrollBox;
  I: Integer;
  P: TPanel;
  L: TLabel;
  B: TButton;
begin
  HeaderTitle.Caption := 'Ferramentas';
  HeaderSubtitle.Caption := 'Acesso direto aos modulos e recursos de desenvolvimento.';

  Scroll := TScrollBox.Create(Content);
  Scroll.Parent := Content;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.Color := SuiteColor(245, 247, 250);
  Scroll.VertScrollBar.Tracking := True;

  AddPageHeader(Scroll, 'Ferramentas da suite',
    'Abra diretamente qualquer modulo registrado no MultiSuite.');

  P := TPanel.Create(Scroll);
  P.Parent := Scroll;
  P.Align := alTop;
  P.Top := 10000;
  P.Height := 84;
  P.BevelOuter := bvNone;
  P.Color := clWhite;
  P.BorderSpacing.Left := 24;
  P.BorderSpacing.Right := 24;
  P.BorderSpacing.Bottom := 10;

  L := TLabel.Create(P);
  L.Parent := P;
  L.Caption := 'Central de testes';
  L.SetBounds(18, 13, 360, 24);
  L.Font.Size := 12;
  L.Font.Style := [fsBold];

  L := TLabel.Create(P);
  L.Parent := P;
  L.Caption := 'Compilacao, validacao e diagnostico dos modulos da suite.';
  L.SetBounds(18, 43, 560, 20);
  L.Font.Size := 9;
  L.Font.Color := SuiteColor(100, 111, 126);

  B := TButton.Create(P);
  B.Parent := P;
  B.Align := alRight;
  B.Width := 140;
  B.BorderSpacing.Around := 18;
  B.Caption := 'Abrir testes';
  B.OnClick := @OpenTestCenter;

  AddSectionTitle(Scroll, 'Aplicacoes');
  for I := 0 to Registry.Count - 1 do
    AddToolCard(Scroll, I);
end;

procedure TMultiSuiteForm.ShowSettings;
var
  Scroll: TScrollBox;
  P: TPanel;
  L: TLabel;
begin
  HeaderTitle.Caption := 'Configuracoes';
  HeaderSubtitle.Caption := 'Informacoes gerais do ambiente MultiSuite.';

  Scroll := TScrollBox.Create(Content);
  Scroll.Parent := Content;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.Color := SuiteColor(245, 247, 250);

  AddPageHeader(Scroll, 'Configuracoes do MultiSuite',
    'Area reservada para preferencias visuais, caminhos, idioma e integracoes da suite.');

  P := TPanel.Create(Scroll);
  P.Parent := Scroll;
  P.Align := alTop;
  P.Top := 10000;
  P.Height := 150;
  P.BevelOuter := bvNone;
  P.Color := clWhite;
  P.BorderSpacing.Left := 24;
  P.BorderSpacing.Right := 24;

  L := TLabel.Create(P);
  L.Parent := P;
  L.Caption := 'Ambiente';
  L.SetBounds(18, 16, 250, 24);
  L.Font.Size := 12;
  L.Font.Style := [fsBold];

  L := TLabel.Create(P);
  L.Parent := P;
  L.AutoSize := False;
  L.SetBounds(18, 48, 850, 80);
  L.WordWrap := True;
  L.Caption := 'Raiz da suite: ' + Root + LineEnding +
    Format('Ferramentas registradas: %d', [Registry.Count]) + LineEnding +
    'A nova navegacao lateral organiza a suite por objetivo: projetar, preparar, simular e fabricar.';
  L.Font.Size := 9;
  L.Font.Color := SuiteColor(90, 101, 116);
end;

procedure TMultiSuiteForm.NewDemo(Sender: TObject);
var
  A: TProjectArtifact;
begin
  Workspace.NewProject(
    'Projeto CNC Integrado',
    IncludeTrailingPathDelimiter(Root) + 'projects' + DirectorySeparator + 'cnc_demo'
  );

  A.Name := 'Estrutura mecanica';
  A.FileName := 'cad/estrutura.mcad';
  A.Kind := akCAD;
  A.Tool := stiMultiCAD;
  Workspace.AddArtifact(A);

  A.Name := 'Placa controladora';
  A.FileName := 'pcb/controladora.mpcb';
  A.Kind := akPCB;
  A.Tool := stiMultiPCB;
  Workspace.AddArtifact(A);

  A.Name := 'Montagem CNC';
  A.FileName := 'assembly/cnc.massembly';
  A.Kind := akAssembly;
  A.Tool := stiMultiAssembly;
  Workspace.AddArtifact(A);

  A.Name := 'Usinagem mecanica';
  A.FileName := 'cam/usinagem.mcam';
  A.Kind := akCAM;
  A.Tool := stiMultiCAM;
  Workspace.AddArtifact(A);

  Workspace.SetStage(wsDesign, ssReady);
  Workspace.SetStage(wsElectronics, ssReady);

  ShowSection(SEC_PROJECT);
end;

procedure TMultiSuiteForm.RefreshWorkspace;
var
  RootNode, N: TTreeNode;
  I: Integer;
  A: TProjectArtifact;
  S: TWorkflowStage;
  ProjectName: string;
begin
  ProjectName := Workspace.Project.Name;
  if ProjectName = '' then
  begin
    ProjectStatus.Caption := 'Nenhum projeto aberto';
    if Info <> nil then
      Info.Caption := 'Nenhum projeto aberto.' + LineEnding +
        'Crie um projeto demonstracao para visualizar o fluxo integrado.';
    if Tree <> nil then
    begin
      Tree.Items.Clear;
      Tree.Items.Add(nil, 'Nenhum projeto aberto');
    end;
    if Flow <> nil then
    begin
      Flow.Clear;
      for S := Low(TWorkflowStage) to High(TWorkflowStage) do
        Flow.Items.Add(StageName(S) + ' : ' + StateName(Workspace.Stage(S)));
    end;
    Exit;
  end;

  ProjectStatus.Caption := 'Projeto: ' + ProjectName;

  if Tree <> nil then
  begin
    Tree.Items.BeginUpdate;
    try
      Tree.Items.Clear;
      RootNode := Tree.Items.Add(nil, ProjectName);

      N := Tree.Items.AddChild(RootNode, 'Artefatos');
      for I := 0 to Workspace.ArtifactCount - 1 do
      begin
        A := Workspace.Artifact(I);
        Tree.Items.AddChildObject(
          N,
          ArtifactKindName(A.Kind) + ' - ' + A.Name + ' [' + A.FileName + ']',
          TObject(PtrInt(I + 1))
        );
      end;

      N := Tree.Items.AddChild(RootNode, 'Ferramentas');
      for I := 0 to Registry.Count - 1 do
        Tree.Items.AddChild(N, Registry.Tool(I).Name);

      RootNode.Expand(True);
    finally
      Tree.Items.EndUpdate;
    end;
  end;

  if Flow <> nil then
  begin
    Flow.Clear;
    for S := Low(TWorkflowStage) to High(TWorkflowStage) do
      Flow.Items.Add(StageName(S) + ' : ' + StateName(Workspace.Stage(S)));
  end;

  if Info <> nil then
    Info.Caption := 'Projeto: ' + ProjectName + LineEnding +
      'Diretorio: ' + Workspace.Project.RootPath + LineEnding +
      Format('%d artefatos | %d ferramentas disponiveis',
        [Workspace.ArtifactCount, Registry.Count]);
end;

procedure TMultiSuiteForm.OpenTestCenter(Sender: TObject);
var
  P: TProcess;
  Exe: string;
begin
  Exe := IncludeTrailingPathDelimiter(Root) + 'multisuite_test_center';
  {$IFDEF Windows}
  Exe := Exe + '.exe';
  {$ENDIF}

  if not FileExists(Exe) then
  begin
    ShowMessage('Central de testes ainda nao compilada: ' + Exe);
    Exit;
  end;

  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    P.Execute;
  finally
    P.Free;
  end;
end;

procedure TMultiSuiteForm.OpenArtifact(Sender: TObject);
var
  I, TI: Integer;
  A: TProjectArtifact;
  T: TSuiteToolInfo;
  E: string;
begin
  if (Tree = nil) or (Tree.Selected = nil) or (Tree.Selected.Data = nil) then
    Exit;

  I := PtrInt(Tree.Selected.Data) - 1;
  if (I < 0) or (I >= Workspace.ArtifactCount) then
    Exit;

  A := Workspace.Artifact(I);
  TI := Registry.Find(A.Tool);
  if TI < 0 then
  begin
    ShowMessage('Ferramenta responsavel nao registrada.');
    Exit;
  end;

  T := Registry.Tool(TI);
  if not TSuiteLauncher.LaunchArtifact(
    T, Root, Workspace.Project.RootPath, A.FileName, E
  ) then
    ShowMessage(E);
end;

procedure TMultiSuiteForm.OpenToolCard(Sender: TObject);
var
  I: Integer;
  T: TSuiteToolInfo;
  E, ProjectRoot: string;
begin
  if not (Sender is TButton) then
    Exit;

  I := TButton(Sender).Tag;
  if (I < 0) or (I >= Registry.Count) then
    Exit;

  T := Registry.Tool(I);
  ProjectRoot := Workspace.Project.RootPath;

  if not TSuiteLauncher.Launch(T, Root, ProjectRoot, E) then
    ShowMessage(E);
end;

end.
