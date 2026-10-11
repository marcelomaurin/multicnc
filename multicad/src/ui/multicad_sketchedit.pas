unit multicad_sketchedit;

{ MultiCAD - modo esboco na vista 3D (fases 3C e 5).

  Liga a sessao de ferramentas (multicad_sketchtools, sem LCL) ao controle
  TCadView3D: converte o mouse em pontos do plano do esboco (raio do pixel
  x plano) e desenha por cima da vista, como no SolidWorks:
  - entidades com as cores de definicao (azul = subdefinida, preto =
    definida, vermelho = problema), construcao tracejada;
  - cotas com linhas de chamada, linha de cota com setas e valor em mm;
    arrastar o texto muda a posicao, clicar edita o valor;
  - grade em mm (passo automatico pelo zoom) com captura opcional;
  - linhas de inferencia pontilhadas, ponto medio, captura de pontos;
  - elastico de cada ferramenta com a medida ao lado do cursor e caixa para
    digitar a medida (comprimento, largura x altura, diametro). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Dialogs, StdCtrls, Forms, LCLType,
  LCLIntf, multicad_types, multicad_document, multicad_sketch, multicad_solver,
  multicad_rebuild, multicad_camera, multicad_softrender, multicad_view3d,
  multicad_sketchtools;

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
    FMouseX, FMouseY: Integer;
    FDimRects: array of TRect;
    FDimIndex: array of Integer;
    FDragDim: Integer;          { cota sendo arrastada (-1 = nenhuma) }
    FDragX, FDragY: Integer;
    FDragMoved: Boolean;
    FGrid: Boolean;
    FInput: TEdit;
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
    function AskDim(Sender: TObject; const ACaption: string; var AText: string;
      var RefOnly: Boolean): Boolean;
    procedure DrawEntity(C: TCanvas; const E: TSketchEntity; Col: TColor; Dashed: Boolean);
    procedure DrawGrid3D(Sender: TObject; R: TCadRaster);
    procedure DrawDims(C: TCanvas);
    procedure DrawArrow(C: TCanvas; const Tip, From: TPoint; Col: TColor);
    procedure DrawRubber(C: TCanvas);
    procedure EditDim(AIndex: Integer);
    procedure InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HideInput;
    procedure UpdateTol;
    procedure Changed;
    function GridStepFor: Double;
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
    procedure ToggleConstruction;
    { Redesenha e avisa (depois de mudar algo pela janela). }
    procedure View3DChanged;
    function StatusText: string;
    { Coordenadas do cursor no esboco (mm). }
    function CursorText: string;
    { Comeca a digitar a medida (tecla numerica com a ferramenta no meio). }
    function BeginTyping(const AFirst: string): Boolean;
    function Typing: Boolean;
    property Grid: Boolean read FGrid;
    procedure SetGrid(AShow, ASnap: Boolean);
    property Session: TCadSketchSession read FSession;
    property Sketch: TCadSketch read FSketch;
    property Frame: TCadFrame read FFrame;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnStatus: TNotifyEvent read FOnStatus write FOnStatus;
  end;

implementation

const
  DIM_COLOR_RGB: array[0..2] of Byte = (20, 20, 20);

{ Arco por inicio A, fim B e ponto M no arco (anti-horario de A para B
  passando por M). }
function Arc3(const A, B, M: TCadVec2; out E: TSketchEntity): Boolean;
var
  D, UX, UY, Cr: Double;
begin
  E := Default(TSketchEntity);
  D := 2 * (A.X * (B.Y - M.Y) + B.X * (M.Y - A.Y) + M.X * (A.Y - B.Y));
  if Abs(D) < 1E-12 then
    Exit(False);
  UX := ((Sqr(A.X) + Sqr(A.Y)) * (B.Y - M.Y) + (Sqr(B.X) + Sqr(B.Y)) * (M.Y - A.Y) +
    (Sqr(M.X) + Sqr(M.Y)) * (A.Y - B.Y)) / D;
  UY := ((Sqr(A.X) + Sqr(A.Y)) * (M.X - B.X) + (Sqr(B.X) + Sqr(B.Y)) * (A.X - M.X) +
    (Sqr(M.X) + Sqr(M.Y)) * (B.X - A.X)) / D;
  E.Kind := seArc;
  E.P1 := V2(UX, UY);
  E.Radius := Sqrt(Sqr(A.X - UX) + Sqr(A.Y - UY));
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

function Fmm(V: Double): string;
begin
  Result := FormatFloat('0.##', V);
end;

{ ---------- criacao ---------- }

constructor TCadSketchEditor.Create(AView: TCadView3D; ADoc: TCadDocument;
  ARB: TCadRebuilder; ASketch: TCadSketch);
var
  Err: string;
begin
  inherited Create;
  FView := AView;
  FDoc := ADoc;
  FSketch := ASketch;
  FDragDim := -1;
  FGrid := True;
  if not ARB.SketchFrame(ASketch, FFrame, Err) then
    FFrame := StdFrame(spFrontal);
  FSession := TCadSketchSession.Create(ADoc, ASketch);
  FSession.OnAskValue := @AskValue;
  FSession.OnAskDim := @AskDim;
  FView.ActiveSketchId := ASketch.Id;
  FView.OnViewMouseDown := @ViewDown;
  FView.OnViewMouseUp := @ViewUp;
  FView.OnViewMouseMove := @ViewMove;
  FView.OnOverlay := @ViewOverlay;
  FView.OnOverlay3D := @DrawGrid3D;
  FInput := TEdit.Create(nil);
  FInput.Visible := False;
  FInput.Parent := FView;
  FInput.Width := 170;
  FInput.OnKeyDown := @InputKeyDown;
  UpdateTol;
  FView.Redraw;
end;

destructor TCadSketchEditor.Destroy;
begin
  FInput.Free;
  if Assigned(FView) then
  begin
    FView.ActiveSketchId := 0;
    FView.OnViewMouseDown := nil;
    FView.OnViewMouseUp := nil;
    FView.OnViewMouseMove := nil;
    FView.OnOverlay := nil;
    FView.OnOverlay3D := nil;
    FView.Redraw;
  end;
  FSession.Free;
  inherited Destroy;
end;

function TCadSketchEditor.GridStepFor: Double;
const
  STEPS: array[0..11] of Double = (0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500);
var
  I: Integer;
  Px: Double;
begin
  { menor passo com pelo menos 12 px entre linhas }
  Px := Max(FView.Camera.Scale, 1E-9);
  Result := STEPS[High(STEPS)];
  for I := 0 to High(STEPS) do
    if STEPS[I] * Px >= 12 then
      Exit(STEPS[I]);
end;

procedure TCadSketchEditor.UpdateTol;
begin
  FSession.PickTol := 7 / Max(FView.Camera.Scale, 1E-6);
  FSession.GridStep := GridStepFor;
end;

procedure TCadSketchEditor.SetGrid(AShow, ASnap: Boolean);
begin
  FGrid := AShow;
  FSession.GridSnap := ASnap and AShow;
  FView.Redraw;
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
  FView.PushView;
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
  end
  else
  begin
    BoxAdd(B, FFrame.Origin);
    FView.Camera.SetViewport(Max(1, FView.ClientWidth), Max(1, FView.ClientHeight));
    FView.Camera.Fit(B);
    FView.Camera.Scale := FView.Camera.Scale * 0.8;
  end;
  UpdateTol;
  FView.Redraw;
end;

procedure TCadSketchEditor.SetTool(T: TCadSketchToolKind);
begin
  HideInput;
  FSession.Tool := T;
  Changed;
end;

procedure TCadSketchEditor.Escape;
begin
  if Typing then
    HideInput
  else if FSession.ClickCount > 0 then
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

procedure TCadSketchEditor.View3DChanged;
begin
  Changed;
end;

procedure TCadSketchEditor.ToggleConstruction;
begin
  FSession.ToggleConstruction;
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

function TCadSketchEditor.CursorText: string;
begin
  Result := Format('X %s mm   Y %s mm', [Fmm(FSession.Cursor.P.X), Fmm(FSession.Cursor.P.Y)]);
end;

function TCadSketchEditor.AskValue(Sender: TObject; const ACaption: string;
  var AText: string): Boolean;
begin
  Result := InputQuery('Modificar', ACaption + ' (mm, graus ou expressão):', AText);
end;

function TCadSketchEditor.AskDim(Sender: TObject; const ACaption: string;
  var AText: string; var RefOnly: Boolean): Boolean;
var
  F: TForm;
  E: TEdit;
  K: TCheckBox;
  L: TLabel;
  B: TButton;
begin
  { como o "Modificar" do SolidWorks, com a opcao de so marcar a medida }
  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Cota ' + ACaption;
    F.BorderStyle := bsDialog;
    F.Position := poMainFormCenter;
    F.Width := 330;
    F.Height := 158;
    L := TLabel.Create(F);
    L.Parent := F;
    L.SetBounds(12, 10, 300, 18);
    L.Caption := 'Valor (mm, graus ou expressão):';
    E := TEdit.Create(F);
    E.Parent := F;
    E.SetBounds(12, 30, 304, 26);
    E.Text := AText;
    K := TCheckBox.Create(F);
    K.Parent := F;
    K.SetBounds(12, 62, 304, 22);
    K.Caption := 'Só marcar a medida (não muda o desenho)';
    K.Checked := RefOnly;
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(146, 94, 82, 30);
    B.Caption := 'OK';
    B.Default := True;
    B.ModalResult := mrOK;
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(234, 94, 82, 30);
    B.Caption := 'Cancelar';
    B.Cancel := True;
    B.ModalResult := mrCancel;
    F.ActiveControl := E;
    E.SelectAll;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AText := E.Text;
      RefOnly := K.Checked;
    end;
  finally
    F.Free;
  end;
end;

{ ---------- digitar a medida ---------- }

function TCadSketchEditor.Typing: Boolean;
begin
  Result := FInput.Visible;
end;

function TCadSketchEditor.BeginTyping(const AFirst: string): Boolean;
begin
  Result := FSession.CanType;
  if not Result then
    Exit;
  FInput.Left := EnsureRange(FMouseX + 18, 0, Max(0, FView.ClientWidth - FInput.Width));
  FInput.Top := EnsureRange(FMouseY + 18, 0, Max(0, FView.ClientHeight - 28));
  FInput.Hint := FSession.TypeHint;
  FInput.ShowHint := True;
  FInput.Text := AFirst;
  FInput.Visible := True;
  FInput.SetFocus;
  FInput.SelStart := Length(FInput.Text);
  FView.Invalidate;
end;

procedure TCadSketchEditor.HideInput;
begin
  if FInput.Visible then
  begin
    FInput.Visible := False;
    if FView.CanFocus then
      FView.SetFocus;
  end;
end;

procedure TCadSketchEditor.InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        if FSession.ApplyTyped(FInput.Text) then
          HideInput
        else
          FInput.Color := $00C8C8FF;
        Changed;
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        HideInput;
        FView.Invalidate;
      end;
  else
    FInput.Color := clWindow;
  end;
end;

{ ---------- coordenadas ---------- }

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

{ ---------- mouse ---------- }

procedure TCadSketchEditor.EditDim(AIndex: Integer);
var
  C: TSketchConstraint;
  Txt: string;
begin
  C := FSketch.Constraint(AIndex);
  if not C.Driving then
    Exit;
  if C.Expr <> '' then
    Txt := C.Expr
  else
    Txt := FormatFloat('0.###', C.Value);
  if AskValue(Self, C.DimName, Txt) and (Trim(Txt) <> '') then
  begin
    FSketch.SetConstraintExpr(AIndex, Trim(Txt));
    FSession.Solve;
    if FSession.LastSolve.Status = ssConflict then
      FSession.LastMessage := FSession.LastSolve.Message
    else
      FSession.LastMessage := '';
    Changed;
  end;
end;

procedure TCadSketchEditor.ViewDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer; var Handled: Boolean);
var
  P: TCadVec2;
  I: Integer;
