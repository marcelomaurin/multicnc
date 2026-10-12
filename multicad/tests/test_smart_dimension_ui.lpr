program test_smart_dimension_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Classes,Forms,Controls,Graphics,SysUtils,Math,StdCtrls,ExtCtrls,LCLType,multisuite_controls,
  multicad_main,multicad_document,multicad_types,multicad_sketch,multicad_refgeom,
  multicad_sketchtools,multicad_view3d,multicad_camera;
type TViewAccess=class(TCadView3D)
  procedure DownAt(X,Y:Integer);procedure MoveAt(X,Y:Integer);
end;
procedure TViewAccess.DownAt(X,Y:Integer);begin MouseDown(mbLeft,[],X,Y);MouseUp(mbLeft,[],X,Y);end;
procedure TViewAccess.MoveAt(X,Y:Integer);begin MouseMove([],X,Y);end;
type TAnswer=class
  Value:string;
  function Ask(Sender:TObject;const Caption:string;var Text:string;var RefOnly:Boolean):Boolean;
  procedure Error(Sender:TObject;E:Exception);
  procedure UnexpectedModal(Sender:TObject);
end;
function TAnswer.Ask(Sender:TObject;const Caption:string;var Text:string;var RefOnly:Boolean):Boolean;
begin Result:=Value<>'';Text:=Value;RefOnly:=False;end;
procedure TAnswer.Error(Sender:TObject;E:Exception);
begin WriteLn('FAIL: UI exception ',E.Message);Halt(1);end;
procedure TAnswer.UnexpectedModal(Sender:TObject);
begin WriteLn('FAIL: unexpected modal dialog while selecting/placing dimension');Halt(1);end;
var Main:TMainForm;D:TCadDocument;S,Source:TCadSketch;Plane:TCadPlane;View:TViewAccess;Fr:TCadFrame;
  Answer:TAnswer;T:TCadSketchSession;C:TSketchConstraint;Item:TCadPickItem;
  FileName,Err:string;SourceId,SourceEntity,ActiveId,PointId,Idx:Integer;Key:Word;
  LineGroup:TRadioGroup;Summary,HintLabel:TLabel;
procedure Check(OK:Boolean;const Msg:string);begin if not OK then raise Exception.Create(Msg);end;
procedure Pump;
begin
  { The viewport presents overlays on its frame timer. Allow a complete
    frame before another synthetic mouse event uses its hit rectangles. }
  Application.ProcessMessages;Sleep(25);Main.View3D.Repaint;Application.ProcessMessages;
end;
function ScreenPoint(X,Y:Double):TCadScreenPt;
begin Result:=View.Camera.Project(FrameToWorld(Fr,V2(X,Y)));end;
procedure Click(X,Y:Double);var P:TCadScreenPt;
begin P:=ScreenPoint(X,Y);View.DownAt(Round(P.X),Round(P.Y));Pump;end;
procedure Move(X,Y:Double);var P:TCadScreenPt;
begin P:=ScreenPoint(X,Y);View.MoveAt(Round(P.X),Round(P.Y));Pump;end;
function Current:TSketchConstraint;
begin Idx:=S.ConstraintIndex(T.PlacingDim);Check(Idx>=0,'Preview exists');Result:=S.Constraint(Idx);end;
procedure Shot(const Name:string);
var B:TBitmap;PNG:TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;ForceDirectories(ParamStr(1));Pump;B:=Main.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+Name+'.png');finally PNG.Free;B.Free;end;
end;
function Button(const Caption:string):TSuiteButton;
var I:Integer;C:TControl;
begin
  Result:=nil;
  for I:=0 to Main.CommandRibbon.ControlCount-1 do begin
    C:=Main.CommandRibbon.Controls[I];
    if C.Visible and (C is TSuiteButton) and (TSuiteButton(C).Caption=Caption) then Exit(TSuiteButton(C));
  end;
  raise Exception.Create('Missing tool button: '+Caption);
