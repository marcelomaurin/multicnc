unit multicad_extrudeedit;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils,Math,Types,Controls,Graphics,multicad_types,multicad_units,
  multicad_extrude,multicad_rebuild,multicad_camera,multicad_view3d,
  multicad_propman,multicad_depthdrag,multisuite_controls;
type
  TCadExtrudeEditor=class
  private
    FView:TCadView3D;
    FRB:TCadRebuilder;
    FPM:TCadPropManager;
    FX:TCadExtrude;
    FDragging:Boolean;
    FDirection,FHover:Integer;
    FStartDepth,FStartMouse:Double;
    FStartExpr:string;
    FHandle:TCadDepthHandle;
    FCamera:TCadCamera;
    function Depth(Direction:Integer):Double;
    function Hit(X,Y:Integer):Integer;
    procedure Draw(Sender:TObject;C:TCanvas);
    procedure Down(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer;var Handled:Boolean);
    procedure Move(Sender:TObject;Shift:TShiftState;X,Y:Integer;var Handled:Boolean);
    procedure Up(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer;var Handled:Boolean);
  public
    constructor Create(View:TCadView3D;RB:TCadRebuilder;PM:TCadPropManager;Feature:TCadExtrude);
    destructor Destroy;override;
    function ScreenHandle(Direction:Integer;out H:TCadDepthHandle):Boolean;
    function CancelDrag:Boolean;
    property Dragging:Boolean read FDragging;
  end;
implementation
uses multicad_log;
constructor TCadExtrudeEditor.Create(View:TCadView3D;RB:TCadRebuilder;PM:TCadPropManager;Feature:TCadExtrude);
begin
  inherited Create;FView:=View;FRB:=RB;FPM:=PM;FX:=Feature;FCamera:=TCadCamera.Create;
  FView.OnOverlay:=@Draw;FView.OnViewMouseDown:=@Down;FView.OnViewMouseMove:=@Move;FView.OnViewMouseUp:=@Up;
  FView.Redraw;
end;
destructor TCadExtrudeEditor.Destroy;
begin
  if GetCaptureControl=FView then SetCaptureControl(nil);FView.Cursor:=crDefault;
  FView.OnOverlay:=nil;FView.OnViewMouseDown:=nil;FView.OnViewMouseMove:=nil;FView.OnViewMouseUp:=nil;
  FCamera.Free;FView.Redraw;inherited Destroy;
end;
function TCadExtrudeEditor.Depth(Direction:Integer):Double;
begin if Direction=1 then Result:=FX.Dir1.Depth else Result:=FX.Dir2.Depth;end;
function TCadExtrudeEditor.ScreenHandle(Direction:Integer;out H:TCadDepthHandle):Boolean;
var A,D:TCadVec3;Factor:Double;
begin
  Result:=FRB.ExtrudeHandle(FX,Direction,A,D,Factor);
  if Result then Result:=CadDepthHandle(FView.Camera,A,D,Factor,Depth(Direction),Direction,H);
end;
function TCadExtrudeEditor.Hit(X,Y:Integer):Integer;
var I:Integer;H:TCadDepthHandle;
begin
  Result:=0;
  for I:=1 to 2 do if ScreenHandle(I,H) and
    (Sqr(X-H.Tip.X)+Sqr(Y-H.Tip.Y)<=Sqr(12)) then Exit(I);