begin
  Handled := True;
  UpdateTol;
  HideInput;
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
  { texto de uma cota: arrastar (move o texto) ou clicar (edita o valor) }
  if FSession.Tool in [tkSelect, tkDimension] then
    for I := 0 to High(FDimRects) do
      if PtInRect(FDimRects[I], Point(X, Y)) then
      begin
        FDragDim := FDimIndex[I];
        FDragX := X;
        FDragY := Y;
        FDragMoved := False;
        Exit;
      end;
  if not ToLocal(X, Y, P) then
    Exit;
  FSession.Click(P, ssCtrl in Shift);
  Changed;
end;

procedure TCadSketchEditor.ViewUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer; var Handled: Boolean);
var
  D: Integer;
begin
  Handled := True;
  if FDragDim >= 0 then
  begin
    D := FDragDim;
    FDragDim := -1;
    if FDragMoved then
      Changed
    else
      EditDim(D);
  end;
end;

procedure TCadSketchEditor.ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer;
  var Handled: Boolean);
var
  P: TCadVec2;
begin
  Handled := True;
  FMouseIn := True;
  FMouseX := X;
  FMouseY := Y;
  UpdateTol;
  if not ToLocal(X, Y, P) then
    Exit;
  if (FDragDim >= 0) and (ssLeft in Shift) then
  begin
    if (Abs(X - FDragX) > 3) or (Abs(Y - FDragY) > 3) then
      FDragMoved := True;
    if FDragMoved and (FDragDim < FSketch.ConstraintCount) then
      FSession.MoveDimText(FDragDim, P);
    Exit;
  end;
  FSession.MouseMove(P);
  FHasHover := (FSession.Tool in [tkSelect, tkDimension]) and FSession.Hit(P, FHover);
  if Assigned(FOnStatus) then
    FOnStatus(Self);
