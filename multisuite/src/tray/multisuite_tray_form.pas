unit multisuite_tray_form;

{ MultiSuite Bandeja
  Aplicativo que fica na area de notificacao (ao lado do relogio).
  Um clique no icone abre um painel vertical, sem borda, ancorado acima da
  barra de tarefas, com um botao com icone para cada ferramenta da suite.

  - Clique no icone da bandeja: abre/fecha o painel.
  - Botao direito: menu (abrir painel, abrir MultiSuite, iniciar com o
    Windows, sair).
  - Digitar no campo de busca filtra as ferramentas; Enter abre a primeira.
  - Setas para cima/baixo navegam; Esc fecha o painel.
  - Parametros: --tray (inicia so na bandeja), --show (abre o painel). }

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows, Registry,{$ENDIF}
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  Menus, LCLType, LazUTF8, Types,
  multisuite_types, multisuite_registry, multisuite_launcher, multisuite_icons;

type
  TSuiteTileStyle = (tsList, tsPrimary);
  TSuiteNavigateEvent = procedure(Sender: TObject; ADelta: Integer) of object;

  { Botao de ferramenta: icone + titulo + descricao + seta }
  TSuiteTile = class(TCustomControl)
  private
    FTitle: string;
    FDescription: string;
    FKind: TSuiteIconKind;
    FAccent: TColor;
    FStyle: TSuiteTileStyle;
    FBackColor: TColor;
    FHover: Boolean;
    FTargetIndex: Integer;
    FGroupTitle: string;
    FIcon, FChevron, FChevronHover: TBitmap;
    FBg, FBgHover: TBitmap;
    FBgW, FBgH: Integer;
    FOnNavigate: TSuiteNavigateEvent;
    procedure FreeBg;
    procedure EnsureCache;
    function IsActive: Boolean;
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor CreateTile(AOwner: TComponent; const ATitle, ADescription: string;
      AKind: TSuiteIconKind; AAccent: TColor; AStyle: TSuiteTileStyle);
    destructor Destroy; override;
    function Matches(const AFilter: string): Boolean;
    property Title: string read FTitle;
    property TargetIndex: Integer read FTargetIndex write FTargetIndex;
    property GroupTitle: string read FGroupTitle write FGroupTitle;
    property BackColor: TColor read FBackColor write FBackColor;
    property OnNavigate: TSuiteNavigateEvent read FOnNavigate write FOnNavigate;
  end;

  { Botao pequeno do rodape: icone + texto }
  TSuiteLinkButton = class(TCustomControl)
  private
    FText: string;
    FIcon: TBitmap;
    FHoverBg: TBitmap;
    FHover: Boolean;
    FTextColor: TColor;
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
  public
    constructor CreateLink(AOwner: TComponent; const AText: string;
      AKind: TSuiteIconKind; AColor: TColor);
    destructor Destroy; override;
    procedure AutoFit;
  end;

  { Campo de busca arredondado com icone de lupa }
  TSuiteSearchBox = class(TCustomControl)
  private
    FEdit: TEdit;
    FIcon: TBitmap;
    FBg, FBgFocus: TBitmap;
    FBgW, FBgH: Integer;
    procedure EditFocusChanged(Sender: TObject);
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Edit: TEdit read FEdit;
  end;

  TSuiteGroup = record
    Header: TLabel;
    Tiles: array of TSuiteTile;
  end;

  { TTrayForm }

  TTrayForm = class(TForm)
  private
    FRoot: string;
    FRegistry: TSuiteRegistry;
    FTargets: array of TSuiteToolInfo;
    FTray: TTrayIcon;
    FMenu: TPopupMenu;
    FAutoStartItem: TMenuItem;
    FBody: TPanel;
    FHeader: TPaintBox;
    FPrimary: TSuiteTile;
    FSearch: TSuiteSearchBox;
    FList: TScrollBox;
    FEmpty: TLabel;
    FFooter: TPanel;
    FTestsButton: TSuiteLinkButton;
    FExitButton: TSuiteLinkButton;
    FGroups: array of TSuiteGroup;
    FHeaderIcon, FHeaderDeco, FCloseIcon: TBitmap;
    FCloseRect: TRect;
    FFade: TTimer;
    FStartup: TTimer;
    FTargetTop: Integer;
    FLastHide: QWord;
    FContentHeight: Integer;
    FLayingOut: Boolean;

    function AddTarget(const AName, ADescription, AExecutable, AProjectFile: string): Integer;
    procedure BuildTargets;
    procedure BuildHeader;
    procedure BuildList;
    procedure BuildFooter;
    procedure BuildTray;
    procedure AddGroup(const ATitle: string; const AIDs: array of TSuiteToolID);
    function NewTile(AParent: TWinControl; AIndex: Integer; AKind: TSuiteIconKind;
      AAccent: TColor; AStyle: TSuiteTileStyle): TSuiteTile;
    function Relayout: Integer;
    procedure UpdatePanelHeight;
    procedure PositionNearClock;
    function VisibleTiles: TList;

    procedure HeaderPaint(Sender: TObject);
    procedure HeaderMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure HeaderMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FooterPaint(Sender: TObject);
    procedure FooterResize(Sender: TObject);
    procedure ListResize(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TileClick(Sender: TObject);
    procedure TileNavigate(Sender: TObject; ADelta: Integer);
    procedure TestsClick(Sender: TObject);
    procedure ExitClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure AppDeactivate(Sender: TObject);
    procedure TrayClick(Sender: TObject);
    procedure FadeTick(Sender: TObject);
    procedure StartupTick(Sender: TObject);
    procedure MenuShowPanel(Sender: TObject);
    procedure MenuOpenSuite(Sender: TObject);
    procedure MenuAutoStart(Sender: TObject);
    procedure LaunchTarget(AIndex: Integer);
    procedure ShowError(const AMessage: string);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ShowPanel;
    procedure HidePanel;
  end;

var
  TrayForm: TTrayForm;

implementation

{ ---------------------------------------------------------------------------- }
{ Paleta                                                                       }

function C(R, G, B: Byte): TColor; inline;
begin
  Result := RGBToColor(R, G, B);
end;

function cSurface: TColor; begin Result := C(247, 249, 252); end;
function cCard: TColor;    begin Result := clWhite; end;
function cText: TColor;    begin Result := C(15, 23, 42); end;
function cMuted: TColor;   begin Result := C(100, 116, 139); end;
function cFaint: TColor;   begin Result := C(148, 163, 184); end;
function cBorder: TColor;  begin Result := C(226, 232, 240); end;
function cHover: TColor;   begin Result := C(236, 241, 248); end;
function cPrimary: TColor; begin Result := C(37, 99, 235); end;
function cPrimaryHover: TColor; begin Result := C(29, 78, 216); end;

const
  UI_FONT = {$IFDEF WINDOWS}'Segoe UI'{$ELSE}'default'{$ENDIF};
  APP_VERSION = '0.01';

{ Escala de DPI: valores de layout escritos em 96 dpi }
function S(V: Integer): Integer;
begin
  Result := MulDiv(V, Screen.PixelsPerInch, 96);
end;

procedure SetupFont(AFont: TFont; ASize: Integer; AStyle: TFontStyles; AColor: TColor);
begin
  if UI_FONT <> 'default' then
    AFont.Name := UI_FONT;
  AFont.Size := ASize;
  AFont.Style := AStyle;
  AFont.Color := AColor;
end;

function FitText(ACanvas: TCanvas; const AText: string; AMaxWidth: Integer): string;
var
  N: Integer;
begin
  Result := AText;
  if (AMaxWidth <= 0) or (ACanvas.TextWidth(Result) <= AMaxWidth) then
    Exit;
  N := UTF8Length(AText);
  while (N > 0) and (ACanvas.TextWidth(UTF8Copy(AText, 1, N) + '…') > AMaxWidth) do
    Dec(N);
  Result := UTF8Copy(AText, 1, N) + '…';
end;

function MeasureText(const AText: string; ASize: Integer; AStyle: TFontStyles): Integer;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.SetSize(4, 4);
    SetupFont(B.Canvas.Font, ASize, AStyle, clBlack);
    Result := B.Canvas.TextWidth(AText);
  finally
    B.Free;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TSuiteTile                                                                   }

