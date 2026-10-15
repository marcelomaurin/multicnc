unit multiassembly_electrical_canvas;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, LCLType, Forms,
  multiassembly_types, multiassembly_project;

type
  TComponentSelectEvent = procedure(Sender: TObject; const ComponentID: string) of object;

  TElectricalAssemblyCanvas = class(TCustomControl)
  private
    FProject: TAssemblyProject;
    FSelectedID: string;
    FScale: Double;
    FPanX, FPanY: Double;
    FDragging: Boolean;
    FDragStartX, FDragStartY: Integer;
    FInitialPanX, FInitialPanY: Double;
    FOnSelect: TComponentSelectEvent;

    function HitTest(X, Y: Integer): string;
    procedure GetPortCoord(const CompID, PortName: string; out PX, PY: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure FitToView;
    procedure ZoomIn;
    procedure ZoomOut;

    property Project: TAssemblyProject read FProject write FProject;
    property SelectedID: string read FSelectedID write FSelectedID;
    property Scale: Double read FScale write FScale;
    property OnSelectComponent: TComponentSelectEvent read FOnSelect write FOnSelect;
  end;

implementation

constructor TElectricalAssemblyCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks];
  DoubleBuffered := True;
  FScale := 1.0;
  FPanX := 20;
  FPanY := 20;
  FDragging := False;
  Cursor := crCross;
end;

destructor TElectricalAssemblyCanvas.Destroy;
begin
  inherited Destroy;
end;

function WireColor(const PortA, PortB, Caption: string): TColor;
var
  U: string;
begin
  U := UpperCase(PortA + ' ' + PortB + ' ' + Caption);
  if (Pos('GND', U) > 0) or (Pos('COM', U) > 0) or (Pos('0V', U) > 0) then
    Result := $404040 // Preto/Cinza Terra
  else if (Pos('24V', U) > 0) or (Pos('VMOT', U) > 0) or (Pos('12V', U) > 0) or (Pos('V+', U) > 0) then
    Result := $2020E0 // Vermelho Alimentacao
  else if (Pos('STEP', U) > 0) then
    Result := $D06020 // Azul STEP
  else if (Pos('DIR', U) > 0) then
    Result := $20A030 // Verde DIR
  else if (Pos('PWM', U) > 0) or (Pos('EN', U) > 0) then
    Result := $2080D0 // Laranja PWM/EN
  else if (Pos('MOTOR', U) > 0) or (Pos('COIL', U) > 0) or (Pos('A+', U) > 0) or (Pos('B+', U) > 0) then
    Result := $A02090 // Roxo Motor
  else if (Pos('ESTOP', U) > 0) or (Pos('SEGURANCA', U) > 0) then
    Result := $3030FF // Vermelho Estop
  else
    Result := $60A0C0; // Ciano
end;

procedure TElectricalAssemblyCanvas.GetPortCoord(const CompID, PortName: string; out PX, PY: Integer);
var
  I, J, Idx, BX, BY, BW, BH, Row, Col: Integer;
  C: TAssemblyComponent;
begin
  PX := 0; PY := 0;
  if FProject = nil then Exit;
  Idx := FProject.FindComponent(CompID);
  if Idx < 0 then Exit;

  // Organiza blocos de componentes em grade 3 colunas
  Col := Idx mod 3;
  Row := Idx div 3;
  BX := Round(FPanX + (Col * 280) * FScale);
  BY := Round(FPanY + (Row * 170) * FScale);
  BW := Round(230 * FScale);
  BH := Round(130 * FScale);

  C := FProject.Component(Idx);
  for J := 0 to High(C.Ports) do
  begin
    if SameText(C.Ports[J].Name, PortName) then
    begin
      if J mod 2 = 0 then
      begin
        // Porta no lado esquerdo
        PX := BX;
        PY := BY + Round((32 + (J div 2) * 18) * FScale);
      end
      else
      begin
        // Porta no lado direito
        PX := BX + BW;
        PY := BY + Round((32 + (J div 2) * 18) * FScale);
      end;
      Exit;
    end;
  end;
  // Padrao centro se porta nao declarada
  PX := BX + BW div 2;
  PY := BY + BH div 2;