end;

{ ---------- desenho ---------- }

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
        C.Pen.Style := psSolid;
        if E.Construction then
        begin
          { canto virtual: pequena cruz }
          C.Pen.Width := 1;
          C.Line(P.X - 4, P.Y - 4, P.X + 5, P.Y + 5);
          C.Line(P.X - 4, P.Y + 4, P.X + 5, P.Y - 5);
        end
        else
        begin
          C.Brush.Color := Col;
          C.Brush.Style := bsSolid;
          C.Rectangle(P.X - 2, P.Y - 2, P.X + 3, P.Y + 3);
        end;
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

procedure TCadSketchEditor.DrawGrid3D(Sender: TObject; R: TCadRaster);
var
  St, X0, X1, Y0, Y1, V: Double;
  P: array[0..3] of TCadVec2;
  I, K, W, H: Integer;
  Minor, Major: LongWord;
begin
  { grade no raster com teste de profundidade: fica atras da peca quando a
    peca esta na frente do plano do esboco }
  if not FGrid then
    Exit;
  W := FView.ClientWidth;
  H := FView.ClientHeight;
  if not ToLocal(0, 0, P[0]) or not ToLocal(W, 0, P[1]) or not ToLocal(0, H, P[2]) or
    not ToLocal(W, H, P[3]) then
    Exit;
  X0 := P[0].X; X1 := P[0].X; Y0 := P[0].Y; Y1 := P[0].Y;
  for I := 1 to 3 do
  begin
    X0 := Min(X0, P[I].X); X1 := Max(X1, P[I].X);
    Y0 := Min(Y0, P[I].Y); Y1 := Max(Y1, P[I].Y);
  end;
  St := GridStepFor;
  if ((X1 - X0) / St > 600) or ((Y1 - Y0) / St > 600) then
    Exit;
  Minor := CadRGB(226, 232, 240);
  Major := CadRGB(196, 206, 222);
  for K := Floor(X0 / St) to Ceil(X1 / St) do
  begin
    V := K * St;
    if K mod 5 = 0 then
      R.DrawLine3D(FrameToWorld(FFrame, V2(V, Y0)), FrameToWorld(FFrame, V2(V, Y1)), Major, 1, True)
    else
      R.DrawLine3D(FrameToWorld(FFrame, V2(V, Y0)), FrameToWorld(FFrame, V2(V, Y1)), Minor, 1, True);
  end;
  for K := Floor(Y0 / St) to Ceil(Y1 / St) do
  begin
    V := K * St;
    if K mod 5 = 0 then
      R.DrawLine3D(FrameToWorld(FFrame, V2(X0, V)), FrameToWorld(FFrame, V2(X1, V)), Major, 1, True)
    else
      R.DrawLine3D(FrameToWorld(FFrame, V2(X0, V)), FrameToWorld(FFrame, V2(X1, V)), Minor, 1, True);
  end;
