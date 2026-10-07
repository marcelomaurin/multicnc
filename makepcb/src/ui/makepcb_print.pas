unit makepcb_print;

{ Impressao direta da arte final do MakePCB, em escala 1:1.

  A escala vem dos DPI da impressora (Printer.XDPI/YDPI). Escolhe a face
  (cobre de baixo, de cima ou serigrafia), espelhamento (transferencia
  termica da face de cima) e quantas copias por folha. A previa mostra a
  folha com as copias; nada e impresso sem clicar em Imprimir.
  Dica de calibracao: imprima, meca a placa com um paquimetro e confira
  com o tamanho mostrado. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Graphics,
  Printers, OSPrinters, PrintersDlgs, makepcb_model, makepcb_render, makepcb_printlayout,
  multisuite_controls, multisuite_icons;

type
  TMPPrintForm = class(TForm)
  private
    FDoc: TMPDocument;
    Preview: TPaintBox;
    LayerBox: TComboBox;
    MirrorBox, OutlineBox: TCheckBox;
    CopiesEdit, GapEdit, MarginEdit: TEdit;
    Info, PrinterLabel: TLabel;
    PrintButton: TSuiteButton;
    FooterPanel: TPanel;
    CloseButton: TSuiteButton;
    function Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function Field(AParent: TWinControl; const AText, Value: string; Y: Integer): TEdit;
    function Options: TMPPrintOptions;
    procedure PageSizeMM(out W, H, DpiX, DpiY: Double);
    function HasPrinter: Boolean;
    procedure Changed(Sender: TObject);
    procedure PreviewPaint(Sender: TObject);
    procedure SetupClick(Sender: TObject);
    procedure PrintClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure FormResized(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; ADoc: TMPDocument; DefaultLayer: TMPLayer; DefaultMirror: Boolean);
  end;

{ desenha as copias numa folha (impressora ou previa); Scale = pixels por mm }
procedure MPPaintSheet(Canvas: TCanvas; Doc: TMPDocument; const O: TMPPrintOptions;
  const Tiles: TMPTiles; OffX, OffY, ScaleX, ScaleY: Double);

implementation

uses multisuite_numfmt;

const
  A4_W = 210;
  A4_H = 297;

procedure MPPaintSheet(Canvas: TCanvas; Doc: TMPDocument; const O: TMPPrintOptions;
  const Tiles: TMPTiles; OffX, OffY, ScaleX, ScaleY: Double);
var
  R: TMPRenderer;
  V: TMPViewport;
  I: Integer;
  Rc: TRect;
begin
  R := TMPRenderer.Create;
  try
    R.Doc := Doc;
    R.Mode := vmArtwork;
    R.ArtworkLayer := O.Layer;
    R.ArtworkMirror := O.Mirror;
    R.ShowOutline := O.Outline;
    { a arte usa uma escala so; impressoras tem DPI X = Y quase sempre }
    V.Scale := Min(ScaleX, ScaleY);
    for I := 0 to High(Tiles) do
    begin
      V.OX := OffX + Tiles[I].Left * ScaleX;
      V.OY := OffY + (Tiles[I].Top + Doc.BoardH) * ScaleY;
      Rc := Rect(Round(V.OX), Round(OffY + Tiles[I].Top * ScaleY),
        Round(V.OX + Doc.BoardW * V.Scale) + 1, Round(V.OY) + 1);
      R.Paint(Canvas, V, Rc);
    end;
  finally
    R.Free;
  end;
end;

{ ---------------- formulario ---------------- }

function TMPPrintForm.Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
  AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TMPPrintForm.Field(AParent: TWinControl; const AText, Value: string; Y: Integer): TEdit;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := AParent; L.SetBounds(16, Y, 260, 18); L.Caption := AText; L.Font.Color := clSuiteMuted;
  Result := TEdit.Create(Self);
  Result.Parent := AParent; Result.SetBounds(16, Y + 20, 260, 28);
  Result.Text := Value;
  Result.OnChange := @Changed;
end;

constructor TMPPrintForm.CreateFor(AOwner: TComponent; ADoc: TMPDocument; DefaultLayer: TMPLayer;
  DefaultMirror: Boolean);
var
  Header: TSuiteHeader;
  Right, Footer: TPanel;
  L: TLabel;
begin
  inherited CreateNew(AOwner, 1);
  FDoc := ADoc;
  Caption := 'Imprimir arte final • MakePCB';
  Width := 980; Height := 720; Position := poOwnerFormCenter;
  Font.Name := SUITE_FONT; Font.Size := 10; Color := clSuiteSurface;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 64;
  Header.Setup('Imprimir arte final', 'Escala 1:1  /  transferencia termica ou fotolito', sikImage);

  Footer := TPanel.Create(Self);
  Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 60;
  Footer.BevelOuter := bvNone; Footer.Color := clSuiteCard;
  FooterPanel := Footer;
  Info := TLabel.Create(Self);
  Info.Parent := Footer; Info.AutoSize := False; Info.SetBounds(18, 10, 540, 42);
  Info.WordWrap := True; Info.Font.Color := clSuiteMuted;
  CloseButton := Button(Footer, 'Fechar', 0, 13, 130, sikClose, @CloseClick);
  PrintButton := Button(Footer, 'Imprimir', 0, 13, 160, sikExport, @PrintClick);
  PrintButton.SetLook(sbsSolid, clSuitePrimary, sikExport);

  Right := TPanel.Create(Self);
  Right.Parent := Self; Right.Align := alRight; Right.Width := 292;
  Right.BevelOuter := bvNone; Right.Color := clSuiteCard;
  L := TLabel.Create(Self);
  L.Parent := Right; L.SetBounds(16, 12, 260, 18); L.Caption := 'Face'; L.Font.Color := clSuiteMuted;
  LayerBox := TComboBox.Create(Self);
  LayerBox.Parent := Right; LayerBox.SetBounds(16, 32, 260, 30); LayerBox.Style := csDropDownList;
  LayerBox.Items.Add('Cobre de baixo (Bottom)');
  LayerBox.Items.Add('Cobre de cima (Top)');
  LayerBox.Items.Add('Serigrafia (componentes)');
  case DefaultLayer of
    mlTopCopper: LayerBox.ItemIndex := 1;
    mlTopSilk: LayerBox.ItemIndex := 2;
  else LayerBox.ItemIndex := 0;
  end;
  LayerBox.OnChange := @Changed;
  MirrorBox := TCheckBox.Create(Self);
  MirrorBox.Parent := Right; MirrorBox.SetBounds(16, 72, 260, 24);
  MirrorBox.Caption := 'Espelhar'; MirrorBox.Checked := DefaultMirror; MirrorBox.OnChange := @Changed;
  OutlineBox := TCheckBox.Create(Self);
  OutlineBox.Parent := Right; OutlineBox.SetBounds(16, 98, 260, 24);
  OutlineBox.Caption := 'Contorno da placa'; OutlineBox.Checked := True; OutlineBox.OnChange := @Changed;
  CopiesEdit := Field(Right, 'Copias (0 = encher a folha)', '1', 132);
  GapEdit := Field(Right, 'Espaco entre copias (mm)', '5', 188);
  MarginEdit := Field(Right, 'Margem (mm)', '5', 244);
  Button(Right, 'Impressora...', 16, 306, 260, sikGear, @SetupClick);
  PrinterLabel := TLabel.Create(Self);
  PrinterLabel.Parent := Right; PrinterLabel.AutoSize := False; PrinterLabel.SetBounds(16, 346, 260, 40);
  PrinterLabel.WordWrap := True; PrinterLabel.Font.Color := clSuiteMuted;
  L := TLabel.Create(Self);
  L.Parent := Right; L.AutoSize := False; L.SetBounds(16, 396, 260, 150); L.WordWrap := True;
  L.Font.Color := clSuiteMuted;
  L.Caption := 'Transferencia termica: o cobre de baixo sai como visto de cima (sem espelhar) e o de cima, espelhado. ' +
    'Use impressora laser, sem "ajustar a pagina", e confira a medida da placa com um paquimetro.';

  Preview := TPaintBox.Create(Self);
  Preview.Parent := Self; Preview.Align := alClient;
  Preview.OnPaint := @PreviewPaint;
  OnResize := @FormResized;
  FormResized(nil);
  Changed(nil);
end;

procedure TMPPrintForm.FormResized(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  PrintButton.Left := FooterPanel.ClientWidth - PrintButton.Width - 18;
  CloseButton.Left := PrintButton.Left - CloseButton.Width - 10;
  Info.Width := Max(100, CloseButton.Left - 30);
end;

function TMPPrintForm.HasPrinter: Boolean;
begin
  try
    Result := Printer.Printers.Count > 0;
  except
    Result := False;
  end;
end;

procedure TMPPrintForm.PageSizeMM(out W, H, DpiX, DpiY: Double);
begin
  W := A4_W; H := A4_H; DpiX := 300; DpiY := 300;
  if not HasPrinter then Exit;
  try
    DpiX := Printer.XDPI; DpiY := Printer.YDPI;
    if (DpiX > 0) and (DpiY > 0) then
    begin
      W := Printer.PageWidth / DpiX * 25.4;
      H := Printer.PageHeight / DpiY * 25.4;
    end;
  except
    W := A4_W; H := A4_H;
  end;
end;

function TMPPrintForm.Options: TMPPrintOptions;
var
  V: Double;
  N: Integer;
begin
  Result := MPDefaultPrintOptions;
  case LayerBox.ItemIndex of
    1: Result.Layer := mlTopCopper;
    2: Result.Layer := mlTopSilk;
  else Result.Layer := mlBottomCopper;
  end;
  Result.Mirror := MirrorBox.Checked;
  Result.Outline := OutlineBox.Checked;
  if TryStrToInt(Trim(CopiesEdit.Text), N) then Result.Copies := EnsureRange(N, 0, 100);
  if TryParseFloat(GapEdit.Text, V) then Result.Gap := EnsureRange(V, 0, 50);
  if TryParseFloat(MarginEdit.Text, V) then Result.Margin := EnsureRange(V, 0, 50);
end;

procedure TMPPrintForm.Changed(Sender: TObject);
var
  W, H, DX, DY: Double;
  T: TMPTiles;
  FS: TFormatSettings;
begin
  PageSizeMM(W, H, DX, DY);
  T := MPTileCopies(W, H, FDoc.BoardW, FDoc.BoardH, Options);
  FS := DefaultFormatSettings; FS.DecimalSeparator := ',';
  if HasPrinter then
    PrinterLabel.Caption := Format('%s'#10'%.0f x %.0f mm, %.0f dpi', [Printer.PrinterName, W, H, DX], FS)
  else
    PrinterLabel.Caption := 'Nenhuma impressora instalada (previa em A4).';
  if Length(T) = 0 then
    Info.Caption := 'A placa nao cabe na folha com essa margem.'
  else
    Info.Caption := Format('%d copia(s) de %.1f x %.1f mm por folha, escala 1:1.',
      [Length(T), FDoc.BoardW, FDoc.BoardH], FS);
  PrintButton.Enabled := HasPrinter and (Length(T) > 0);
  Preview.Invalidate;
end;

procedure TMPPrintForm.PreviewPaint(Sender: TObject);
var
  W, H, DX, DY, S, OX, OY: Double;
  T: TMPTiles;
  Page: TRect;
begin
  PageSizeMM(W, H, DX, DY);
  Preview.Canvas.Brush.Color := TColor($E9E4DE);
  Preview.Canvas.FillRect(0, 0, Preview.Width, Preview.Height);
  S := Min((Preview.Width - 40) / W, (Preview.Height - 40) / H);
  OX := (Preview.Width - W * S) / 2;
  OY := (Preview.Height - H * S) / 2;
  Page := Rect(Round(OX), Round(OY), Round(OX + W * S), Round(OY + H * S));
  Preview.Canvas.Brush.Color := TColor($B4AAA0);
  Preview.Canvas.Pen.Style := psClear;
  Preview.Canvas.Rectangle(Page.Left + 4, Page.Top + 4, Page.Right + 4, Page.Bottom + 4);
  Preview.Canvas.Brush.Color := clWhite;
  Preview.Canvas.Rectangle(Page);
  Preview.Canvas.Pen.Style := psSolid;
  T := MPTileCopies(W, H, FDoc.BoardW, FDoc.BoardH, Options);
  MPPaintSheet(Preview.Canvas, FDoc, Options, T, OX, OY, S, S);
end;

procedure TMPPrintForm.SetupClick(Sender: TObject);
var
  D: TPrinterSetupDialog;
begin
  if not HasPrinter then
  begin
    MessageDlg('MakePCB', 'Nenhuma impressora instalada neste computador.', mtInformation, [mbOK], 0);
    Exit;
  end;
  D := TPrinterSetupDialog.Create(Self);
  try
    if D.Execute then Changed(nil);
  finally
    D.Free;
  end;
end;

procedure TMPPrintForm.PrintClick(Sender: TObject);
var
  W, H, DX, DY: Double;
  T: TMPTiles;
begin
  if not HasPrinter then Exit;
  PageSizeMM(W, H, DX, DY);
  T := MPTileCopies(W, H, FDoc.BoardW, FDoc.BoardH, Options);
  if Length(T) = 0 then Exit;
  Printer.Title := 'MakePCB - ' + FDoc.Name;
  Printer.BeginDoc;
  try
    MPPaintSheet(Printer.Canvas, FDoc, Options, T, 0, 0, DX / 25.4, DY / 25.4);
  finally
    Printer.EndDoc;
  end;
  Info.Caption := 'Enviado para ' + Printer.PrinterName + '.';
end;

procedure TMPPrintForm.CloseClick(Sender: TObject);
begin
  Close;
end;

end.
