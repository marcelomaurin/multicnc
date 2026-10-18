unit multiphysics_view3d;

{ Vista 3D da malha do MultiPhysics: faces de contorno com sombreamento,
  mapa de cores de um campo nodal (azul -> vermelho), deformada com escala,
  animacao de forma modal, realce de faces (condicoes de contorno) e
  selecao de face pelo clique.

  Mouse: arrastar com o botao esquerdo gira, com o direito ou o do meio
  desloca, roda do mouse aproxima. Clique sem arrastar seleciona a face. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, LCLIntf, ExtCtrls,
  multisuite_controls, multiphysics_vector, multiphysics_geometry, multiphysics_mesh;

type
  TPickFaceEvent = procedure(Sender: TObject; FaceTag: Integer; const TagName: string) of object;

  TFaceMark = record
    Tag: Integer;
    Color: TColor;
    Arrow: TVector3;      { forca: direcao desenhada no centro da face (0 = sem) }
  end;

  TPhysicsView3D = class(TCustomControl)
  private
    FMesh: TFEMMesh;
    FScalar: array of Double;
    FHasScalar: Boolean;
    FScalarMin, FScalarMax: Double;
    FScalarTitle, FScalarUnit: string;
    FDisp: array of Double;
    FDispScale: Double;
    FAnimPhase: Double;
    FAnimate: Boolean;
    FTimer: TTimer;
    FYaw, FPitch, FZoom: Double;
    FPanX, FPanY: Double;
    FCenter: TVector3;
    FRadius: Double;
    FDown: Boolean;
    FDownBtn: TMouseButton;
    FDownPt, FLastPt: TPoint;
    FMoved: Boolean;
    FMarks: array of TFaceMark;
    FSelectedTag: Integer;
    FOnPickFace: TPickFaceEvent;
    FMessage: string;
    { projecao por face (cache da ultima pintura, para o clique) }
    FProj: array of TPoint;
    FOrder: array of Integer;
    FVisible: array of Boolean;
    procedure TimerTick(Sender: TObject);
    function NodePos(I: Integer): TVector3;
    function Project(const P: TVector3; out Depth: Double): TPoint;
    function MarkOf(FaceTag: Integer; out M: TFaceMark): Boolean;
    procedure DrawLegend(C: TCanvas);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetMesh(AMesh: TFEMMesh);
    procedure SetScalar(const V: array of Double; const Title, AUnit: string);
    procedure ClearScalar;
    procedure SetDisplacement(const U: array of Double; Scale: Double);
    procedure ClearDisplacement;
    procedure ClearMarks;
    procedure AddMark(FaceTag: Integer; AColor: TColor; const Arrow: TVector3);
    procedure FitView;
    procedure SetView(Yaw, Pitch: Double);
    { escala automatica: maior deslocamento = 8% do tamanho do modelo }
    function AutoScale(const U: array of Double): Double;
    property Animate: Boolean read FAnimate write FAnimate;
    property DispScale: Double read FDispScale write FDispScale;
    property SelectedTag: Integer read FSelectedTag write FSelectedTag;
    property Message: string read FMessage write FMessage;
    property OnPickFace: TPickFaceEvent read FOnPickFace write FOnPickFace;
  end;

{ cor do mapa (0 = azul, 1 = vermelho) }
function HeatColor(T: Double): TColor;

implementation

function HeatColor(T: Double): TColor;
var
  R, G, B: Double;
begin
  T := EnsureRange(T, 0, 1);
  { azul -> ciano -> verde -> amarelo -> vermelho }
  if T < 0.25 then begin R := 0; G := 4 * T; B := 1; end
  else if T < 0.5 then begin R := 0; G := 1; B := 1 - 4 * (T - 0.25); end
  else if T < 0.75 then begin R := 4 * (T - 0.5); G := 1; B := 0; end
  else begin R := 1; G := 1 - 4 * (T - 0.75); B := 0; end;
  Result := RGBToColor(Round(40 + 205 * R), Round(40 + 205 * G), Round(60 + 195 * B));
end;

constructor TPhysicsView3D.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  Color := clSuiteSurface;
  FYaw := -35; FPitch := 25; FZoom := 1;
  FDispScale := 0;
  FSelectedTag := -1;
  FRadius := 1;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
end;

procedure TPhysicsView3D.TimerTick(Sender: TObject);
begin
  if FAnimate and (Length(FDisp) > 0) and Visible then
  begin
    FAnimPhase := FAnimPhase + 0.25;
    if FAnimPhase > 2 * Pi then FAnimPhase := FAnimPhase - 2 * Pi;
    Invalidate;
  end;
end;

procedure TPhysicsView3D.SetMesh(AMesh: TFEMMesh);
begin
  FMesh := AMesh;
  ClearScalar;
  ClearDisplacement;
  FSelectedTag := -1;
  FitView;
end;

procedure TPhysicsView3D.SetScalar(const V: array of Double; const Title, AUnit: string);
var
  I: Integer;
begin
  SetLength(FScalar, Length(V));
  FScalarMin := MaxDouble; FScalarMax := -MaxDouble;
  for I := 0 to High(V) do
  begin
    FScalar[I] := V[I];
    FScalarMin := Min(FScalarMin, V[I]);
    FScalarMax := Max(FScalarMax, V[I]);
  end;
  FHasScalar := Length(V) > 0;
  FScalarTitle := Title; FScalarUnit := AUnit;
  Invalidate;
end;

procedure TPhysicsView3D.ClearScalar;
begin
  FScalar := nil;
  FHasScalar := False;
  Invalidate;
end;

procedure TPhysicsView3D.SetDisplacement(const U: array of Double; Scale: Double);
var
  I: Integer;
begin
  SetLength(FDisp, Length(U));
  for I := 0 to High(U) do FDisp[I] := U[I];
  FDispScale := Scale;
  Invalidate;
end;

procedure TPhysicsView3D.ClearDisplacement;
begin
  FDisp := nil;
  FAnimate := False;
  Invalidate;
end;

procedure TPhysicsView3D.ClearMarks;
begin
  FMarks := nil;
  Invalidate;
end;

procedure TPhysicsView3D.AddMark(FaceTag: Integer; AColor: TColor; const Arrow: TVector3);
begin
  SetLength(FMarks, Length(FMarks) + 1);
  FMarks[High(FMarks)].Tag := FaceTag;
  FMarks[High(FMarks)].Color := AColor;
  FMarks[High(FMarks)].Arrow := Arrow;
  Invalidate;
end;

function TPhysicsView3D.MarkOf(FaceTag: Integer; out M: TFaceMark): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FMarks) do
    if FMarks[I].Tag = FaceTag then
    begin
      M := FMarks[I];
      Exit(True);
    end;
  Result := False;
