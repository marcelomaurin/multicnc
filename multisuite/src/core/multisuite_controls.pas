unit multisuite_controls;

{ Controles visuais compartilhados pela suite MultiSuite.

  TSuiteButton        - botao arredondado com cor, icone e estados
                        (normal, hover, pressionado, foco, desabilitado)
  TSuiteBadge         - "pilula" de estado com ponto colorido
  TSuiteHeader        - faixa de cabecalho em degrade com icone e titulos
  TSuiteSectionTitle  - titulo de secao com icone (ex.: "MANUAL JOG")

  Todos desenham com anti-aliasing via multisuite_icons, sem imagens
  externas. Compativeis com o uso de TButton (Caption, OnClick, Enabled,
  Tag, Hint), de modo que substituir TButton por TSuiteButton nao exige
  mudar a logica dos formularios. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, LazUTF8,
  multisuite_icons;

type
  TSuiteButtonStyle = (sbsSolid, sbsSoft, sbsOutline);

  TSuiteButton = class(TCustomControl)
  private
    FStyle: TSuiteButtonStyle;
    FAccent: TColor;
    FIconKind: TSuiteIconKind;
    FHasIcon: Boolean;
    FHover, FDown: Boolean;
    FRadius: Integer;
    FBackColor: TColor;
    FBg: TBitmap;
    FBgKey: string;
    FIcon: TBitmap;
    FIconKey: string;
    procedure GetColors(out AFill, ABorder, AFore, AIcon: TColor; out ABorderW: Integer);
    function ResolveBack: TColor;
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure EnabledChanged; override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetLook(AStyle: TSuiteButtonStyle; AAccent: TColor); overload;
    procedure SetLook(AStyle: TSuiteButtonStyle; AAccent: TColor; AIcon: TSuiteIconKind); overload;
    procedure ClearIcon;
    procedure Click; override;
    property Caption;
    property Font;
    property ParentFont;
    property OnClick;
    property Style: TSuiteButtonStyle read FStyle;
    property Accent: TColor read FAccent;
    property Radius: Integer read FRadius write FRadius;
    property BackColor: TColor read FBackColor write FBackColor;
  end;

  TSuiteBadge = class(TGraphicControl)
  private
    FDotColor: TColor;
    FFillColor: TColor;
    FTextColor: TColor;
    FBg: TBitmap;
    FBgKey: string;
    FDot: TBitmap;
    FDotKey: string;
    FAnchorRight: Integer;
    procedure SetDotColor(AValue: TColor);
  protected
    procedure Paint; override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AutoFit;
    { mantem a borda direita fixa ao mudar de largura }
    property AnchorRight: Integer read FAnchorRight write FAnchorRight;
    property Caption;
    property Font;
    property DotColor: TColor read FDotColor write SetDotColor;
    property FillColor: TColor read FFillColor write FFillColor;
    property TextColor: TColor read FTextColor write FTextColor;
  end;

  TSuiteHeader = class(TCustomControl)
  private
    FTitle, FSubtitle: string;
    FIconKind: TSuiteIconKind;
    FIcon: TBitmap;
    FColorFrom, FColorTo: TColor;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Setup(const ATitle, ASubtitle: string; AIcon: TSuiteIconKind);
    property OnResize;
  end;

  TSuiteSectionTitle = class(TGraphicControl)
  private
    FIcon: TBitmap;
    FColor: TColor;
  protected
    procedure Paint; override;
  public
    constructor CreateTitle(AOwner: TComponent; const ACaption: string;
      AIcon: TSuiteIconKind; AColor: TColor);
    destructor Destroy; override;
  end;

{ Paleta comum da suite }
function SuiteRGB(R, G, B: Byte): TColor;
function SuiteMix(A, B: TColor; T: Double): TColor;
function SuiteDarken(A: TColor; T: Double): TColor;

const
  SUITE_FONT = {$IFDEF WINDOWS}'Segoe UI'{$ELSE}'default'{$ENDIF};
  SUITE_FONT_SEMIBOLD = {$IFDEF WINDOWS}'Segoe UI Semibold'{$ELSE}'default'{$ENDIF};

var
  { cores semanticas (inicializadas na secao initialization) }
  clSuiteSurface, clSuiteCard, clSuiteText, clSuiteMuted, clSuiteFaint,
  clSuiteBorder, clSuitePrimary, clSuiteSuccess, clSuiteWarning,
  clSuiteDanger, clSuiteInfo, clSuiteNeutral, clSuiteAxisX, clSuiteAxisY,
  clSuiteAxisZ, clSuiteNavy, clSuiteNavy2: TColor;

implementation

function SuiteRGB(R, G, B: Byte): TColor;
begin
  Result := RGBToColor(R, G, B);
end;

function SuiteMix(A, B: TColor; T: Double): TColor;
var
  CA, CB: TColor;
begin
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  Result := RGBToColor(
    Round(Red(CA) * T + Red(CB) * (1 - T)),
    Round(Green(CA) * T + Green(CB) * (1 - T)),
    Round(Blue(CA) * T + Blue(CB) * (1 - T)));
end;

function SuiteDarken(A: TColor; T: Double): TColor;
begin
  Result := SuiteMix(clBlack, A, T);
end;

function MeasureWidth(AFont: TFont; const AText: string): Integer;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.SetSize(4, 4);
    B.Canvas.Font.Assign(AFont);
    Result := B.Canvas.TextWidth(AText);
  finally
    B.Free;
  end;
end;

function Ellipsize(ACanvas: TCanvas; const AText: string; AMax: Integer): string;
var
  N: Integer;
begin
  Result := AText;
  if ACanvas.TextWidth(Result) <= AMax then
    Exit;
  N := UTF8Length(AText);
  while (N > 0) and (ACanvas.TextWidth(UTF8Copy(AText, 1, N) + '…') > AMax) do
    Dec(N);
  Result := UTF8Copy(AText, 1, N) + '…';
end;

{ ---------------------------------------------------------------------------- }
{ TSuiteButton                                                                 }

constructor TSuiteButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStyle := sbsOutline;
  FAccent := clSuitePrimary;
  FRadius := 8;
  FBackColor := clNone;
  TabStop := True;
  Cursor := crHandPoint;
  DoubleBuffered := True;
  SetInitialBounds(0, 0, 100, 34);
end;

destructor TSuiteButton.Destroy;
begin
  FBg.Free;
  FIcon.Free;
  inherited Destroy;
end;

procedure TSuiteButton.SetLook(AStyle: TSuiteButtonStyle; AAccent: TColor);
begin
  if (FStyle = AStyle) and (FAccent = AAccent) then
    Exit;
  FStyle := AStyle;
  FAccent := AAccent;
  Invalidate;
end;

procedure TSuiteButton.SetLook(AStyle: TSuiteButtonStyle; AAccent: TColor;
  AIcon: TSuiteIconKind);
begin
  if (not FHasIcon) or (FIconKind <> AIcon) then
  begin
    FIconKind := AIcon;
    FHasIcon := True;
    FIconKey := '';
    Invalidate;
  end;
  SetLook(AStyle, AAccent);
end;

procedure TSuiteButton.Click;
begin
  inherited Click;
end;

procedure TSuiteButton.ClearIcon;
begin
  FHasIcon := False;
  Invalidate;
end;

function TSuiteButton.ResolveBack: TColor;
begin
  if FBackColor <> clNone then
    Result := ColorToRGB(FBackColor)
  else if Parent <> nil then
    Result := ColorToRGB(Parent.GetRGBColorResolvingParent)
  else
    Result := ColorToRGB(clBtnFace);
end;

procedure TSuiteButton.GetColors(out AFill, ABorder, AFore, AIcon: TColor;
  out ABorderW: Integer);
var
  Active: Boolean;
begin
  ABorderW := 1;
  Active := FHover and not FDown;
  if not Enabled then
  begin
    if FStyle = sbsOutline then
      AFill := SuiteRGB(248, 250, 252)
    else
      AFill := SuiteRGB(237, 241, 246);
    ABorder := SuiteRGB(226, 232, 240);
    AFore := SuiteRGB(148, 163, 184);
    AIcon := SuiteRGB(160, 174, 192);
    Exit;
  end;

  case FStyle of
    sbsSolid:
      begin
        AFill := FAccent;
        if Active then AFill := SuiteDarken(FAccent, 0.10);
        if FDown then AFill := SuiteDarken(FAccent, 0.22);
        ABorder := AFill;
        AFore := clWhite;
        AIcon := clWhite;
      end;
    sbsSoft:
      begin
        AFill := SuiteMix(FAccent, clWhite, 0.12);
        if Active then AFill := SuiteMix(FAccent, clWhite, 0.20);
        if FDown then AFill := SuiteMix(FAccent, clWhite, 0.30);
        ABorder := SuiteMix(FAccent, clWhite, 0.30);
        AFore := SuiteDarken(FAccent, 0.18);
        AIcon := FAccent;
      end;
  else
    begin
      AFill := clWhite;
      if Active then AFill := SuiteRGB(241, 245, 249);
      if FDown then AFill := SuiteRGB(226, 232, 240);
      ABorder := SuiteRGB(203, 213, 225);
      if Active then ABorder := SuiteMix(FAccent, SuiteRGB(203, 213, 225), 0.45);
      AFore := clSuiteText;
      AIcon := FAccent;
    end;
  end;

  if Focused and not FDown then
  begin
    ABorder := SuiteMix(FAccent, clWhite, 0.65);
    ABorderW := 2;
  end;
end;

procedure TSuiteButton.Paint;
var
  Fill, Border, Fore, IconCol: TColor;
  BW, IconSize, Gap, TextW, ContentW, X, Y, Avail: Integer;
  Key, Txt: string;
begin
  GetColors(Fill, Border, Fore, IconCol, BW);

  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ResolveBack;
  Canvas.FillRect(ClientRect);

  Key := Format('%d|%d|%d|%d|%d|%d', [Width, Height, Fill, Border, BW, FRadius]);
  if (FBg = nil) or (Key <> FBgKey) then
  begin
    FreeAndNil(FBg);
    FBg := RenderRoundRect(Width, Height, FRadius, Fill, Border, BW);
    FBgKey := Key;
  end;
  Canvas.Draw(0, 0, FBg);

  if Height >= 32 then
    IconSize := 18
  else
    IconSize := 16;
  if FHasIcon then
  begin
    Key := Format('%d|%d|%d', [Ord(FIconKind), IconCol, IconSize]);
    if (FIcon = nil) or (Key <> FIconKey) then
    begin
      FreeAndNil(FIcon);
      FIcon := RenderSuiteIcon(FIconKind, IconSize, IconCol, sifNone, 2);
      FIconKey := Key;
    end;
  end;

  Canvas.Font.Assign(Font);
  if SUITE_FONT_SEMIBOLD <> 'default' then
    Canvas.Font.Name := SUITE_FONT_SEMIBOLD
  else
    Canvas.Font.Style := [fsBold];
  Canvas.Font.Size := 9;
  Canvas.Font.Color := Fore;
  Canvas.Brush.Style := bsClear;

  Txt := Caption;
  Gap := 0;
  if FHasIcon and (Txt <> '') then
    Gap := 7;
  if Width < 90 then
    Avail := Width - 10
  else
    Avail := Width - 20;
  if FHasIcon then
    Avail := Avail - IconSize - Gap;
  Txt := Ellipsize(Canvas, Txt, Max(10, Avail));
  TextW := 0;
  if Txt <> '' then
    TextW := Canvas.TextWidth(Txt);
  ContentW := TextW;
  if FHasIcon then
    ContentW := ContentW + IconSize + Gap;

  X := (Width - ContentW) div 2;
  if FDown then
    Y := 1
  else
    Y := 0;
  if FHasIcon then
  begin
    Canvas.Draw(X, (Height - IconSize) div 2 + Y, FIcon);
    X := X + IconSize + Gap;
  end;
  if Txt <> '' then
    Canvas.TextOut(X, (Height - Canvas.TextHeight('Ag')) div 2 + Y, Txt);
end;

procedure TSuiteButton.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TSuiteButton.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  FDown := False;
  Invalidate;
end;

procedure TSuiteButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDown := True;
    Invalidate;
  end;
end;

procedure TSuiteButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDown := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TSuiteButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key in [VK_RETURN, VK_SPACE]) and (Shift = []) then
  begin
    Key := 0;
    Click;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TSuiteButton.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TSuiteButton.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TSuiteButton.EnabledChanged;