constructor TSuiteTile.CreateTile(AOwner: TComponent; const ATitle,
  ADescription: string; AKind: TSuiteIconKind; AAccent: TColor;
  AStyle: TSuiteTileStyle);
begin
  inherited Create(AOwner);
  FTitle := ATitle;
  FDescription := ADescription;
  FKind := AKind;
  FAccent := AAccent;
  FStyle := AStyle;
  FBackColor := cSurface;
  FTargetIndex := -1;
  TabStop := True;
  Cursor := crHandPoint;
  DoubleBuffered := True;
  ControlStyle := ControlStyle + [csOpaque];

  if FStyle = tsPrimary then
  begin
    FIcon := RenderSuiteIcon(FKind, S(42), clWhite, sifOutline, 1.6, clWhite, 0.16);
    FChevron := RenderSuiteIcon(sikArrowRight, S(18), clWhite, sifNone, 2);
    FChevronHover := RenderSuiteIcon(sikArrowRight, S(18), clWhite, sifNone, 2.2);
  end
  else
  begin
    FIcon := RenderSuiteIcon(FKind, S(40), FAccent, sifOutline, 1.6, FAccent, 0.10);
    FChevron := RenderSuiteIcon(sikChevron, S(16), cFaint, sifNone, 2);
    FChevronHover := RenderSuiteIcon(sikChevron, S(16), FAccent, sifNone, 2.2);
  end;
end;

destructor TSuiteTile.Destroy;
begin
  FreeBg;
  FIcon.Free;
  FChevron.Free;
  FChevronHover.Free;
  inherited Destroy;
end;

procedure TSuiteTile.FreeBg;
begin
  FreeAndNil(FBg);
  FreeAndNil(FBgHover);
end;

procedure TSuiteTile.EnsureCache;
begin
  if (FBgHover <> nil) and (FBgW = Width) and (FBgH = Height) then
    Exit;
  FreeBg;
  FBgW := Width;
  FBgH := Height;
  if FStyle = tsPrimary then
  begin
    FBg := RenderRoundRect(Width, Height, S(14), cPrimary);
    FBgHover := RenderRoundRect(Width, Height, S(14), cPrimaryHover);
  end
  else
    FBgHover := RenderRoundRect(Width, Height, S(12), cCard, cBorder, 1);
end;

function TSuiteTile.IsActive: Boolean;
begin
  Result := FHover or Focused;
end;

procedure TSuiteTile.Paint;
var
  X, Y, TitleH, DescH, TextW, Gap: Integer;
  Chev: TBitmap;
  TitleColor, DescColor: TColor;