end;

procedure TPhysicsView3D.FitView;
var
  I: Integer;
  Lo, Hi: TVector3;
begin
  FZoom := 1; FPanX := 0; FPanY := 0;
  if (FMesh = nil) or (FMesh.NodeCount = 0) then
  begin
    FCenter := V3(0, 0, 0); FRadius := 1;
    Invalidate;
    Exit;
  end;
  Lo := FMesh.Nodes[0]; Hi := Lo;
  for I := 1 to FMesh.NodeCount - 1 do
  begin
    Lo := V3(Min(Lo.X, FMesh.Nodes[I].X), Min(Lo.Y, FMesh.Nodes[I].Y), Min(Lo.Z, FMesh.Nodes[I].Z));
    Hi := V3(Max(Hi.X, FMesh.Nodes[I].X), Max(Hi.Y, FMesh.Nodes[I].Y), Max(Hi.Z, FMesh.Nodes[I].Z));
  end;
  FCenter := VScale(VAdd(Lo, Hi), 0.5);
  FRadius := Max(VLength(VSub(Hi, Lo)) / 2, 1e-6);
  Invalidate;
end;

procedure TPhysicsView3D.SetView(Yaw, Pitch: Double);
begin
  FYaw := Yaw; FPitch := Pitch;
  Invalidate;
end;

function TPhysicsView3D.AutoScale(const U: array of Double): Double;
var
  I: Integer;
  M: Double;
begin
  M := 0;
  for I := 0 to Length(U) div 3 - 1 do
    M := Max(M, Sqrt(Sqr(U[3 * I]) + Sqr(U[3 * I + 1]) + Sqr(U[3 * I + 2])));
  if M <= 0 then Exit(0);
  Result := 0.08 * 2 * FRadius / M;
end;

function TPhysicsView3D.NodePos(I: Integer): TVector3;
var
  S: Double;
