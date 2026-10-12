program test_sketch_visibility_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Classes,Forms,Controls,Graphics,SysUtils,Math,ExtCtrls,
  LMessages,LCLType,multicad_main,multicad_document,multicad_types,multicad_sketch,
  multicad_extrude,multicad_camera,multicad_view3d,multisuite_controls,multicad_sketchtools;
var Main:TMainForm;D:TCadDocument;S:TCadSketch;Cut:TCadExtrude;
  FileName,Err,Ref:string;CutId,ProfileId,Failed:Integer;Fr:TCadFrame;P:TCadScreenPt;C:TControl;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then begin Inc(Failed);WriteLn('FAIL: ',Msg);end;end;
procedure Pump;
begin
  Main.View3D.Redraw;Application.ProcessMessages;Sleep(25);
  Main.View3D.Repaint;Application.ProcessMessages;
end;
function PickProfile(Id:Integer;const Point:TCadVec2):string;
var Sketch:TCadSketch;
begin
  Sketch:=TCadSketch(Main.Document.FindById(Id));
  if not Main.Rebuilder.SketchFrame(Sketch,Fr,Err) then raise Exception.Create(Err);
  P:=Main.View3D.Camera.Project(FrameToWorld(Fr,Point));Pump;
  Result:=Main.View3D.RefAt(Round(P.X),Round(P.Y));
end;
procedure CheckSupportHidden(Id:Integer;const Context:string);
var X:Integer;Hidden:Boolean;
begin
  Hidden:=True;
  for X:=3 to 17 do
    if (PickProfile(Id,V2(X,35))='sketch:'+IntToStr(Id)) or
       (PickProfile(Id,V2(X,39))='sketch:'+IntToStr(Id)) then Hidden:=False;
  Check(Hidden,'Construction and center lines are invisible and unpickable: '+Context);
end;
function OverlayHasSupport(Id:Integer):Boolean;
var B:TBitmap;A,Z:TCadScreenPt;X,Y:Integer;
begin
  Result:=False;
  if not Assigned(Main.View3D.OnOverlay) then Exit;
  if not Main.Rebuilder.SketchFrame(TCadSketch(Main.Document.FindById(Id)),Fr,Err) then
    raise Exception.Create(Err);
  A:=Main.View3D.Camera.Project(FrameToWorld(Fr,V2(4,35)));
  Z:=Main.View3D.Camera.Project(FrameToWorld(Fr,V2(16,35)));
  B:=TBitmap.Create;
  try
    B.SetSize(Main.View3D.ClientWidth,Main.View3D.ClientHeight);
    B.Canvas.Brush.Color:=clWhite;B.Canvas.FillRect(0,0,B.Width,B.Height);
    Main.View3D.OnOverlay(Main.View3D,B.Canvas);
    for X:=Max(0,Floor(Min(A.X,Z.X))) to Min(B.Width-1,Ceil(Max(A.X,Z.X))) do
      for Y:=Max(0,Round(A.Y)-2) to Min(B.Height-1,Round(A.Y)+2) do
        if ColorToRGB(B.Canvas.Pixels[X,Y])<>ColorToRGB(clWhite) then Exit(True);
  finally B.Free;end;
end;
function Find(C:TWinControl;const Caption:string):TControl;
var I:Integer;Q:TControl;
begin
  Result:=nil;
  for I:=0 to C.ControlCount-1 do
  begin
    Q:=C.Controls[I];
    if (Q is TSuiteButton) and Q.Visible and (TSuiteButton(Q).Caption=Caption) then Exit(Q);
    if Q is TWinControl then begin Result:=Find(TWinControl(Q),Caption);if Result<>nil then Exit;end;
  end;
end;
procedure RealClick(const Caption:string);
var Button:TControl;XY:PtrInt;
begin
  Button:=Find(Main,Caption);if Button=nil then raise Exception.Create('Missing command '+Caption);
  XY:=(Button.Height div 2) shl 16 or (Button.Width div 2);
  Button.Perform(LM_LBUTTONDOWN,MK_LBUTTON,XY);
  Button.Perform(LM_LBUTTONUP,0,XY);
  Pump;
end;
procedure Shot(const Name:string);
var B:TBitmap;PNG:TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;ForceDirectories(ParamStr(1));Pump;
  B:=Main.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+Name+'.png');
  finally PNG.Free;B.Free;end;