begin
  EnsureCache;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(ClientRect);

  if FStyle = tsPrimary then
  begin
    if IsActive then
      Canvas.Draw(0, 0, FBgHover)
    else
      Canvas.Draw(0, 0, FBg);
    TitleColor := clWhite;
    DescColor := C(205, 222, 255);
  end
  else
  begin
    if IsActive then
      Canvas.Draw(0, 0, FBgHover);
    TitleColor := cText;
    DescColor := cMuted;
  end;

  X := S(11);
  Canvas.Draw(X, (Height - FIcon.Height) div 2, FIcon);
  X := X + FIcon.Width + S(13);

  if IsActive then
    Chev := FChevronHover
  else
    Chev := FChevron;
  Canvas.Draw(Width - Chev.Width - S(14), (Height - Chev.Height) div 2, Chev);
  TextW := Width - X - Chev.Width - S(24);

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  SetupFont(Canvas.Font, 10, [fsBold], TitleColor);
  TitleH := Canvas.TextHeight('Ag');
  SetupFont(Canvas.Font, 8, [], DescColor);
  DescH := Canvas.TextHeight('Ag');
  Gap := S(1);
  Y := (Height - (TitleH + Gap + DescH)) div 2;

  SetupFont(Canvas.Font, 10, [fsBold], TitleColor);
  Canvas.TextOut(X, Y, FitText(Canvas, FTitle, TextW));
  SetupFont(Canvas.Font, 8, [], DescColor);
  Canvas.TextOut(X, Y + TitleH + Gap, FitText(Canvas, FDescription, TextW));
end;

procedure TSuiteTile.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TSuiteTile.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TSuiteTile.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TSuiteTile.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TSuiteTile.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN, VK_SPACE:
      begin
        Key := 0;
        Click;
        Exit;
      end;
    VK_DOWN:
      begin
        Key := 0;
        if Assigned(FOnNavigate) then FOnNavigate(Self, 1);
        Exit;
      end;
    VK_UP:
      begin
        Key := 0;
        if Assigned(FOnNavigate) then FOnNavigate(Self, -1);
        Exit;
      end;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TSuiteTile.Resize;
begin
  inherited Resize;
  Invalidate;
end;

{ A roda do mouse sobre um botao rola a lista que o contem }
function TSuiteTile.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  SB: TScrollBox;
begin
  if Parent is TScrollBox then
  begin
    SB := TScrollBox(Parent);
    SB.VertScrollBar.Position := SB.VertScrollBar.Position -
      (WheelDelta div 120) * SB.VertScrollBar.Increment * 2;
    Result := True;
  end
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TSuiteTile.Matches(const AFilter: string): Boolean;
var
  F: string;
begin
  F := UTF8LowerCase(Trim(AFilter));
  Result := (F = '') or
    (Pos(F, UTF8LowerCase(FTitle + ' ' + FDescription + ' ' + FGroupTitle)) > 0);
end;

{ ---------------------------------------------------------------------------- }
{ TSuiteLinkButton                                                             }

constructor TSuiteLinkButton.CreateLink(AOwner: TComponent; const AText: string;
  AKind: TSuiteIconKind; AColor: TColor);
begin
  inherited Create(AOwner);
  FText := AText;
  FTextColor := AColor;
  FIcon := RenderSuiteIcon(AKind, S(18), AColor, sifNone, 2);
  Cursor := crHandPoint;
  DoubleBuffered := True;
  Height := S(34);
end;

destructor TSuiteLinkButton.Destroy;
begin
  FIcon.Free;
  FHoverBg.Free;
  inherited Destroy;
end;

procedure TSuiteLinkButton.AutoFit;
begin
  Width := S(10) + FIcon.Width + S(8) + MeasureText(FText, 9, []) + S(12);
  FreeAndNil(FHoverBg);
end;

procedure TSuiteLinkButton.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := cCard;
  Canvas.FillRect(ClientRect);
  if FHover then
  begin
    if (FHoverBg = nil) or (FHoverBg.Width <> Width) or (FHoverBg.Height <> Height) then
    begin
      FreeAndNil(FHoverBg);
      FHoverBg := RenderRoundRect(Width, Height, S(9), cHover);
    end;
    Canvas.Draw(0, 0, FHoverBg);
  end;
  Canvas.Draw(S(10), (Height - FIcon.Height) div 2, FIcon);
  Canvas.Brush.Style := bsClear;
  SetupFont(Canvas.Font, 9, [], FTextColor);
  Canvas.TextOut(S(10) + FIcon.Width + S(8),
    (Height - Canvas.TextHeight('Ag')) div 2, FText);
end;

procedure TSuiteLinkButton.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TSuiteLinkButton.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

{ ---------------------------------------------------------------------------- }
{ TSuiteSearchBox                                                              }

constructor TSuiteSearchBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  FIcon := RenderSuiteIcon(sikSearch, S(18), cFaint, sifNone, 2);
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.BorderStyle := bsNone;
  FEdit.Color := cCard;
  SetupFont(FEdit.Font, 10, [], cText);
  FEdit.TextHint := 'Buscar ferramenta…';
  FEdit.OnEnter := @EditFocusChanged;
  FEdit.OnExit := @EditFocusChanged;
end;

destructor TSuiteSearchBox.Destroy;
begin
  FIcon.Free;
  FBg.Free;
  FBgFocus.Free;
  inherited Destroy;
end;

