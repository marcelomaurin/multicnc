unit makepcb_gerber;

{ Exportacao de fabricacao do MakePCB: Gerber RS-274X (com atributos X2) e
  Excellon, nos nomes usados pelo KiCad para o LaserPCB reconhecer a funcao
  de cada camada sozinho:

    <base>-B_Cu.gbl          cobre inferior (sempre)
    <base>-F_Cu.gtl          cobre superior (dupla face ou se houver cobre em cima)
    <base>-B_Mask.gbs / -F_Mask.gts   mascara de solda (pads + folga)
    <base>-F_Silkscreen.gto  serigrafia (contornos, referencias, textos)
    <base>-Edge_Cuts.gm1     contorno da placa
    <base>-PTH.drl / -NPTH.drl        furos metalizados / nao metalizados

  Coordenadas em mm, formato 4.6, origem no canto inferior esquerdo.

  Areas de cobre: regiao (G36/G37, LPD), depois folga (LPC) em volta dos
  pads, trilhas e textos de outras redes, e por fim os itens desenhados de
  novo (LPD). Itens da rede da area ficam ligados direto a ela. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, makepcb_model, makepcb_font;

const
  MP_MASK_EXPANSION = 0.1;   { folga da mascara em volta do pad (cada lado) }
  MP_SILK_WIDTH = 0.15;
  MP_EDGE_WIDTH = 0.1;
  MP_REF_HEIGHT = 1.2;

type
  TMPFabOptions = record
    Folder, BaseName: string;
    TopCopper: Boolean;        { forca o cobre superior mesmo em face simples }
    Silkscreen, SolderMask: Boolean;
  end;

{ escreve os arquivos e devolve os caminhos em Files; levanta excecao se a
  placa for invalida }
procedure MPExportFabrication(Doc: TMPDocument; const O: TMPFabOptions; Files: TStrings);
function MPDefaultFabOptions(const Folder, BaseName: string): TMPFabOptions;
{ conteudo de cada camada (usado pelos testes) }
function MPCopperGerber(Doc: TMPDocument; Layer: TMPLayer): string;
function MPDrillFile(Doc: TMPDocument; Plated: Boolean; out HoleCount: Integer): string;
{ ponto da referencia (texto) de um componente }
function MPRefPosition(C: TMPComponent): TMPPoint;

implementation

var
  InvFS: TFormatSettings;

type
  TGerber = class
  private
    FBody, FApertures: TStringList;
    FKeys: TStringList;
    FCurrent: Integer;
    FFunction: string;
  public
    constructor Create(const AFunction: string);
    destructor Destroy; override;
    function Aperture(const Kind: Char; W: Double; H: Double = 0): Integer;
    procedure Use(D: Integer);
    procedure Flash(D: Integer; X, Y: Double);
    procedure Polyline(D: Integer; const P: TMPPoints);
    procedure Region(const P: TMPPoints);
    procedure Polarity(Dark: Boolean);
    function Text: string;
  end;

function Coord(V: Double): string;
begin
  Result := IntToStr(Round(V * 1000000));
end;

function Num(V: Double): string;
begin
  Result := FormatFloat('0.0###', V, InvFS);
end;

constructor TGerber.Create(const AFunction: string);
begin
  inherited Create;
  FBody := TStringList.Create;
  FApertures := TStringList.Create;
  FKeys := TStringList.Create;
  FCurrent := -1;
  FFunction := AFunction;
end;

destructor TGerber.Destroy;
begin
  FBody.Free;
  FApertures.Free;
  FKeys.Free;
  inherited Destroy;
end;

function TGerber.Aperture(const Kind: Char; W: Double; H: Double): Integer;
var
  Key: string;
  I: Integer;
begin
  W := Max(0.01, W);
  H := Max(0.01, H);
  if Kind = 'C' then Key := 'C,' + Num(W) else Key := Kind + ',' + Num(W) + 'X' + Num(H);
  I := FKeys.IndexOf(Key);
  if I >= 0 then Exit(10 + I);
  FKeys.Add(Key);
  Result := 10 + FKeys.Count - 1;
  FApertures.Add('%ADD' + IntToStr(Result) + Key + '*%');
end;

procedure TGerber.Use(D: Integer);
begin
  if D <> FCurrent then
  begin
    FBody.Add('D' + IntToStr(D) + '*');
    FCurrent := D;
  end;
end;

procedure TGerber.Flash(D: Integer; X, Y: Double);
begin
  Use(D);
  FBody.Add('X' + Coord(X) + 'Y' + Coord(Y) + 'D03*');
end;

procedure TGerber.Polyline(D: Integer; const P: TMPPoints);
var
  I: Integer;
begin
  if Length(P) = 0 then Exit;
  Use(D);
  FBody.Add('X' + Coord(P[0].X) + 'Y' + Coord(P[0].Y) + 'D02*');
  if Length(P) = 1 then
    FBody.Add('X' + Coord(P[0].X) + 'Y' + Coord(P[0].Y) + 'D01*')
  else
    for I := 1 to High(P) do FBody.Add('X' + Coord(P[I].X) + 'Y' + Coord(P[I].Y) + 'D01*');
end;

procedure TGerber.Region(const P: TMPPoints);
var
  I: Integer;
begin
  if Length(P) < 3 then Exit;
  FBody.Add('G36*');
  FBody.Add('X' + Coord(P[0].X) + 'Y' + Coord(P[0].Y) + 'D02*');
  for I := 1 to High(P) do FBody.Add('X' + Coord(P[I].X) + 'Y' + Coord(P[I].Y) + 'D01*');
  FBody.Add('X' + Coord(P[0].X) + 'Y' + Coord(P[0].Y) + 'D01*');
  FBody.Add('G37*');
end;

procedure TGerber.Polarity(Dark: Boolean);
begin
  if Dark then FBody.Add('%LPD*%') else FBody.Add('%LPC*%');
end;

function TGerber.Text: string;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Add('G04 MakePCB*');
    S.Add('%TF.GenerationSoftware,Maurinsoft,MakePCB,0.1*%');
    S.Add('%TF.FileFunction,' + FFunction + '*%');
    S.Add('%FSLAX46Y46*%');
    S.Add('%MOMM*%');
    S.Add('%LPD*%');
    S.AddStrings(FApertures);
    S.Add('G01*');
    S.AddStrings(FBody);
    S.Add('M02*');
    Result := S.Text;
  finally
    S.Free;
  end;
end;

{ ---------------- auxiliares de geometria ---------------- }

function CirclePoints(CX, CY, R: Double): TMPPoints;
var
  I, N: Integer;
begin
  Result := nil;
  N := Max(16, Min(96, Round(2 * Pi * R / 0.25)));
  SetLength(Result, N + 1);
  for I := 0 to N do
    Result[I] := MPPoint(CX + R * Cos(2 * Pi * I / N), CY + R * Sin(2 * Pi * I / N));
end;

function PadAperture(G: TGerber; C: TMPComponent; I: Integer; Grow: Double): Integer;
var
  W, H: Double;
begin
  C.PadSize(I, W, H);
  W := W + 2 * Grow;
  H := H + 2 * Grow;
  case C.Footprint.Pads[I].Shape of
    psSquare: Result := G.Aperture('R', W, H);
    psOblong: Result := G.Aperture('O', W, H);
  else Result := G.Aperture('C', Max(W, H));
  end;
end;

function MPRefPosition(C: TMPComponent): TMPPoint;
var
  B: TMPRect;
  W: Double;
begin
  B := C.Bounds;
  W := MPTextWidth(C.Ref, MP_REF_HEIGHT);
  Result := MPPoint((B.MinX + B.MaxX) / 2 - W / 2, B.MaxY + 0.6);
end;

procedure DrawStrokes(G: TGerber; D: Integer; const S: TMPStrokes);
var
  I: Integer;
begin
  for I := 0 to High(S) do G.Polyline(D, S[I]);
end;

function CopperTextStrokes(T: TMPText): TMPStrokes;
begin
  Result := MPTextStrokes(T.Text, T.X, T.Y, T.Height, T.Layer = mlBottomCopper);
end;

{ ---------------- camadas ---------------- }

function MPCopperGerber(Doc: TMPDocument; Layer: TMPLayer): string;
var
  G: TGerber;
  I, J: Integer;
  A: TMPArea;
  Pts: TMPPoints;
  Clr: Double;

  procedure DrawItems(Grow: Double; AreaIndex: Integer);
  { AreaIndex >= 0: so os itens que NAO pertencem a area (folga) }
  var
    CI, PI2, TI, XI: Integer;
    Cm: TMPComponent;
    Pp: TMPPoint;
  begin
    for CI := 0 to Doc.ComponentCount - 1 do
    begin
      Cm := Doc.Component(CI);
      for PI2 := 0 to Cm.PadCount - 1 do
      begin
        if not Cm.PadOnLayer(PI2, Layer) then Continue;
        if (AreaIndex >= 0) and Doc.PadInArea(AreaIndex, CI, PI2) then Continue;
        { furo sem metalizacao sem cobre: so a folga }
        if (AreaIndex < 0) and not Cm.Footprint.Pads[PI2].Plated then Continue;
        Pp := Cm.PadPos(PI2);
        G.Flash(PadAperture(G, Cm, PI2, Grow), Pp.X, Pp.Y);
      end;
    end;
    for TI := 0 to Doc.TrackCount - 1 do
    begin
      if Doc.Track(TI).Layer <> Layer then Continue;
      if (AreaIndex >= 0) and Doc.TrackInArea(AreaIndex, TI) then Continue;
      G.Polyline(G.Aperture('C', Doc.Track(TI).Width + 2 * Grow), Doc.Track(TI).Points);
    end;
    for XI := 0 to Doc.TextCount - 1 do
      if Doc.Text(XI).Layer = Layer then
        DrawStrokes(G, G.Aperture('C', MPTextStrokeWidth(Doc.Text(XI).Height) + 2 * Grow),
          CopperTextStrokes(Doc.Text(XI)));
  end;

begin
  if Layer = mlBottomCopper then G := TGerber.Create('Copper,L2,Bot')
  else G := TGerber.Create('Copper,L1,Top');
  try
    Doc.ComputeNets;
    { 1. areas de cobre }
    for I := 0 to Doc.AreaCount - 1 do
    begin
      A := Doc.Area(I);
      if (A.Layer <> Layer) or (Length(A.Points) < 3) then Continue;
      Clr := A.Clearance;
      SetLength(Pts, Length(A.Points));
      for J := 0 to High(A.Points) do
        Pts[J] := MPPoint(EnsureRange(A.Points[J].X, Clr, Doc.BoardW - Clr),
                          EnsureRange(A.Points[J].Y, Clr, Doc.BoardH - Clr));
      G.Polarity(True);
      G.Region(Pts);
      { 2. folga em volta das outras redes }
      G.Polarity(False);
      DrawItems(Clr, I);
    end;
    { 3. pads, trilhas e textos }
    G.Polarity(True);
    DrawItems(0, -1);
    Result := G.Text;
  finally
    G.Free;
  end;
end;

function MaskGerber(Doc: TMPDocument; Top: Boolean): string;
var
  G: TGerber;
  I, J: Integer;
  C: TMPComponent;
  P: TMPPoint;
begin
  if Top then G := TGerber.Create('Soldermask,Top') else G := TGerber.Create('Soldermask,Bot');
  try
    for I := 0 to Doc.ComponentCount - 1 do
    begin
      C := Doc.Component(I);
      for J := 0 to C.PadCount - 1 do
      begin
        if Top and not C.PadOnLayer(J, mlTopCopper) then Continue;
        if (not Top) and not C.PadOnLayer(J, mlBottomCopper) then Continue;
        P := C.PadPos(J);
        G.Flash(PadAperture(G, C, J, MP_MASK_EXPANSION), P.X, P.Y);
      end;
    end;
    Result := G.Text;
  finally
    G.Free;
  end;
end;

function SilkGerber(Doc: TMPDocument): string;
var
  G: TGerber;
  I, J, D: Integer;
  C: TMPComponent;
  S: TMPSilk;
  P: TMPPoints;
  A, R: TMPPoint;
begin
  G := TGerber.Create('Legend,Top');
  try
    D := G.Aperture('C', MP_SILK_WIDTH);
    for I := 0 to Doc.ComponentCount - 1 do
    begin
      C := Doc.Component(I);
      { componente virado fica embaixo: sem serigrafia em cima }
      if C.Flipped then Continue;
      for J := 0 to High(C.Footprint.Silk) do
      begin
        S := C.Footprint.Silk[J];
        case S.Kind of
          skLine:
            begin
              SetLength(P, 2);
              P[0] := C.LocalToWorld(S.X1, S.Y1);
              P[1] := C.LocalToWorld(S.X2, S.Y2);
            end;
          skCircle:
            begin
              A := C.LocalToWorld(S.X1, S.Y1);
              P := CirclePoints(A.X, A.Y, S.R);
            end;
          skRect:
            begin
              SetLength(P, 5);
              P[0] := C.LocalToWorld(S.X1, S.Y1);
              P[1] := C.LocalToWorld(S.X2, S.Y1);
              P[2] := C.LocalToWorld(S.X2, S.Y2);
              P[3] := C.LocalToWorld(S.X1, S.Y2);
              P[4] := P[0];
            end;
        end;
        G.Polyline(D, P);
      end;
      if (C.Ref <> '') and not C.IsPadOnly then
      begin
        R := MPRefPosition(C);
        DrawStrokes(G, G.Aperture('C', MPTextStrokeWidth(MP_REF_HEIGHT)),
          MPTextStrokes(C.Ref, R.X, R.Y, MP_REF_HEIGHT));
      end;
    end;
    for I := 0 to Doc.TextCount - 1 do
      if Doc.Text(I).Layer = mlTopSilk then
        DrawStrokes(G, G.Aperture('C', MPTextStrokeWidth(Doc.Text(I).Height)),
          MPTextStrokes(Doc.Text(I).Text, Doc.Text(I).X, Doc.Text(I).Y, Doc.Text(I).Height));
    Result := G.Text;
  finally
    G.Free;
  end;
end;

function EdgeGerber(Doc: TMPDocument): string;
var
  G: TGerber;
  P: TMPPoints;
begin
  G := TGerber.Create('Profile,NP');
  try
    SetLength(P, 5);
    P[0] := MPPoint(0, 0);
    P[1] := MPPoint(Doc.BoardW, 0);
    P[2] := MPPoint(Doc.BoardW, Doc.BoardH);
    P[3] := MPPoint(0, Doc.BoardH);
    P[4] := P[0];
    G.Polyline(G.Aperture('C', MP_EDGE_WIDTH), P);
    Result := G.Text;
  finally
    G.Free;
  end;
end;

function MPDrillFile(Doc: TMPDocument; Plated: Boolean; out HoleCount: Integer): string;
var
  Tools: array of Double;
  S: TStringList;
  I, J, T: Integer;
  C: TMPComponent;
  P: TMPPoint;
  Dia: Double;

  function ToolOf(D: Double): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(Tools) do
      if Abs(Tools[K] - D) < 1e-4 then Exit(K);
    Result := -1;
  end;

begin
  Tools := nil;
  HoleCount := 0;
  for I := 0 to Doc.ComponentCount - 1 do
  begin
    C := Doc.Component(I);
    for J := 0 to C.PadCount - 1 do
      if (C.Footprint.Pads[J].Plated = Plated) and (C.Footprint.Pads[J].Drill > 0) and
         (ToolOf(C.Footprint.Pads[J].Drill) < 0) then
      begin
        SetLength(Tools, Length(Tools) + 1);
        Tools[High(Tools)] := C.Footprint.Pads[J].Drill;
      end;
  end;
  { brocas da menor para a maior }
  for I := 1 to High(Tools) do
  begin
    Dia := Tools[I];
    J := I - 1;
    while (J >= 0) and (Tools[J] > Dia) do
    begin
      Tools[J + 1] := Tools[J];
      Dec(J);
    end;
    Tools[J + 1] := Dia;
  end;
  S := TStringList.Create;
  try
    S.Add('M48');
    if Plated then S.Add('; DRILL file {MakePCB} PTH') else S.Add('; DRILL file {MakePCB} NPTH');
    S.Add('; FORMAT={-:-/ absolute / metric / decimal}');
    if Plated then S.Add(';TF.FileFunction,Plated,1,2,PTH') else S.Add(';TF.FileFunction,NonPlated,1,2,NPTH');
    S.Add('FMAT,2');
    S.Add('METRIC');
    for T := 0 to High(Tools) do S.Add('T' + IntToStr(T + 1) + 'C' + FormatFloat('0.000', Tools[T], InvFS));
    S.Add('%');
    S.Add('G90');
    S.Add('G05');
    for T := 0 to High(Tools) do
    begin
      S.Add('T' + IntToStr(T + 1));
      for I := 0 to Doc.ComponentCount - 1 do
      begin
        C := Doc.Component(I);
        for J := 0 to C.PadCount - 1 do
          if (C.Footprint.Pads[J].Plated = Plated) and (ToolOf(C.Footprint.Pads[J].Drill) = T) then
          begin
            P := C.PadPos(J);
            S.Add('X' + FormatFloat('0.000', P.X, InvFS) + 'Y' + FormatFloat('0.000', P.Y, InvFS));
            Inc(HoleCount);
          end;
      end;
    end;
    S.Add('T0');
    S.Add('M30');
    Result := S.Text;
  finally
    S.Free;
  end;
end;

function MPDefaultFabOptions(const Folder, BaseName: string): TMPFabOptions;
begin
  Result.Folder := Folder;
  Result.BaseName := BaseName;
  Result.TopCopper := False;
  Result.Silkscreen := True;
  Result.SolderMask := True;
end;

procedure MPExportFabrication(Doc: TMPDocument; const O: TMPFabOptions; Files: TStrings);
var
  Errors: TStringList;
  Base: string;
  HasTop: Boolean;
  I, Holes: Integer;
  Txt: string;

  procedure Save(const Suffix, Content: string);
  var
    SL: TStringList;
    FN: string;
  begin
    FN := Base + Suffix;
    SL := TStringList.Create;
    try
      SL.Text := Content;
      SL.SaveToFile(FN);
    finally
      SL.Free;
    end;
    Files.Add(FN);
  end;

begin
  Errors := TStringList.Create;
  try
    if not Doc.ValidateBoard(Errors) then raise Exception.Create(Trim(Errors.Text));
  finally
    Errors.Free;
  end;
  if Trim(O.BaseName) = '' then raise Exception.Create('Informe o nome dos arquivos');
  ForceDirectories(O.Folder);
  Base := IncludeTrailingPathDelimiter(O.Folder) + O.BaseName;
  Files.Clear;
  HasTop := Doc.DoubleSided or O.TopCopper;
  for I := 0 to Doc.TrackCount - 1 do if Doc.Track(I).Layer = mlTopCopper then HasTop := True;
  for I := 0 to Doc.AreaCount - 1 do if Doc.Area(I).Layer = mlTopCopper then HasTop := True;
  for I := 0 to Doc.TextCount - 1 do if Doc.Text(I).Layer = mlTopCopper then HasTop := True;
  for I := 0 to Doc.ComponentCount - 1 do
    if Doc.Component(I).HasSMD and not Doc.Component(I).Flipped then HasTop := True;
  Save('-B_Cu.gbl', MPCopperGerber(Doc, mlBottomCopper));
  if HasTop then Save('-F_Cu.gtl', MPCopperGerber(Doc, mlTopCopper));
  if O.SolderMask then
  begin
    Save('-B_Mask.gbs', MaskGerber(Doc, False));
    if HasTop then Save('-F_Mask.gts', MaskGerber(Doc, True));
  end;
  if O.Silkscreen then Save('-F_Silkscreen.gto', SilkGerber(Doc));
  Save('-Edge_Cuts.gm1', EdgeGerber(Doc));
  Txt := MPDrillFile(Doc, True, Holes);
  if Holes > 0 then Save('-PTH.drl', Txt);
  Txt := MPDrillFile(Doc, False, Holes);
  if Holes > 0 then Save('-NPTH.drl', Txt);
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
  InvFS.ThousandSeparator := #0;
end.
