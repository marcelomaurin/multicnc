unit multicad_sketchpatterndlg;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, multicad_document,
  multicad_sketchpattern;

type
  TCadSketchPatternDialog = class(TForm)
  private
    FDoc: TCadDocument;
    FEntityCount: Integer;
    FValues: array[0..5] of TEdit;
    FError: TLabel;
    procedure Accept(Sender: TObject);
    procedure Field(Index: Integer; const Title, Value: string);
  public
    Settings: TCadSketchPatternSettings;
    constructor CreatePattern(AOwner: TComponent; ADoc: TCadDocument;
      Kind: TCadSketchPatternKind; EntityCount: Integer);
  end;

implementation

constructor TCadSketchPatternDialog.CreatePattern(AOwner: TComponent;
  ADoc: TCadDocument; Kind: TCadSketchPatternKind; EntityCount: Integer);
var L: TLabel; B: TButton;
begin
  inherited CreateNew(AOwner);Name:='SketchPatternDialog';FDoc:=ADoc;FEntityCount:=EntityCount;
  Settings:=DefaultSketchPattern(Kind);
  Position:=poOwnerFormCenter;BorderStyle:=bsDialog;ClientWidth:=420;ClientHeight:=350;
  if Kind=skpLinear then Caption:='Padrão linear do esboço' else Caption:='Padrão circular do esboço';
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(12,10,396,42);L.WordWrap:=True;
  L.Caption:=Format('%d entidades selecionadas. A quantidade inclui o original; as cópias ficam independentes e editáveis.',[EntityCount]);
  if Kind=skpLinear then begin
    Field(0,'Quantidade em X','3');Field(1,'Espaçamento X (mm)','20');
    Field(2,'Quantidade em Y','1');Field(3,'Espaçamento Y (mm)','20');
  end else begin
    Field(0,'Quantidade','3');Field(1,'Ângulo total (graus)','360');
    Field(2,'Centro X (mm)','0');Field(3,'Centro Y (mm)','0');
  end;
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(12,198,396,42);L.WordWrap:=True;
  if Kind=skpLinear then L.Caption:='X e Y são os eixos do plano do esboço. Use espaçamentos negativos para inverter a direção.'
  else L.Caption:='360° distribui as instâncias na volta completa. Use ângulo negativo para inverter o sentido.';
  FError:=TLabel.Create(Self);FError.Parent:=Self;FError.Name:='PatternError';
  FError.SetBounds(12,244,396,52);FError.WordWrap:=True;
  B:=TButton.Create(Self);B.Parent:=Self;B.Name:='PatternOK';B.Caption:='Criar padrão';
  B.SetBounds(186,308,108,30);B.Default:=True;B.OnClick:=@Accept;
  B:=TButton.Create(Self);B.Parent:=Self;B.Name:='PatternCancel';B.Caption:='Cancelar';
  B.SetBounds(300,308,108,30);B.Cancel:=True;B.ModalResult:=mrCancel;
  ActiveControl:=FValues[0];
end;

procedure TCadSketchPatternDialog.Field(Index: Integer; const Title, Value: string);
var L: TLabel;
begin
  L:=TLabel.Create(Self);L.Parent:=Self;L.Caption:=Title;L.SetBounds(12,60+Index*34,230,24);
  FValues[Index]:=TEdit.Create(Self);FValues[Index].Parent:=Self;
  FValues[Index].Name:='PatternValue'+IntToStr(Index);
  FValues[Index].SetBounds(250,56+Index*34,158,26);FValues[Index].Text:=Value;
end;

procedure TCadSketchPatternDialog.Accept(Sender: TObject);
var P: TCadSketchPatternSettings; Error: string;
  function Number(Index: Integer; out V: Double): Boolean;
  begin Result:=FDoc.Eval(FValues[Index].Text,V,Error);end;
begin
  P:=Settings;Error:='';
  if not TryStrToInt(Trim(FValues[0].Text),P.CountX) then Error:='Informe uma quantidade inteira.'
  else if P.Kind=skpLinear then begin
    if not TryStrToInt(Trim(FValues[2].Text),P.CountY) then Error:='Informe uma quantidade inteira em Y.'
    else if Number(1,P.SpacingX) then Number(3,P.SpacingY);
  end else if Number(1,P.Angle) and Number(2,P.Center.X) then Number(3,P.Center.Y);
  if Error='' then Error:=ValidateSketchPattern(P,FEntityCount);
  FError.Caption:=Error;
  if Error<>'' then Exit;
  Settings:=P;ModalResult:=mrOK;
end;

end.
