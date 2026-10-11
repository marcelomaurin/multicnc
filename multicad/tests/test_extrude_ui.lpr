program test_extrude_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Classes,Forms,Controls,Graphics,StdCtrls,SysUtils,Math,Types,LCLType,
  multicad_main,multicad_document,multicad_types,multicad_sketch,multicad_extrude,
  multicad_view3d,multicad_depthdrag,multicad_camera,multisuite_controls;
type TViewAccess=class(TCadView3D)
  procedure Down(X,Y:Integer);
  procedure MoveTo(X,Y:Integer);
  procedure Up(X,Y:Integer);
end;
procedure TViewAccess.Down(X,Y:Integer);begin MouseDown(mbLeft,[],X,Y);end;
procedure TViewAccess.MoveTo(X,Y:Integer);begin MouseMove([ssLeft],X,Y);end;
procedure TViewAccess.Up(X,Y:Integer);begin MouseUp(mbLeft,[],X,Y);end;
var Main:TMainForm;D:TCadDocument;S:TCadSketch;Base,Cut:TCadExtrude;View:TViewAccess;
  H:TCadDepthHandle;P:TCadScreenPt;FileName,Err:string;CutId,BaseId,NewId,N:Integer;
  SavedDepth,Volume:Double;Key:Word;Edit:TEdit;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
function Find(C:TWinControl;const Name,Caption:string):TControl;
var I:Integer;Q:TControl;
begin
  Result:=nil;
  for I:=0 to C.ControlCount-1 do
  begin
    Q:=C.Controls[I];
    if ((Name<>'') and (Q.Name=Name)) or ((Q is TSuiteButton) and (TSuiteButton(Q).Caption=Caption)) then Exit(Q);
    if Q is TWinControl then begin Result:=Find(TWinControl(Q),Name,Caption);if Result<>nil then Exit;end;
  end;
end;
procedure Click(const Caption:string);
var C:TControl;
begin C:=Find(Main,'',Caption);Check(C<>nil,'Button missing: '+Caption);TSuiteButton(C).Click;Application.ProcessMessages;end;
procedure Pump;begin Main.Repaint;Application.ProcessMessages;end;
procedure StartDrag;
begin Check(Main.ExtrudeEditor.ScreenHandle(1,H),'Depth handle present');View.Down(Round(H.Tip.X),Round(H.Tip.Y));Check(Main.ExtrudeEditor.Dragging,'Mouse captures depth handle');end;
procedure MoveDepth(Value:Double;Finish:Boolean);
var X,Y:Integer;
begin
  if H.Fallback then P:=Default(TCadScreenPt)
  else P:=View.Camera.Project(VAdd(H.Anchor,VScale(H.Axis,Value*H.Factor)));
  if H.Fallback then begin P.X:=H.Base.X+H.ScreenDir.X*Value*H.PixelsPerMM;P.Y:=H.Base.Y+H.ScreenDir.Y*Value*H.PixelsPerMM;end;
  X:=Round(P.X+H.Offset.X);Y:=Round(P.Y+H.Offset.Y);View.MoveTo(X,Y);if Finish then View.Up(X,Y);Pump;
end;
procedure Shot(const Name:string);
var B:TBitmap;PNG:TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;ForceDirectories(ParamStr(1));Pump;
  B:=Main.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+Name+'.png');finally PNG.Free;B.Free;end;
