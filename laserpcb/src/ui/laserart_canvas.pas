unit laserart_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,laserart_document,laserart_types;
type TLaserArtCanvas=class(TCustomControl)
 private FDoc:TLaserArtDocument;FZoom:Double;FSelected:Integer;FDragging:Boolean;function Hit(X,Y:Integer):Integer;
 protected procedure Paint;override;procedure MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);override;procedure MouseMove(Shift:TShiftState;X,Y:Integer);override;procedure MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);override;
 public constructor Create(AOwner:TComponent);override;property Document:TLaserArtDocument read FDoc write FDoc;property Selected:Integer read FSelected;procedure ZoomIn;procedure ZoomOut;
 end;
implementation
constructor TLaserArtCanvas.Create(AOwner:TComponent);begin inherited;Color:=clWhite;FZoom:=2;FSelected:=-1;end;
function TLaserArtCanvas.Hit(X,Y:Integer):Integer;var I:Integer;A:TLaserArtItem;begin Result:=-1;if not Assigned(FDoc)then Exit;for I:=FDoc.Count-1 downto 0 do begin A:=FDoc.Item(I);if(X>=20+Round(A.X*FZoom))and(X<=20+Round((A.X+A.Width)*FZoom))and(Y>=20+Round(A.Y*FZoom))and(Y<=20+Round((A.Y+A.Height)*FZoom))then Exit(I);end;end;
procedure TLaserArtCanvas.MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin inherited;if Button=mbLeft then begin FSelected:=Hit(X,Y);FDragging:=FSelected>=0;Invalidate;end;end;
procedure TLaserArtCanvas.MouseMove(Shift:TShiftState;X,Y:Integer);var A:TLaserArtItem;begin inherited;if FDragging and(FSelected>=0)then begin A:=FDoc.Item(FSelected);A.X:=Max(0,(X-20)/FZoom-A.Width/2);A.Y:=Max(0,(Y-20)/FZoom-A.Height/2);Invalidate;end;end;
procedure TLaserArtCanvas.MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin inherited;FDragging:=False;end;
procedure TLaserArtCanvas.Paint;var I:Integer;A:TLaserArtItem;R:TRect;begin Canvas.Brush.Color:=clBtnFace;Canvas.FillRect(ClientRect);if not Assigned(FDoc)then Exit;Canvas.Brush.Color:=clWhite;Canvas.Pen.Color:=clBlack;Canvas.Rectangle(20,20,20+Round(FDoc.BedWidth*FZoom),20+Round(FDoc.BedHeight*FZoom));for I:=0 to FDoc.Count-1 do begin A:=FDoc.Item(I);if not A.Visible then Continue;R:=Rect(20+Round(A.X*FZoom),20+Round(A.Y*FZoom),20+Round((A.X+A.Width)*FZoom),20+Round((A.Y+A.Height)*FZoom));if I=FSelected then Canvas.Pen.Color:=clFuchsia else Canvas.Pen.Color:=clBlack;Canvas.Brush.Style:=bsClear;Canvas.Rectangle(R);case A.Kind of lakText:Canvas.TextOut(R.Left+3,R.Top+3,A.Text);lakImage:Canvas.TextOut(R.Left+3,R.Top+3,'IMG '+ExtractFileName(A.SourceFile));lakVector:Canvas.TextOut(R.Left+3,R.Top+3,'SVG');lakRectangle:Canvas.TextOut(R.Left+3,R.Top+3,'Retangulo');lakEllipse:Canvas.Ellipse(R);end;end;end;
procedure TLaserArtCanvas.ZoomIn;begin FZoom:=Min(10,FZoom*1.25);Invalidate;end;procedure TLaserArtCanvas.ZoomOut;begin FZoom:=Max(.25,FZoom/1.25);Invalidate;end;
end.
