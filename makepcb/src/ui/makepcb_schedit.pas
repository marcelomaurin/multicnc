unit makepcb_schedit;

{ Editor do esquematico do MakePCB e galeria de simbolos.

  Ferramentas: Selecionar (arrasta partes e rotulos; R gira, Del apaga,
  clique num fio seleciona o fio), Colocar (simbolo da galeria), Fio
  (clique nos pontos, ortogonal; termina num pino, num fio, com duplo
  clique ou botao direito) e Rotulo (nome de rede). GND e VCC da galeria
  sao rotulos desenhados como simbolo de alimentacao.
  Fundo branco, grade de pontos de 2,54 mm, fios verdes, juncoes em
  pontos cheios (3 ou mais ligacoes), como no PCB Wizard. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, Forms, Dialogs, LCLType,
  makepcb_model, makepcb_schematic, makepcb_font;

type
  TMPSchTool = (stSelect, stPlace, stWire, stLabel);
  TMPSchSelKind = (ssNone, ssPart, ssWire, ssLabel);

  TMPSchStatusEvent = procedure(Sender: TObject; const Text: string) of object;

  TMPSchematicEditor = class(TCustomControl)
  private
    FSch: TMPSchematic;
    FScale, FOX, FOY: Double;
    FFitted: Boolean;
    FTool: TMPSchTool;
    FPlaceSym: TMPSymbol;
    FGhostRot: Integer;
    FMouse: TMPPoint;
    FPoints: TMPPoints;
    FSelKind: TMPSchSelKind;
    FSelIndex: Integer;
    FDragging, FDragMoved, FPanning: Boolean;
    FDragStart, FDragOrig: TMPPoint;
    FPanStart: TPoint;
    FPanOX, FPanOY: Double;
    FUndo, FRedo: TStringList;
    FModified: Boolean;
    FOnChange, FOnSelect: TNotifyEvent;
    FOnStatus: TMPSchStatusEvent;
    function SX(X: Double): Integer; inline;
    function SY(Y: Double): Integer; inline;
    function ToSch(PX, PY: Integer): TMPPoint;
    function Snap(const P: TMPPoint): TMPPoint;
    function Ortho(const A, B: TMPPoint): TMPPoint;
    function PinAt(const P: TMPPoint): Boolean;
    function OnAnyWire(const P: TMPPoint): Boolean;
    procedure DrawSymbol(S: TMPSymbol; Part: TMPPart; GX, GY: Double; Rot: Integer; C: TColor);
    procedure DrawLabel(L: TMPSchLabel; C: TColor);
    procedure DrawText(const S: string; X, Y, H: Double; C: TColor);
    procedure DoChanged;
    procedure Status(const S: string);
    procedure FinishWire;
    procedure HitTest(const P: TMPPoint; out K: TMPSchSelKind; out I: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetSchematic(ASch: TMPSchematic);
    procedure SetTool(T: TMPSchTool);
    procedure SetPlaceSymbol(S: TMPSymbol);
    procedure ZoomToFit;
    procedure ZoomBy(F: Double);
    procedure Snapshot;
    procedure Undo;
    procedure Redo;
    procedure ClearHistory;
    procedure Select(K: TMPSchSelKind; I: Integer);
    procedure DeleteSelection;
    procedure RotateSelection;
    procedure CancelOperation;
    procedure Changed;
    property Schematic: TMPSchematic read FSch;
    property Tool: TMPSchTool read FTool;
    property SelKind: TMPSchSelKind read FSelKind;
    property SelIndex: Integer read FSelIndex;
    property Modified: Boolean read FModified write FModified;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnStatus: TMPSchStatusEvent read FOnStatus write FOnStatus;
  end;

  TMPSymPickEvent = procedure(Sender: TObject; S: TMPSymbol) of object;

  { galeria de simbolos (miniaturas em duas colunas) }
  TMPSymbolGallery = class(TCustomControl)
  private
    FItems: TList;
    FSelected, FHot: Integer;
    FOnPick: TMPSymPickEvent;
    FCategory: string;
    procedure SetCategory(const AValue: string);
    function TileRect(I: Integer): TRect;
    function IndexAt(X, Y: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Rebuild;
    procedure ClearSelection;
    function NeededHeight: Integer;
    property Category: string read FCategory write SetCategory;
    property OnPick: TMPSymPickEvent read FOnPick write FOnPick;
  end;

const
  SCH_WIRE_COLOR = TColor($3C8C1E);   { verde }
  SCH_SYM_COLOR = TColor($7A2A10);    { azul escuro }
  SCH_SEL_COLOR = TColor($1E90F5);    { laranja }

{ desenha um simbolo num retangulo (galeria e previas) }
procedure MPPaintSymbol(Canvas: TCanvas; S: TMPSymbol; const R: TRect; C: TColor);

implementation

uses multisuite_controls;

const
  MAX_UNDO = 60;

{ ---------------- desenho de simbolo generico ---------------- }

type
  TXform = record
    OX, OY, Scale: Double;
    PX, PY: Double;   { posicao da parte }
    Rot: Integer;
  end;

function XPt(const T: TXform; LX, LY: Double): TPoint;
var
  WX, WY: Double;
begin
  case ((T.Rot mod 360) + 360) mod 360 of
    90: begin WX := T.PX - LY; WY := T.PY + LX; end;
    180: begin WX := T.PX - LX; WY := T.PY - LY; end;
    270: begin WX := T.PX + LY; WY := T.PY - LX; end;
  else begin WX := T.PX + LX; WY := T.PY + LY; end;
  end;
  Result := Point(Round(T.OX + WX * T.Scale), Round(T.OY - WY * T.Scale));
end;

procedure PaintSym(Canvas: TCanvas; S: TMPSymbol; const T: TXform; C: TColor; Width: Integer);
var
  I, R: Integer;
  Q: TPoint;
  Parts: TStringList;
  FS: TFormatSettings;
  TX, TY, TH: Double;
  St: TMPStrokes;
  J, K: Integer;
  Pts: array of TPoint;
begin
  Canvas.Pen.Color := C;
  Canvas.Pen.Width := Width;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsClear;
  I := 0;
  while I < High(S.Lines) do
  begin
    Canvas.Line(XPt(T, S.Lines[I].X, S.Lines[I].Y), XPt(T, S.Lines[I + 1].X, S.Lines[I + 1].Y));
    Inc(I, 2);
  end;
  for I := 0 to High(S.Circles) do
  begin
    Q := XPt(T, S.Circles[I].X, S.Circles[I].Y);
    R := Max(1, Round(S.Radii[I] * T.Scale));
    Canvas.Ellipse(Q.X - R, Q.Y - R, Q.X + R + 1, Q.Y + R + 1);
  end;
  { textos do simbolo (so sem rotacao, para continuarem legiveis) }
  if (S.Texts.Count > 0) and (T.Scale >= 3) then
  begin
    FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ';'; Parts.StrictDelimiter := True;
      for I := 0 to S.Texts.Count - 1 do
      begin
        Parts.DelimitedText := S.Texts[I];
        if Parts.Count < 4 then Continue;
        TX := StrToFloat(Parts[0], FS); TY := StrToFloat(Parts[1], FS); TH := StrToFloat(Parts[2], FS);
        if ((T.Rot mod 360) + 360) mod 360 <> 0 then Continue;
        St := MPTextStrokes(Parts[3], TX, TY, TH);
        Canvas.Pen.Width := 1;
        for J := 0 to High(St) do
        begin
          SetLength(Pts, Length(St[J]));
          for K := 0 to High(St[J]) do Pts[K] := XPt(T, St[J][K].X, St[J][K].Y);
          if Length(Pts) > 1 then Canvas.Polyline(Pts);
        end;
        Canvas.Pen.Width := Width;
      end;
    finally
      Parts.Free;
    end;
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure PaintPower(Canvas: TCanvas; Kind: TMPSymKind; P: TPoint; Scale: Double; C: TColor;
  const Name: string);
var
  U: Integer;
  St: TMPStrokes;
  J, K: Integer;
  Pts: array of TPoint;
  W, H: Double;
begin
  U := Max(3, Round(1.27 * Scale));
  Canvas.Pen.Color := C;
  Canvas.Pen.Width := Max(1, Round(Scale * 0.25));
  case Kind of
    symGround:
      begin
        Canvas.Line(P.X, P.Y, P.X, P.Y + U);
        Canvas.Line(P.X - U, P.Y + U, P.X + U + 1, P.Y + U);
        Canvas.Line(P.X - U * 2 div 3, P.Y + U + U div 3, P.X + U * 2 div 3 + 1, P.Y + U + U div 3);
        Canvas.Line(P.X - U div 3, P.Y + U + 2 * U div 3, P.X + U div 3 + 1, P.Y + U + 2 * U div 3);
      end;
    symPower:
      begin
        Canvas.Line(P.X, P.Y, P.X, P.Y - U);
        Canvas.Line(P.X - U, P.Y - U, P.X + U + 1, P.Y - U);
      end;
  else
    begin
      { rotulo: bandeira com o nome }
      Canvas.Brush.Color := clWhite;
      Canvas.Line(P.X, P.Y, P.X + U div 2, P.Y - U div 2);
    end;
  end;
  if Kind = symGround then Exit;
  { nome }
  H := 1.2;
  W := MPTextWidth(Name, H);
  if Kind = symPower then
    St := MPTextStrokes(Name, -W / 2, 1.27 * 1.25, H)
  else
    St := MPTextStrokes(Name, 0.8, 0.8, H);
  Canvas.Pen.Width := 1;
  for J := 0 to High(St) do
  begin
    SetLength(Pts, Length(St[J]));
    for K := 0 to High(St[J]) do
      Pts[K] := Point(P.X + Round(St[J][K].X * Scale), P.Y - Round(St[J][K].Y * Scale));
    if Length(Pts) > 1 then Canvas.Polyline(Pts);
  end;
end;

procedure MPPaintSymbol(Canvas: TCanvas; S: TMPSymbol; const R: TRect; C: TColor);
var
  B: TMPRect;
  T: TXform;
begin
  if S.Kind <> symPart then
  begin
    PaintPower(Canvas, S.Kind, Point((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2), 6, C,
      S.DefaultValue);
    Exit;
  end;
  B := S.Bounds;
  if not B.Valid then Exit;
  T.Scale := Min(Min((R.Right - R.Left - 12) / Max(1, B.MaxX - B.MinX),
    (R.Bottom - R.Top - 12) / Max(1, B.MaxY - B.MinY)), 7);
  T.PX := 0; T.PY := 0; T.Rot := 0;
  T.OX := (R.Left + R.Right) / 2 - (B.MinX + B.MaxX) / 2 * T.Scale;
  T.OY := (R.Top + R.Bottom) / 2 + (B.MinY + B.MaxY) / 2 * T.Scale;
  PaintSym(Canvas, S, T, C, Max(1, Round(T.Scale * 0.2)));
end;

{ ---------------- TMPSchematicEditor ---------------- }

constructor TMPSchematicEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FScale := 6;
  FUndo := TStringList.Create;
  FRedo := TStringList.Create;
  FSelIndex := -1;
  TabStop := True;
  DoubleBuffered := True;
  Color := clWhite;
end;

destructor TMPSchematicEditor.Destroy;
begin
  FUndo.Free;
  FRedo.Free;
  inherited Destroy;
end;

function TMPSchematicEditor.SX(X: Double): Integer;
begin
  Result := Round(FOX + X * FScale);
end;

function TMPSchematicEditor.SY(Y: Double): Integer;
begin
  Result := Round(FOY - Y * FScale);
end;

function TMPSchematicEditor.ToSch(PX, PY: Integer): TMPPoint;
begin
  Result.X := (PX - FOX) / FScale;
  Result.Y := (FOY - PY) / FScale;
end;

function TMPSchematicEditor.Snap(const P: TMPPoint): TMPPoint;
begin
  Result.X := Round(P.X / MP_SCH_GRID) * MP_SCH_GRID;
  Result.Y := Round(P.Y / MP_SCH_GRID) * MP_SCH_GRID;
end;

function TMPSchematicEditor.Ortho(const A, B: TMPPoint): TMPPoint;
begin
  if Abs(B.X - A.X) >= Abs(B.Y - A.Y) then Result := MPPoint(B.X, A.Y)
  else Result := MPPoint(A.X, B.Y);
end;

procedure TMPSchematicEditor.SetSchematic(ASch: TMPSchematic);
begin
  FSch := ASch;
  FSelKind := ssNone; FSelIndex := -1;
  FFitted := False;
  if ClientWidth > 100 then ZoomToFit;
  Invalidate;
end;

procedure TMPSchematicEditor.Status(const S: string);
begin
  if Assigned(FOnStatus) then FOnStatus(Self, S);
end;

procedure TMPSchematicEditor.DoChanged;
begin
  FModified := True;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMPSchematicEditor.Changed;
begin
  DoChanged;
end;

procedure TMPSchematicEditor.SetTool(T: TMPSchTool);
begin
  CancelOperation;
  FTool := T;
  case T of
    stWire: Status('Fio: clique nos pontos (horizontal/vertical); termina num pino ou fio, duplo clique ou botao direito.');
    stLabel: Status('Rotulo: clique num pino ou fio e de o nome da rede (pinos com o mesmo nome ficam ligados).');
    stPlace: Status('Clique para colocar. R gira, Esc termina.');
  else Status('Selecionar: arraste partes; R gira; Del apaga.');
  end;
  Invalidate;
end;

procedure TMPSchematicEditor.SetPlaceSymbol(S: TMPSymbol);
begin
  FPlaceSym := S;
  FGhostRot := 0;
  if S <> nil then
  begin
    FTool := stPlace;
    if S.Kind = symPart then Status('Colocar ' + S.Name + ': clique no esquema. R gira, Esc termina.')
    else Status('Colocar ' + S.Name + ': clique na ponta de um pino ou num fio.');
  end;
  Invalidate;
end;

procedure TMPSchematicEditor.ZoomToFit;
var
  B: TMPRect;
  W, H: Double;
begin
  if FSch = nil then Exit;
  B := FSch.Bounds;
  if not B.Valid then
  begin
    B := MPEmptyRect;
    MPRectInclude(B, 0, 0);
    MPRectInclude(B, 120, 80);
  end;
  W := Max(B.MaxX - B.MinX, 20) + 20;
  H := Max(B.MaxY - B.MinY, 20) + 20;
  FScale := EnsureRange(Min(ClientWidth / W, ClientHeight / H), 1, 40);
  FOX := ClientWidth / 2 - (B.MinX + B.MaxX) / 2 * FScale;
  FOY := ClientHeight / 2 + (B.MinY + B.MaxY) / 2 * FScale;
  FFitted := True;
  Invalidate;
end;

procedure TMPSchematicEditor.ZoomBy(F: Double);
var
  C: TMPPoint;
begin
  C := ToSch(ClientWidth div 2, ClientHeight div 2);
  FScale := EnsureRange(FScale * F, 1, 60);
  FOX := ClientWidth / 2 - C.X * FScale;
  FOY := ClientHeight / 2 + C.Y * FScale;
  Invalidate;
end;

procedure TMPSchematicEditor.Resize;
begin
  inherited Resize;
  if (FSch <> nil) and not FFitted and (ClientWidth > 100) then ZoomToFit;
end;

{ ---------------- historico ---------------- }

procedure TMPSchematicEditor.Snapshot;
begin
  if FSch = nil then Exit;
  FUndo.Add(FSch.ToJSON);
  while FUndo.Count > MAX_UNDO do FUndo.Delete(0);
  FRedo.Clear;
end;

procedure TMPSchematicEditor.Undo;
begin
  if (FSch = nil) or (FUndo.Count = 0) then Exit;
  CancelOperation;
  FRedo.Add(FSch.ToJSON);
  FSch.FromJSON(FUndo[FUndo.Count - 1]);
  FUndo.Delete(FUndo.Count - 1);
  Select(ssNone, -1);
  DoChanged;
end;

procedure TMPSchematicEditor.Redo;
begin
  if (FSch = nil) or (FRedo.Count = 0) then Exit;
  CancelOperation;
  FUndo.Add(FSch.ToJSON);
  FSch.FromJSON(FRedo[FRedo.Count - 1]);
  FRedo.Delete(FRedo.Count - 1);
  Select(ssNone, -1);
  DoChanged;
end;

procedure TMPSchematicEditor.ClearHistory;
begin
  FUndo.Clear;
  FRedo.Clear;
end;

{ ---------------- selecao ---------------- }

procedure TMPSchematicEditor.HitTest(const P: TMPPoint; out K: TMPSchSelKind; out I: Integer);
var
  N, J: Integer;
  B: TMPRect;
  Tol: Double;
  W: TMPSchWire;
begin
  K := ssNone; I := -1;
  if FSch = nil then Exit;
  Tol := Max(0.8, 5 / FScale);
  for N := FSch.LabelCount - 1 downto 0 do
    if MPDist(P, MPPoint(FSch.Label_(N).X, FSch.Label_(N).Y)) <= Tol * 1.5 then
    begin K := ssLabel; I := N; Exit; end;
  for N := FSch.PartCount - 1 downto 0 do
  begin
    B := FSch.Part(N).Bounds;
    if (P.X >= B.MinX - Tol) and (P.X <= B.MaxX + Tol) and (P.Y >= B.MinY - Tol) and (P.Y <= B.MaxY + Tol) then
    begin K := ssPart; I := N; Exit; end;
  end;
  for N := FSch.WireCount - 1 downto 0 do
  begin
    W := FSch.Wire(N);
    for J := 1 to High(W.Points) do
      if MPSegDist(P, W.Points[J - 1], W.Points[J]) <= Tol then
      begin K := ssWire; I := N; Exit; end;
  end;
end;

procedure TMPSchematicEditor.Select(K: TMPSchSelKind; I: Integer);
begin
  FSelKind := K;
  FSelIndex := I;
  if I < 0 then FSelKind := ssNone;
  Invalidate;
  if Assigned(FOnSelect) then FOnSelect(Self);
end;

procedure TMPSchematicEditor.DeleteSelection;
begin
  if (FSch = nil) or (FSelIndex < 0) then Exit;
  Snapshot;
  case FSelKind of
    ssPart: FSch.DeletePart(FSelIndex);
    ssWire: FSch.DeleteWire(FSelIndex);
    ssLabel: FSch.DeleteLabel(FSelIndex);
  else Exit;
  end;
  Select(ssNone, -1);
  DoChanged;
end;

procedure TMPSchematicEditor.RotateSelection;
begin
  if FTool = stPlace then
  begin
    FGhostRot := (FGhostRot + 90) mod 360;
    Invalidate;
    Exit;
  end;
  if (FSch = nil) or (FSelKind <> ssPart) or (FSelIndex < 0) then Exit;
  Snapshot;
  with FSch.Part(FSelIndex) do Rotation := (Rotation + 90) mod 360;
  DoChanged;
end;

procedure TMPSchematicEditor.CancelOperation;
begin
  SetLength(FPoints, 0);
  FDragging := False;
  Invalidate;
end;

function TMPSchematicEditor.PinAt(const P: TMPPoint): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  if FSch = nil then Exit;
  for I := 0 to FSch.PartCount - 1 do
    for J := 0 to High(FSch.Part(I).Symbol.Pins) do
      if MPDist(P, FSch.Part(I).PinPos(J)) < 0.01 then Exit(True);
end;

function TMPSchematicEditor.OnAnyWire(const P: TMPPoint): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  if FSch = nil then Exit;
  for I := 0 to FSch.WireCount - 1 do
    for J := 1 to High(FSch.Wire(I).Points) do
      if MPSegDist(P, FSch.Wire(I).Points[J - 1], FSch.Wire(I).Points[J]) < 0.01 then Exit(True);
end;

procedure TMPSchematicEditor.FinishWire;
var
  N: Integer;
begin
  N := Length(FPoints);
  { remove ponto repetido do duplo clique }
  if (N >= 2) and (MPDist(FPoints[N - 1], FPoints[N - 2]) < 1e-6) then
  begin
    SetLength(FPoints, N - 1);
    Dec(N);
  end;
  if N >= 2 then
  begin
    Snapshot;
    FSch.AddWire(FPoints);
    DoChanged;
  end;
  SetLength(FPoints, 0);
  Invalidate;
end;

{ ---------------- mouse e teclado ---------------- }

procedure TMPSchematicEditor.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P, Q: TMPPoint;
  K: TMPSchSelKind;
  I, N: Integer;
  Part: TMPPart;
  S: string;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  if FSch = nil then Exit;
  P := ToSch(X, Y);
  if (Button = mbMiddle) or ((Button = mbRight) and (FTool = stSelect)) then
  begin
    FPanning := True; FPanStart := Point(X, Y); FPanOX := FOX; FPanOY := FOY;
    Exit;
  end;
  if Button = mbRight then
  begin
    if FTool = stWire then FinishWire
    else SetTool(stSelect);
    Exit;
  end;
  Q := Snap(P);
  case FTool of
    stSelect:
      begin
        HitTest(P, K, I);
        Select(K, I);
        if K in [ssPart, ssLabel] then
        begin
          FDragging := True; FDragMoved := False;
          FDragStart := Q;
          if K = ssPart then FDragOrig := MPPoint(FSch.Part(I).X, FSch.Part(I).Y)
          else FDragOrig := MPPoint(FSch.Label_(I).X, FSch.Label_(I).Y);
          Snapshot;
        end;
      end;
    stPlace:
      if FPlaceSym <> nil then
      begin
        Snapshot;
        if FPlaceSym.Kind = symPart then
        begin
          Part := FSch.AddPart(FPlaceSym, Q.X, Q.Y);
          Part.Rotation := FGhostRot;
          Select(ssPart, FSch.PartCount - 1);
          Status(Part.Ref + ' colocado. Clique para outro; Esc termina.');
        end
        else
        begin
          FSch.AddLabel(FPlaceSym.DefaultValue, Q.X, Q.Y, FPlaceSym.Kind);
          if not (PinAt(Q) or OnAnyWire(Q)) then
            Status('Atencao: o simbolo so liga se ficar na ponta de um pino ou sobre um fio.');
        end;
        DoChanged;
      end;
    stWire:
      begin
        N := Length(FPoints);
        if N > 0 then Q := Ortho(FPoints[N - 1], Q);
        if (N = 0) or (MPDist(FPoints[N - 1], Q) > 1e-6) then
        begin
          SetLength(FPoints, N + 1);
          FPoints[N] := Q;
        end;
        { chegou num pino ou noutro fio: termina }
        if (Length(FPoints) >= 2) and (PinAt(Q) or OnAnyWire(Q)) then FinishWire;
        Invalidate;
      end;
    stLabel:
      begin
        S := '';
        if InputQuery('Rotulo de rede', 'Nome da rede (ex.: SAIDA, 5V, SDA):', S) and (Trim(S) <> '') then
        begin
          Snapshot;
          if SameText(Trim(S), 'GND') then FSch.AddLabel('GND', Q.X, Q.Y, symGround)
          else if SameText(Trim(S), 'VCC') then FSch.AddLabel('VCC', Q.X, Q.Y, symPower)
          else FSch.AddLabel(S, Q.X, Q.Y, symLabel);
          DoChanged;
        end;
      end;
  end;
end;

procedure TMPSchematicEditor.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  D: TMPPoint;
  FS: TFormatSettings;
begin
  inherited MouseMove(Shift, X, Y);
  if FPanning then
  begin
    FOX := FPanOX + (X - FPanStart.X);
    FOY := FPanOY + (Y - FPanStart.Y);
    Invalidate;
    Exit;
  end;
  if FSch = nil then Exit;
  FMouse := Snap(ToSch(X, Y));
  if FDragging and (FSelIndex >= 0) then
  begin
    D := MPPoint(FMouse.X - FDragStart.X, FMouse.Y - FDragStart.Y);
    if (Abs(D.X) > 1e-9) or (Abs(D.Y) > 1e-9) then FDragMoved := True;
    case FSelKind of
      ssPart: with FSch.Part(FSelIndex) do begin X := FDragOrig.X + D.X; Y := FDragOrig.Y + D.Y; end;
      ssLabel: with FSch.Label_(FSelIndex) do begin X := FDragOrig.X + D.X; Y := FDragOrig.Y + D.Y; end;
    end;
  end;
  FS := DefaultFormatSettings; FS.DecimalSeparator := ',';
  Status(Format('X %.2f  Y %.2f mm', [FMouse.X, FMouse.Y], FS));
  Invalidate;
end;

procedure TMPSchematicEditor.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FPanning then begin FPanning := False; Exit; end;
  if FDragging then
  begin
    FDragging := False;
    if FDragMoved then DoChanged
    else if FUndo.Count > 0 then FUndo.Delete(FUndo.Count - 1);
  end;
end;

procedure TMPSchematicEditor.DblClick;
begin
  inherited DblClick;
  if FTool = stWire then FinishWire;
end;

function TMPSchematicEditor.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  P: TMPPoint;
  F: Double;
begin
  Result := True;
  P := ToSch(MousePos.X, MousePos.Y);
  if WheelDelta > 0 then F := 1.2 else F := 1 / 1.2;
  FScale := EnsureRange(FScale * F, 1, 60);
  FOX := MousePos.X - P.X * FScale;
  FOY := MousePos.Y + P.Y * FScale;
  Invalidate;
end;

procedure TMPSchematicEditor.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_ESCAPE:
      begin
        if Length(FPoints) > 0 then CancelOperation
        else if FTool <> stSelect then SetTool(stSelect)
        else Select(ssNone, -1);
        Key := 0;
      end;
    VK_DELETE: begin DeleteSelection; Key := 0; end;
    VK_R: begin RotateSelection; Key := 0; end;
    VK_BACK:
      if Length(FPoints) > 0 then
      begin
        SetLength(FPoints, Length(FPoints) - 1);
        Invalidate; Key := 0;
      end;
  end;
end;

{ ---------------- desenho ---------------- }

procedure TMPSchematicEditor.DrawText(const S: string; X, Y, H: Double; C: TColor);
var
  St: TMPStrokes;
  J, K: Integer;
  Pts: array of TPoint;
begin
  St := MPTextStrokes(S, X, Y, H);
  Canvas.Pen.Color := C;
  Canvas.Pen.Width := 1;
  for J := 0 to High(St) do
  begin
    SetLength(Pts, Length(St[J]));
    for K := 0 to High(St[J]) do Pts[K] := Point(SX(St[J][K].X), SY(St[J][K].Y));
    if Length(Pts) > 1 then Canvas.Polyline(Pts);
  end;
end;

procedure TMPSchematicEditor.DrawSymbol(S: TMPSymbol; Part: TMPPart; GX, GY: Double; Rot: Integer; C: TColor);
var
  T: TXform;
  I: Integer;
  B: TMPRect;
  Q: TPoint;
begin
  T.OX := FOX; T.OY := FOY; T.Scale := FScale;
  T.PX := GX; T.PY := GY; T.Rot := Rot;
  PaintSym(Canvas, S, T, C, Max(1, Round(FScale * 0.22)));
  { pontas dos pinos }
  Canvas.Brush.Color := C;
  Canvas.Pen.Color := C;
  for I := 0 to High(S.Pins) do
  begin
    Q := XPt(T, S.Pins[I].X, S.Pins[I].Y);
    Canvas.Ellipse(Q.X - 2, Q.Y - 2, Q.X + 3, Q.Y + 3);
  end;
  if Part <> nil then
  begin
    B := Part.Bounds;
    if (B.MaxY - B.MinY > 8) and (B.MaxX - B.MinX > 8) then
    begin
      { parte grande (CI): referencia em cima, valor embaixo }
      DrawText(Part.Ref, (B.MinX + B.MaxX) / 2 - MPTextWidth(Part.Ref, 1.4) / 2, B.MaxY + 0.8, 1.4, C);
      if Part.Value <> '' then
        DrawText(Part.Value, (B.MinX + B.MaxX) / 2 - MPTextWidth(Part.Value, 1.2) / 2, B.MinY - 2.0,
          1.2, TColor($5A5A5A));
    end
    else
    begin
      DrawText(Part.Ref, B.MaxX + 0.6, (B.MinY + B.MaxY) / 2 + 0.4, 1.4, C);
      if Part.Value <> '' then
        DrawText(Part.Value, B.MaxX + 0.6, (B.MinY + B.MaxY) / 2 - 1.8, 1.2, TColor($5A5A5A));
    end;
  end;
end;

procedure TMPSchematicEditor.DrawLabel(L: TMPSchLabel; C: TColor);
begin
  PaintPower(Canvas, L.Kind, Point(SX(L.X), SY(L.Y)), FScale, C, L.Name);
end;

procedure TMPSchematicEditor.Paint;
var
  I, J, K, Cnt, Step: Integer;
  X, Y: Double;
  C: TColor;
  W: TMPSchWire;
  Pts: array of TPoint;
  Ends: TMPPoints;
  P: TMPPoint;
  G: TMPPoint;
  A: TPoint;
begin
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(ClientRect);
  if FSch = nil then Exit;
  { grade de pontos }
  Step := 1;
  while MP_SCH_GRID * Step * FScale < 9 do Step := Step * 2;
  G := ToSch(0, ClientHeight);
  X := Floor(G.X / (MP_SCH_GRID * Step)) * MP_SCH_GRID * Step;
  while SX(X) < ClientWidth do
  begin
    Y := Floor(G.Y / (MP_SCH_GRID * Step)) * MP_SCH_GRID * Step;
    while SY(Y) > 0 do
    begin
      Canvas.Pixels[SX(X), SY(Y)] := TColor($C8BEB4);
      Y := Y + MP_SCH_GRID * Step;
    end;
    X := X + MP_SCH_GRID * Step;
  end;
  { fios }
  for I := 0 to FSch.WireCount - 1 do
  begin
    W := FSch.Wire(I);
    SetLength(Pts, Length(W.Points));
    for J := 0 to High(W.Points) do Pts[J] := Point(SX(W.Points[J].X), SY(W.Points[J].Y));
    if (FSelKind = ssWire) and (FSelIndex = I) then C := SCH_SEL_COLOR else C := SCH_WIRE_COLOR;
    Canvas.Pen.Color := C;
    Canvas.Pen.Width := Max(1, Round(FScale * 0.25));
    Canvas.Polyline(Pts);
    { pontas para as juncoes }
    SetLength(Ends, Length(Ends) + 2);
    Ends[High(Ends) - 1] := W.Points[0];
    Ends[High(Ends)] := W.Points[High(W.Points)];
  end;
  { juncoes: ponta de fio no meio de outro, ou 3+ pontas }
  Canvas.Brush.Color := SCH_WIRE_COLOR;
  Canvas.Pen.Color := SCH_WIRE_COLOR;
  for I := 0 to High(Ends) do
  begin
    P := Ends[I];
    Cnt := 0;
    for K := 0 to FSch.WireCount - 1 do
    begin
      W := FSch.Wire(K);
      for J := 1 to High(W.Points) do
        if MPSegDist(P, W.Points[J - 1], W.Points[J]) < 0.01 then
        begin
          if (MPDist(P, W.Points[0]) < 0.01) or (MPDist(P, W.Points[High(W.Points)]) < 0.01) then Inc(Cnt)
          else Inc(Cnt, 2);
          Break;
        end;
    end;
    if Cnt >= 3 then
    begin
      A := Point(SX(P.X), SY(P.Y));
      J := Max(2, Round(FScale * 0.5));
      Canvas.Ellipse(A.X - J, A.Y - J, A.X + J + 1, A.Y + J + 1);
    end;
  end;
  { partes }
  for I := 0 to FSch.PartCount - 1 do
  begin
    if (FSelKind = ssPart) and (FSelIndex = I) then C := SCH_SEL_COLOR else C := SCH_SYM_COLOR;
    DrawSymbol(FSch.Part(I).Symbol, FSch.Part(I), FSch.Part(I).X, FSch.Part(I).Y, FSch.Part(I).Rotation, C);
  end;
  { rotulos }
  for I := 0 to FSch.LabelCount - 1 do
  begin
    if (FSelKind = ssLabel) and (FSelIndex = I) then C := SCH_SEL_COLOR else C := SCH_SYM_COLOR;
    DrawLabel(FSch.Label_(I), C);
  end;
  { em construcao }
  if (FTool = stWire) and (Length(FPoints) > 0) then
  begin
    SetLength(Pts, Length(FPoints) + 1);
    for I := 0 to High(FPoints) do Pts[I] := Point(SX(FPoints[I].X), SY(FPoints[I].Y));
    P := Ortho(FPoints[High(FPoints)], FMouse);
    Pts[High(Pts)] := Point(SX(P.X), SY(P.Y));
    Canvas.Pen.Color := SCH_SEL_COLOR;
    Canvas.Pen.Width := Max(1, Round(FScale * 0.25));
    Canvas.Polyline(Pts);
  end;
  if (FTool = stPlace) and (FPlaceSym <> nil) then
  begin
    if FPlaceSym.Kind = symPart then
      DrawSymbol(FPlaceSym, nil, FMouse.X, FMouse.Y, FGhostRot, SCH_SEL_COLOR)
    else
      PaintPower(Canvas, FPlaceSym.Kind, Point(SX(FMouse.X), SY(FMouse.Y)), FScale, SCH_SEL_COLOR,
        FPlaceSym.DefaultValue);
  end;
  if FTool in [stWire, stLabel, stPlace] then
  begin
    A := Point(SX(FMouse.X), SY(FMouse.Y));
    Canvas.Pen.Color := SCH_SEL_COLOR; Canvas.Pen.Width := 1;
    Canvas.Line(A.X - 7, A.Y, A.X + 8, A.Y);
    Canvas.Line(A.X, A.Y - 7, A.X, A.Y + 8);
  end;
end;

{ ---------------- TMPSymbolGallery ---------------- }

const
  STILE_H = 84;
  SGAP = 8;

constructor TMPSymbolGallery.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList.Create;
  FSelected := -1; FHot := -1;
  Color := clSuiteCard;
  DoubleBuffered := True;
  Rebuild;
end;

destructor TMPSymbolGallery.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TMPSymbolGallery.SetCategory(const AValue: string);
begin
  FCategory := AValue;
  Rebuild;
end;

procedure TMPSymbolGallery.Rebuild;
var
  I: Integer;
begin
  FItems.Clear;
  for I := 0 to MPSymbols.Count - 1 do
    if (FCategory = '') or SameText(MPSymbols.Item(I).Category, FCategory) then
      FItems.Add(MPSymbols.Item(I));
  FSelected := -1;
  Height := NeededHeight;
  Invalidate;
end;

function TMPSymbolGallery.NeededHeight: Integer;
begin
  Result := Max(40, SGAP + ((FItems.Count + 1) div 2) * (STILE_H + SGAP));
end;

function TMPSymbolGallery.TileRect(I: Integer): TRect;
var
  W: Integer;
begin
  W := (ClientWidth - SGAP * 3) div 2;
  Result.Left := SGAP + (I mod 2) * (W + SGAP);
  Result.Top := SGAP + (I div 2) * (STILE_H + SGAP);
  Result.Right := Result.Left + W;
  Result.Bottom := Result.Top + STILE_H;
end;

function TMPSymbolGallery.IndexAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if PtInRect(TileRect(I), Point(X, Y)) then Exit(I);
  Result := -1;
end;

procedure TMPSymbolGallery.Paint;
var
  I: Integer;
  R, RS: TRect;
  S: TMPSymbol;
  T: string;
begin
  Canvas.Brush.Color := clSuiteCard;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Name := SUITE_FONT;
  for I := 0 to FItems.Count - 1 do
  begin
    S := TMPSymbol(FItems[I]);
    R := TileRect(I);
    Canvas.Pen.Width := 1;
    if I = FSelected then begin Canvas.Brush.Color := TColor($FFF1E3); Canvas.Pen.Color := clSuitePrimary; Canvas.Pen.Width := 2; end
    else if I = FHot then begin Canvas.Brush.Color := clWhite; Canvas.Pen.Color := clSuitePrimary; end
    else begin Canvas.Brush.Color := clWhite; Canvas.Pen.Color := clSuiteBorder; end;
    Canvas.RoundRect(R, 10, 10);
    RS := Rect(R.Left + 4, R.Top + 4, R.Right - 4, R.Bottom - 22);
    MPPaintSymbol(Canvas, S, RS, SCH_SYM_COLOR);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Size := 8;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := clSuiteText;
    T := S.Name;
    while (Canvas.TextWidth(T) > R.Right - R.Left - 8) and (Length(T) > 3) do T := Copy(T, 1, Length(T) - 2) + '.';
    Canvas.TextOut(R.Left + (R.Right - R.Left - Canvas.TextWidth(T)) div 2, R.Bottom - 19, T);
    Canvas.Font.Style := [];
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TMPSymbolGallery.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  I := IndexAt(X, Y);
  if I < 0 then Exit;
  FSelected := I;
  Invalidate;
  if Assigned(FOnPick) then FOnPick(Self, TMPSymbol(FItems[I]));
end;

procedure TMPSymbolGallery.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  I := IndexAt(X, Y);
  if I <> FHot then
  begin
    FHot := I;
    Invalidate;
  end;
end;

procedure TMPSymbolGallery.ClearSelection;
begin
  FSelected := -1;
  Invalidate;
end;

end.