end;
begin
  try
    Application.Initialize;Main:=nil;D:=TCadDocument.Create;
    FileName:=GetTempFileName(GetTempDir,'cad');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
    try
      D.NewPart;S:=D.AddSketch('plane:1');S.AddRectangle(-20,-15,20,15);Base:=D.AddExtrude(S.Id,20);BaseId:=Base.Id;
      S:=D.AddSketch('face:'+Base.Name+'/fim');S.AddCircle(0,0,3);Cut:=D.AddExtrude(S.Id,5,True);Cut.Dir1.DepthExpr:='10/2';CutId:=Cut.Id;
      Check(D.SaveToFile(FileName,Err),'Seed CAD saved: '+Err);
      Main:=TMainForm.Create(nil);Main.Position:=poDesigned;Main.SetBounds(-2400,20,1360,860);Main.Show;
      Check(Main.OpenFile(FileName),'Open test part');View:=TViewAccess(Main.View3D);Pump;
      Main.EditFeatureById(CutId);Pump;Check(Main.ExtrudeEditor<>nil,'Cut opens depth editor');
      Check(Main.Color=clSuiteSurface,'Theme remains unchanged');
      Cut:=TCadExtrude(Main.Document.FindById(CutId));Volume:=Main.Rebuilder.TotalVolume;
      Shot('01-corte-alca');StartDrag;MoveDepth(8,False);
      Check(Abs(Cut.Dir1.Depth-8)<0.2,'Dragging changes physical depth');
      Check(Main.Rebuilder.TotalVolume<Volume-70,'Preview cuts more material while dragging');
      Check(Cut.Dir1.DepthExpr='','Dragging clears previous expression');
      Edit:=TEdit(Find(Main,'ExtrudeDepth1',''));Check(Edit<>nil,'Depth field present');
      Check(Abs(StrToFloat(Edit.Text)-Cut.Dir1.Depth)<0.0001,'Numeric field follows drag');Shot('02-corte-arrastado');
      Key:=VK_ESCAPE;Main.OnKeyDown(Main,Key,[]);
      Check((Key=0) and (Main.ExtrudeEditor<>nil) and not Main.ExtrudeEditor.Dragging,'Escape cancels only active drag');
      Check((Abs(Cut.Dir1.Depth-5)<0.0001) and (Cut.Dir1.DepthExpr='10/2'),'Escape restores depth and expression');
      StartDrag;MoveDepth(8,True);SavedDepth:=Cut.Dir1.Depth;Click('OK');
      Check(Main.ExtrudeEditor=nil,'OK releases editor');Check(Main.Document.Modified,'OK marks document modified');
      Check(Main.Document.SaveToFile(FileName,Err),'Save accepted depth');Check(D.LoadFromFile(FileName,Err),'Reload accepted depth');
      Check(Abs(TCadExtrude(D.FindById(CutId)).Dir1.Depth-SavedDepth)<0.0001,'Accepted depth persists in mcad');
      Main.EditFeatureById(CutId);Pump;Edit:=TEdit(Find(Main,'ExtrudeDepth1',''));Edit.Text:='6';Pump;
      Check(Main.ExtrudeEditor.ScreenHandle(1,H),'Numeric entry keeps handle');Check(Abs(Cut.Dir1.Depth-6)<0.0001,'Numeric editing still works');
      View.SetView(svFront);Pump;StartDrag;Check(H.Fallback,'Normal view offers usable screen handle');MoveDepth(9,True);
      Check(Abs(Cut.Dir1.Depth-9)<0.2,'Normal-view drag changes depth');
      Main.CancelEdit;Check(Abs(Cut.Dir1.Depth-SavedDepth)<0.0001,'Cancel restores whole edit');
      Main.EditFeatureById(CutId);Cut.Dir1.EndCond:=ecThroughAll;Pump;
      Check(not Main.ExtrudeEditor.ScreenHandle(1,H),'Through-all has no manual depth handle');Main.CancelEdit;
      Main.EditFeatureById(BaseId);Pump;StartDrag;MoveDepth(24,True);
      Check(Abs(TCadExtrude(Main.Document.FindById(BaseId)).Dir1.Depth-24)<0.2,'Boss uses the same depth interaction');Main.CancelEdit;
      Base:=TCadExtrude(Main.Document.FindById(BaseId));S:=Main.Document.AddSketch('face:'+Base.Name+'/fim');S.AddCircle(10,0,2);
      View.Selected.Clear;View.Selected.Add('sketch:'+IntToStr(S.Id));N:=Main.Document.Count;Click('Corte extrudado');
      Check(Main.ExtrudeEditor<>nil,'New extruded cut opens handle');NewId:=Main.Document.Feature(Main.Document.Count-1).Id;
      Pump;StartDrag;MoveDepth(7,True);Click('Cancelar');
      Check((Main.Document.Count=N) and (Main.Document.FindById(NewId)=nil),'Cancel new operation deletes the preview feature');
      Check(Main.SketchEditor=nil,'No sketch editor left attached');
      WriteLn('PASS: real mouse drag, live cut volume, numeric sync, Escape/Cancel/OK, persistence, normal view, boss, through-all and new cut');
    finally Main.Free;D.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