begin
  inherited EnabledChanged;
  if not Enabled then
  begin
    FHover := False;
    FDown := False;
  end;
  Invalidate;
end;

procedure TSuiteButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

{ ---------------------------------------------------------------------------- }
{ TSuiteBadge                                                                  }

constructor TSuiteBadge.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDotColor := clSuiteNeutral;
  FFillColor := SuiteRGB(30, 41, 59);
  FTextColor := clWhite;
  FAnchorRight := -1;
  SetInitialBounds(0, 0, 140, 30);
end;

destructor TSuiteBadge.Destroy;
begin
  FBg.Free;
  FDot.Free;
  inherited Destroy;
end;

procedure TSuiteBadge.SetDotColor(AValue: TColor);
begin
  if FDotColor = AValue then
    Exit;
  FDotColor := AValue;
  Invalidate;
end;

procedure TSuiteBadge.AutoFit;
var
  F: TFont;
  W: Integer;
begin
  F := TFont.Create;
  try
    F.Assign(Font);
    if SUITE_FONT_SEMIBOLD <> 'default' then
      F.Name := SUITE_FONT_SEMIBOLD
    else
      F.Style := [fsBold];
    F.Size := 9;
    W := 14 + 10 + 8 + MeasureWidth(F, Caption) + 16;
  finally
    F.Free;
  end;
  if FAnchorRight >= 0 then
    SetBounds(FAnchorRight - W, Top, W, Height)
  else
    Width := W;
