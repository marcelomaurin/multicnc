unit makepcb_render;

{ Desenho da placa do MakePCB num TCanvas.

  Vistas (como as abas verticais do PCB Wizard):
    vmNormal      - edicao: grade de pontos, cobre colorido por face
                    (Top vermelho, Bottom verde, como no LaserPCB),
                    contornos dos componentes e ligacoes pendentes.
    vmRealWorld   - placa montada: FR4 verde com mascara, pads estanhados,
                    serigrafia branca e corpo de cada componente.
    vmUnpopulated - igual ao mundo real, sem os componentes.
    vmArtwork     - arte final: cobre preto em fundo branco, furos abertos,
                    para conferir/imprimir (transferencia termica).

  Coordenadas da placa em mm, Y para cima; TMPViewport faz a conversao
  para pixels. A mesma rotina desenha um footprint isolado (galeria). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Types, makepcb_model, makepcb_font,
  makepcb_route, makepcb_drc, makepcb_gerber;

type
  TMPViewMode = (vmNormal, vmRealWorld, vmUnpopulated, vmArtwork);

  TMPViewport = record
    Scale: Double;      { pixels por mm }
    OX, OY: Double;     { pixel da origem (0,0) da placa }
  end;

  TMPSelKind = (selNone, selComponent, selTrack, selText, selArea);

  TMPRenderer = class
  private
    FCanvas: TCanvas;
    FV: TMPViewport;
    FBare: Boolean;     { so o componente (galeria) }
    function SX(X: Double): Integer; inline;
    function SY(Y: Double): Integer; inline;
    function SP(const P: TMPPoint): TPoint; inline;
    function MPx(MM: Double; MinPx: Integer = 1): Integer;
    procedure ThickLine(const A, B: TMPPoint; Width: Double; C: TColor);
    procedure Polyline(const P: TMPPoints; Width: Double; C: TColor);
    procedure FillPoly(const P: TMPPoints; C: TColor);
    procedure PadShape(Comp: TMPComponent; I: Integer; Grow: Double; C: TColor);
    procedure Hole(Comp: TMPComponent; I: Integer; C: TColor);
    procedure Strokes(const S: TMPStrokes; Width: Double; C: TColor);
    procedure DrawGrid;
    procedure DrawLayerCopper(L: TMPLayer; C, Bg: TColor);
    procedure DrawSilkOf(Comp: TMPComponent; C: TColor; Width: Double);
    procedure DrawBody(Comp: TMPComponent);
    procedure DrawRefs(C: TColor);
    function CopperColor(L: TMPLayer): TColor;
  public
    Doc: TMPDocument;
    Mode: TMPViewMode;
    ShowTop, ShowBottom, ShowSilk, ShowGrid, ShowRatsnest: Boolean;
    ArtworkLayer: TMPLayer;        { face impressa na arte final }
    ArtworkMirror: Boolean;
    SelKind: TMPSelKind;
    SelIndex: Integer;
    HighlightNet: Integer;         { -1 = nenhuma }
    Issues: TMPDrcIssues;
    constructor Create;
    procedure Paint(ACanvas: TCanvas; const AView: TMPViewport; const ARect: TRect);
    { footprint isolado centrado no retangulo (galeria) }
    procedure PaintFootprint(ACanvas: TCanvas; FP: TMPFootprint; const ARect: TRect;
      AMode: TMPViewMode);
    { componente "fantasma" seguindo o mouse }
    procedure PaintGhost(ACanvas: TCanvas; const AView: TMPViewport; Comp: TMPComponent);
  end;

function MPColor(RGB: LongWord): TColor;
function MPToScreen(const V: TMPViewport; X, Y: Double): TPoint;
function MPToBoard(const V: TMPViewport; PX, PY: Integer): TMPPoint;
function ViewModeName(M: TMPViewMode): string;

const
  MP_TOP_COLOR = TColor($3E48CD);      { RGB(205,72,62) - igual ao LaserPCB }
  MP_BOTTOM_COLOR = TColor($5C962E);   { RGB(46,150,92) }
  MP_SELECT_COLOR = TColor($1E90F5);   { laranja }
  MP_SILK_COLOR = TColor($5A3A1F);     { azul-marinho }
  MP_RATS_COLOR = TColor($C08040);

implementation

function MPColor(RGB: LongWord): TColor;
begin
  Result := RGBToColor((RGB shr 16) and $FF, (RGB shr 8) and $FF, RGB and $FF);
end;

function MPToScreen(const V: TMPViewport; X, Y: Double): TPoint;
begin
  Result.X := Round(V.OX + X * V.Scale);
  Result.Y := Round(V.OY - Y * V.Scale);
end;

function MPToBoard(const V: TMPViewport; PX, PY: Integer): TMPPoint;
begin
  Result.X := (PX - V.OX) / V.Scale;
  Result.Y := (V.OY - PY) / V.Scale;
end;

function ViewModeName(M: TMPViewMode): string;
begin
  case M of
    vmNormal: Result := 'Normal';
    vmRealWorld: Result := 'Mundo real';
    vmUnpopulated: Result := 'Sem componentes';
    vmArtwork: Result := 'Arte final';
  end;
end;

function Blend(A, B: TColor; T: Double): TColor;
var
  CA, CB: LongInt;
begin
  CA := ColorToRGB(A); CB := ColorToRGB(B);
  Result := RGBToColor(
    Round(Red(CA) + (Red(CB) - Red(CA)) * T),
    Round(Green(CA) + (Green(CB) - Green(CA)) * T),
    Round(Blue(CA) + (Blue(CB) - Blue(CA)) * T));
end;

{ ---------------- TMPRenderer ---------------- }

constructor TMPRenderer.Create;
begin
  inherited Create;
  Mode := vmNormal;
  ShowTop := True; ShowBottom := True; ShowSilk := True; ShowGrid := True;
  ShowRatsnest := True;
  ArtworkLayer := mlBottomCopper;
  ArtworkMirror := False;
  SelKind := selNone; SelIndex := -1;
  HighlightNet := -1;
end;

function TMPRenderer.SX(X: Double): Integer;
begin
  if ArtworkMirror and (Mode = vmArtwork) and (Doc <> nil) then X := Doc.BoardW - X;
  Result := Round(FV.OX + X * FV.Scale);
end;

function TMPRenderer.SY(Y: Double): Integer;
begin
  Result := Round(FV.OY - Y * FV.Scale);
end;

function TMPRenderer.SP(const P: TMPPoint): TPoint;
begin
  Result := Point(SX(P.X), SY(P.Y));
end;

function TMPRenderer.MPx(MM: Double; MinPx: Integer): Integer;
begin
  Result := Max(MinPx, Round(MM * FV.Scale));
end;

procedure TMPRenderer.ThickLine(const A, B: TMPPoint; Width: Double; C: TColor);
begin
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Color := C;
  FCanvas.Pen.Width := MPx(Width);
  FCanvas.Pen.EndCap := pecRound;
  FCanvas.Pen.JoinStyle := pjsRound;
  FCanvas.Line(SP(A), SP(B));
end;

procedure TMPRenderer.Polyline(const P: TMPPoints; Width: Double; C: TColor);
var
  Pts: array of TPoint;
  I: Integer;
begin
  if Length(P) = 0 then Exit;
  if Length(P) = 1 then
  begin
    FCanvas.Brush.Style := bsSolid; FCanvas.Brush.Color := C;
    FCanvas.Pen.Style := psClear;
    FCanvas.Ellipse(SX(P[0].X) - MPx(Width / 2), SY(P[0].Y) - MPx(Width / 2),
      SX(P[0].X) + MPx(Width / 2) + 1, SY(P[0].Y) + MPx(Width / 2) + 1);
    FCanvas.Pen.Style := psSolid;
    Exit;
  end;
  SetLength(Pts, Length(P));
  for I := 0 to High(P) do Pts[I] := SP(P[I]);
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Color := C;
  FCanvas.Pen.Width := MPx(Width);
  FCanvas.Pen.EndCap := pecRound;
  FCanvas.Pen.JoinStyle := pjsRound;
  FCanvas.Polyline(Pts);
end;

procedure TMPRenderer.FillPoly(const P: TMPPoints; C: TColor);
var
  Pts: array of TPoint;
  I: Integer;
begin
  if Length(P) < 3 then Exit;
  SetLength(Pts, Length(P));
  for I := 0 to High(P) do Pts[I] := SP(P[I]);
  FCanvas.Pen.Style := psClear;
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := C;
  FCanvas.Polygon(Pts);
  FCanvas.Pen.Style := psSolid;
end;

procedure TMPRenderer.PadShape(Comp: TMPComponent; I: Integer; Grow: Double; C: TColor);
var
  P: TPoint;
  W, H: Double;
  HW, HH, R: Integer;
begin
  Comp.PadSize(I, W, H);
  W := W + 2 * Grow; H := H + 2 * Grow;
  P := SP(Comp.PadPos(I));
  HW := Max(1, Round(W * FV.Scale / 2)); HH := Max(1, Round(H * FV.Scale / 2));
  FCanvas.Pen.Style := psClear;
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := C;
  case Comp.Footprint.Pads[I].Shape of
    psSquare: FCanvas.Rectangle(P.X - HW, P.Y - HH, P.X + HW + 1, P.Y + HH + 1);
    psOblong:
      begin
        R := Min(HW, HH) * 2;
        FCanvas.RoundRect(P.X - HW, P.Y - HH, P.X + HW + 1, P.Y + HH + 1, R, R);
      end;
  else
    FCanvas.Ellipse(P.X - HW, P.Y - HH, P.X + HW + 1, P.Y + HH + 1);
  end;
  FCanvas.Pen.Style := psSolid;
end;

procedure TMPRenderer.Hole(Comp: TMPComponent; I: Integer; C: TColor);
var
  P: TPoint;
  R: Integer;
begin
  P := SP(Comp.PadPos(I));
  R := Max(1, Round(Comp.Footprint.Pads[I].Drill * FV.Scale / 2));
  FCanvas.Pen.Style := psClear;
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := C;
  FCanvas.Ellipse(P.X - R, P.Y - R, P.X + R + 1, P.Y + R + 1);
  FCanvas.Pen.Style := psSolid;
end;

procedure TMPRenderer.Strokes(const S: TMPStrokes; Width: Double; C: TColor);
var
  I: Integer;
begin
  for I := 0 to High(S) do Polyline(S[I], Width, C);
end;

procedure TMPRenderer.DrawGrid;
var
  G, X, Y: Double;
  Step: Integer;
  C: TColor;
  PX, PY: Integer;
begin
  G := Doc.Grid;
  if G <= 0 then G := MP_GRID;
  Step := 1;
  while G * Step * FV.Scale < 7 do Step := Step * 2;
  G := G * Step;
  if Mode = vmNormal then C := TColor($C8BEB4) else C := TColor($6E9A5A);
  X := 0;
  while X <= Doc.BoardW + 1e-6 do
  begin
    Y := 0;
    PX := SX(X);
    while Y <= Doc.BoardH + 1e-6 do
    begin
      PY := SY(Y);
      FCanvas.Pixels[PX, PY] := C;
      Y := Y + G;
    end;
    X := X + G;
  end;
end;

function TMPRenderer.CopperColor(L: TMPLayer): TColor;
begin
  case Mode of
    vmArtwork: Result := clBlack;
    vmRealWorld, vmUnpopulated:
      if L = mlTopCopper then Result := TColor($4CA84C)   { cobre sob a mascara }
      else Result := TColor($3C8F3C);
  else
    if L = mlTopCopper then Result := MP_TOP_COLOR else Result := MP_BOTTOM_COLOR;
  end;
end;

procedure TMPRenderer.DrawLayerCopper(L: TMPLayer; C, Bg: TColor);
var
  K, I, J: Integer;
  Ar: TMPArea;
  T: TMPTrack;
  Tx: TMPText;
  Clr, W: Double;
  Net: Integer;
  TC: TColor;
begin
  { areas de cobre: poligono, folga para as outras redes, itens por cima }
  for K := 0 to Doc.AreaCount - 1 do
  begin
    Ar := Doc.Area(K);
    if Ar.Layer <> L then Continue;
    if Mode = vmNormal then FillPoly(Ar.Points, Blend(C, clWhite, 0.55))
    else FillPoly(Ar.Points, C);
    Clr := Max(Ar.Clearance, Doc.Clearance);
    for I := 0 to Doc.ComponentCount - 1 do
      for J := 0 to Doc.Component(I).PadCount - 1 do
        if not Doc.PadInArea(K, I, J) then PadShape(Doc.Component(I), J, Clr, Bg);
    for I := 0 to Doc.TrackCount - 1 do
      if (Doc.Track(I).Layer = L) and not Doc.TrackInArea(K, I) then
        Polyline(Doc.Track(I).Points, Doc.Track(I).Width + 2 * Clr, Bg);
    for I := 0 to Doc.TextCount - 1 do
      if Doc.Text(I).Layer = L then
      begin
        Tx := Doc.Text(I);
        Strokes(MPTextStrokes(Tx.Text, Tx.X, Tx.Y, Tx.Height, L = mlBottomCopper),
          MPTextStrokeWidth(Tx.Height) + 2 * Clr, Bg);
      end;
    if (SelKind = selArea) and (SelIndex = K) then
    begin
      Polyline(Ar.Points, 0, MP_SELECT_COLOR);
      if Length(Ar.Points) > 1 then
        ThickLine(Ar.Points[High(Ar.Points)], Ar.Points[0], 0, MP_SELECT_COLOR);
    end;
  end;
  { trilhas }
  for I := 0 to Doc.TrackCount - 1 do
  begin
    T := Doc.Track(I);
    if T.Layer <> L then Continue;
    TC := C;
    if (Mode = vmNormal) and (HighlightNet >= 0) then
    begin
      Net := Doc.TrackNet(I);
      if Net = HighlightNet then TC := MP_SELECT_COLOR;
    end;
    W := T.Width;
    Polyline(T.Points, W, TC);
    if (SelKind = selTrack) and (SelIndex = I) and (Mode = vmNormal) then
      Polyline(T.Points, Max(W * 0.35, 1 / FV.Scale), MP_SELECT_COLOR);
  end;
  { textos no cobre }
  for I := 0 to Doc.TextCount - 1 do
  begin
    Tx := Doc.Text(I);
    if Tx.Layer <> L then Continue;
    TC := C;
    if (SelKind = selText) and (SelIndex = I) and (Mode = vmNormal) then TC := MP_SELECT_COLOR;
    Strokes(MPTextStrokes(Tx.Text, Tx.X, Tx.Y, Tx.Height, L = mlBottomCopper),
      MPTextStrokeWidth(Tx.Height), TC);
  end;
end;

procedure TMPRenderer.DrawSilkOf(Comp: TMPComponent; C: TColor; Width: Double);
var
  I: Integer;
  S: TMPSilk;
  P: TMPPoints;
  Q: TPoint;
  R: Integer;
begin
  for I := 0 to High(Comp.Footprint.Silk) do
  begin
    S := Comp.Footprint.Silk[I];
    case S.Kind of
      skLine: ThickLine(Comp.LocalToWorld(S.X1, S.Y1), Comp.LocalToWorld(S.X2, S.Y2), Width, C);
      skCircle:
        begin
          Q := SP(Comp.LocalToWorld(S.X1, S.Y1));
          R := Round(S.R * FV.Scale);
          FCanvas.Brush.Style := bsClear;
          FCanvas.Pen.Style := psSolid; FCanvas.Pen.Color := C; FCanvas.Pen.Width := MPx(Width);
          FCanvas.Ellipse(Q.X - R, Q.Y - R, Q.X + R + 1, Q.Y + R + 1);
          FCanvas.Brush.Style := bsSolid;
        end;
      skRect:
        begin
          SetLength(P, 5);
          P[0] := Comp.LocalToWorld(S.X1, S.Y1);
          P[1] := Comp.LocalToWorld(S.X2, S.Y1);
          P[2] := Comp.LocalToWorld(S.X2, S.Y2);
          P[3] := Comp.LocalToWorld(S.X1, S.Y2);
          P[4] := P[0];
          Polyline(P, Width, C);
        end;
    end;
  end;
end;

procedure TMPRenderer.DrawRefs(C: TColor);
var
  I: Integer;
  Comp: TMPComponent;
  P: TMPPoint;
begin
  for I := 0 to Doc.ComponentCount - 1 do
  begin
    Comp := Doc.Component(I);
    if (Comp.Ref = '') or Comp.IsPadOnly then Continue;
    P := MPRefPosition(Comp);
    Strokes(MPTextStrokes(Comp.Ref, P.X, P.Y, 1.2), MPTextStrokeWidth(1.2), C);
  end;
end;

{ corpo do componente na visao mundo real }
procedure TMPRenderer.DrawBody(Comp: TMPComponent);
var
  FP: TMPFootprint;
  A, B, Cn: TMPPoint;
  R: TRect;
  BodyC, Dark, Light: TColor;
  I, W, H, Rad, K: Integer;
  Horizontal: Boolean;
  P1, P2: TMPPoint;

  procedure Box(ARect: TRect; Fill, Edge: TColor; Round_: Integer);
  begin
    FCanvas.Brush.Style := bsSolid; FCanvas.Brush.Color := Fill;
    FCanvas.Pen.Style := psSolid; FCanvas.Pen.Color := Edge; FCanvas.Pen.Width := 1;
    if Round_ > 0 then FCanvas.RoundRect(ARect, Round_, Round_)
    else FCanvas.Rectangle(ARect);
  end;

  procedure Disc(Ctr: TPoint; Radius: Integer; Fill, Edge: TColor);
  begin
    FCanvas.Brush.Style := bsSolid; FCanvas.Brush.Color := Fill;
    FCanvas.Pen.Style := psSolid; FCanvas.Pen.Color := Edge; FCanvas.Pen.Width := 1;
    FCanvas.Ellipse(Ctr.X - Radius, Ctr.Y - Radius, Ctr.X + Radius + 1, Ctr.Y + Radius + 1);
  end;

const
  Bands: array[0..3] of TColor = (TColor($2A4A8B), clBlack, TColor($1E1EC8), TColor($1C9CD4));
begin
  FP := Comp.Footprint;
  if FP.Body in [bkNone, bkPad] then Exit;
  A := Comp.LocalToWorld(FP.BodyX1, FP.BodyY1);
  B := Comp.LocalToWorld(FP.BodyX2, FP.BodyY2);
  R := Rect(Min(SX(A.X), SX(B.X)), Min(SY(A.Y), SY(B.Y)), Max(SX(A.X), SX(B.X)), Max(SY(A.Y), SY(B.Y)));
  W := R.Right - R.Left; H := R.Bottom - R.Top;
  Cn := Comp.LocalToWorld((FP.BodyX1 + FP.BodyX2) / 2, (FP.BodyY1 + FP.BodyY2) / 2);
  BodyC := MPColor(FP.BodyColor);
  Dark := Blend(BodyC, clBlack, 0.45);
  Light := Blend(BodyC, clWhite, 0.45);
  Horizontal := W >= H;
  { terminais (pernas) dos axiais ate os pads }
  if FP.Body in [bkResistor, bkDiode] then
    if (Length(FP.Pads) = 2) and (Abs(FP.Pads[1].X - FP.Pads[0].X) > Abs(FP.BodyX2 - FP.BodyX1)) then
    begin
      P1 := Comp.PadPos(0); P2 := Comp.PadPos(1);
      ThickLine(P1, P2, 0.6, TColor($B4B4B4));
    end;
  if (FP.Body = bkCapElectrolytic) and (Length(FP.Pads) = 2) and
     (Abs(FP.Pads[1].X - FP.Pads[0].X) > Abs(FP.BodyX2 - FP.BodyX1)) then
    ThickLine(Comp.PadPos(0), Comp.PadPos(1), 0.6, TColor($B4B4B4));
  case FP.Body of
    bkResistor:
      begin
        Box(R, BodyC, Dark, Min(W, H));
        { faixas de cor }
        for K := 0 to 3 do
          if Horizontal then
          begin
            I := R.Left + W * (2 + K * 2) div 12;
            FCanvas.Brush.Color := Bands[K]; FCanvas.Pen.Style := psClear;
            FCanvas.Rectangle(I, R.Top + 1, I + Max(2, W div 14), R.Bottom);
          end
          else
          begin
            I := R.Top + H * (2 + K * 2) div 12;
            FCanvas.Brush.Color := Bands[K]; FCanvas.Pen.Style := psClear;
            FCanvas.Rectangle(R.Left + 1, I, R.Right, I + Max(2, H div 14));
          end;
        FCanvas.Pen.Style := psSolid;
      end;
    bkDiode:
      begin
        Box(R, BodyC, Dark, Min(W, H) div 2);
        FCanvas.Brush.Color := TColor($DCDCDC); FCanvas.Pen.Style := psClear;
        if Horizontal then FCanvas.Rectangle(R.Right - Max(2, W div 6), R.Top + 1, R.Right - Max(1, W div 10), R.Bottom)
        else FCanvas.Rectangle(R.Left + 1, R.Top + Max(1, H div 10), R.Right, R.Top + Max(2, H div 6));
        FCanvas.Pen.Style := psSolid;
      end;
    bkCapCeramic, bkLDR, bkBuzzer, bkLED:
      begin
        Rad := Min(W, H) div 2;
        Disc(SP(Cn), Rad, BodyC, Dark);
        Disc(Point(SP(Cn).X - Rad div 3, SP(Cn).Y - Rad div 3), Max(1, Rad div 3), Light, Light);
        if FP.Body = bkLDR then
        begin
          FCanvas.Pen.Color := TColor($2050A0); FCanvas.Pen.Width := Max(1, Rad div 8);
          for K := -1 to 1 do
            FCanvas.Line(SP(Cn).X - Rad div 2, SP(Cn).Y + K * Rad div 3, SP(Cn).X + Rad div 2, SP(Cn).Y + K * Rad div 3);
        end;
        if FP.Body = bkBuzzer then Disc(SP(Cn), Max(1, Rad div 5), clBlack, TColor($505050));
      end;
    bkCapElectrolytic:
      begin
        if (Abs(FP.BodyX2 - FP.BodyX1 - (FP.BodyY2 - FP.BodyY1)) < 0.01) then
        begin
          Rad := Min(W, H) div 2;
          Disc(SP(Cn), Rad, BodyC, Dark);
          { faixa do negativo }
          FCanvas.Brush.Color := TColor($E6E6E6); FCanvas.Pen.Style := psClear;
          FCanvas.Pie(SP(Cn).X - Rad, SP(Cn).Y - Rad, SP(Cn).X + Rad, SP(Cn).Y + Rad,
            SP(Comp.PadPos(1)).X + (SP(Comp.PadPos(1)).Y - SP(Cn).Y), SP(Comp.PadPos(1)).Y - (SP(Comp.PadPos(1)).X - SP(Cn).X),
            SP(Comp.PadPos(1)).X - (SP(Comp.PadPos(1)).Y - SP(Cn).Y), SP(Comp.PadPos(1)).Y + (SP(Comp.PadPos(1)).X - SP(Cn).X));
          FCanvas.Pen.Style := psSolid;
          Disc(SP(Cn), Max(1, Rad * 2 div 3), Blend(BodyC, clWhite, 0.15), Blend(BodyC, clWhite, 0.15));
        end
        else Box(R, BodyC, Dark, Min(W, H));
      end;
    bkCapFilm: Box(R, BodyC, Dark, Min(W, H) div 3);
    bkTransistor:
      begin
        Box(R, BodyC, TColor($101010), Min(W, H) div 2);
        FCanvas.Brush.Style := bsClear;
      end;
    bkPower:
      begin
        Box(R, BodyC, TColor($101010), 2);
        if FP.Name = 'TO-220' then
        begin
          FCanvas.Brush.Color := TColor($B0B0B0);
          if Horizontal then FCanvas.Rectangle(R.Left, R.Top, R.Right, R.Top + Max(2, H div 4))
          else FCanvas.Rectangle(R.Left, R.Top, R.Left + Max(2, W div 4), R.Bottom);
        end;
      end;
    bkIC:
      begin
        Box(R, TColor($262626), TColor($0A0A0A), 2);
        { entalhe e ponto do pino 1 }
        P1 := Comp.PadPos(0);
        Disc(Point((SP(P1).X * 2 + SP(Cn).X) div 3, (SP(P1).Y * 2 + SP(Cn).Y) div 3),
          Max(1, MPx(0.5)), TColor($5A5A5A), TColor($5A5A5A));
      end;
    bkHeader:
      begin
        Box(R, TColor($202020), TColor($080808), 1);
        for I := 0 to High(FP.Pads) do
        begin
          Cn := Comp.PadPos(I);
          K := Max(1, MPx(0.32));
          FCanvas.Brush.Color := TColor($37AFD4); FCanvas.Pen.Style := psClear;
          FCanvas.Rectangle(SX(Cn.X) - K, SY(Cn.Y) - K, SX(Cn.X) + K + 1, SY(Cn.Y) + K + 1);
          FCanvas.Pen.Style := psSolid;
        end;
      end;
    bkTerminal:
      begin
        Box(R, BodyC, Dark, 2);
        for I := 0 to High(FP.Pads) do
          Disc(SP(Comp.PadPos(I)), Max(1, MPx(1.1)), TColor($C0C0C0), TColor($707070));
      end;
    bkPot:
      begin
        Box(R, BodyC, Dark, 3);
        Rad := Min(W, H) * 2 div 5;
        Disc(SP(Cn), Rad, Light, Dark);
        FCanvas.Pen.Color := Dark; FCanvas.Pen.Width := Max(1, Rad div 5);
        FCanvas.Line(SP(Cn).X - Rad div 2, SP(Cn).Y, SP(Cn).X + Rad div 2, SP(Cn).Y);
      end;
    bkCrystal: Box(R, BodyC, Dark, Min(W, H));
    bkSwitch:
      begin
        Box(R, BodyC, TColor($101010), 2);
        Disc(SP(Cn), Min(W, H) div 3, TColor($505050), TColor($101010));
      end;
  end;
  FCanvas.Brush.Style := bsSolid;
end;

procedure TMPRenderer.Paint(ACanvas: TCanvas; const AView: TMPViewport; const ARect: TRect);
var
  BoardRect: TRect;
  Bg, Board, Mask, Silk, PadC, HoleC: TColor;
  I, J: Integer;
  Comp: TMPComponent;
  Pend: TMPConnections;
  B: TMPRect;
  Q: TPoint;
  Rad: Integer;
  ShowB, ShowT, Populated: Boolean;
begin
  FCanvas := ACanvas;
  FV := AView;
  if Doc = nil then Exit;
  case Mode of
    vmArtwork: begin Bg := clWhite; Board := clWhite; end;
    vmRealWorld, vmUnpopulated: begin Bg := TColor($2A2622); Board := TColor($2F7A2A); end;
  else
    begin Bg := TColor($F4EFEA); Board := clWhite; end;
  end;
  if FBare then
  begin
    Bg := TColor($FBF8F6);
    if Mode <> vmArtwork then Board := Bg;
  end;
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := Bg;
  FCanvas.FillRect(ARect);
  BoardRect := Rect(Min(SX(0), SX(Doc.BoardW)), SY(Doc.BoardH), Max(SX(0), SX(Doc.BoardW)) + 1, SY(0) + 1);
  FCanvas.Brush.Color := Board;
  FCanvas.Pen.Style := psClear;
  if FBare then
  begin
  end
  else if Mode in [vmRealWorld, vmUnpopulated] then
  begin
    { sombra e chanfro da placa }
    FCanvas.Brush.Color := TColor($141210);
    FCanvas.RoundRect(BoardRect.Left + 5, BoardRect.Top + 5, BoardRect.Right + 5, BoardRect.Bottom + 5, 8, 8);
    FCanvas.Brush.Color := Board;
    FCanvas.RoundRect(BoardRect, 8, 8);
  end
  else
    FCanvas.Rectangle(BoardRect);
  FCanvas.Pen.Style := psSolid;
  if ShowGrid and (Mode in [vmNormal]) then DrawGrid;

  ShowB := ShowBottom; ShowT := ShowTop and (Doc.DoubleSided or (Mode <> vmArtwork));
  Populated := Mode = vmRealWorld;
  if Mode = vmArtwork then
  begin
    DrawLayerCopper(ArtworkLayer, clBlack, clWhite);
    for I := 0 to Doc.ComponentCount - 1 do
      for J := 0 to Doc.Component(I).PadCount - 1 do
        if Doc.Component(I).Footprint.Pads[J].Plated then
          PadShape(Doc.Component(I), J, 0, clBlack);
    for I := 0 to Doc.ComponentCount - 1 do
      for J := 0 to Doc.Component(I).PadCount - 1 do
        Hole(Doc.Component(I), J, clWhite);
  end
  else
  begin
    Mask := Board;
    if Mode = vmNormal then Mask := clWhite;
    if Mode = vmNormal then
    begin
      { na edicao a face de baixo fica por baixo, como vista do lado dos componentes }
      if ShowB then DrawLayerCopper(mlBottomCopper, CopperColor(mlBottomCopper), Mask);
      if ShowT and Doc.DoubleSided then DrawLayerCopper(mlTopCopper, CopperColor(mlTopCopper), Mask);
    end
    else
    begin
      if Doc.DoubleSided then DrawLayerCopper(mlTopCopper, CopperColor(mlTopCopper), Board)
      else if ShowB then DrawLayerCopper(mlBottomCopper, Blend(Board, clBlack, 0.12), Board);
    end;
    { pads }
    if Mode = vmNormal then
    begin
      if Doc.DoubleSided and ShowT then PadC := MP_TOP_COLOR else PadC := MP_BOTTOM_COLOR;
      HoleC := clWhite;
    end
    else
    begin
      PadC := TColor($C8CDCF);   { estanhado }
      HoleC := TColor($1E1E1E);
    end;
    for I := 0 to Doc.ComponentCount - 1 do
    begin
      Comp := Doc.Component(I);
      for J := 0 to Comp.PadCount - 1 do
      begin
        if Comp.Footprint.Pads[J].Plated then
        begin
          if (Mode = vmNormal) and (HighlightNet >= 0) and (Doc.PadNet(I, J) = HighlightNet) then
            PadShape(Comp, J, 0, MP_SELECT_COLOR)
          else
            PadShape(Comp, J, 0, PadC);
        end
        else if Mode <> vmNormal then
          PadShape(Comp, J, 0.15, Blend(Board, clBlack, 0.2));
        if (Mode = vmNormal) and not Comp.Footprint.Pads[J].Plated then
          Hole(Comp, J, TColor($DCD6D0))   { furo sem cobre (fixacao) }
        else
          Hole(Comp, J, HoleC);
      end;
    end;
    { serigrafia / corpos }
    if Mode = vmNormal then Silk := MP_SILK_COLOR else Silk := TColor($F0F0F0);
    if ShowSilk then
    begin
      for I := 0 to Doc.ComponentCount - 1 do
      begin
        Comp := Doc.Component(I);
        if Populated then DrawBody(Comp)
        else DrawSilkOf(Comp, Silk, 0.18);
      end;
      if not Populated then DrawRefs(Silk);
      for I := 0 to Doc.TextCount - 1 do
        if Doc.Text(I).Layer = mlTopSilk then
        begin
          if (SelKind = selText) and (SelIndex = I) and (Mode = vmNormal) then
            Strokes(MPTextStrokes(Doc.Text(I).Text, Doc.Text(I).X, Doc.Text(I).Y, Doc.Text(I).Height),
              MPTextStrokeWidth(Doc.Text(I).Height), MP_SELECT_COLOR)
          else
            Strokes(MPTextStrokes(Doc.Text(I).Text, Doc.Text(I).X, Doc.Text(I).Y, Doc.Text(I).Height),
              MPTextStrokeWidth(Doc.Text(I).Height), Silk);
        end;
    end
    else if Populated then
      for I := 0 to Doc.ComponentCount - 1 do DrawBody(Doc.Component(I));
    { ligacoes pendentes (ratsnest) }
    if ShowRatsnest and (Mode = vmNormal) then
    begin
      Pend := MPPendingConnections(Doc);
      FCanvas.Pen.Width := 1;
      FCanvas.Pen.Style := psDash;
      FCanvas.Pen.Color := MP_RATS_COLOR;
      FCanvas.Brush.Style := bsClear;
      for I := 0 to High(Pend) do
        FCanvas.Line(SP(Doc.PadPoint(Pend[I].A)), SP(Doc.PadPoint(Pend[I].B)));
      FCanvas.Pen.Style := psSolid;
      FCanvas.Brush.Style := bsSolid;
    end;
  end;
  { componente selecionado }
  if (SelKind = selComponent) and (SelIndex >= 0) and (SelIndex < Doc.ComponentCount) then
  begin
    B := Doc.Component(SelIndex).Bounds;
    FCanvas.Brush.Style := bsClear;
    FCanvas.Pen.Color := MP_SELECT_COLOR; FCanvas.Pen.Width := 2; FCanvas.Pen.Style := psDot;
    FCanvas.Rectangle(Min(SX(B.MinX), SX(B.MaxX)) - 4, SY(B.MaxY) - 4, Max(SX(B.MinX), SX(B.MaxX)) + 5, SY(B.MinY) + 5);
    FCanvas.Pen.Style := psSolid; FCanvas.Brush.Style := bsSolid;
  end;
  { problemas do DRC }
  if Mode = vmNormal then
    for I := 0 to High(Issues) do
    begin
      Q := Point(SX(Issues[I].X), SY(Issues[I].Y));
      Rad := 9;
      FCanvas.Brush.Style := bsClear;
      FCanvas.Pen.Color := clRed; FCanvas.Pen.Width := 2;
      FCanvas.Ellipse(Q.X - Rad, Q.Y - Rad, Q.X + Rad, Q.Y + Rad);
      FCanvas.Line(Q.X - 4, Q.Y - 4, Q.X + 5, Q.Y + 5);
      FCanvas.Line(Q.X + 4, Q.Y - 4, Q.X - 5, Q.Y + 5);
      FCanvas.Brush.Style := bsSolid;
    end;
  { contorno da placa }
  if FBare then Exit;
  FCanvas.Brush.Style := bsClear;
  FCanvas.Pen.Width := 1;
  if Mode = vmArtwork then FCanvas.Pen.Color := clBlack
  else if Mode = vmNormal then FCanvas.Pen.Color := TColor($5A3A1F)
  else FCanvas.Pen.Color := TColor($1E5A1A);
  if Mode in [vmRealWorld, vmUnpopulated] then FCanvas.RoundRect(BoardRect, 8, 8)
  else FCanvas.Rectangle(BoardRect);
  FCanvas.Brush.Style := bsSolid;
end;

procedure TMPRenderer.PaintFootprint(ACanvas: TCanvas; FP: TMPFootprint; const ARect: TRect;
  AMode: TMPViewMode);
var
  Tmp: TMPDocument;
  Comp: TMPComponent;
  B: TMPRect;
  V: TMPViewport;
  S: Double;
  OldDoc: TMPDocument;
  OldMode: TMPViewMode;
  OldGrid, OldRats: Boolean;
  OldSel: TMPSelKind;
begin
  B := FP.Bounds;
  if not B.Valid then Exit;
  Tmp := TMPDocument.Create;
  OldDoc := Doc; OldMode := Mode; OldGrid := ShowGrid; OldRats := ShowRatsnest; OldSel := SelKind;
  try
    Tmp.BoardW := B.MaxX - B.MinX + 2;
    Tmp.BoardH := B.MaxY - B.MinY + 2;
    Comp := Tmp.AddComponent(FP, 1 - B.MinX, 1 - B.MinY);
    Comp.Ref := '';
    S := Min((ARect.Right - ARect.Left - 8) / Tmp.BoardW, (ARect.Bottom - ARect.Top - 8) / Tmp.BoardH);
    S := Min(S, 9);
    V.Scale := S;
    V.OX := (ARect.Left + ARect.Right) / 2 - Tmp.BoardW * S / 2;
    V.OY := (ARect.Top + ARect.Bottom) / 2 + Tmp.BoardH * S / 2;
    Doc := Tmp; Mode := AMode; ShowGrid := False; ShowRatsnest := False; SelKind := selNone;
    FCanvas := ACanvas; FV := V;
    FBare := True;
    Paint(ACanvas, V, ARect);
  finally
    FBare := False;
    Doc := OldDoc; Mode := OldMode; ShowGrid := OldGrid; ShowRatsnest := OldRats; SelKind := OldSel;
    Tmp.Free;
  end;
end;

procedure TMPRenderer.PaintGhost(ACanvas: TCanvas; const AView: TMPViewport; Comp: TMPComponent);
var
  I: Integer;
begin
  FCanvas := ACanvas;
  FV := AView;
  for I := 0 to Comp.PadCount - 1 do
    PadShape(Comp, I, 0, Blend(MP_SELECT_COLOR, clWhite, 0.35));
  DrawSilkOf(Comp, MP_SELECT_COLOR, 0.2);
end;

end.