procedure TSuiteSearchBox.EditFocusChanged(Sender: TObject);
begin
  Invalidate;
end;

procedure TSuiteSearchBox.Resize;
begin
  inherited Resize;
  FEdit.SetBounds(S(40), (Height - FEdit.Height) div 2, Max(10, Width - S(52)), FEdit.Height);
end;

procedure TSuiteSearchBox.Paint;
begin
  if (FBg = nil) or (FBgW <> Width) or (FBgH <> Height) then
  begin
    FreeAndNil(FBg);
    FreeAndNil(FBgFocus);
    FBgW := Width;
    FBgH := Height;
    FBg := RenderRoundRect(Width, Height, S(11), cCard, cBorder, 1);
    FBgFocus := RenderRoundRect(Width, Height, S(11), cCard, C(147, 180, 250), S(2));
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := cSurface;
  Canvas.FillRect(ClientRect);
  if FEdit.Focused then
    Canvas.Draw(0, 0, FBgFocus)
  else
    Canvas.Draw(0, 0, FBg);
  Canvas.Draw(S(13), (Height - FIcon.Height) div 2, FIcon);
end;

{ ---------------------------------------------------------------------------- }
{ Utilitarios                                                                  }

{ Sobe a partir da pasta do executavel procurando a raiz do repositorio
  (que contem multisuite/src/app/multisuite.lpi). Instalado, a raiz e a
  propria pasta do executavel. }
function FindSuiteRoot: string;
var
  Dir, Parent, Marker: string;
  I: Integer;
begin
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))));
  Marker := 'multisuite' + DirectorySeparator + 'src' + DirectorySeparator +
    'app' + DirectorySeparator + 'multisuite.lpi';
  for I := 0 to 6 do
  begin
    if FileExists(IncludeTrailingPathDelimiter(Dir) + Marker) then
      Exit(IncludeTrailingPathDelimiter(Dir));
    Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if (Parent = '') or (Parent = Dir) then
      Break;
    Dir := Parent;
  end;
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))));
end;

function ToolIcon(AID: TSuiteToolID): TSuiteIconKind;
begin
  case AID of
    stiMultiCAD:      Result := sikCAD;
    stiMultiPCB:      Result := sikPCB;
    stiMakePCB:       Result := sikMakePCB;
    stiMultiAssembly: Result := sikAssembly;
    stiMultiPhysics:  Result := sikPhysics;
    stiMultiCAM:      Result := sikCAM;
    stiMultiSlicer:   Result := sikSlicer;
    stiLaserPCB:      Result := sikLaserPCB;
    stiLaserArt:      Result := sikLaserArt;
    stiMultiCNC:      Result := sikCNC;
  else
    Result := sikSuite;
  end;
end;

function ToolAccent(AID: TSuiteToolID): TColor;
begin
  case AID of
    stiMultiCAD:      Result := C(59, 130, 246);
    stiMultiPCB:      Result := C(13, 148, 136);
    stiMakePCB:       Result := C(5, 150, 105);
    stiLaserPCB:      Result := C(239, 68, 68);
    stiLaserArt:      Result := C(219, 39, 119);
    stiMultiCAM:      Result := C(217, 119, 6);
    stiMultiSlicer:   Result := C(234, 88, 12);
    stiMultiPhysics:  Result := C(124, 58, 237);
    stiMultiAssembly: Result := C(79, 70, 229);
    stiMultiCNC:      Result := C(5, 150, 105);
  else
    Result := cMuted;
  end;
end;

{$IFDEF WINDOWS}
const
  RUN_KEY = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RUN_VALUE = 'MultiSuiteTray';

function IsAutoStart: Boolean;
var
  R: TRegistry;
begin
  Result := False;
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly(RUN_KEY) then
      Result := R.ValueExists(RUN_VALUE);
  finally
    R.Free;
  end;
end;

procedure SetAutoStart(AEnabled: Boolean);
var
  R: TRegistry;
begin
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKey(RUN_KEY, True) then
    begin
      if AEnabled then
        R.WriteString(RUN_VALUE, '"' + ParamStr(0) + '" --tray')
      else if R.ValueExists(RUN_VALUE) then
        R.DeleteValue(RUN_VALUE);
    end;
  finally
    R.Free;
  end;
end;

{ Windows 11: cantos arredondados nativos (sem efeito no Windows 10) }
procedure ApplyRoundedCorners(AHandle: HWND);
type
  TDwmSetWindowAttribute = function(hwnd: HWND; dwAttribute: DWORD;
    pvAttribute: Pointer; cbAttribute: DWORD): HRESULT; stdcall;
const
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
  DWMWCP_ROUND = 2;
var
  Lib: HMODULE;
  F: TDwmSetWindowAttribute;
  Pref: DWORD;
begin
  Lib := LoadLibrary('dwmapi.dll');
  if Lib = 0 then
    Exit;
  Pointer(F) := GetProcAddress(Lib, 'DwmSetWindowAttribute');
  if Assigned(F) then
  begin
    Pref := DWMWCP_ROUND;
    F(AHandle, DWMWA_WINDOW_CORNER_PREFERENCE, @Pref, SizeOf(Pref));
  end;
end;
{$ENDIF}

{ ---------------------------------------------------------------------------- }
{ TTrayForm                                                                    }

