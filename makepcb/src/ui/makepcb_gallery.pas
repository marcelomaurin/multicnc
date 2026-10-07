unit makepcb_gallery;

{ Galeria de componentes do MakePCB (como o "PCB Component Gallery" do
  PCB Wizard): miniaturas em duas colunas, filtradas por categoria e por
  texto. As miniaturas sao desenhadas pelo proprio renderizador da placa,
  na vista Mundo real, e guardadas em cache. Clique escolhe o footprint. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, Forms,
  makepcb_model, makepcb_library, makepcb_render;

type
  TMPPickEvent = procedure(Sender: TObject; FP: TMPFootprint) of object;

  TMPGallery = class(TCustomControl)
  private
    FLib: TMPLibrary;
    FItems: TList;
    FCategory, FFilter: string;
    FSelected, FHot: Integer;
    FCache: array of TBitmap;
    FCacheFP: TList;
    FRender: TMPRenderer;
    FOnPick: TMPPickEvent;
    FCols: Integer;
    procedure Rebuild;
    procedure SetCategory(const AValue: string);
    procedure SetFilter(const AValue: string);
    procedure SetLib(AValue: TMPLibrary);
    function TileRect(I: Integer): TRect;
    function IndexAt(X, Y: Integer): Integer;
    function Thumb(FP: TMPFootprint): TBitmap;
    function GetSelectedFootprint: TMPFootprint;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function NeededHeight: Integer;
    procedure ClearSelection;
    { refaz miniaturas e lista (footprint editado ou biblioteca mudou) }
    procedure Reload;
    property Lib: TMPLibrary read FLib write SetLib;
    property Category: string read FCategory write SetCategory;
    property Filter: string read FFilter write SetFilter;
    property SelectedFootprint: TMPFootprint read GetSelectedFootprint;
    property OnPick: TMPPickEvent read FOnPick write FOnPick;
  end;

implementation

uses multisuite_controls;

const
  TILE_H = 104;
  GAP = 8;

constructor TMPGallery.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList.Create;
  FCacheFP := TList.Create;
  FRender := TMPRenderer.Create;
  FSelected := -1; FHot := -1;
  FCols := 2;
  Color := clSuiteCard;
  DoubleBuffered := True;
end;

destructor TMPGallery.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FCache) do FCache[I].Free;
  FCacheFP.Free;
  FItems.Free;
  FRender.Free;
  inherited Destroy;
end;

procedure TMPGallery.SetLib(AValue: TMPLibrary);
begin
  FLib := AValue;
  Rebuild;
end;

procedure TMPGallery.SetCategory(const AValue: string);
begin
  FCategory := AValue;
  Rebuild;
end;

procedure TMPGallery.SetFilter(const AValue: string);
begin
  FFilter := AValue;
  Rebuild;
end;

procedure TMPGallery.Rebuild;
var
  I: Integer;
  FP: TMPFootprint;
  F: string;
begin
  FItems.Clear;
  FSelected := -1; FHot := -1;
  if FLib <> nil then
  begin
    F := LowerCase(Trim(FFilter));
    for I := 0 to FLib.Count - 1 do
    begin
      FP := FLib.Item(I);
      if (FCategory <> '') and not SameText(FP.Category, FCategory) then Continue;
      if (F <> '') and (Pos(F, LowerCase(FP.Name + ' ' + FP.Description + ' ' + FP.DefaultValue)) = 0) then Continue;
      FItems.Add(FP);
    end;
  end;
  Height := NeededHeight;
  Invalidate;
end;

function TMPGallery.NeededHeight: Integer;
begin
  Result := GAP + ((FItems.Count + FCols - 1) div FCols) * (TILE_H + GAP);
  Result := Max(Result, 40);
end;

function TMPGallery.TileRect(I: Integer): TRect;
var
  W, C, R: Integer;
begin
  W := (ClientWidth - GAP * (FCols + 1)) div FCols;
  C := I mod FCols; R := I div FCols;
  Result := Rect(GAP + C * (W + GAP), GAP + R * (TILE_H + GAP), 0, 0);
  Result.Right := Result.Left + W;
  Result.Bottom := Result.Top + TILE_H;
end;