end;

procedure TSuiteBadge.TextChanged;
begin
  inherited TextChanged;
  AutoFit;
  Invalidate;
end;

procedure TSuiteBadge.Paint;
var
  Key: string;
  X: Integer;
begin
  Key := Format('%d|%d|%d', [Width, Height, FFillColor]);
  if (FBg = nil) or (Key <> FBgKey) then
  begin
    FreeAndNil(FBg);
    FBg := RenderRoundRect(Width, Height, Height div 2, FFillColor,
      SuiteMix(clWhite, FFillColor, 0.12), 1);
    FBgKey := Key;
  end;
  Canvas.Draw(0, 0, FBg);

  Key := IntToStr(FDotColor);
  if (FDot = nil) or (Key <> FDotKey) then
  begin
    FreeAndNil(FDot);
    FDot := RenderRoundRect(10, 10, 5, FDotColor, SuiteMix(clWhite, FDotColor, 0.35), 2);
    FDotKey := Key;
  end;
  X := 14;
  Canvas.Draw(X, (Height - FDot.Height) div 2, FDot);

  Canvas.Font.Assign(Font);
  if SUITE_FONT_SEMIBOLD <> 'default' then
    Canvas.Font.Name := SUITE_FONT_SEMIBOLD
  else
    Canvas.Font.Style := [fsBold];
  Canvas.Font.Size := 9;
  Canvas.Font.Color := FTextColor;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X + 10 + 8, (Height - Canvas.TextHeight('Ag')) div 2, Caption);