end;

procedure TElectricalAssemblyCanvas.Paint;
var
  I, J, Col, Row, BX, BY, BW, BH: Integer;
  PX, PY, X1, Y1, X2, Y2, MidX: Integer;
  C: TAssemblyComponent;
  W: TElectricalConnection;
  IsSel: Boolean;
  WColor: TColor;
begin
  Canvas.Brush.Color := $131926; // Fundo escuro azulado
  Canvas.FillRect(ClientRect);

  if FProject = nil then Exit;

  // Grade discreta
  Canvas.Pen.Color := $1E293B;
  Canvas.Pen.Width := 1;
  for I := 0 to Width div 40 do
    Canvas.Line(I * 40, 0, I * 40, Height);
  for I := 0 to Height div 40 do
    Canvas.Line(0, I * 40, Width, I * 40);

  // 1. Desenha as conexoes eletricas (fios ortogonais)
  for I := 0 to FProject.WireCount - 1 do
  begin
    W := FProject.Wire(I);
    GetPortCoord(W.FromComponent, W.FromPort, X1, Y1);
    GetPortCoord(W.ToComponent, W.ToPort, X2, Y2);

    WColor := WireColor(W.FromPort, W.ToPort, W.Caption);
    Canvas.Pen.Color := WColor;

    if SameText(W.FromComponent, FSelectedID) or SameText(W.ToComponent, FSelectedID) then
      Canvas.Pen.Width := 3
    else
      Canvas.Pen.Width := 2;

    // Rota ortogonal com canto arredondado/duas dobras
    MidX := (X1 + X2) div 2;
    Canvas.Line(X1, Y1, MidX, Y1);
    Canvas.Line(MidX, Y1, MidX, Y2);
    Canvas.Line(MidX, Y2, X2, Y2);

    // Terminal circular
    Canvas.Brush.Color := WColor;
    Canvas.Ellipse(X1 - 3, Y1 - 3, X1 + 4, Y1 + 4);
    Canvas.Ellipse(X2 - 3, Y2 - 3, X2 + 4, Y2 + 4);

    // Rotulo da conexao
    if Trim(W.Caption) <> '' then
    begin
      Canvas.Font.Size := 7;
      Canvas.Font.Color := $94A3B8;
      Canvas.Brush.Color := $1E293B;
      Canvas.TextOut(MidX - Canvas.TextWidth(W.Caption) div 2, (Y1 + Y2) div 2 - 6, W.Caption);
    end;
  end;

  // 2. Desenha os blocos dos componentes eletronicos
  for I := 0 to FProject.ComponentCount - 1 do
  begin
    C := FProject.Component(I);
    IsSel := SameText(C.ID, FSelectedID);

    Col := I mod 3;
    Row := I div 3;
    BX := Round(FPanX + (Col * 280) * FScale);
    BY := Round(FPanY + (Row * 170) * FScale);
    BW := Round(230 * FScale);
    BH := Round(130 * FScale);

    // Fundo do cartao do componente
    if IsSel then
    begin
      Canvas.Brush.Color := $1E293B;
      Canvas.Pen.Color := $38BDF8; // Borda azul brilhante
      Canvas.Pen.Width := 3;
    end
    else
    begin
      Canvas.Brush.Color := $0F172A;
      Canvas.Pen.Color := $334155;
      Canvas.Pen.Width := 1;
    end;
    Canvas.RoundRect(BX, BY, BX + BW, BY + BH, 8, 8);

    // Barra de titulo do componente
    if IsSel then
      Canvas.Brush.Color := $0369A1
    else
      Canvas.Brush.Color := $1E293B;
    Canvas.RoundRect(BX, BY, BX + BW, BY + Round(26 * FScale), 6, 6);

    Canvas.Font.Size := 8;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := $F8FAFC;
    Canvas.TextOut(BX + 8, BY + 5, C.ID + ' - ' + C.Name);

    // Lista de portas
    Canvas.Font.Size := 7;
    Canvas.Font.Style := [];
    for J := 0 to High(C.Ports) do
    begin
      if J mod 2 = 0 then
      begin
        // Esquerda
        PX := BX + 6;
        PY := BY + Round((32 + (J div 2) * 18) * FScale);
        Canvas.Brush.Color := $38BDF8;
        Canvas.Ellipse(BX - 3, PY + 4, BX + 4, PY + 11);
        Canvas.Font.Color := $38BDF8;
        Canvas.Brush.Color := $0F172A;
        Canvas.TextOut(PX, PY, C.Ports[J].Name);
      end
      else
      begin
        // Direita
        PX := BX + BW - 6;
        PY := BY + Round((32 + (J div 2) * 18) * FScale);
        Canvas.Brush.Color := $F97316;
        Canvas.Ellipse(BX + BW - 3, PY + 4, BX + BW + 4, PY + 11);
        Canvas.Font.Color := $F97316;
        Canvas.Brush.Color := $0F172A;
        Canvas.TextOut(PX - Canvas.TextWidth(C.Ports[J].Name), PY, C.Ports[J].Name);
      end;
    end;
  end;

  Canvas.Font.Size := 9;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := $94A3B8;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(16, 16, 'ESQUEMA ELÉTRICO & CABEAMENTO');
  Canvas.Brush.Style := bsSolid;