end;
procedure Choose(const Caption:string);
begin Button(Caption).Click;Pump;end;
begin
  Main:=nil;D:=nil;Answer:=TAnswer.Create;
  FileName:=GetTempFileName(GetTempDir,'dim');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      Application.Initialize;Application.OnException:=@Answer.Error;
      Application.OnModalBegin:=@Answer.UnexpectedModal;D:=TCadDocument.Create;
      Source:=D.AddSketch('plane:1');SourceEntity:=Source.AddLine(10,10,40,50);Source.AddCircle(70,30,5);SourceId:=Source.Id;
      Plane:=D.AddPlane(ptOffset,['plane:1'],20);S:=D.AddSketch('plane:'+IntToStr(Plane.Id));ActiveId:=S.Id;
      S.AddLine(-30,-10,0,30);PointId:=S.AddPoint(60,10);
      D.AddSketch('plane:1').AddPoint(100,100);
      Check(D.SaveToFile(FileName,Err),'Save seed');Application.CreateForm(TMainForm,Main);Main.SetBounds(-2400,20,1360,860);Main.Show;
      Check(Main.OpenFile(FileName),'Open part');Main.EditSketchById(ActiveId);S:=Main.SketchEditor.Sketch;
      T:=Main.SketchEditor.Session;T.OnAskDim:=@Answer.Ask;View:=TViewAccess(Main.View3D);View.SetView(svFront);
      Check(Main.Rebuilder.SketchFrame(S,Fr,Err),'Sketch frame');
      LineGroup:=TRadioGroup(Main.FindComponent('SketchLineKind'));
      Summary:=TLabel(Main.FindComponent('SketchToolSummary'));HintLabel:=TLabel(Main.FindComponent('SketchToolHint'));
      Check(Assigned(LineGroup) and Assigned(Summary) and Assigned(HintLabel),'Sketch panel controls exist');
      Check(LineGroup.Visible and (Pos('Linha',Summary.Caption)=1),'Initial line tool shows line settings');
      Choose('Cota inteligente');
      Check((T.Tool=tkDimension) and not LineGroup.Visible and (Pos('Cota inteligente',Summary.Caption)=1),'Changing tool replaces line properties with dimension context');
      Check((Pos('comprimento real',HintLabel.Caption)>0) and (Button('Cota inteligente').Style=sbsSolid),'Dimension hints and active command agree');
      Key:=VK_ESCAPE;Main.OnKeyDown(Main,Key,[]);Pump;
      Check((T.Tool=tkSelect) and not LineGroup.Visible and (Pos('Selecionar',Summary.Caption)=1),'Escape updates selection panel');
      Check((Button('Selecionar').Style=sbsSolid) and (Button('Cota inteligente').Style=sbsSoft),'Escape updates ribbon without rebuilding it');
      Click(-21,2);Check(LineGroup.Visible,'Selection still exposes geometry properties');
      Choose('Aparar (Trim)');Check(not LineGroup.Visible and (T.Tool=tkTrim) and
        (Pos('Aparar',Summary.Caption)=1),'Trim replaces fillet and hides line settings');
      Choose('Chanfro');Check(not LineGroup.Visible and (Pos('Chanfro',Summary.Caption)=1),'Chamfer hides line settings');
      Choose('Círculo');Check(LineGroup.Visible and (LineGroup.Caption='Tipo de geometria'),'Circle uses geometry settings');
      Choose('Linha');Check(LineGroup.Visible and (LineGroup.Caption='Tipo de linha'),'Return to line restores line settings');
      Choose('Cota inteligente');
      Check((HintLabel.Top=66) and (HintLabel.Height=110),Format('Dimension hint fits available panel: top=%d height=%d width=%d',[HintLabel.Top,HintLabel.Height,HintLabel.Width]));
      Shot('09-painel-cota');
      Main.SketchEditor.SetTool(tkDimension);Pump;
      Click(-15,10);Move(-15,45);C:=Current;Check(C.Kind=ckHorizontalDistance,'Real mouse above line infers X');Shot('07-cota-horizontal');
      Move(15,10);C:=Current;Check(C.Kind=ckVerticalDistance,'Real mouse beside line infers Y');
      Move(15,45);C:=Current;Check((C.Kind=ckDistance) and (Abs(C.Value-50)<1E-6),'Real mouse diagonally measures true length');Click(15,45);
      Click(10,10);Click(60,10);Move(35,-20);C:=Current;Check(C.Kind=ckHorizontalDistance,'Background endpoint creates horizontal dimension');
      Answer.Value:='55';Click(35,-20);Check(Abs(S.Entity(S.EntityIndex(PointId)).P1.X-65)<1E-6,'UI entered dimension drives active point');
      Source:=TCadSketch(Main.Document.FindById(SourceId));Check(Abs(Source.Entity(0).P1.X-10)<1E-6,'Source remains unchanged');
      Check(S.Entity(S.EntityCount-1).SourceRef=SketchPointRef(SourceId,SourceEntity,1),'UI preserves source identity');Shot('08-cota-outro-esboco');
      Check(not T.Hit(V2(100,100),Item),'Later sketch cannot create circular dependency');
      Main.View3D.SetHidden(SourceId,True);Main.SketchEditor.SetTool(tkDimension);Check(not T.Hit(V2(40,50),Item),'Hidden source is not selectable');
      Main.View3D.SetHidden(SourceId,False);Main.SketchEditor.SetTool(tkDimension);Check(T.Hit(V2(40,50),Item) and (Item.Ent<-1),'Visible earlier sketch can be selected');
      Main.ExitSketchMode;Check(Main.Document.SaveToFile(FileName,Err),'Save dimensioned part');
      Check(Main.OpenFile(FileName),'Reopen dimensioned part');S:=TCadSketch(Main.Document.FindById(ActiveId));
      Check((S.ConstraintCount=2) and (S.Entity(S.EntityCount-1).SourceRef<>''),'Dimension and associative source survive reopen');
      WriteLn('PASS: tool panel/ribbon synchronization, Escape, real viewport X/Y/aligned clicks, projected earlier sketch, driving value, hidden/later exclusions and reopen');
    finally Application.OnException:=nil;Application.OnModalBegin:=nil;Main.Free;D.Free;Answer.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
