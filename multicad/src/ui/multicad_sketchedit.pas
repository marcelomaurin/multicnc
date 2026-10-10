unit multicad_sketchedit;

{ MultiCAD - modo esboco na vista 3D (fase 3C).

  Liga a sessao de ferramentas (multicad_sketchtools, sem LCL) ao controle
  TCadView3D: converte o mouse em pontos do plano do esboco (raio do pixel
  x plano), desenha as entidades por cima da vista com as cores de
  definicao do SolidWorks (azul = subdefinida, preto = definida,
  vermelho = problema), o elastico da ferramenta, captura, inferencia
  H/V e o texto das cotas (clicar numa cota edita o valor). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Dialogs, LCLIntf, multicad_types,
  multicad_document, multicad_sketch, multicad_solver, multicad_rebuild,
  multicad_camera, multicad_softrender, multicad_view3d, multicad_sketchtools;

type
  TCadSketchEditor = class
  private
    FView: TCadView3D;
    FDoc: TCadDocument;
    FSketch: TCadSketch;
    FFrame: TCadFrame;
    FSession: TCadSketchSession;
    FHover: TCadPickItem;
    FHasHover: Boolean;
    FMouseIn: Boolean;
    FDimRects: array of TRect;
    FDimIndex: array of Integer;
    FOnChanged: TNotifyEvent;
    FOnStatus: TNotifyEvent;
    function ToLocal(X, Y: Integer; out P: TCadVec2): Boolean;
    function ToScreen(const P: TCadVec2): TPoint;
    procedure ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer; var Handled: Boolean);
    procedure ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer; var Handled: Boolean);
    procedure ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer; var Handled: Boolean);
    procedure ViewOverlay(Sender: TObject; C: TCanvas);
    function AskValue(Sender: TObject; const ACaption: string; var AText: string): Boolean;
    procedure DrawEntity(C: TCanvas; const E: TSketchEntity; Col: TColor; Dashed: Boolean);
    procedure UpdateTol;
    procedure Changed;
  public
    constructor Create(AView: TCadView3D; ADoc: TCadDocument; ARB: TCadRebuilder;
      ASketch: TCadSketch);
    destructor Destroy; override;
    procedure NormalTo;
    procedure SetTool(T: TCadSketchToolKind);
    { Esc: encerra a cadeia; de novo, volta para Selecionar. }
    procedure Escape;
    procedure DeleteSelection;
    function AddRelation(K: TConstraintKind): Boolean;
    function StatusText: string;
    property Session: TCadSketchSession read FSession;
    property Sketch: TCadSketch read FSketch;
    property Frame: TCadFrame read FFrame;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnStatus: TNotifyEvent read FOnStatus write FOnStatus;
  end;

implementation

{ Arco por inicio A, fim B e ponto M no arco (anti-horario de A para B
  passando por M). }
function Arc3(const A, B, M: TCadVec2; out E: TSketchEntity): Boolean;
var
  D, UX, UY, CX, CY: Double;
  Cr: Double;
begin
  E := Default(TSketchEntity);
  D := 2 * (A.X * (B.Y - M.Y) + B.X * (M.Y - A.Y) + M.X * (A.Y - B.Y));
  if Abs(D) < 1E-12 then
    Exit(False);
  UX := ((Sqr(A.X) + Sqr(A.Y)) * (B.Y - M.Y) + (Sqr(B.X) + Sqr(B.Y)) * (M.Y - A.Y) +
    (Sqr(M.X) + Sqr(M.Y)) * (A.Y - B.Y)) / D;
  UY := ((Sqr(A.X) + Sqr(A.Y)) * (M.X - B.X) + (Sqr(B.X) + Sqr(B.Y)) * (A.X - M.X) +
    (Sqr(M.X) + Sqr(M.Y)) * (B.X - A.X)) / D;
  CX := UX;
  CY := UY;
  E.Kind := seArc;
  E.P1 := V2(CX, CY);
  E.Radius := Sqrt(Sqr(A.X - CX) + Sqr(A.Y - CY));
  { sentido: M a esquerda de A->B = horario }
  Cr := (B.X - A.X) * (M.Y - A.Y) - (B.Y - A.Y) * (M.X - A.X);
  if Cr < 0 then
  begin
    E.P2 := A;
    E.P3 := B;
  end
  else
  begin
    E.P2 := B;
    E.P3 := A;
  end;
  Result := True;
end;

