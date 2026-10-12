unit multicad_sketchtextdlg;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  multicad_types, multicad_document, multicad_sketchtext;
type
  TCadSketchTextDialog = class(TForm)
  private
    FDoc: TCadDocument;
    FText: TMemo;
    FFont, FAlign: TComboBox;
    FHeight, FX, FY, FAngle: TEdit;
    FBold, FItalic: TCheckBox;
    FError: TLabel;
    FPreview: TPaintBox;
    FReady: Boolean;
    procedure Change(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure Accept(Sender: TObject);
    function ReadSettings: Boolean;
    procedure Field(var E: TEdit; const AName, Title, Value: string; X,Y,W: Integer);
    procedure LabelAt(const Title: string; X,Y,W: Integer);
  public
    Settings: TCadTextSettings;
    Contours: TCadTextContours;
    constructor CreateText(AOwner: TComponent; ADoc: TCadDocument; const Origin: TCadVec2);
  end;
implementation
uses multicad_fontoutlines, multicad_sketch;
procedure TCadSketchTextDialog.LabelAt(const Title: string; X,Y,W: Integer);
var L:TLabel;
begin L:=TLabel.Create(Self);L.Parent:=Self;L.Caption:=Title;L.SetBounds(X,Y,W,20);end;
procedure TCadSketchTextDialog.Field(var E:TEdit;const AName,Title,Value:string;X,Y,W:Integer);
begin
  LabelAt(Title,X,Y,W);E:=TEdit.Create(Self);E.Parent:=Self;E.Name:=AName;
  E.SetBounds(X,Y+22,W,28);E.Text:=Value;E.OnChange:=@Change;
end;
constructor TCadSketchTextDialog.CreateText(AOwner:TComponent;ADoc:TCadDocument;const Origin:TCadVec2);
var B:TButton;L:TLabel;Panel:TPanel;I:Integer;
begin
  inherited CreateNew(AOwner);Name:='SketchTextDialog';Caption:='Texto do esboço';
  FDoc:=ADoc;Settings:=DefaultSketchText;Settings.Origin:=Origin;
  Position:=poOwnerFormCenter;BorderStyle:=bsDialog;ClientWidth:=760;ClientHeight:=580;
  LabelAt('Texto',16,12,320);
  FText:=TMemo.Create(Self);FText.Parent:=Self;FText.Name:='TextContent';
  FText.Text:='';
  FText.SetBounds(16,36,320,104);FText.ScrollBars:=ssVertical;FText.OnChange:=@Change;
  LabelAt('Fonte',16,152,320);FFont:=TComboBox.Create(Self);FFont.Parent:=Self;
  FFont.Name:='TextFont';FFont.SetBounds(16,174,320,28);FFont.Style:=csDropDownList;
  for I:=0 to Screen.Fonts.Count-1 do
    if (Screen.Fonts[I]<>'') and (Screen.Fonts[I][1]<>'@') then FFont.Items.Add(Screen.Fonts[I]);
  FFont.ItemIndex:=FFont.Items.IndexOf(Settings.FontName);
  if FFont.ItemIndex<0 then FFont.ItemIndex:=FFont.Items.IndexOf('DejaVu Sans');
  if (FFont.ItemIndex<0) and (FFont.Items.Count>0) then FFont.ItemIndex:=0;
  FFont.OnChange:=@Change;
  Field(FHeight,'TextHeight','Altura da letra H (mm)','10',16,216,150);
  Field(FAngle,'TextAngle','Ângulo (graus)','0',186,216,150);
  FBold:=TCheckBox.Create(Self);FBold.Parent:=Self;FBold.Name:='TextBold';
  FBold.Caption:='Negrito';FBold.SetBounds(16,280,140,26);FBold.OnChange:=@Change;
  FItalic:=TCheckBox.Create(Self);FItalic.Parent:=Self;FItalic.Name:='TextItalic';
  FItalic.Caption:='Itálico';FItalic.SetBounds(186,280,140,26);FItalic.OnChange:=@Change;
  Field(FX,'TextX','Base X (mm)',FormatFloat('0.###',Origin.X),16,320,150);
  Field(FY,'TextY','Base Y (mm)',FormatFloat('0.###',Origin.Y),186,320,150);
  LabelAt('Alinhamento na base',16,384,320);FAlign:=TComboBox.Create(Self);FAlign.Parent:=Self;
  FAlign.Name:='TextAlignment';FAlign.SetBounds(16,406,320,28);FAlign.Style:=csDropDownList;
  FAlign.Items.Add('Esquerda');FAlign.Items.Add('Centro');FAlign.Items.Add('Direita');FAlign.ItemIndex:=0;
  FAlign.OnChange:=@Change;
  LabelAt('Prévia dos contornos',356,12,388);
  Panel:=TPanel.Create(Self);Panel.Parent:=Self;Panel.SetBounds(356,36,388,398);Panel.BevelOuter:=bvLowered;
  FPreview:=TPaintBox.Create(Self);FPreview.Parent:=Panel;FPreview.Name:='TextPreview';FPreview.Align:=alClient;
  FPreview.OnPaint:=@PaintPreview;
  L:=TLabel.Create(Self);L.Parent:=Self;L.AutoSize:=False;L.SetBounds(16,448,728,46);L.WordWrap:=True;
  L.Caption:='O texto será convertido em contornos fechados do esboço, para extrusão ou corte. Depois de criar, você pode editar os segmentos. Para trocar o texto ou a fonte, desfaça e crie novamente.';
  FError:=TLabel.Create(Self);FError.Parent:=Self;FError.Name:='TextError';FError.AutoSize:=False;FError.SetBounds(16,498,728,38);
  FError.WordWrap:=True;FError.Font.Color:=clRed;
  B:=TButton.Create(Self);B.Parent:=Self;B.Name:='TextOK';B.Caption:='Criar contornos';
  B.SetBounds(480,540,132,30);B.Default:=True;B.OnClick:=@Accept;
  B:=TButton.Create(Self);B.Parent:=Self;B.Name:='TextCancel';B.Caption:='Cancelar';
  B.SetBounds(624,540,120,30);B.Cancel:=True;B.ModalResult:=mrCancel;
  ActiveControl:=FText;FReady:=True;Change(nil);
end;
function TCadSketchTextDialog.ReadSettings:Boolean;
var Error:string;
  function Number(E:TEdit;out V:Double):Boolean;
  begin Result:=FDoc.Eval(E.Text,V,Error);end;
begin
  Result:=False;Error:='';Settings.Text:=FText.Text;Settings.FontName:=FFont.Text;
  Settings.Bold:=FBold.Checked;Settings.Italic:=FItalic.Checked;
  Settings.Alignment:=TCadTextAlignment(Max(0,FAlign.ItemIndex));
  if Number(FHeight,Settings.Height) and Number(FX,Settings.Origin.X) and
    Number(FY,Settings.Origin.Y) and Number(FAngle,Settings.Angle) then Error:=ValidateSketchText(Settings);
  FError.Caption:=Error;Result:=Error='';
end;
procedure TCadSketchTextDialog.Change(Sender:TObject);
var Error:string;
begin
  if not FReady then Exit;Contours:=nil;
  if ReadSettings then begin CadFontOutlines(Settings,Contours,Error);FError.Caption:=Error;end;
  FPreview.Invalidate;
end;
procedure TCadSketchTextDialog.PaintPreview(Sender:TObject);
var C:TCanvas;I,J,X1,Y1,X2,Y2:Integer;MinX,MinY,MaxX,MaxY,Scale,OffX,OffY:Double;P:TCadVec2;
  function ScreenPoint(const V:TCadVec2):TPoint;
  begin
    Result:=Point(Round(OffX+(V.X-MinX)*Scale),Round(FPreview.Height-OffY-(V.Y-MinY)*Scale));
  end;
var A,B:TPoint;
begin
  C:=FPreview.Canvas;C.Brush.Color:=clWhite;C.FillRect(FPreview.ClientRect);
  if Length(Contours)=0 then begin C.Font.Color:=clGray;C.TextOut(20,20,'Digite o texto para ver a prévia.');Exit;end;
  MinX:=Settings.Origin.X;MaxX:=MinX;MinY:=Settings.Origin.Y;MaxY:=MinY;
  for I:=0 to High(Contours) do for J:=0 to High(Contours[I]) do begin
    P:=Contours[I][J];MinX:=Min(MinX,P.X);MaxX:=Max(MaxX,P.X);MinY:=Min(MinY,P.Y);MaxY:=Max(MaxY,P.Y);
  end;
  Scale:=Min((FPreview.Width-40)/Max(0.01,MaxX-MinX),(FPreview.Height-40)/Max(0.01,MaxY-MinY));
  OffX:=(FPreview.Width-(MaxX-MinX)*Scale)/2;OffY:=(FPreview.Height-(MaxY-MinY)*Scale)/2;
  C.Pen.Color:=clNavy;C.Pen.Width:=1;
  for I:=0 to High(Contours) do for J:=0 to High(Contours[I]) do begin
    A:=ScreenPoint(Contours[I][J]);B:=ScreenPoint(Contours[I][(J+1) mod Length(Contours[I])]);C.Line(A,B);
  end;
  A:=ScreenPoint(Settings.Origin);X1:=A.X-5;X2:=A.X+5;Y1:=A.Y-5;Y2:=A.Y+5;
  C.Pen.Color:=clRed;C.Line(X1,A.Y,X2,A.Y);C.Line(A.X,Y1,A.X,Y2);
end;
procedure TCadSketchTextDialog.Accept(Sender:TObject);
var T:TCadSketch;Ids:TCadIdArray;Error:string;
begin
  Change(nil);if FError.Caption<>'' then Exit;
  T:=TCadSketch.Create;
  try
    if not CadInsertSketchText(T,Contours,Ids,Error) then begin FError.Caption:=Error;Exit;end;
  finally T.Free;end;
  ModalResult:=mrOK;
end;
end.