constructor TTrayForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'MultiSuite';
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  ShowInTaskBar := stNever;
  Position := poDesigned;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  Color := cBorder;
  Width := S(372);
  Height := S(640);
  DoubleBuffered := True;
  SetupFont(Font, 9, [], cText);

  FRoot := FindSuiteRoot;
  FRegistry := TSuiteRegistry.Create;
  BuildTargets;

  FBody := TPanel.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BorderSpacing.Around := 1;
  FBody.BevelOuter := bvNone;
  FBody.Color := cSurface;
  FBody.ParentColor := False;
  FBody.DoubleBuffered := True;

  BuildHeader;
  BuildFooter;
  BuildList;
  BuildTray;

  FFade := TTimer.Create(Self);
  FFade.Enabled := False;
  FFade.Interval := 15;
  FFade.OnTimer := @FadeTick;

  FStartup := TTimer.Create(Self);
  FStartup.Interval := 250;
  FStartup.OnTimer := @StartupTick;
  FStartup.Enabled := True;

  Application.OnDeactivate := @AppDeactivate;
end;

destructor TTrayForm.Destroy;
begin
  Application.OnDeactivate := nil;
  FHeaderIcon.Free;
  FHeaderDeco.Free;
  FCloseIcon.Free;
  FRegistry.Free;
  inherited Destroy;
end;

procedure TTrayForm.CreateWnd;
begin
  inherited CreateWnd;
  {$IFDEF WINDOWS}
  ApplyRoundedCorners(Handle);
  {$ENDIF}
end;

function TTrayForm.AddTarget(const AName, ADescription, AExecutable,
  AProjectFile: string): Integer;
begin
  Result := Length(FTargets);
  SetLength(FTargets, Result + 1);
  FTargets[Result].ID := stiMultiCNC;
  FTargets[Result].Name := AName;
  FTargets[Result].Description := ADescription;
  FTargets[Result].Executable := AExecutable;
  FTargets[Result].ProjectFile := AProjectFile;
end;

{ Indice 0 = MultiSuite, 1 = Central de testes, 2.. = ferramentas do registro }
procedure TTrayForm.BuildTargets;
var
  I: Integer;
begin
  SetLength(FTargets, 0);
  AddTarget('MultiSuite', 'Painel completo de projeto e fabricação',
    'multisuite', 'multisuite/src/app/multisuite.lpi');
  AddTarget('Central de testes', 'Validação dos módulos da suite',
    'multisuite_test_center', 'multisuite/src/testing/multisuite_test_center.lpi');
  for I := 0 to FRegistry.Count - 1 do
  begin
    SetLength(FTargets, Length(FTargets) + 1);
    FTargets[High(FTargets)] := FRegistry.Tool(I);
  end;
end;

procedure TTrayForm.BuildHeader;
begin
  FHeader := TPaintBox.Create(Self);
  FHeader.Parent := FBody;
  FHeader.Align := alTop;
  FHeader.Height := S(96);
  FHeader.OnPaint := @HeaderPaint;
  FHeader.OnMouseMove := @HeaderMouseMove;
  FHeader.OnMouseUp := @HeaderMouseUp;

  FHeaderIcon := RenderSuiteIcon(sikSuite, S(46), clWhite, sifOutline, 1.5, clWhite, 0.14);
  FHeaderDeco := RenderSuiteIcon(sikSuite, S(150), C(52, 86, 168), sifOutline, 1.2, C(52, 86, 168), 0.25);
  FCloseIcon := RenderSuiteIcon(sikClose, S(16), C(160, 174, 200), sifNone, 2);

  FPrimary := NewTile(FBody, 0, sikSuite, cPrimary, tsPrimary);
  FPrimary.Align := alTop;
  FPrimary.Top := FHeader.Top + FHeader.Height + 1;
  FPrimary.Height := S(68);
  FPrimary.BorderSpacing.Left := S(14);
  FPrimary.BorderSpacing.Right := S(14);
  FPrimary.BorderSpacing.Top := S(14);

  FSearch := TSuiteSearchBox.Create(Self);
  FSearch.Parent := FBody;
  FSearch.Align := alTop;
  FSearch.Top := FPrimary.Top + FPrimary.Height + 1;
  FSearch.Height := S(40);
  FSearch.BorderSpacing.Left := S(14);
  FSearch.BorderSpacing.Right := S(14);
  FSearch.BorderSpacing.Top := S(12);
  FSearch.Edit.OnChange := @SearchChange;
  FSearch.Edit.OnKeyDown := @SearchKeyDown;
end;

procedure TTrayForm.BuildFooter;
begin
  FFooter := TPanel.Create(Self);
  FFooter.Parent := FBody;
  FFooter.Align := alBottom;
  FFooter.Height := S(52);
  FFooter.BevelOuter := bvNone;
  FFooter.Color := cCard;
  FFooter.ParentColor := False;
  FFooter.OnPaint := @FooterPaint;

  FTestsButton := TSuiteLinkButton.CreateLink(Self, 'Central de testes', sikTests, cMuted);
  FTestsButton.Parent := FFooter;
  FTestsButton.AutoFit;
  FTestsButton.Left := S(10);
  FTestsButton.Top := (FFooter.Height - FTestsButton.Height) div 2;
  FTestsButton.OnClick := @TestsClick;
  FTestsButton.Hint := 'Raiz da suite: ' + FRoot;
  FTestsButton.ShowHint := True;

  FExitButton := TSuiteLinkButton.CreateLink(Self, 'Sair', sikPower, cMuted);
  FExitButton.Parent := FFooter;
  FExitButton.AutoFit;
  FExitButton.Top := (FFooter.Height - FExitButton.Height) div 2;
  FFooter.OnResize := @FooterResize;
  FExitButton.OnClick := @ExitClick;
  FExitButton.Hint := 'Encerrar o MultiSuite da bandeja';
  FExitButton.ShowHint := True;