begin
  Result := FMesh.Nodes[I];
  if (Length(FDisp) = 3 * FMesh.NodeCount) and (FDispScale <> 0) then
  begin
    S := FDispScale;
    if FAnimate then S := S * Sin(FAnimPhase);
    Result := VAdd(Result, V3(FDisp[3 * I] * S, FDisp[3 * I + 1] * S, FDisp[3 * I + 2] * S));
  end;
end;

{ camera: gira em torno de Z (yaw) e inclina (pitch); Z do mundo para cima }
function TPhysicsView3D.Project(const P: TVector3; out Depth: Double): TPoint;
var
  D: TVector3;
  CY, SY, CP, SP, X1, Y1, Z1, Y2, Z2, Sc: Double;
begin
  D := VSub(P, FCenter);
  SinCos(DegToRad(FYaw), SY, CY);
  SinCos(DegToRad(FPitch), SP, CP);
  X1 := CY * D.X - SY * D.Y;
  Y1 := SY * D.X + CY * D.Y;
  Z1 := D.Z;
  Y2 := CP * Y1 - SP * Z1;    { profundidade (para dentro da tela) }
  Z2 := SP * Y1 + CP * Z1;    { altura na tela }
  Depth := Y2;
  Sc := 0.42 * Min(ClientWidth, ClientHeight) / FRadius * FZoom;
  Result.X := Round(ClientWidth / 2 + FPanX + X1 * Sc);
  Result.Y := Round(ClientHeight / 2 + FPanY - Z2 * Sc);
end;

procedure TPhysicsView3D.Paint;
var
  C: TCanvas;
  N, F, I, K, V: Integer;
  Depth: array of Double;
  D, Shade, T, Avg: Double;
  P3: array[0..2] of TVector3;
  Pts: array[0..2] of TPoint;
  Nrm, Ctr, Light: TVector3;
  Col: TColor;
  M: TFaceMark;
  R, G, B: Integer;

  procedure SortFaces(L, H: Integer);
  var
    A, Z, Tmp: Integer;
    Pv: Double;
  begin
    while L < H do
    begin
      Pv := Depth[FOrder[(L + H) shr 1]]; A := L; Z := H;
      repeat
        while Depth[FOrder[A]] > Pv do Inc(A);
        while Pv > Depth[FOrder[Z]] do Dec(Z);
        if A <= Z then
        begin
          Tmp := FOrder[A]; FOrder[A] := FOrder[Z]; FOrder[Z] := Tmp;
          Inc(A); Dec(Z);
        end;
      until A > Z;
      if Z - L < H - A then begin SortFaces(L, Z); L := A; end
      else begin SortFaces(A, H); H := Z; end;
    end;
  end;

  procedure Arrow(const From, Dir: TVector3; Clr: TColor);
  var
    A, B2: TPoint;
    Dd, Ang: Double;
    E: TVector3;
  begin
    E := VAdd(From, VScale(VNormalize(Dir), 0.25 * FRadius));
    A := Project(E, Dd); B2 := Project(From, Dd);
    C.Pen.Color := Clr; C.Pen.Width := 2;
    C.Line(A.X, A.Y, B2.X, B2.Y);
    Ang := ArcTan2(B2.Y - A.Y, B2.X - A.X);
    C.Line(B2.X, B2.Y, Round(B2.X - 9 * Cos(Ang - 0.4)), Round(B2.Y - 9 * Sin(Ang - 0.4)));
    C.Line(B2.X, B2.Y, Round(B2.X - 9 * Cos(Ang + 0.4)), Round(B2.Y - 9 * Sin(Ang + 0.4)));
    C.Pen.Width := 1;
  end;

