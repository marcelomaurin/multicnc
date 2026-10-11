program test_plane_cancel_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Classes,Forms,Menus,SysUtils,
  multicad_main,multicad_document,multicad_types,multicad_sketch,multicad_extrude,
  multicad_refgeom;
var Main:TMainForm;D:TCadDocument;S:TCadSketch;X:TCadExtrude;P,Q:TCadPlane;
  FileName,Err,Ref:string;PlaneId:Integer;Fr:TCadFrame;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
function FindItem(M:TMenuItem;const Caption:string):TMenuItem;
var I:Integer;
begin
  if M.Caption=Caption then Exit(M);Result:=nil;
  for I:=0 to M.Count-1 do begin Result:=FindItem(M.Items[I],Caption);if Result<>nil then Exit;end;
end;
begin
  Main:=nil;D:=nil;
  FileName:=GetTempFileName(GetTempDir,'pln');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      Application.Initialize;D:=TCadDocument.Create;
      S:=D.AddSketch('plane:2');S.AddRectangle(0,0,20,50);X:=D.AddExtrude(S.Id,10);
      P:=D.AddPlane(ptCoincident,['face:'+X.Name+'/fim']);PlaneId:=P.Id;
      Q:=D.AddPlane(ptOffset,['plane:'+IntToStr(P.Id)],3);
      Check(D.SaveToFile(FileName,Err),'Save part');
      Application.CreateForm(TMainForm,Main);Main.SetBounds(-2400,20,1360,860);Main.Show;
      Check(Main.OpenFile(FileName),'Open test part');Ref:='plane:'+IntToStr(PlaneId);
      P:=TCadPlane(Main.Document.FindById(PlaneId));
      Main.EditFeatureById(PlaneId);Main.CancelEdit;Application.ProcessMessages;
      Check(P.FrameValid,'Cancel unchanged plane must restore its valid frame');
      Check(TCadPlane(Main.Document.FindById(Q.Id)).FrameValid,'Dependent offset plane remains valid');
      Check(Main.Rebuilder.ResolvePlane(Ref,Fr,Err),'Plane resolves after Cancel: '+Err);
      Main.EditFeatureById(PlaneId);P.PlaneType:=ptOffset;P.Distance:=25;
      Main.CancelEdit;Application.ProcessMessages;
      Check((P.PlaneType=ptCoincident) and P.FrameValid,'Cancel changed plane restores original type and frame');
      Main.View3D.Selected.Clear;Main.View3D.Selected.Add(Ref);
      Check(FindItem(Main.Menu.Items,'Esboço')<>nil,'Sketch menu exists');
      FindItem(Main.Menu.Items,'Esboço').Click;Application.ProcessMessages;
      Check(Main.SketchEditor<>nil,'Can start sketch on cancelled plane');
      Check(Main.SketchEditor.Sketch.PlaneRef=Ref,'Sketch uses the selected plane');
      Main.ExitSketchMode;Main.View3D.Repaint;
      Main.Document.Modified:=False;Check(Main.OpenFile(FileName),'Reopen saved part');
      Check(Main.Rebuilder.ResolvePlane(Ref,Fr,Err),'Saved plane rebuilds normally');
      WriteLn('PASS: Cancel unchanged/changed plane, dependent reference, new sketch and reopen');
    finally Main.Free;D.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