end;

procedure TTrayForm.BuildList;
begin
  FList := TScrollBox.Create(Self);
  FList.Parent := FBody;
  FList.Align := alClient;
  FList.BorderSpacing.Top := S(6);
  FList.BorderStyle := bsNone;
  FList.Color := cSurface;
  FList.ParentColor := False;
  FList.HorzScrollBar.Visible := False;
  FList.VertScrollBar.Tracking := True;
  FList.VertScrollBar.Increment := S(32);
  FList.DoubleBuffered := True;
  FList.OnResize := @ListResize;

  AddGroup('PROJETAR', [stiMultiCAD, stiMultiPCB, stiMakePCB, stiLaserPCB, stiLaserArt]);
  AddGroup('PREPARAR', [stiMultiCAM, stiMultiSlicer]);
  AddGroup('SIMULAR', [stiMultiPhysics, stiMultiAssembly]);
  AddGroup('FABRICAR', [stiMultiCNC]);

  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := FList;
  FEmpty.AutoSize := False;
  FEmpty.Alignment := taCenter;
  FEmpty.Caption := 'Nenhuma ferramenta encontrada';
  SetupFont(FEmpty.Font, 9, [], cMuted);
  FEmpty.Visible := False;

  FContentHeight := Relayout;
end;

procedure TTrayForm.AddGroup(const ATitle: string; const AIDs: array of TSuiteToolID);
var
  G, I, T: Integer;
  NewT: TSuiteTile;
begin
  G := Length(FGroups);
  SetLength(FGroups, G + 1);
  FGroups[G].Header := TLabel.Create(Self);
  FGroups[G].Header.Parent := FList;
  FGroups[G].Header.AutoSize := False;
  FGroups[G].Header.Layout := tlCenter;
  FGroups[G].Header.Caption := ATitle;
  FGroups[G].Header.Transparent := True;
  SetupFont(FGroups[G].Header.Font, 7, [fsBold], cFaint);
  SetLength(FGroups[G].Tiles, 0);

  for I := 0 to High(AIDs) do
    for T := 2 to High(FTargets) do
      if FTargets[T].ID = AIDs[I] then
      begin
        NewT := NewTile(FList, T, ToolIcon(AIDs[I]), ToolAccent(AIDs[I]), tsList);
        NewT.GroupTitle := ATitle;
        SetLength(FGroups[G].Tiles, Length(FGroups[G].Tiles) + 1);
        FGroups[G].Tiles[High(FGroups[G].Tiles)] := NewT;
        Break;
      end;
end;

function TTrayForm.NewTile(AParent: TWinControl; AIndex: Integer;
  AKind: TSuiteIconKind; AAccent: TColor; AStyle: TSuiteTileStyle): TSuiteTile;
var
  Title: string;
begin
  Title := FTargets[AIndex].Name;
  if AStyle = tsPrimary then
    Title := 'Abrir ' + Title;
  Result := TSuiteTile.CreateTile(Self, Title, FTargets[AIndex].Description,
    AKind, AAccent, AStyle);
  Result.TargetIndex := AIndex;
  Result.BackColor := cSurface;
  Result.Parent := AParent;
  Result.OnClick := @TileClick;
  Result.OnNavigate := @TileNavigate;
end;

{ Posiciona cabecalhos e botoes da lista conforme o filtro.
  Retorna a altura total do conteudo. }
function TTrayForm.Relayout: Integer;
var
  G, I, Y, X, W, Count: Integer;
  Filter: string;
  T: TSuiteTile;
begin
  Result := 0;
  if (FList = nil) or FLayingOut then
    Exit;
  FLayingOut := True;
  FList.DisableAlign;
  try
    FList.VertScrollBar.Position := 0;
    Filter := '';
    if FSearch <> nil then
      Filter := FSearch.Edit.Text;
    X := S(14);
    W := Max(S(100), FList.ClientWidth - 2 * S(14));
    Y := 0;
    Count := 0;
    for G := 0 to High(FGroups) do
    begin
      FGroups[G].Header.Visible := False;
      for I := 0 to High(FGroups[G].Tiles) do
      begin
        T := FGroups[G].Tiles[I];
        if T.Matches(Filter) then
        begin
          if not FGroups[G].Header.Visible then
          begin
            FGroups[G].Header.SetBounds(X + S(12), Y, W - S(12), S(28));
            FGroups[G].Header.Visible := True;
            Inc(Y, S(28));
          end;
          T.SetBounds(X, Y, W, S(60));
          T.Visible := True;
          Inc(Y, S(62));
          Inc(Count);
        end
        else
          T.Visible := False;
      end;
      if FGroups[G].Header.Visible then
        Inc(Y, S(4));
    end;
    FEmpty.Visible := Count = 0;
    if Count = 0 then
    begin
      FEmpty.SetBounds(X, S(24), W, S(24));
      Y := S(72);
    end;
    Result := Y + S(8);
  finally
    FList.EnableAlign;
    FLayingOut := False;
  end;
end;

procedure TTrayForm.UpdatePanelHeight;
var
  Fixed, MaxH: Integer;
  WA: TRect;