end;

procedure TCadSketchEditor.DrawArrow(C: TCanvas; const Tip, From: TPoint; Col: TColor);
var
  DX, DY, L: Double;
  Pts: array[0..2] of TPoint;
begin
  DX := Tip.X - From.X;
  DY := Tip.Y - From.Y;
  L := Sqrt(DX * DX + DY * DY);
  if L < 1E-6 then
    Exit;
  DX := DX / L;
  DY := DY / L;
  Pts[0] := Tip;
  Pts[1] := Point(Round(Tip.X - DX * 10 - DY * 3.2), Round(Tip.Y - DY * 10 + DX * 3.2));
  Pts[2] := Point(Round(Tip.X - DX * 10 + DY * 3.2), Round(Tip.Y - DY * 10 - DX * 3.2));
  C.Brush.Style := bsSolid;
  C.Brush.Color := Col;
  C.Pen.Color := Col;
  C.Polygon(Pts);
end;

procedure TCadSketchEditor.DrawDims(C: TCanvas);
var
  I, K, N, TW, TH: Integer;
  Cn: TSketchConstraint;
  G: TCadDimGeom;
  Col, Ext: TColor;
  SA, SB, SDA, SDB, ST, SC, Mid: TPoint;
  DX, DY, L, T: Double;
  Pts: array of TPoint;
  Bad: Boolean;

  function Outward(const P, Q: TPoint; Dist: Integer): TPoint;
  var
    VX, VY, VL: Double;
  begin
    VX := P.X - Q.X;
    VY := P.Y - Q.Y;
    VL := Max(Sqrt(VX * VX + VY * VY), 1E-6);
    Result := Point(Round(P.X + VX / VL * Dist), Round(P.Y + VY / VL * Dist));
  end;