end;

function TElectricalAssemblyCanvas.HitTest(X, Y: Integer): string;
var
  I, Col, Row, BX, BY, BW, BH: Integer;
  C: TAssemblyComponent;
begin
  Result := '';
  if FProject = nil then Exit;
  for I := 0 to FProject.ComponentCount - 1 do
  begin
    C := FProject.Component(I);
    Col := I mod 3;
    Row := I div 3;
    BX := Round(FPanX + (Col * 280) * FScale);
    BY := Round(FPanY + (Row * 170) * FScale);
    BW := Round(230 * FScale);
    BH := Round(130 * FScale);

    if (X >= BX) and (X <= BX + BW) and (Y >= BY) and (Y <= BY + BH) then
      Exit(C.ID);
  end;
end;

procedure TElectricalAssemblyCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  HitID: string;
begin
  SetFocus;
  HitID := HitTest(X, Y);
  if HitID <> '' then
  begin
    FSelectedID := HitID;
    if Assigned(FOnSelect) then
      FOnSelect(Self, HitID);
    Invalidate;
  end
  else
  begin
    FDragging := True;
    FDragStartX := X;
    FDragStartY := Y;
    FInitialPanX := FPanX;
    FInitialPanY := FPanY;
  end;
end;

procedure TElectricalAssemblyCanvas.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if FDragging then
  begin
    FPanX := FInitialPanX + (X - FDragStartX);
    FPanY := FInitialPanY + (Y - FDragStartY);
    Invalidate;
  end;
end;

procedure TElectricalAssemblyCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
end;

function TElectricalAssemblyCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then
    FScale := FScale * 1.15
  else
    FScale := Max(0.4, FScale / 1.15);
  Invalidate;
  Result := True;
end;

procedure TElectricalAssemblyCanvas.FitToView;
begin
  FPanX := 20;
  FPanY := 20;
  FScale := 1.0;
  Invalidate;
end;

procedure TElectricalAssemblyCanvas.ZoomIn;
begin
  FScale := FScale * 1.25;
  Invalidate;
end;

procedure TElectricalAssemblyCanvas.ZoomOut;
begin
  FScale := Max(0.4, FScale / 1.25);
  Invalidate;
end;

end.