end;
procedure TestSupportSketch;
var Support,Other:TCadSketch;Group:TRadioGroup;Hit:TCadPickItem;
begin
  Support:=Main.Document.AddSketch('plane:2');Support.AddRectangle(2,28,18,44);
  Main.EditSketchById(Support.Id);RealClick('Linha');
  Check(Find(Main,'Linha de apoio')=nil,'No duplicate construction command on the ribbon');
  Group:=TRadioGroup(Main.FindComponent('SketchLineKind'));
  Check((Group<>nil) and Group.Visible,'Line component exposes normal/construction choice');
  Group.ItemIndex:=1;Group.OnClick(Group);
  Check(Main.SketchEditor.Session.ConstructionMode,'Line component enables construction drawing');
  Main.SketchEditor.Session.Click(V2(2,35));Main.SketchEditor.Session.Click(V2(18,35));
  Main.SketchEditor.Session.Cancel;
  Check(Support.Entity(Support.EntityCount-1).Construction,'Line drawn through component is construction');
  Support.AddCenterline(2,39,18,39);Main.SketchEditor.View3DChanged;Pump;
  Check(OverlayHasSupport(Support.Id),'Construction line is drawn in its active sketch');
  Main.ExitSketchMode;Main.View3D.SetView(svTop);Pump;
  Check(PickProfile(Support.Id,V2(2,31))='sketch:'+IntToStr(Support.Id),'Normal contour remains visible after exit');
  CheckSupportHidden(Support.Id,'finished selected sketch');
  Main.View3D.Selected.Clear;Pump;CheckSupportHidden(Support.Id,'unselected sketch');
  Main.EditSketchById(Support.Id);Pump;
  Check(OverlayHasSupport(Support.Id),'Reentering sketch restores construction line');
  Main.ExitSketchMode;
  Other:=Main.Document.AddSketch('plane:2');Other.AddRectangle(0,0,22,46);
  Main.EditSketchById(Other.Id);
  Main.SketchEditor.SetTool(tkDimension);Pump;
  Check(not OverlayHasSupport(Support.Id),'Construction from another sketch is not drawn as background');
  Check(not Main.SketchEditor.Session.Hit(V2(10,35),Hit),'Construction midpoint is not offered as external reference');
  Check(not Main.SketchEditor.Session.Hit(V2(10,39),Hit),'Centerline midpoint is not offered as external reference');
  Main.ExitSketchMode;
end;
begin
  Main:=nil;D:=nil;Failed:=0;
  FileName:=GetTempFileName(GetTempDir,'vis');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      Application.Initialize;D:=TCadDocument.Create;
      S:=D.AddSketch('plane:2');S.AddRectangle(0,0,20,50);D.AddExtrude(S.Id,10);
      S:=D.AddSketch('plane:2');S.AddCircle(5,20,3);ProfileId:=S.Id;
      S.AddLine(2,35,18,35,True);S.AddCenterline(2,39,18,39);
      Cut:=D.AddExtrude(S.Id,5,True);Cut.Dir1.Reverse:=True;CutId:=Cut.Id;
      if not D.SaveToFile(FileName,Err) then raise Exception.Create(Err);
      Application.CreateForm(TMainForm,Main);Main.Position:=poDesigned;Main.SetBounds(-2400,20,1360,860);Main.Show;
      if not Main.OpenFile(FileName) then raise Exception.Create('Open test part');
      Main.View3D.SetView(svTop);Pump;
      Check(Main.Rebuilder.BodyCount=1,'Part has one solid');
      Ref:=PickProfile(ProfileId,V2(8,20));
      Check(Ref<>'sketch:'+IntToStr(ProfileId),'Consumed sketch is normally hidden');
      Main.EditFeatureById(CutId);Pump;
      Ref:=PickProfile(ProfileId,V2(8,20));
      Check(Ref='sketch:'+IntToStr(ProfileId),'Operation profile must remain visible through the solid: '+Ref);
      CheckSupportHidden(ProfileId,'operation preview after file reload');
      Shot('05-perfil-na-previa');Main.CancelEdit;Pump;
      Check(PickProfile(ProfileId,V2(8,20))<>'sketch:'+IntToStr(ProfileId),'Cancel clears temporary profile display');
      Main.View3D.SetHidden(ProfileId,True);Main.EditFeatureById(CutId);Pump;
      Check(PickProfile(ProfileId,V2(8,20))='sketch:'+IntToStr(ProfileId),'Editing temporarily shows a manually hidden profile');
      CheckSupportHidden(ProfileId,'manually hidden operation profile');
      Main.CancelEdit;Check(Main.View3D.IsHidden(ProfileId),'Cancel preserves manual visibility');
      Main.EditFeatureById(CutId);RealClick('OK');
      Check(Main.View3D.OperationSketchId=0,'OK clears temporary profile display');
      Check(Main.View3D.IsHidden(ProfileId),'OK preserves manual visibility');
      Main.EditFeatureById(6);Pump;
      Check(PickProfile(5,V2(0,25))='sketch:5','Boss extrusion also shows its source profile');
      Main.CancelEdit;
      S:=Main.Document.AddSketch('plane:2');S.AddCircle(14,20,2);
      Main.EditSketchById(S.Id);Main.ExitSketchMode;Main.View3D.SetView(svTop);Pump;
      Check(PickProfile(S.Id,V2(16,20))='sketch:'+IntToStr(S.Id),'Finished selected sketch must be visible through existing body');
      Shot('06-esboco-selecionado');
      Main.EditSketchById(S.Id);RealClick('Selecionar');
      C:=Find(Main,'Operações');TSuiteButton(C).Click;Pump;
      RealClick('Corte extrudado');
      Check(Main.ExtrudeEditor<>nil,'Native mouse cut directly from active sketch opens editor');
      Check(TCadExtrude(Main.Document.Feature(Main.Document.Count-1)).SketchId=S.Id,'Native click keeps correct sketch');
      Main.CancelEdit;
      C:=Find(Main,'Esboço');TSuiteButton(C).Click;Pump;
      Main.EditSketchById(S.Id);RealClick('Sair do esboço');
      Check(Main.SketchEditor=nil,'Native mouse exit sketch completes without destroyed button');
      TestSupportSketch;
    finally Main.Free;D.Free;DeleteFile(FileName);end;
  except on E:Exception do begin Inc(Failed);WriteLn('FAIL: ',E.ClassName,': ',E.Message);end;end;
  if Failed>0 then Halt(1);
  WriteLn('PASS: operation profile, hidden-profile restoration, selected sketch through solid, native mouse command lifetime and construction limited to active sketch');
end.
