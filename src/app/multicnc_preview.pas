unit multicnc_preview;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, Controls, Graphics, multicnc_gcode_analyzer;
type
  TPreviewPlane = (ppXY, ppXZ, ppYZ);
  TGCodePreview = class(TCustomControl)
  private
    FTrace: TGCodeTrace; // owned by the form; the view never interprets G-code
    FEnvelope: TMachineEnvelope;
    FPlane: TPreviewPlane;
    procedure SetPlane(Value: TPreviewPlane);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetProgram(Trace: TGCodeTrace; const Envelope: TMachineEnvelope);
    property Plane: TPreviewPlane read FPlane write SetPlane;
  end;
implementation

constructor TGCodePreview.Create(AOwner: TComponent);
begin inherited; Color := clWhite; FPlane := ppXY; end;

procedure TGCodePreview.SetProgram(Trace: TGCodeTrace; const Envelope: TMachineEnvelope);
begin FTrace := Trace; FEnvelope := Envelope; Invalidate; end;

procedure TGCodePreview.SetPlane(Value: TPreviewPlane);
begin FPlane := Value; Invalidate; end;

procedure TGCodePreview.Paint;
var I: Integer; S: TGCodeSegment; A, B: TGCodePoint;
  MinU, MaxU, MinV, MaxV, U, V, Scale, OffsetU, OffsetV: Double;
  X1, Y1, X2, Y2: Integer;
  procedure Project(const P: TGCodePoint; out U, V: Double);
  begin
    case FPlane of
      ppXY: begin U := P.X; V := P.Y; end;
      ppXZ: begin U := P.X; V := P.Z; end;
      ppYZ: begin U := P.Y; V := P.Z; end;
    end;
  end;
  procedure IncludePoint(const P: TGCodePoint);
  begin
    Project(P, U, V); MinU := Min(MinU, U); MaxU := Max(MaxU, U);
    MinV := Min(MinV, V); MaxV := Max(MaxV, V);
  end;
  procedure Pixel(const P: TGCodePoint; out X, Y: Integer);
  begin
    Project(P, U, V);
    X := Round(EnsureRange(OffsetU + (U - MinU) * Scale, -10000.0, 10000.0));
    Y := Round(EnsureRange(Height - OffsetV - (V - MinV) * Scale, -10000.0, 10000.0));
  end;
  function Outside(const P: TGCodePoint): Boolean;
  begin
    Result := (P.X < FEnvelope.MinX - 1e-6) or (P.X > FEnvelope.MaxX + 1e-6) or
      (P.Y < FEnvelope.MinY - 1e-6) or (P.Y > FEnvelope.MaxY + 1e-6) or
      (P.Z < FEnvelope.MinZ - 1e-6) or (P.Z > FEnvelope.MaxZ + 1e-6);
  end;
begin
  Canvas.Brush.Color := Color; Canvas.FillRect(ClientRect);
  Canvas.Font.Color := clGrayText;
  Canvas.TextOut(12, 8, 'Azul: corte | Cinza pontilhado: rapido | Vermelho: fora dos limites');
  if (FTrace = nil) or (FTrace.Count = 0) then begin
    Canvas.TextOut(20, 55, 'Abra um G-code com movimentos para visualizar a trajetoria.'); Exit;
  end;
  if (Width < 90) or (Height < 90) then Exit;
  S := FTrace.Segment(0); Project(S.StartPoint, MinU, MinV); MaxU := MinU; MaxV := MinV;
  for I := 0 to FTrace.Count - 1 do begin
    S := FTrace.Segment(I); IncludePoint(S.StartPoint); IncludePoint(S.EndPoint);
  end;
  Scale := Min((Width - 64) / Max(1, MaxU - MinU), (Height - 76) / Max(1, MaxV - MinV));
  OffsetU := (Width - (MaxU - MinU) * Scale) / 2;
  OffsetV := (Height - (MaxV - MinV) * Scale) / 2 - 10;
  A.X := FEnvelope.MinX; A.Y := FEnvelope.MinY; A.Z := FEnvelope.MinZ;
  B.X := FEnvelope.MaxX; B.Y := FEnvelope.MaxY; B.Z := FEnvelope.MaxZ;
  Pixel(A, X1, Y1); Pixel(B, X2, Y2);
  Canvas.Brush.Style := bsClear; Canvas.Pen.Color := clSilver; Canvas.Pen.Style := psDot;
  Canvas.Rectangle(X1, Y2, X2, Y1);
  for I := 0 to FTrace.Count - 1 do begin
    S := FTrace.Segment(I); Pixel(S.StartPoint, X1, Y1); Pixel(S.EndPoint, X2, Y2);
    if S.Rapid then begin Canvas.Pen.Color := clGray; Canvas.Pen.Style := psDot; end
    else begin Canvas.Pen.Color := clBlue; Canvas.Pen.Style := psSolid; end;
    if Outside(S.StartPoint) or Outside(S.EndPoint) then Canvas.Pen.Color := clRed;
    Canvas.Line(X1, Y1, X2, Y2);
  end;
  Canvas.Pen.Style := psSolid; Canvas.Brush.Style := bsSolid;
  Canvas.TextOut(12, Height - 22, Format('Vista em mm | %.2f .. %.2f / %.2f .. %.2f', [MinU, MaxU, MinV, MaxV]));
end;
end.