constructor TCadSketchEditor.Create(AView: TCadView3D; ADoc: TCadDocument;
  ARB: TCadRebuilder; ASketch: TCadSketch);
var
  Err: string;
begin
  inherited Create;
  FView := AView;
  FDoc := ADoc;
  FSketch := ASketch;
  if not ARB.SketchFrame(ASketch, FFrame, Err) then
    FFrame := StdFrame(spFrontal);
  FSession := TCadSketchSession.Create(ADoc, ASketch);
  FSession.OnAskValue := @AskValue;
  FView.ActiveSketchId := ASketch.Id;
  FView.OnViewMouseDown := @ViewDown;
  FView.OnViewMouseUp := @ViewUp;
  FView.OnViewMouseMove := @ViewMove;
  FView.OnOverlay := @ViewOverlay;
  UpdateTol;
  FView.Redraw;
end;

destructor TCadSketchEditor.Destroy;
begin
  if Assigned(FView) then
  begin
    FView.ActiveSketchId := 0;
    FView.OnViewMouseDown := nil;
    FView.OnViewMouseUp := nil;
    FView.OnViewMouseMove := nil;
    FView.OnOverlay := nil;
    FView.Redraw;
  end;
  FSession.Free;
  inherited Destroy;
end;

procedure TCadSketchEditor.UpdateTol;
begin
  FSession.PickTol := 7 / Max(FView.Camera.Scale, 1E-6);
end;

procedure TCadSketchEditor.Changed;
begin
  FView.Invalidate;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  if Assigned(FOnStatus) then
    FOnStatus(Self);
end;

procedure TCadSketchEditor.NormalTo;
var
  B: TCadBox3;
  I: Integer;
  E: TSketchEntity;
  R: Double;
begin
  FView.Camera.NormalTo(FFrame, False);
  B := BoxEmpty;
  for I := 0 to FSketch.EntityCount - 1 do
  begin
    E := FSketch.Entity(I);
    R := 0;
    if E.Kind in [seCircle, seArc] then
      R := E.Radius;
    BoxAdd(B, FrameToWorld(FFrame, V2(E.P1.X - R, E.P1.Y - R)));
    BoxAdd(B, FrameToWorld(FFrame, V2(E.P1.X + R, E.P1.Y + R)));
    if E.Kind = seLine then
      BoxAdd(B, FrameToWorld(FFrame, E.P2));
  end;
  if B.Empty then
  begin
    FView.Camera.Target := FFrame.Origin;
    if FView.ModelBox.Empty then
      FView.Camera.Scale := Min(FView.ClientWidth, FView.ClientHeight) / 160;
    UpdateTol;
    FView.Redraw;
  end
  else
  begin
    BoxAdd(B, FFrame.Origin);
    FView.Camera.SetViewport(Max(1, FView.ClientWidth), Max(1, FView.ClientHeight));
    FView.Camera.Fit(B);
    FView.Camera.Scale := FView.Camera.Scale * 0.8;
    UpdateTol;
    FView.Redraw;
  end;
end;

procedure TCadSketchEditor.SetTool(T: TCadSketchToolKind);
begin
  FSession.Tool := T;
  Changed;
end;

procedure TCadSketchEditor.Escape;
begin
  if FSession.ClickCount > 0 then
    FSession.Cancel
  else
    FSession.Tool := tkSelect;
  Changed;
end;

procedure TCadSketchEditor.DeleteSelection;
begin
  if FSession.DeleteSelection then
    Changed;
end;

function TCadSketchEditor.AddRelation(K: TConstraintKind): Boolean;
begin
  Result := FSession.AddRelation(K);
  Changed;
end;

function TCadSketchEditor.StatusText: string;
begin
  Result := FSketch.Name + ': ' + CAD_SKETCH_STATUS_NAMES[FSession.LastSolve.Status];
  if FSession.LastSolve.Status = ssUnderDefined then
    Result := Result + Format(' (%d graus de liberdade)', [FSession.LastSolve.DOF]);
  if FSession.LastMessage <> '' then
    Result := Result + '  -  ' + FSession.LastMessage;
end;

function TCadSketchEditor.AskValue(Sender: TObject; const ACaption: string;
  var AText: string): Boolean;
begin
  Result := InputQuery('Modificar cota', ACaption + ' (mm, graus ou expressão):', AText);
end;

function TCadSketchEditor.ToLocal(X, Y: Integer; out P: TCadVec2): Boolean;
var
  O, D, Q: TCadVec3;
  Den, T: Double;
