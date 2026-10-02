unit multislicer_layerpreview;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, Controls, Graphics, multislicer_pipeline;
type TSlicerLayerPreview = class(TCustomControl)
private
  Engine: TModernSlicer; Layer: Integer;
protected
  procedure Paint; override;
public
  constructor Create(AOwner: TComponent); override;
  procedure SetSlice(AEngine: TModernSlicer; ALayer: Integer);
end;
implementation
constructor TSlicerLayerPreview.Create(AOwner: TComponent);
begin inherited; Color := clWhite; end;
procedure TSlicerLayerPreview.SetSlice(AEngine: TModernSlicer; ALayer: Integer);
begin Engine := AEngine; Layer := ALayer; Invalidate; end;
procedure TSlicerLayerPreview.Paint;
var D: TLayerData; I, J, K, Last: Integer; MinX, MinY, MaxX, MaxY, Scale, OX, OY: Double;
  X1, Y1, X2, Y2: Integer;
begin
  Canvas.Brush.Color := Color; Canvas.FillRect(ClientRect);
  Canvas.TextOut(12, 8, 'Azul: parede externa | Verde: parede interna | Laranja: solido | Roxo: preenchimento');
  if (Engine = nil) or (Layer < 0) or (Layer >= Length(Engine.Layers)) then begin
    Canvas.TextOut(20, 55, 'Fatie um STL para visualizar os percursos de cada camada.'); Exit;
  end;
  D := Engine.Layers[Layer]; MinX := MaxDouble; MinY := MaxDouble; MaxX := -MaxDouble; MaxY := -MaxDouble;
  for I := 0 to High(D.Paths) do for J := 0 to High(D.Paths[I].Points) do begin
    MinX := Min(MinX, D.Paths[I].Points[J].X); MaxX := Max(MaxX, D.Paths[I].Points[J].X);
    MinY := Min(MinY, D.Paths[I].Points[J].Y); MaxY := Max(MaxY, D.Paths[I].Points[J].Y);
  end;
  if (MaxX < MinX) or (Width < 90) or (Height < 90) then Exit;
  Scale := Min((Width - 60) / Max(1, MaxX - MinX), (Height - 70) / Max(1, MaxY - MinY));
  OX := (Width - (MaxX - MinX) * Scale) / 2; OY := (Height - (MaxY - MinY) * Scale) / 2 - 10;
  for I := 0 to High(D.Paths) do begin
    case D.Paths[I].Role of
      prOuterWall: Canvas.Pen.Color := clBlue;
      prInnerWall: Canvas.Pen.Color := clGreen;
      prSolidInfill: Canvas.Pen.Color := $0080FF;
      prSparseInfill: Canvas.Pen.Color := clPurple;
    else Canvas.Pen.Color := clGray; end;
    Last := High(D.Paths[I].Points);
    if not D.Paths[I].Closed then Dec(Last);
    for J := 0 to Last do begin
      K := (J + 1) mod Length(D.Paths[I].Points);
      X1 := Round(OX + (D.Paths[I].Points[J].X - MinX) * Scale);
      Y1 := Round(Height - OY - (D.Paths[I].Points[J].Y - MinY) * Scale);
      X2 := Round(OX + (D.Paths[I].Points[K].X - MinX) * Scale);
      Y2 := Round(Height - OY - (D.Paths[I].Points[K].Y - MinY) * Scale);
      Canvas.Line(X1, Y1, X2, Y2);
    end;
  end;
  Canvas.TextOut(12, Height - 22, Format('Camada %d | Z %.3f mm | Altura %.3f mm', [Layer + 1, D.Z, D.Height]));
end;
end.