begin
  C.Font.Height := -13;
  C.Font.Style := [];
  SetLength(FDimRects, 0);
  SetLength(FDimIndex, 0);
  for I := 0 to FSketch.ConstraintCount - 1 do
  begin
    Cn := FSketch.Constraint(I);
    if not FSession.DimGeometry(I, G) then
      Continue;
    Bad := (I < Length(FSession.LastSolve.ConstraintState)) and
      (FSession.LastSolve.ConstraintState[I] in [csConflict, csRedundant]);
    if Bad then
      Col := RGBToColor(210, 30, 30)
    else if Cn.Driving then
      Col := RGBToColor(DIM_COLOR_RGB[0], DIM_COLOR_RGB[1], DIM_COLOR_RGB[2])
    else
      Col := RGBToColor(120, 120, 120);
    Ext := RGBToColor(90, 100, 120);
    SA := ToScreen(G.A);
    SB := ToScreen(G.B);
    SDA := ToScreen(G.DA);
    SDB := ToScreen(G.DB);
    ST := ToScreen(G.T);
    C.Pen.Width := 1;
    C.Pen.Style := psSolid;
    case G.Kind of
      dgLinear:
        begin
          { linhas de chamada: da medida ate um pouco alem da linha de cota }
          C.Pen.Color := Ext;
          if (Abs(SA.X - SDA.X) + Abs(SA.Y - SDA.Y)) > 2 then
            C.Line(Outward(SA, SDA, -3), Outward(SDA, SA, 5));
          if (Abs(SB.X - SDB.X) + Abs(SB.Y - SDB.Y)) > 2 then
            C.Line(Outward(SB, SDB, -3), Outward(SDB, SB, 5));
          { linha de cota (estende ate o texto se ele estiver fora) }
          C.Pen.Color := Col;
          DX := SDB.X - SDA.X;
          DY := SDB.Y - SDA.Y;
          L := DX * DX + DY * DY;
          if L > 1 then
          begin
            T := ((ST.X - SDA.X) * DX + (ST.Y - SDA.Y) * DY) / L;
            if T < 0 then
              C.Line(Point(Round(SDA.X + DX * T), Round(SDA.Y + DY * T)), SDB)
            else if T > 1 then
              C.Line(SDA, Point(Round(SDA.X + DX * T), Round(SDA.Y + DY * T)))
            else
              C.Line(SDA, SDB);
            if Sqrt(L) > 26 then
            begin
              DrawArrow(C, SDA, SDB, Col);
              DrawArrow(C, SDB, SDA, Col);
            end
            else
            begin
              { espaco curto: setas por fora }
              DrawArrow(C, SDA, Outward(SDA, SDB, 12), Col);
              DrawArrow(C, SDB, Outward(SDB, SDA, 12), Col);
            end;
          end;
        end;
      dgRadius, dgDiameter:
        begin
          C.Pen.Color := Col;
          SC := ToScreen(G.C);
          if G.Kind = dgDiameter then
          begin
            C.Line(SDA, SDB);
            DrawArrow(C, SDA, SDB, Col);
            DrawArrow(C, SDB, SDA, Col);
            if (Abs(ST.X - SDB.X) + Abs(ST.Y - SDB.Y)) > 4 then
              C.Line(SDB, ST);
          end
          else
          begin
            C.Line(SC, SDB);
            DrawArrow(C, SDB, SC, Col);
            if (Abs(ST.X - SDB.X) + Abs(ST.Y - SDB.Y)) > 4 then
              C.Line(SDB, ST);
          end;
        end;
      dgAngle:
        begin
          C.Pen.Color := Col;
          N := 32;
          SetLength(Pts, N + 1);
          L := G.Ang1 - G.Ang0;
          while L < 0 do L := L + 2 * Pi;
          for K := 0 to N do
          begin
            T := G.Ang0 + L * K / N;
            Pts[K] := ToScreen(V2(G.C.X + G.R * Cos(T), G.C.Y + G.R * Sin(T)));
          end;
          C.Polyline(Pts);
          if N > 2 then
          begin
            DrawArrow(C, Pts[0], Pts[2], Col);
            DrawArrow(C, Pts[N], Pts[N - 2], Col);
          end;
        end;
    end;
    { texto (fundo claro para ler sobre as linhas) }
    TW := C.TextWidth(G.Text) + 6;
    TH := C.TextHeight(G.Text) + 2;
    Mid := ST;
    C.Brush.Style := bsSolid;
    if Bad then
      C.Brush.Color := RGBToColor(255, 220, 214)
    else
      C.Brush.Color := RGBToColor(250, 251, 253);
    C.Pen.Color := C.Brush.Color;
    C.Rectangle(Mid.X - TW div 2, Mid.Y - TH div 2, Mid.X + TW div 2, Mid.Y + TH div 2);
    C.Font.Color := Col;
    C.Brush.Style := bsClear;
    C.TextOut(Mid.X - TW div 2 + 3, Mid.Y - TH div 2 + 1, G.Text);
    C.Brush.Style := bsSolid;
    SetLength(FDimRects, Length(FDimRects) + 1);
    FDimRects[High(FDimRects)] := Rect(Mid.X - TW div 2, Mid.Y - TH div 2, Mid.X + TW div 2, Mid.Y + TH div 2);
    SetLength(FDimIndex, Length(FDimIndex) + 1);
    FDimIndex[High(FDimIndex)] := I;
  end;