end;
procedure TCadExtrudeEditor.Draw(Sender:TObject;C:TCanvas);
var I,PX,PY:Integer;H:TCadDepthHandle;DX,DY:Double;S:string;R:TRect;
begin
  for I:=1 to 2 do if ScreenHandle(I,H) then
  begin
    C.Pen.Color:=clSuitePrimary;C.Pen.Width:=2;
    if H.Fallback then C.Pen.Style:=psDash else C.Pen.Style:=psSolid;
    C.Line(Round(H.Base.X),Round(H.Base.Y),Round(H.Tip.X),Round(H.Tip.Y));C.Pen.Style:=psSolid;
    PX:=Round(H.Tip.X);PY:=Round(H.Tip.Y);DX:=H.ScreenDir.X;DY:=H.ScreenDir.Y;
    C.Brush.Color:=clSuitePrimary;
    C.Polygon([Point(PX,PY),Point(Round(PX-DX*14-DY*6),Round(PY-DY*14+DX*6)),
      Point(Round(PX-DX*14+DY*6),Round(PY-DY*14-DX*6))]);
    C.Brush.Color:=clSuiteCard;
    if (FHover=I) or (FDragging and (FDirection=I)) then C.Brush.Color:=clSuitePrimary;
    C.Ellipse(PX-6,PY-6,PX+7,PY+7);
    S:=CadFmt(Depth(I),2)+' mm';if FX.UseDir2 then S:='D'+IntToStr(I)+': '+S;
    C.Font.Color:=clSuitePrimary;C.Font.Style:=[fsBold];C.Brush.Color:=clSuiteCard;
    R:=Rect(PX+12,PY-12,PX+20+C.TextWidth(S),PY+12);
    OffsetRect(R,Min(0,FView.ClientWidth-4-R.Right),0);
    C.FillRect(R);C.TextOut(R.Left+4,R.Top+3,S);
  end;
  C.Pen.Width:=1;C.Font.Style:=[];
end;
procedure TCadExtrudeEditor.Down(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer;var Handled:Boolean);
begin
  if FDragging and (Button=mbRight) then begin CancelDrag;Handled:=True;Exit;end;
  if Button<>mbLeft then Exit;
  FDirection:=Hit(X,Y);if FDirection=0 then Exit;
  if not ScreenHandle(FDirection,FHandle) then Exit;
  FCamera.Assign(FView.Camera);FStartDepth:=Depth(FDirection);
  if FDirection=1 then FStartExpr:=FX.Dir1.DepthExpr else FStartExpr:=FX.Dir2.DepthExpr;
  FStartMouse:=CadDepthAtMouse(FCamera,FHandle,X,Y);FDragging:=True;
  CadLog('DEPTH.DRAG.START',Format('id=%d direction=%d depth=%f',[FX.Id,FDirection,FStartDepth]));
  SetCaptureControl(FView);FView.Cursor:=crSizeAll;Handled:=True;
end;
procedure TCadExtrudeEditor.Move(Sender:TObject;Shift:TShiftState;X,Y:Integer;var Handled:Boolean);
var Value,Step:Double;
begin
  if not FDragging then
  begin
    FHover:=Hit(X,Y);if FHover>0 then FView.Cursor:=crSizeAll else FView.Cursor:=crDefault;
    Handled:=FHover>0;Exit;
  end;
  Value:=FStartDepth+CadDepthAtMouse(FCamera,FHandle,X,Y)-FStartMouse;
  Step:=0.1;if ssShift in Shift then Step:=0.01;
  Value:=EnsureRange(Value,0.01,1000000.0);Value:=Round(Value/Step)*Step;Value:=Max(0.01,Value);
  if Abs(Value-Depth(FDirection))>1E-7 then FPM.SetExtrudeDepth(FDirection,Value);
  Handled:=True;
end;
procedure TCadExtrudeEditor.Up(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer;var Handled:Boolean);
begin
  if not FDragging or (Button<>mbLeft) then Exit;
  Move(Sender,Shift,X,Y,Handled);FDragging:=False;if GetCaptureControl=FView then SetCaptureControl(nil);FView.Cursor:=crDefault;Handled:=True;
  CadLog('DEPTH.DRAG.END',Format('id=%d direction=%d depth=%f',[FX.Id,FDirection,Depth(FDirection)]));
end;
function TCadExtrudeEditor.CancelDrag:Boolean;
begin
  Result:=FDragging;if not Result then Exit;
  FDragging:=False;if GetCaptureControl=FView then SetCaptureControl(nil);FView.Cursor:=crDefault;
  FPM.SetExtrudeDepth(FDirection,FStartDepth,FStartExpr);
  CadLog('DEPTH.DRAG.CANCEL',Format('id=%d depth=%f',[FX.Id,FStartDepth]));
end;
end.