begin
  FView.Camera.ScreenRay(X + 0.5, Y + 0.5, O, D);
  Den := VDot(D, FFrame.Normal);
  if Abs(Den) < 1E-9 then
    Exit(False);
  T := VDot(VSub(FFrame.Origin, O), FFrame.Normal) / Den;
  Q := VAdd(O, VScale(D, T));
  P := FrameToLocal(FFrame, Q);
  Result := True;
end;

function TCadSketchEditor.ToScreen(const P: TCadVec2): TPoint;
var
  S: TCadScreenPt;
begin
  S := FView.Camera.Project(FrameToWorld(FFrame, P));
  Result.X := Round(S.X);
  Result.Y := Round(S.Y);
end;

procedure TCadSketchEditor.ViewDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer; var Handled: Boolean);
var
  P: TCadVec2;
  I: Integer;
  Txt: string;
  C: TSketchConstraint;
begin
  Handled := True;
  UpdateTol;
  if Button = mbRight then
  begin
    Escape;
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  if ssDouble in Shift then
  begin
    FSession.Cancel;
    Changed;
    Exit;
  end;
  { clique no texto de uma cota: editar o valor }
  if FSession.Tool in [tkSelect, tkDimension] then
    for I := 0 to High(FDimRects) do
      if PtInRect(FDimRects[I], Point(X, Y)) then
      begin
        C := FSketch.Constraint(FDimIndex[I]);
        if not C.Driving then
          Exit;
        if C.Expr <> '' then
          Txt := C.Expr
        else
          Txt := FormatFloat('0.###', C.Value);
        if AskValue(Self, C.DimName, Txt) and (Trim(Txt) <> '') then
        begin
          FSketch.SetConstraintExpr(FDimIndex[I], Trim(Txt));
          FSession.Solve;
          if FSession.LastSolve.Status = ssConflict then
            FSession.LastMessage := FSession.LastSolve.Message
          else
            FSession.LastMessage := '';
          Changed;
        end;
        Exit;
      end;
  if not ToLocal(X, Y, P) then
    Exit;
  FSession.Click(P, ssCtrl in Shift);
  Changed;
end;

procedure TCadSketchEditor.ViewUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer; var Handled: Boolean);
begin
  Handled := True;
end;

procedure TCadSketchEditor.ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer;
  var Handled: Boolean);
var
  P: TCadVec2;
begin
  Handled := True;
  FMouseIn := True;
  UpdateTol;
  if not ToLocal(X, Y, P) then
    Exit;
  FSession.MouseMove(P);
  FHasHover := (FSession.Tool in [tkSelect, tkDimension]) and FSession.Hit(P, FHover);
end;

procedure TCadSketchEditor.DrawEntity(C: TCanvas; const E: TSketchEntity; Col: TColor;
  Dashed: Boolean);
var
  A0, A1, Sweep, T: Double;
  N, J: Integer;
  Pts: array of TPoint;
  P: TPoint;
begin
  C.Pen.Color := Col;
  if Dashed then
    C.Pen.Style := psDash
  else
    C.Pen.Style := psSolid;
  case E.Kind of
    seLine:
      C.Line(ToScreen(E.P1), ToScreen(E.P2));
    sePoint:
      begin
        P := ToScreen(E.P1);
        C.Brush.Color := Col;
        C.Brush.Style := bsSolid;
        C.Pen.Style := psSolid;
        C.Rectangle(P.X - 2, P.Y - 2, P.X + 3, P.Y + 3);
      end;
    seCircle, seArc:
      begin
        if E.Kind = seCircle then
        begin
          A0 := 0;
          Sweep := 2 * Pi;
        end
        else
        begin
          A0 := ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X);
          A1 := ArcTan2(E.P3.Y - E.P1.Y, E.P3.X - E.P1.X);
          Sweep := A1 - A0;
          while Sweep <= 0 do
            Sweep := Sweep + 2 * Pi;
        end;
        N := Max(12, Ceil(Sweep / (2 * Pi) * 96));
        SetLength(Pts, N + 1);
        for J := 0 to N do
        begin
          T := A0 + Sweep * J / N;
          Pts[J] := ToScreen(V2(E.P1.X + E.Radius * Cos(T), E.P1.Y + E.Radius * Sin(T)));
        end;
        C.Polyline(Pts);
      end;
  end;
  C.Pen.Style := psSolid;
end;