end;

{ ---------------------------------------------------------------------------- }
{ TSuiteHeader                                                                 }

constructor TSuiteHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColorFrom := clSuiteNavy;
  FColorTo := clSuiteNavy2;
  DoubleBuffered := True;
  ControlStyle := ControlStyle + [csAcceptsControls];
end;

destructor TSuiteHeader.Destroy;
begin
  FIcon.Free;
  inherited Destroy;
end;

procedure TSuiteHeader.Setup(const ATitle, ASubtitle: string; AIcon: TSuiteIconKind);
begin
  FTitle := ATitle;
  FSubtitle := ASubtitle;
  FIconKind := AIcon;
  FreeAndNil(FIcon);
  FIcon := RenderSuiteIcon(AIcon, 44, clWhite, sifOutline, 1.5, clWhite, 0.14);
  Invalidate;
end;

procedure TSuiteHeader.Paint;
var
  X, Y: Integer;
begin
  Canvas.GradientFill(ClientRect, FColorFrom, FColorTo, gdHorizontal);
  X := 20;
  if FIcon <> nil then
  begin
    Canvas.Draw(X, (Height - FIcon.Height) div 2, FIcon);
    X := X + FIcon.Width + 14;
  end;
  Y := (Height - 46) div 2;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  if SUITE_FONT <> 'default' then
    Canvas.Font.Name := SUITE_FONT;
  Canvas.Font.Size := 15;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := clWhite;
  Canvas.TextOut(X, Y, FTitle);
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  Canvas.Font.Color := SuiteRGB(176, 194, 226);
  Canvas.TextOut(X, Y + 28, FSubtitle);