begin
  C := Canvas;
  C.Brush.Color := clSuiteSurface;
  C.FillRect(ClientRect);
  if (FMesh = nil) or (FMesh.FaceCount = 0) then
  begin
    C.Font.Color := clSuiteMuted;
    C.Font.Size := 11;
    if FMessage <> '' then C.TextOut(24, 24, FMessage)
    else C.TextOut(24, 24, 'Sem malha. Adicione pecas e gere a malha (etapa Malha).');
    Exit;
  end;
  N := FMesh.FaceCount;
  SetLength(Depth, N); SetLength(FOrder, N); SetLength(FProj, 3 * N); SetLength(FVisible, N);
  Light := VNormalize(V3(-0.3, -0.6, 0.75));
  for F := 0 to N - 1 do
  begin
    FOrder[F] := F;
    Avg := 0;
    for K := 0 to 2 do
    begin
      P3[K] := NodePos(FMesh.Faces[F].N[K]);
      FProj[3 * F + K] := Project(P3[K], D);
      Avg := Avg + D;
    end;
    Depth[F] := Avg / 3;
    { descarta faces de costas (normal para longe da camera) }
    FVisible[F] := (FProj[3 * F + 1].X - FProj[3 * F].X) * (FProj[3 * F + 2].Y - FProj[3 * F].Y) -
                   (FProj[3 * F + 1].Y - FProj[3 * F].Y) * (FProj[3 * F + 2].X - FProj[3 * F].X) < 0;
  end;
  if N > 1 then SortFaces(0, N - 1);
  C.Pen.Style := psSolid;
  for I := 0 to N - 1 do
  begin
    F := FOrder[I];
    if not FVisible[F] then Continue;
    for K := 0 to 2 do
    begin
      Pts[K] := FProj[3 * F + K];
      P3[K] := NodePos(FMesh.Faces[F].N[K]);
    end;
    Nrm := VNormalize(VCross(VSub(P3[1], P3[0]), VSub(P3[2], P3[0])));
    Shade := 0.55 + 0.45 * Abs(VDot(Nrm, Light));
    if FHasScalar and (Length(FScalar) = FMesh.NodeCount) then
    begin
      T := 0; V := 0;
      for K := 0 to 5 do
        if FMesh.Faces[F].N[K] >= 0 then
        begin
          T := T + FScalar[FMesh.Faces[F].N[K]];
          Inc(V);
        end;
      T := T / Max(V, 1);
      if FScalarMax > FScalarMin then T := (T - FScalarMin) / (FScalarMax - FScalarMin) else T := 0.5;
      Col := HeatColor(T);
    end
    else if MarkOf(FMesh.Faces[F].Tag, M) then
      Col := M.Color
    else
      Col := SuiteRGB(176, 190, 210);
    if FMesh.Faces[F].Tag = FSelectedTag then Col := SuiteMix(Col, clSuitePrimary, 0.55);
    R := Round(Red(Col) * Shade); G := Round(Green(Col) * Shade); B := Round(Blue(Col) * Shade);
    C.Brush.Color := RGBToColor(Min(R, 255), Min(G, 255), Min(B, 255));
    if FMesh.FaceCount < 6000 then C.Pen.Color := SuiteMix(C.Brush.Color, clBlack, 0.18)
    else C.Pen.Color := C.Brush.Color;
    C.Polygon(Pts);
  end;
  { setas de forca }
  for I := 0 to High(FMarks) do
    if VLength(FMarks[I].Arrow) > 0 then
    begin
      Ctr := V3(0, 0, 0); V := 0;
      for F := 0 to N - 1 do
        if FMesh.Faces[F].Tag = FMarks[I].Tag then
        begin
          Ctr := VAdd(Ctr, VScale(VAdd(VAdd(NodePos(FMesh.Faces[F].N[0]), NodePos(FMesh.Faces[F].N[1])), NodePos(FMesh.Faces[F].N[2])), 1 / 3));
          Inc(V);
        end;
      if V > 0 then Arrow(VScale(Ctr, 1 / V), FMarks[I].Arrow, clSuiteDanger);
    end;
  { eixos }
  Ctr := FCenter;
  C.Font.Size := 8;
  for K := 0 to 2 do
  begin
    case K of
      0: begin Nrm := V3(1, 0, 0); Col := clSuiteAxisX; end;
      1: begin Nrm := V3(0, 1, 0); Col := clSuiteAxisY; end;
      else begin Nrm := V3(0, 0, 1); Col := clSuiteAxisZ; end;
    end;
    Pts[0] := Project(Ctr, D);
    Pts[1] := Project(VAdd(Ctr, VScale(Nrm, FRadius * 0.15)), D);
    { eixo de 36 px no canto, encurtado pela perspectiva da camera }
    D := (Pts[1].X - Pts[0].X) / Max(1e-9, 0.15 * 0.42 * Min(ClientWidth, ClientHeight) * FZoom);
    T := (Pts[1].Y - Pts[0].Y) / Max(1e-9, 0.15 * 0.42 * Min(ClientWidth, ClientHeight) * FZoom);
    C.Pen.Color := Col; C.Pen.Width := 2;
    C.Line(40, ClientHeight - 40, 40 + Round(36 * D), ClientHeight - 40 + Round(36 * T));
    C.Font.Color := Col;
    C.Brush.Style := bsClear;
    C.TextOut(36 + Round(46 * D), ClientHeight - 47 + Round(46 * T), Chr(Ord('X') + K));
  end;
  C.Pen.Width := 1;
  C.Brush.Style := bsSolid;
  if FHasScalar then DrawLegend(C);
  if FMessage <> '' then
  begin
    C.Font.Color := clSuiteText; C.Font.Size := 9;
    C.Brush.Style := bsClear;
    C.TextOut(14, 10, FMessage);
    C.Brush.Style := bsSolid;
  end;