end;

procedure TCadSketchEditor.DrawRubber(C: TCanvas);
var
  S, S1: TCadSnap;
  Col: TColor;
  Tmp: TSketchEntity;
  P, Q: TPoint;
  Txt: string;
  W, H, L, Ang, A0, A1: Double;
begin
  S := FSession.Cursor;
  Col := RGBToColor(230, 120, 0);
  C.Pen.Width := 1;
  C.Pen.Style := psSolid;
  Txt := '';
  { linhas de inferencia (pontilhadas) }
  C.Pen.Color := RGBToColor(80, 130, 220);
  C.Pen.Style := psDot;
  if S.GuideX then
    C.Line(ToScreen(S.GX), ToScreen(S.P));
  if S.GuideY then
    C.Line(ToScreen(S.GY), ToScreen(S.P));
  C.Pen.Style := psSolid;
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
          L := Sqrt(Sqr(S.P.X - S1.P.X) + Sqr(S.P.Y - S1.P.Y));
          Ang := RadToDeg(ArcTan2(S.P.Y - S1.P.Y, S.P.X - S1.P.X));
          Txt := Format('%s mm  ∠ %s°', [Fmm(L), FormatFloat('0.#', Ang)]);
        end;
      tkRectangle:
        begin
          C.Pen.Color := Col;
          C.Line(ToScreen(V2(S1.P.X, S1.P.Y)), ToScreen(V2(S.P.X, S1.P.Y)));
          C.Line(ToScreen(V2(S.P.X, S1.P.Y)), ToScreen(V2(S.P.X, S.P.Y)));
          C.Line(ToScreen(V2(S.P.X, S.P.Y)), ToScreen(V2(S1.P.X, S.P.Y)));
          C.Line(ToScreen(V2(S1.P.X, S.P.Y)), ToScreen(V2(S1.P.X, S1.P.Y)));
          W := Abs(S.P.X - S1.P.X);
          H := Abs(S.P.Y - S1.P.Y);
          Txt := Format('%s x %s mm', [Fmm(W), Fmm(H)]);
        end;
      tkCircle:
        begin
          Tmp.Kind := seCircle;
          Tmp.P1 := S1.P;
          Tmp.Radius := Sqrt(Sqr(S.P.X - S1.P.X) + Sqr(S.P.Y - S1.P.Y));
          DrawEntity(C, Tmp, Col, False);
          C.Pen.Color := Col;
          C.Pen.Style := psDot;
          C.Line(ToScreen(S1.P), ToScreen(S.P));
          C.Pen.Style := psSolid;
          Txt := 'Ø ' + Fmm(2 * Tmp.Radius) + ' mm';
        end;
      tkArc3P:
        begin
          C.Pen.Color := Col;
          if FSession.ClickCount = 1 then
            C.Line(ToScreen(S1.P), ToScreen(S.P))
          else if Arc3(S1.P, FSession.ClickAt(1).P, S.P, Tmp) then
          begin
            DrawEntity(C, Tmp, Col, False);
            Txt := 'R ' + Fmm(Tmp.Radius) + ' mm';
          end;
        end;
      tkArcCenter:
        begin
          C.Pen.Color := Col;
          C.Pen.Style := psDot;
          C.Line(ToScreen(S1.P), ToScreen(S.P));
          C.Pen.Style := psSolid;
          if FSession.ClickCount = 1 then
            Txt := 'R ' + Fmm(Sqrt(Sqr(S.P.X - S1.P.X) + Sqr(S.P.Y - S1.P.Y))) + ' mm'
          else
          begin
            Tmp.Kind := seArc;
            Tmp.P1 := S1.P;
            Tmp.P2 := FSession.ClickAt(1).P;
            Tmp.Radius := Sqrt(Sqr(Tmp.P2.X - S1.P.X) + Sqr(Tmp.P2.Y - S1.P.Y));
            Tmp.P3 := S.P;
            DrawEntity(C, Tmp, Col, False);
            A0 := ArcTan2(Tmp.P2.Y - S1.P.Y, Tmp.P2.X - S1.P.X);
            A1 := ArcTan2(S.P.Y - S1.P.Y, S.P.X - S1.P.X);
            Ang := RadToDeg(A1 - A0);
            while Ang <= 0 do Ang := Ang + 360;
            Txt := Format('R %s mm  %s°', [Fmm(Tmp.Radius), FormatFloat('0.#', Ang)]);
          end;
        end;
      tkArcTangent:
        if FSession.TangentArc(S1, S.P, Tmp) then
        begin
          DrawEntity(C, Tmp, Col, False);
          Txt := 'R ' + Fmm(Tmp.Radius) + ' mm';
        end;
    end;
  end;
  { captura }
  P := ToScreen(S.P);
  C.Pen.Color := Col;
  C.Brush.Style := bsClear;
  if (S.Ent <> 0) and (S.Pt > 0) then
    C.Ellipse(P.X - 6, P.Y - 6, P.X + 7, P.Y + 7)
  else if S.Pt < 0 then
  begin
    { ponto medio: losango }
    C.Polygon([Point(P.X, P.Y - 6), Point(P.X + 6, P.Y), Point(P.X, P.Y + 6), Point(P.X - 6, P.Y)]);
  end
  else if S.Ent <> 0 then
    C.Rectangle(P.X - 3, P.Y - 3, P.X + 4, P.Y + 4);
  if FSession.CursorInfer <> 0 then
  begin
    C.Font.Color := Col;
    if FSession.CursorInfer = 1 then
      C.TextOut(P.X + 10, P.Y + 8, '—')
    else
      C.TextOut(P.X + 10, P.Y + 8, '|');
  end;
  { medida ao lado do cursor e dica para digitar }
  C.Font.Height := -12;
  if Txt <> '' then
  begin
    Q := Point(P.X + 14, P.Y - 34);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(255, 248, 225);
    C.Pen.Color := RGBToColor(230, 180, 90);
    C.Rectangle(Q.X - 3, Q.Y - 1, Q.X + C.TextWidth(Txt) + 4, Q.Y + C.TextHeight(Txt) + 1);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(110, 70, 0);
    C.TextOut(Q.X, Q.Y, Txt);
    if FSession.CanType and not Typing then
    begin
      C.Font.Color := RGBToColor(110, 120, 140);
      C.TextOut(Q.X, Q.Y - 16, 'digite a medida e Enter');
    end;
  end
  else
  begin
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(60, 70, 90);
    C.TextOut(P.X + 12, P.Y - 18, Format('%s; %s mm', [Fmm(S.P.X), Fmm(S.P.Y)]));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TCadSketchEditor.ViewOverlay(Sender: TObject; C: TCanvas);
var
  I, K, N: Integer;
  E: TSketchEntity;
  Col: TColor;
  St: TSketchEntityState;
  P: TPoint;
  A: TCadVec2;

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
  { cotas embaixo das entidades }
  DrawDims(C);
  { entidades }
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
    DrawEntity(C, E, Col, (E.Construction or E.Centerline) and (E.Kind <> sePoint));
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
  if FMouseIn and (FSession.Tool <> tkSelect) then
    DrawRubber(C);
end;

end.
