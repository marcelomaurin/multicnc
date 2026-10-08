unit makerouter_main;

{ MakeRouter - tela provisoria (dummy).

  O MakeRouter (projeto e usinagem de madeira na CNC Router) esta em analise:
  esta tela so ocupa o lugar na suite (registro, bandeja, MultiSuite) no padrao
  visual das outras ferramentas e mostra o que vira em cada etapa. Nenhum
  calculo, arquivo ou G-code e gerado. Plano em makerouter/docs/TAREFA.md. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  multisuite_controls, multisuite_icons;

type
  TMakeRouterForm = class(TForm)
  private
    Nav: array[0..5] of TSuiteButton;
    StepTitle, StepText: TLabel;
    State: TSuiteBadge;
    function LabelAt(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function TopLabel(AParent: TWinControl; const AText: string; ATop, AHeight: Integer): TLabel;
    function FooterButton(AParent: TWinControl; const AText: string; AWidth: Integer;
      AIcon: TSuiteIconKind; AStyle: TSuiteButtonStyle): TSuiteButton;
    procedure NavClick(Sender: TObject);
    procedure ShowStep(N: Integer);
  public
    constructor Create(AOwner: TComponent); override;
  end;

const
  MR_STEPS: array[0..5] of string = ('1  Material', '2  Desenho', '3  Relevo',
    '4  Percursos', '5  Simular', '6  Saida');

implementation

const
  STEP_ICONS: array[0..5] of TSuiteIconKind = (sikRect, sikPen, sikLayers,
    sikMakeRouter, sikPlay, sikExport);
  STEP_TEXT: array[0..5] of string = (
    'Tamanho e espessura do material e ponto de zero: um dos 9 pontos em XY (cantos, meios de borda ou centro) e Z no topo do material ou na mesa. O G-code sai relativo a esse zero virtual; no MultiCNC voce leva a ferramenta ao ponto, usa Zero Workpiece e confere com Frame (Test).',
    'Vetores: retangulo, circulo, elipse, poligono, estrela, arco, polilinha, curva e texto. Importacao de DXF e SVG. Mover, girar, espelhar, alinhar, soldar, subtrair, offset e camadas.',
    'Relevo como mapa de alturas: domo, rampa, extrusao, revolucao, imagem em tons de cinza e STL, combinados por somar, subtrair, maximo e minimo.',
    'Lista de percursos com ferramenta e profundidades: perfil (fora, dentro, na linha, com pontes e rampa), bolsao, furacao, gravacao, V-Carve, desbaste 3D e acabamento 3D.',
    'Simulacao da remocao de material em 3D com textura de madeira, tempo estimado e alertas de colisao e de mergulho rapido no material.',
    'Validacao e G-code GRBL com o cabecalho da suite (zero, material e caixa do trabalho): um arquivo por ferramenta ou unico com pausa M0. Abrir no MultiCNC em modo CNC Router.');

function TMakeRouterForm.LabelAt(AParent: TWinControl; const AText: string;
  X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.WordWrap := True;
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

{ rotulo que ocupa a largura do cartao (alTop), sem estourar a direita }
function TMakeRouterForm.TopLabel(AParent: TWinControl; const AText: string;
  ATop, AHeight: Integer): TLabel;
begin
  Result := LabelAt(AParent, AText, 0, ATop, 100, AHeight);
  Result.Align := alTop;
  Result.BorderSpacing.Left := 24;
  Result.BorderSpacing.Right := 24;
  Result.BorderSpacing.Top := 8;
end;

function TMakeRouterForm.FooterButton(AParent: TWinControl; const AText: string;
  AWidth: Integer; AIcon: TSuiteIconKind; AStyle: TSuiteButtonStyle): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.Width := AWidth;
  Result.Align := alRight;
  Result.BorderSpacing.Top := 15;
  Result.BorderSpacing.Bottom := 17;
  Result.BorderSpacing.Right := 12;
  Result.Caption := AText;
  Result.SetLook(AStyle, clSuitePrimary, AIcon);
  Result.Enabled := False;
end;

constructor TMakeRouterForm.Create(AOwner: TComponent);
var
  Header: TSuiteHeader;
  Sidebar, Work, Card, Footer: TPanel;
  I: Integer;
  B: TSuiteButton;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MakeRouter • MultiSuite';
  Width := 1100; Height := 720;
  Constraints.MinWidth := 900; Constraints.MinHeight := 600;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('MakeRouter', 'Projeto e usinagem de madeira  /  MultiSuite', sikMakeRouter);

  Footer := TPanel.Create(Self);
  Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 66;
  Footer.BevelOuter := bvNone; Footer.Color := clSuiteCard;
  LabelAt(Footer, 'Em desenvolvimento: esta versao ainda nao gera percursos nem G-code.',
    18, 22, 520, 24);
  { botoes a direita (alRight: o mais a direita e criado primeiro) }
  B := FooterButton(Footer, 'Abrir no MultiCNC', 222, sikSend, sbsSoft);
  B := FooterButton(Footer, 'Gerar G-code', 160, sikExport, sbsSolid);
  B := FooterButton(Footer, 'Validar', 130, sikTests, sbsSoft);

  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self; Sidebar.Align := alLeft; Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone; Sidebar.Color := clSuiteCard;
  for I := 0 to 5 do
  begin
    Nav[I] := TSuiteButton.Create(Self);
    Nav[I].Parent := Sidebar;
    Nav[I].SetBounds(12, 16 + I * 44, 190, 34);
    Nav[I].Caption := MR_STEPS[I];
    Nav[I].SetLook(sbsSoft, clSuitePrimary, STEP_ICONS[I]);
    Nav[I].Tag := I;
    Nav[I].OnClick := @NavClick;
  end;

  Work := TPanel.Create(Self);
  Work.Parent := Self; Work.Align := alClient;
  Work.BevelOuter := bvNone; Work.Color := clSuiteSurface;
  Work.BorderSpacing.Around := 24;

  Card := TPanel.Create(Self);
  Card.Parent := Work; Card.Align := alTop; Card.Height := 360;
  Card.BevelOuter := bvNone; Card.Color := clSuiteCard;

  { cartao de cima para baixo (alTop na ordem de criacao inversa ao Top) }
  TopLabel(Card, 'Projeto e decisoes: makerouter/docs/TAREFA.md. Contrato de G-code: docs/CONTRATO_GCODE.md.',
    300, 44).Top := 300;
  TopLabel(Card, 'Fluxo: MakeRouter (desenho, relevo e percursos) gera o G-code com zero virtual; o MultiCNC posiciona a peca na mesa e executa.',
    240, 50).Top := 240;
  StepText := TopLabel(Card, '', 110, 120);
  StepText.Top := 110;
  StepTitle := TopLabel(Card, '', 70, 32);
  StepTitle.Top := 70;
  StepTitle.Font.Style := [fsBold]; StepTitle.Font.Size := 14;
  StepTitle.Font.Color := clSuiteText;

  State := TSuiteBadge.Create(Self);
  State.Parent := Card; State.SetBounds(24, 20, 230, 32);
  State.Caption := 'Em analise / desenvolvimento';
  State.DotColor := clSuiteWarning;
  State.Align := alTop;
  State.BorderSpacing.Left := 24; State.BorderSpacing.Top := 20;
  State.Constraints.MaxWidth := 254;
  State.Top := 0;

  ShowStep(0);
end;

procedure TMakeRouterForm.NavClick(Sender: TObject);
begin
  ShowStep(TSuiteButton(Sender).Tag);
end;

procedure TMakeRouterForm.ShowStep(N: Integer);
var
  I: Integer;
begin
  for I := 0 to 5 do
    if I = N then Nav[I].SetLook(sbsSolid, clSuitePrimary)
    else Nav[I].SetLook(sbsSoft, clSuitePrimary);
  StepTitle.Caption := Trim(Copy(MR_STEPS[N], 4, MaxInt)) + ' (previsto)';
  StepText.Caption := STEP_TEXT[N];
end;

end.