function TMPGallery.IndexAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if PtInRect(TileRect(I), Point(X, Y)) then Exit(I);
  Result := -1;
end;

function TMPGallery.Thumb(FP: TMPFootprint): TBitmap;
var
  I: Integer;
  W: Integer;
begin
  W := Max(40, (ClientWidth - GAP * (FCols + 1)) div FCols - 8);
  I := FCacheFP.IndexOf(FP);
  if (I >= 0) and (FCache[I].Width = W) then Exit(FCache[I]);
  if I < 0 then
  begin
    I := FCacheFP.Add(FP);
    SetLength(FCache, FCacheFP.Count);
    FCache[I] := TBitmap.Create;
  end;
  Result := FCache[I];
  Result.SetSize(W, TILE_H - 30);
  FRender.PaintFootprint(Result.Canvas, FP, Rect(0, 0, W, TILE_H - 30), vmRealWorld);
end;

procedure TMPGallery.Paint;
var
  I: Integer;
  R: TRect;
  FP: TMPFootprint;
  S: string;
begin
  Canvas.Brush.Color := clSuiteCard;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Name := SUITE_FONT;
  for I := 0 to FItems.Count - 1 do
  begin
    FP := TMPFootprint(FItems[I]);
    R := TileRect(I);
    Canvas.Pen.Width := 1;
    if I = FSelected then
    begin
      Canvas.Brush.Color := TColor($FFF1E3);
      Canvas.Pen.Color := clSuitePrimary;
      Canvas.Pen.Width := 2;
    end
    else if I = FHot then
    begin
      Canvas.Brush.Color := TColor($FBF8F6);
      Canvas.Pen.Color := clSuitePrimary;
    end
    else
    begin
      Canvas.Brush.Color := TColor($FBF8F6);
      Canvas.Pen.Color := clSuiteBorder;
    end;
    Canvas.RoundRect(R, 10, 10);
    Canvas.Draw(R.Left + 4, R.Top + 4, Thumb(FP));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Size := 8;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := clSuiteText;
    S := FP.Name;
    while (Canvas.TextWidth(S) > R.Right - R.Left - 8) and (Length(S) > 3) do
      S := Copy(S, 1, Length(S) - 2) + '.';
    Canvas.TextOut(R.Left + (R.Right - R.Left - Canvas.TextWidth(S)) div 2, R.Bottom - 24, S);
    Canvas.Font.Style := [];
    Canvas.Font.Size := 7;
    Canvas.Font.Color := clSuiteMuted;
    S := FP.DefaultValue;
    if S = '' then S := FP.Category;
    Canvas.TextOut(R.Left + (R.Right - R.Left - Canvas.TextWidth(S)) div 2, R.Bottom - 12, S);
    Canvas.Brush.Style := bsSolid;
  end;
  if FItems.Count = 0 then
  begin
    Canvas.Font.Color := clSuiteMuted;
    Canvas.TextOut(GAP, GAP, 'Nenhum componente.');
  end;
end;

procedure TMPGallery.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TMPGallery.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  I := IndexAt(X, Y);
  if I < 0 then Exit;
  FSelected := I;
  Invalidate;
  if Assigned(FOnPick) then FOnPick(Self, TMPFootprint(FItems[I]));
end;

procedure TMPGallery.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  I := IndexAt(X, Y);
  if I <> FHot then
  begin
    FHot := I;
    if I >= 0 then Hint := TMPFootprint(FItems[I]).Description else Hint := '';
    Invalidate;
  end;
end;

procedure TMPGallery.MouseLeave;
begin
  inherited MouseLeave;
  FHot := -1;
  Invalidate;
end;

procedure TMPGallery.Reload;
var
  I: Integer;
begin
  for I := 0 to High(FCache) do FCache[I].Free;
  SetLength(FCache, 0);
  FCacheFP.Clear;
  Rebuild;
end;

procedure TMPGallery.ClearSelection;
begin
  FSelected := -1;
  Invalidate;
end;

function TMPGallery.GetSelectedFootprint: TMPFootprint;
begin
  if (FSelected >= 0) and (FSelected < FItems.Count) then Result := TMPFootprint(FItems[FSelected])
  else Result := nil;
end;

end.