end;

{ ---------------------------------------------------------------------------- }
{ TSuiteSectionTitle                                                           }

constructor TSuiteSectionTitle.CreateTitle(AOwner: TComponent;
  const ACaption: string; AIcon: TSuiteIconKind; AColor: TColor);
begin
  inherited Create(AOwner);
  Caption := ACaption;
  FColor := AColor;
  FIcon := RenderSuiteIcon(AIcon, 16, AColor, sifNone, 2);
  SetInitialBounds(0, 0, 200, 22);
end;

destructor TSuiteSectionTitle.Destroy;
begin
  FIcon.Free;
  inherited Destroy;
end;

procedure TSuiteSectionTitle.Paint;
begin
  Canvas.Draw(0, (Height - FIcon.Height) div 2, FIcon);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := clSuiteMuted;
  Canvas.TextOut(FIcon.Width + 8, (Height - Canvas.TextHeight('Ag')) div 2, Caption);
end;

initialization
  clSuiteSurface := SuiteRGB(244, 246, 250);
  clSuiteCard    := clWhite;
  clSuiteText    := SuiteRGB(15, 23, 42);
  clSuiteMuted   := SuiteRGB(100, 116, 139);
  clSuiteFaint   := SuiteRGB(148, 163, 184);
  clSuiteBorder  := SuiteRGB(226, 232, 240);
  clSuitePrimary := SuiteRGB(37, 99, 235);
  clSuiteSuccess := SuiteRGB(22, 163, 74);
  clSuiteWarning := SuiteRGB(217, 119, 6);
  clSuiteDanger  := SuiteRGB(220, 38, 38);
  clSuiteInfo    := SuiteRGB(14, 165, 233);
  clSuiteNeutral := SuiteRGB(100, 116, 139);
  clSuiteAxisX   := SuiteRGB(220, 38, 38);
  clSuiteAxisY   := SuiteRGB(22, 163, 74);
  clSuiteAxisZ   := SuiteRGB(37, 99, 235);
  clSuiteNavy    := SuiteRGB(15, 23, 42);
  clSuiteNavy2   := SuiteRGB(30, 64, 145);

end.