procedure TCadSketchEditor.ViewOverlay(Sender: TObject; C: TCanvas);
var
  I, K, N: Integer;
  E: TSketchEntity;
  Col: TColor;
  St: TSketchEntityState;
  Cn: TSketchConstraint;
  P, Q: TPoint;
  A: TCadVec2;
  S, S1: TCadSnap;
  Txt: string;
  W, H: Integer;
  Tmp: TSketchEntity;

  procedure Mark(const Pt: TCadVec2; Cl: TColor);
  var
    M: TPoint;
  begin
    M := ToScreen(Pt);
    C.Brush.Style := bsSolid;
    C.Brush.Color := Cl;
    C.Pen.Color := Cl;
    C.Pen.Style := psSolid;
    C.Rectangle(M.X - 2, M.Y - 2, M.X + 3, M.Y + 3);
  end;

begin
  UpdateTol;
  C.Pen.Width := 1;
  { origem do esboco }
  P := ToScreen(V2(0, 0));
  C.Pen.Color := RGBToColor(200, 30, 30);
  C.Line(P.X, P.Y, P.X + 22, P.Y);
  C.Line(P.X, P.Y, P.X, P.Y - 22);
  C.Line(P.X + 22, P.Y, P.X + 17, P.Y - 3);
  C.Line(P.X + 22, P.Y, P.X + 17, P.Y + 3);
  C.Line(P.X, P.Y - 22, P.X - 3, P.Y - 17);
  C.Line(P.X, P.Y - 22, P.X + 3, P.Y - 17);
  { entidades }
  C.Pen.Width := 2;
  for I := 0 to FSketch.EntityCount - 1 do
  begin
    E := FSketch.Entity(I);
    St := esFree;
    if I < Length(FSession.LastSolve.EntityState) then
      St := FSession.LastSolve.EntityState[I];
    case St of
      esDefined: Col := clBlack;
      esProblem: Col := RGBToColor(220, 30, 30);
    else
      Col := RGBToColor(20, 40, 230);
    end;
    if E.Construction or E.Centerline then
      C.Pen.Width := 1
    else
      C.Pen.Width := 2;
    if FSession.IsSelected(E.Id, 0) then
      Col := CadToColor(CAD_SELECT_COLOR)
    else if FHasHover and (FHover.Ent = E.Id) and (FHover.Pt = 0) then
      Col := CadToColor(CAD_HOVER_COLOR);
    DrawEntity(C, E, Col, E.Construction or E.Centerline);
  end;
  C.Pen.Width := 1;
  { pontos das extremidades }
  for I := 0 to FSketch.EntityCount - 1 do
  begin
    E := FSketch.Entity(I);
    case E.Kind of
      seLine: N := 2;
      seArc: N := 3;
      seCircle: N := 1;
    else
      N := 0;
    end;
    for K := 1 to N do
    begin
      case K of
        1: A := E.P1;
        2: A := E.P2;
      else
        A := E.P3;
      end;
      Col := RGBToColor(20, 40, 230);
      if FSession.IsSelected(E.Id, K) then
        Col := CadToColor(CAD_SELECT_COLOR)
      else if FHasHover and (FHover.Ent = E.Id) and (FHover.Pt = K) then
        Col := CadToColor(CAD_HOVER_COLOR);
      Mark(A, Col);
    end;
  end;
  { cotas }
  C.Font.Height := -13;
  C.Font.Style := [];
  SetLength(FDimRects, 0);
  SetLength(FDimIndex, 0);
  for I := 0 to FSketch.ConstraintCount - 1 do
  begin
    Cn := FSketch.Constraint(I);
    if not IsDimensionKind(Cn.Kind) or not FSession.DimAnchor(I, A) then
      Continue;
    case Cn.Kind of
      ckDiameter: Txt := 'Ø' + FormatFloat('0.##', Cn.Value);
      ckRadius: Txt := 'R' + FormatFloat('0.##', Cn.Value);
      ckAngle: Txt := FormatFloat('0.##', Cn.Value) + '°';
    else
      Txt := FormatFloat('0.##', Cn.Value);
    end;
    if not Cn.Driving then
      Txt := '(' + Txt + ')';
    P := ToScreen(A);
    W := C.TextWidth(Txt) + 8;
    H := C.TextHeight(Txt) + 2;
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(255, 255, 255);
    if I < Length(FSession.LastSolve.ConstraintState) then
      if FSession.LastSolve.ConstraintState[I] in [csConflict, csRedundant] then
        C.Brush.Color := RGBToColor(255, 210, 200);
    C.Pen.Color := RGBToColor(150, 160, 175);
    C.Rectangle(P.X - W div 2, P.Y - H div 2, P.X + W div 2, P.Y + H div 2);
    if Cn.Driving then
      C.Font.Color := clBlack
    else
      C.Font.Color := RGBToColor(110, 110, 110);
    C.Brush.Style := bsClear;
    C.TextOut(P.X - W div 2 + 4, P.Y - H div 2 + 1, Txt);
    SetLength(FDimRects, Length(FDimRects) + 1);
    FDimRects[High(FDimRects)] := Rect(P.X - W div 2, P.Y - H div 2, P.X + W div 2, P.Y + H div 2);
    SetLength(FDimIndex, Length(FDimIndex) + 1);
    FDimIndex[High(FDimIndex)] := I;
  end;
  C.Brush.Style := bsSolid;
  { elastico da ferramenta }
  if FMouseIn and (FSession.Tool <> tkSelect) then
  begin
    S := FSession.Cursor;
    Col := RGBToColor(230, 120, 0);
    C.Pen.Width := 1;
    if FSession.ClickCount > 0 then
    begin
      S1 := FSession.ClickAt(0);
      Tmp := Default(TSketchEntity);
      case FSession.Tool of
        tkLine, tkCenterline:
          begin
            C.Pen.Color := Col;
            if FSession.Tool = tkCenterline then
              C.Pen.Style := psDash;
            C.Line(ToScreen(S1.P), ToScreen(S.P));
            C.Pen.Style := psSolid;
          end;
        tkRectangle:
          begin
            C.Pen.Color := Col;
            P := ToScreen(S1.P);
            Q := ToScreen(S.P);
            C.Line(ToScreen(V2(S1.P.X, S1.P.Y)), ToScreen(V2(S.P.X, S1.P.Y)));
            C.Line(ToScreen(V2(S.P.X, S1.P.Y)), ToScreen(V2(S.P.X, S.P.Y)));
            C.Line(ToScreen(V2(S.P.X, S.P.Y)), ToScreen(V2(S1.P.X, S.P.Y)));
            C.Line(ToScreen(V2(S1.P.X, S.P.Y)), ToScreen(V2(S1.P.X, S1.P.Y)));
          end;
        tkCircle:
          begin
            Tmp.Kind := seCircle;
            Tmp.P1 := S1.P;
            Tmp.Radius := Sqrt(Sqr(S.P.X - S1.P.X) + Sqr(S.P.Y - S1.P.Y));
            DrawEntity(C, Tmp, Col, False);
          end;
        tkArc3P:
          begin
            C.Pen.Color := Col;
            if FSession.ClickCount = 1 then
              C.Line(ToScreen(S1.P), ToScreen(S.P))
            else
            begin
              C.Pen.Style := psDot;
              C.Line(ToScreen(S1.P), ToScreen(FSession.ClickAt(1).P));
              C.Pen.Style := psSolid;
              { arco pelos 3 pontos (inicio, fim, cursor) }
              if Arc3(S1.P, FSession.ClickAt(1).P, S.P, Tmp) then
                DrawEntity(C, Tmp, Col, False);
            end;
          end;
      end;
    end;
    { captura e inferencia }
    if S.Ent <> 0 then
    begin
      P := ToScreen(S.P);
      C.Pen.Color := Col;
      C.Brush.Style := bsClear;
      C.Ellipse(P.X - 6, P.Y - 6, P.X + 7, P.Y + 7);
      C.Brush.Style := bsSolid;
    end;
    if FSession.CursorInfer <> 0 then
    begin
      P := ToScreen(S.P);
      C.Font.Color := Col;
      C.Brush.Style := bsClear;
      if FSession.CursorInfer = 1 then
        C.TextOut(P.X + 10, P.Y + 8, '—')
      else
        C.TextOut(P.X + 10, P.Y + 8, '|');
      C.Brush.Style := bsSolid;
    end;
    P := ToScreen(S.P);
    C.Font.Color := RGBToColor(60, 70, 90);
    C.Brush.Style := bsClear;
    C.Font.Height := -11;
    C.TextOut(P.X + 12, P.Y - 18, Format('%.2f; %.2f', [S.P.X, S.P.Y]));
    C.Brush.Style := bsSolid;
  end;
end;

end.