end;

procedure TPhysicsView3D.DrawLegend(C: TCanvas);
var
  X, Y, H, I: Integer;
  V: Double;
begin
  H := Min(260, ClientHeight - 80);
  X := ClientWidth - 120; Y := 40;
  C.Font.Size := 8;
  C.Font.Color := clSuiteText;
  C.Brush.Style := bsClear;
  C.TextOut(X - 20, Y - 22, FScalarTitle + ' (' + FScalarUnit + ')');
  for I := 0 to H - 1 do
  begin
    C.Pen.Color := HeatColor(1 - I / H);
    C.Line(X, Y + I, X + 18, Y + I);
  end;
  C.Pen.Color := clSuiteBorder;
  C.Brush.Style := bsClear;
  C.Rectangle(X, Y, X + 18, Y + H);
  for I := 0 to 4 do
  begin
    V := FScalarMax - (FScalarMax - FScalarMin) * I / 4;
    C.TextOut(X + 24, Y + Round(H * I / 4) - 7, FormatFloat('0.###E+0', V));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TPhysicsView3D.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  FDown := True; FDownBtn := Button;
  FDownPt := Point(X, Y); FLastPt := FDownPt;
  FMoved := False;
end;

procedure TPhysicsView3D.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDown then Exit;
  if Abs(X - FDownPt.X) + Abs(Y - FDownPt.Y) > 3 then FMoved := True;
  if FDownBtn = mbLeft then
  begin
    FYaw := FYaw + (X - FLastPt.X) * 0.5;
    FPitch := EnsureRange(FPitch + (Y - FLastPt.Y) * 0.5, -89, 89);
  end
  else
  begin
    FPanX := FPanX + (X - FLastPt.X);
    FPanY := FPanY + (Y - FLastPt.Y);
  end;
  FLastPt := Point(X, Y);
  Invalidate;
end;

function PointInTri2(P, A, B, C: TPoint): Boolean;
var
  D1, D2, D3: Int64;
begin
  D1 := Int64(B.X - A.X) * (P.Y - A.Y) - Int64(B.Y - A.Y) * (P.X - A.X);
  D2 := Int64(C.X - B.X) * (P.Y - B.Y) - Int64(C.Y - B.Y) * (P.X - B.X);
  D3 := Int64(A.X - C.X) * (P.Y - C.Y) - Int64(A.Y - C.Y) * (P.X - C.X);
  Result := ((D1 >= 0) and (D2 >= 0) and (D3 >= 0)) or ((D1 <= 0) and (D2 <= 0) and (D3 <= 0));
end;

procedure TPhysicsView3D.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, F, Hit: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDown := False;
  if FMoved or (Button <> mbLeft) or (FMesh = nil) or (Length(FOrder) <> FMesh.FaceCount) then Exit;
  { a face mais a frente e a ultima pintada que contem o ponto }
  Hit := -1;
  for I := High(FOrder) downto 0 do
  begin
    F := FOrder[I];
    if FVisible[F] and PointInTri2(Point(X, Y), FProj[3 * F], FProj[3 * F + 1], FProj[3 * F + 2]) then
    begin
      Hit := F;
      Break;
    end;
  end;
  if Hit < 0 then Exit;
  FSelectedTag := FMesh.Faces[Hit].Tag;
  Invalidate;
  if Assigned(FOnPickFace) and (FSelectedTag >= 0) then
    FOnPickFace(Self, FSelectedTag, FMesh.FaceNames[FSelectedTag]);
end;

function TPhysicsView3D.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then FZoom := FZoom * 1.15 else FZoom := FZoom / 1.15;
  FZoom := EnsureRange(FZoom, 0.05, 50);
  Invalidate;
  Result := True;
end;

end.