begin
  FSearch.Edit.Text := '';
  FContentHeight := Relayout;
  Fixed := 2 + FHeader.Height +
    FPrimary.Height + FPrimary.BorderSpacing.Top +
    FSearch.Height + FSearch.BorderSpacing.Top +
    FList.BorderSpacing.Top + FFooter.Height;
  WA := Screen.PrimaryMonitor.WorkareaRect;
  MaxH := Min(S(780), (WA.Bottom - WA.Top) - 2 * S(12));
  Height := Min(Fixed + FContentHeight, MaxH);
end;

{ Ancora o painel no canto da area de trabalho onde fica a bandeja,
  respeitando a posicao da barra de tarefas (embaixo, em cima, lados). }
procedure TTrayForm.PositionNearClock;
var
  WA, MB: TRect;
  M: Integer;
begin
  WA := Screen.PrimaryMonitor.WorkareaRect;
  MB := Screen.PrimaryMonitor.BoundsRect;
  M := S(12);
  Left := WA.Right - Width - M;
  Top := WA.Bottom - Height - M;
  if WA.Top > MB.Top then
    Top := WA.Top + M
  else if WA.Left > MB.Left then
    Left := WA.Left + M;
end;

procedure TTrayForm.ShowPanel;
begin
  FFade.Enabled := False;
  UpdatePanelHeight;
  PositionNearClock;
  FTargetTop := Top;
  Top := FTargetTop + S(10);
  AlphaBlend := True;
  AlphaBlendValue := 0;
  Show;
  BringToFront;
  {$IFDEF WINDOWS}
  SetForegroundWindow(Handle);
  {$ENDIF}
  if FSearch.Edit.CanFocus then
    FSearch.Edit.SetFocus;
  FFade.Enabled := True;
end;

procedure TTrayForm.HidePanel;
begin
  FFade.Enabled := False;
  if Visible then
  begin
    Hide;
    FLastHide := GetTickCount64;
  end;
end;

procedure TTrayForm.FadeTick(Sender: TObject);
var
  V: Integer;
begin
  V := Min(255, AlphaBlendValue + 40);
  AlphaBlendValue := V;
  Top := FTargetTop + Round(S(10) * (1 - V / 255));
  if V >= 255 then
  begin
    FFade.Enabled := False;
    Top := FTargetTop;
    AlphaBlend := False;
  end;
end;

procedure TTrayForm.StartupTick(Sender: TObject);
begin
  FStartup.Enabled := False;
  if not Application.HasOption('tray') then
    ShowPanel;
end;

function TTrayForm.VisibleTiles: TList;
var
  G, I: Integer;
begin
  Result := TList.Create;
  Result.Add(FPrimary);
  for G := 0 to High(FGroups) do
    for I := 0 to High(FGroups[G].Tiles) do
      if FGroups[G].Tiles[I].Visible then
        Result.Add(FGroups[G].Tiles[I]);
end;

{ --- eventos ---------------------------------------------------------------- }

procedure TTrayForm.HeaderPaint(Sender: TObject);
var
  R: TRect;
  Cv: TCanvas;
  X, Y: Integer;
begin
  R := FHeader.ClientRect;
  Cv := FHeader.Canvas;
  Cv.GradientFill(R, C(15, 23, 42), C(30, 64, 145), gdHorizontal);
  Cv.Draw(R.Right - S(150), -S(52), FHeaderDeco);

  X := S(18);
  Y := (R.Bottom - FHeaderIcon.Height) div 2;
  Cv.Draw(X, Y, FHeaderIcon);
  X := X + FHeaderIcon.Width + S(14);

  Cv.Brush.Style := bsClear;
  SetupFont(Cv.Font, 15, [fsBold], clWhite);
  Cv.TextOut(X, Y - S(2), 'MultiSuite');
  SetupFont(Cv.Font, 9, [], C(176, 194, 226));
  Cv.TextOut(X, Y + S(28), 'Projeto e fabricação digital');

  FCloseRect := Rect(R.Right - S(36), S(10), R.Right - S(10), S(36));
  Cv.Draw(FCloseRect.Left + (FCloseRect.Right - FCloseRect.Left - FCloseIcon.Width) div 2,
    FCloseRect.Top + (FCloseRect.Bottom - FCloseRect.Top - FCloseIcon.Height) div 2,
    FCloseIcon);
end;

procedure TTrayForm.HeaderMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if PtInRect(FCloseRect, Point(X, Y)) then
    FHeader.Cursor := crHandPoint
  else
    FHeader.Cursor := crDefault;
end;

procedure TTrayForm.HeaderMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(FCloseRect, Point(X, Y)) then
    HidePanel;
end;

procedure TTrayForm.FooterPaint(Sender: TObject);
begin
  FFooter.Canvas.Pen.Color := cBorder;
  FFooter.Canvas.Line(0, 0, FFooter.Width, 0);
  FFooter.Canvas.Brush.Style := bsClear;
  SetupFont(FFooter.Canvas.Font, 8, [], cFaint);
  FFooter.Canvas.TextOut(
    (FFooter.Width - FFooter.Canvas.TextWidth('v' + APP_VERSION)) div 2,
    (FFooter.Height - FFooter.Canvas.TextHeight('v')) div 2, 'v' + APP_VERSION);
end;

procedure TTrayForm.FooterResize(Sender: TObject);
begin
  FExitButton.Left := FFooter.ClientWidth - FExitButton.Width - S(10);
