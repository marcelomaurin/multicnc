program test_simucnc_view;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Graphics, SysUtils, aimarlinsimulator, multicnc_print3d_view;
type TRenderView=class(TPrint3DView)
  procedure Render(Bitmap:TBitmap);
end;
procedure TRenderView.Render(Bitmap:TBitmap);
begin RenderScene(Bitmap.Canvas);end;
var F:TForm; V:TRenderView; M:TAIMarlinSimulator; B:TBitmap; I:Integer;
procedure Save(const Name:string);
begin
  B.SetSize(V.Width,V.Height); V.Render(B); B.SaveToFile(Name);
end;
begin
  Application.Initialize;
  F:=TForm.CreateNew(nil);B:=TBitmap.Create;
  try
    F.SetBounds(0,0,850,600);V:=TRenderView.Create(F);V.Parent:=F;V.SetBounds(0,0,850,600);
    F.HandleNeeded;V.HandleNeeded;
    M:=TAIMarlinSimulator.Create(F);M.OnMotion:=@V.AddMotion;
    Save('tests/lib/view_empty.bmp');
    M.Receive('G1 X100 Y100 Z10 F600'+#10);
    M.Advance(1);
    if (V.CurrentPosition.X<=0) or (V.CurrentPosition.X>=100) then raise Exception.Create('No intermediate movement');
    Save('tests/lib/view_moving.bmp');
    if V.SegmentCount<>0 then raise Exception.Create('Travel deposited material');
    for I:=1 to 20 do M.Advance(1);
    if Abs(V.CurrentPosition.X-100)>0.01 then raise Exception.Create('Wrong final nozzle position');
    M.Receive('M104 S200'+#10);
    for I:=1 to 120 do M.Advance(1);
    M.Receive('G90'+#10+'G1 X60 Y60 Z0.2 F6000'+#10);M.Advance(2);
    for I:=1 to 15 do begin
      M.Receive(Format('G1 X160 Y60 E%d F3000',[I*4-3])+#10+
        Format('G1 X160 Y160 E%d',[I*4-2])+#10+
        Format('G1 X60 Y160 E%d',[I*4-1])+#10+
        Format('G1 X60 Y60 E%d',[I*4])+#10+
        'G91'+#10+'G1 Z1'+#10+'G90'+#10);
      M.Advance(10);
    end;
    if V.SegmentCount=0 then raise Exception.Create('Extrusion invisible');
    Save('tests/lib/view_print.bmp');
    V.TopView;Save('tests/lib/view_top.bmp');
    V.ResetView;V.ShowFrame:=True;Save('tests/lib/view_frame.bmp');
    V.ClearPrint;
    if V.SegmentCount<>0 then raise Exception.Create('Clear failed');
    Writeln('PASS: intermediate movement, final nozzle position and five rendered views');
  finally B.Free;F.Free;end;
end.
