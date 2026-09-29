unit multicam_signal_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multicam_signal_trace;
type TSignalCanvas=class(TCustomControl)
 private FTrace:TSignalTrace;
 protected procedure Paint;override;
 public property Trace:TSignalTrace read FTrace write FTrace;
 end;
implementation
procedure TSignalCanvas.Paint;var I,W,H,Y:Integer;S:TSignalSample;procedure DigitalLine(Base:Integer;Value:Boolean);var YY:Integer;begin if Value then YY:=Base-10 else YY:=Base;if I=0 then Canvas.MoveTo(0,YY)else Canvas.LineTo(I*W,YY);end;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if(FTrace=nil)or(FTrace.Count=0)then Exit;W:=Max(1,ClientWidth div Max(1,FTrace.Count-1));H:=Max(18,ClientHeight div 10);for I:=0 to FTrace.Count-1 do begin S:=FTrace.Sample(I);Y:=H;DigitalLine(Y,S.XStep);DigitalLine(Y+H,S.XDir);DigitalLine(Y+2*H,S.YStep);DigitalLine(Y+3*H,S.YDir);DigitalLine(Y+4*H,S.ZStep);DigitalLine(Y+5*H,S.ZDir);DigitalLine(Y+6*H,S.EnableX);DigitalLine(Y+7*H,S.EStop);end;Canvas.TextOut(4,2,'STEP/DIR X Y Z | ENABLE | ESTOP');end;
end.