end;

procedure TTrayForm.ListResize(Sender: TObject);
begin
  Relayout;
end;

procedure TTrayForm.SearchChange(Sender: TObject);
begin
  Relayout;
end;

procedure TTrayForm.SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  L: TList;
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        L := VisibleTiles;
        try
          if Trim(FSearch.Edit.Text) = '' then
            LaunchTarget(0)
          else if L.Count > 1 then
            LaunchTarget(TSuiteTile(L[1]).TargetIndex);
        finally
          L.Free;
        end;
      end;
    VK_DOWN:
      begin
        Key := 0;
        L := VisibleTiles;
        try
          if L.Count > 1 then
          begin
            TSuiteTile(L[1]).SetFocus;
            FList.ScrollInView(TSuiteTile(L[1]));
          end;
        finally
          L.Free;
        end;
      end;
    VK_UP:
      begin
        Key := 0;
        FPrimary.SetFocus;
      end;
  end;
end;

procedure TTrayForm.TileNavigate(Sender: TObject; ADelta: Integer);
var
  L: TList;
  I: Integer;
  T: TSuiteTile;
begin
  L := VisibleTiles;
  try
    I := L.IndexOf(Sender) + ADelta;
    if (Sender = FPrimary) and (ADelta > 0) then
    begin
      FSearch.Edit.SetFocus;
      Exit;
    end;
    if (I = 0) and (ADelta < 0) then
    begin
      FSearch.Edit.SetFocus;
      Exit;
    end;
    if (I >= 0) and (I < L.Count) then
    begin
      T := TSuiteTile(L[I]);
      T.SetFocus;
      if T.Parent = FList then
        FList.ScrollInView(T);
    end;
  finally
    L.Free;
  end;
end;

procedure TTrayForm.TileClick(Sender: TObject);
begin
  if Sender is TSuiteTile then
    LaunchTarget(TSuiteTile(Sender).TargetIndex);
end;

procedure TTrayForm.TestsClick(Sender: TObject);
begin
  LaunchTarget(1);
end;

procedure TTrayForm.ExitClick(Sender: TObject);
begin
  FTray.Visible := False;
  Application.Terminate;
end;

procedure TTrayForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    HidePanel;
  end;
end;

procedure TTrayForm.AppDeactivate(Sender: TObject);
begin
  HidePanel;
end;

procedure TTrayForm.TrayClick(Sender: TObject);
begin
  if Visible then
    HidePanel
  else if GetTickCount64 - FLastHide > 350 then
    ShowPanel;
end;

procedure TTrayForm.MenuShowPanel(Sender: TObject);
begin
  ShowPanel;
end;

procedure TTrayForm.MenuOpenSuite(Sender: TObject);
begin
  LaunchTarget(0);
end;

procedure TTrayForm.MenuAutoStart(Sender: TObject);
begin
  {$IFDEF WINDOWS}
  SetAutoStart(not FAutoStartItem.Checked);
  FAutoStartItem.Checked := IsAutoStart;
  {$ENDIF}
end;

procedure TTrayForm.LaunchTarget(AIndex: Integer);
var
  Err: string;
begin
  if (AIndex < 0) or (AIndex > High(FTargets)) then
    Exit;
  if TSuiteLauncher.Launch(FTargets[AIndex], FRoot, '', Err) then
    HidePanel
  else
    ShowError(FTargets[AIndex].Name + ' ainda não está disponível.' + LineEnding + Err);
end;

procedure TTrayForm.ShowError(const AMessage: string);
begin
  HidePanel;
  FTray.BalloonTitle := 'MultiSuite';
  FTray.BalloonHint := AMessage;
  FTray.BalloonFlags := bfError;
  FTray.ShowBalloonHint;
end;

procedure TTrayForm.BuildTray;
var
  Bmp: TBitmap;
  Ico: TIcon;
  Item: TMenuItem;
begin
  FMenu := TPopupMenu.Create(Self);

  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Abrir painel';
  Item.Default := True;
  Item.OnClick := @MenuShowPanel;
  FMenu.Items.Add(Item);

  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Abrir MultiSuite';
  Item.OnClick := @MenuOpenSuite;
  FMenu.Items.Add(Item);

  {$IFDEF WINDOWS}
  FMenu.Items.AddSeparator;
  FAutoStartItem := TMenuItem.Create(FMenu);
  FAutoStartItem.Caption := 'Iniciar com o Windows';
  FAutoStartItem.Checked := IsAutoStart;
  FAutoStartItem.OnClick := @MenuAutoStart;
  FMenu.Items.Add(FAutoStartItem);
  {$ENDIF}

  FMenu.Items.AddSeparator;
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Sair';
  Item.OnClick := @ExitClick;
  FMenu.Items.Add(Item);

  FTray := TTrayIcon.Create(Self);
  FTray.Hint := 'MultiSuite';
  FTray.PopUpMenu := FMenu;
  FTray.OnClick := @TrayClick;

  Bmp := RenderSuiteIcon(sikSuite, 32, clWhite, sifFilled, 2.2, cPrimary, 1);
  Ico := TIcon.Create;
  try
    Ico.Add(pf32bit, 32, 32);
    Ico.Current := 0;
    Ico.AssignImage(Bmp);
    FTray.Icon.Assign(Ico);
    Self.Icon.Assign(Ico);
  finally
    Ico.Free;
    Bmp.Free;
  end;
  FTray.Visible := True;
end;

end.
