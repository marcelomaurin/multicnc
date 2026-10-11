program test_workflow;
{$mode objfpc}{$H+}
uses Interfaces,Forms,Controls,StdCtrls,ComCtrls,Classes,SysUtils,Graphics,Types,
  laserpcb_main,laserpcb_project,laserpcb_design,laserpcb_components,laserpcb_componentsform,
  laserpcb_types,laserpcb_roles,laserpcb_job,makepcb_model,makepcb_library,
  makepcb_editor,makepcb_render,makepcb_route,multisuite_controls;

type TEditorAccess=class(TMPEditor)
  procedure ClickAt(const P:TMPPoint);
  procedure MoveAt(const P:TMPPoint);
  procedure Finish;
end;
procedure TEditorAccess.ClickAt(const P:TMPPoint);
var Q:TPoint;
begin Q:=MPToScreen(Viewport,P.X,P.Y);MouseDown(mbLeft,[],Q.X,Q.Y);MouseUp(mbLeft,[],Q.X,Q.Y);end;
procedure TEditorAccess.MoveAt(const P:TMPPoint);
var Q:TPoint;
begin Q:=MPToScreen(Viewport,P.X,P.Y);MouseMove([],Q.X,Q.Y);end;
procedure TEditorAccess.Finish;
begin MouseDown(mbRight,[],0,0);end;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;

var Main:TLaserPCBForm;Doc,Loaded:TMPDocument;P:TLaserPCBProject;Lib:TMPLibrary;
  Errors:TStringList;R:TMPRouteResult;I,N:Integer;FileName,Before:string;Dialog:TLPComponentsForm;
  OpTop,OpBottom:TLPOperation;Job:TLaserPCBJob;Editor:TEditorAccess;

function Button(const Caption:string):TSuiteButton;
var K:Integer;
begin
  Result:=nil;
  for K:=0 to Main.ComponentCount-1 do
    if (Main.Components[K] is TSuiteButton) and (TSuiteButton(Main.Components[K]).Caption=Caption) then
      Exit(TSuiteButton(Main.Components[K]));
  raise Exception.Create('Button missing: '+Caption);
end;
procedure Click(const Caption:string);
begin Button(Caption).Click;Application.ProcessMessages;end;
procedure SetField(const Caption,Value:string);
var K,J:Integer;L:TLabel;E:TEdit;
begin
  for K:=0 to Main.ComponentCount-1 do if Main.Components[K] is TLabel then
  begin
    L:=TLabel(Main.Components[K]);if L.Caption<>Caption then Continue;
    for J:=0 to L.Parent.ControlCount-1 do if L.Parent.Controls[J] is TEdit then
    begin E:=TEdit(L.Parent.Controls[J]);if E.Top=L.Top+20 then begin E.Text:=Value;Exit;end;end;
  end;
  raise Exception.Create('Field missing: '+Caption);
end;
procedure Snapshot(const Name:string);
var B:TBitmap;PNG:TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;
  ForceDirectories(ParamStr(1));Main.Repaint;Application.ProcessMessages;
  B:=Main.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+Name+'.png');
  finally PNG.Free;B.Free;end;
end;
procedure BuildDesign(Top:Boolean);
begin
  Doc.Clear;P.CreateBoard(80,60,1,not Top);Doc.BoardW:=80;Doc.BoardH:=60;Doc.DoubleSided:=Top;
  Doc.AddComponent(Lib.Find('Resistor 0.4 pol'),20,20);
  Doc.AddComponent(Lib.Find('Resistor 0.4 pol'),50,20);
  Doc.AddWire(0,0,1,0);
end;
begin
  try
    Application.Initialize;Lib:=MakePCBLibrary;Doc:=TMPDocument.Create;Loaded:=TMPDocument.Create;
    P:=TLaserPCBProject.Create;Errors:=TStringList.Create;Main:=nil;Dialog:=nil;
    FileName:=GetTempFileName(GetTempDir,'pcb');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mpcb');
    try
      for I:=0 to 1 do
      begin
        BuildDesign(I=1);Errors.Clear;
        Check(not LPCheckPCBDesign(Doc,P,Errors),'Unrouted connection must fail DRC');Errors.Clear;
        R:=LPRoutePCBDesign(Doc,Lib,P,Errors);
        Check((R.Routed=1) and (R.Failed=0) and (Doc.TrackCount>0),'Single-face routing');
        for N:=0 to Doc.TrackCount-1 do
          Check((I=1)=(Doc.Track(N).Layer=mlTopCopper),'Tracks stay on the physical copper face');
        Check(Length(MPPendingConnections(Doc))=0,'Routing joins intended terminals');
        Errors.Clear;Check(LPCheckPCBDesign(Doc,P,Errors),'Routed DRC: '+Errors.Text);
        Doc.TrackWidth:=0.6;Doc.Clearance:=0.4;
        LPSavePCBDesign(FileName,P,Doc);
        LPOpenPCBDesign(FileName,Lib,P,Loaded);
        Check((P.CopperLayerCount=1) and ((I=1)=(P.Side=lsTop)),'Save/reopen preserves single Top/Bottom');
        Check((Loaded.TrackCount=Doc.TrackCount) and (Loaded.WireCount=1),'Save/reopen preserves tracks and nets');
      end;
      LPApplyComponents(Loaded,P);Before:=P.ComponentSetJSON;
      for I:=0 to 1 do
      begin
        Doc.Clear;P.CreateBoard(80,60,1,I=0);Doc.BoardW:=80;Doc.BoardH:=60;Doc.DoubleSided:=I=1;
        Doc.AddComponent(Lib.Find('0805'),20,20);Doc.AddComponent(Lib.Find('0805'),50,30);
        Doc.Component(0).Flipped:=I=0;Doc.Component(1).Flipped:=I=0;
        Doc.Component(0).Rotation:=90;Doc.Component(1).Rotation:=270;Doc.AddWire(0,1,1,0);
        Errors.Clear;R:=LPRoutePCBDesign(Doc,Lib,P,Errors);
        Check((R.Failed=0) and (Length(MPPendingConnections(Doc))=0),'Rotated SMD route on the physical face');
        Errors.Clear;Check(LPCheckPCBDesign(Doc,P,Errors),'SMD DRC: '+Errors.Text);
        Doc.Component(0).Flipped:=not Doc.Component(0).Flipped;Doc.Changed;Errors.Clear;
        Check(not LPCheckPCBDesign(Doc,P,Errors),'Single-face SMD on missing copper must fail');
      end;
      LPOpenPCBDesign(FileName,Lib,P,Loaded);LPApplyComponents(Loaded,P);
      Dialog:=TLPComponentsForm.CreateFor(nil,P);
      Check((Dialog.Document.TrackCount=Loaded.TrackCount) and (Dialog.Document.WireCount=1),'Component editor preserves full PCB');
      FreeAndNil(Dialog);

      Main:=TLaserPCBForm.Create(nil);Main.Position:=poDesigned;Main.SetBounds(-2400,20,1240,850);Main.Show;
      Application.ProcessMessages;Main.OpenFile(FileName);
      Check(Main.PCBEditor.Visible,'Editable project opens in tracks');
      SetField('Largura minima / nova trilha (mm)','0.5');SetField('Folga minima (mm)','0.3');
      Main.OpenFile(FileName);
      Check((Abs(Main.PCBDesign.TrackWidth-0.6)<0.0001) and (Abs(Main.PCBDesign.Clearance-0.4)<0.0001),
        'Reopening a PCB preserves its rules instead of the previous fields');
      Check(Main.Color=clSuiteSurface,'Main theme retained');
      Check(Main.PCBEditor.Renderer.NormalBackgroundColor=Main.Preview.Color,'Canvas background retained');
      Check(Main.PCBEditor.Renderer.NormalBoardColor=RGBToColor(224,238,231),'Board color retained');
      Click('1  Placa');Snapshot('01-placa');
      Click('2  Posicionar componentes');Check(Main.PCBEditor.Visible,'Components use central editor');Snapshot('02-componentes');
      Click('3  Trilhas');Snapshot('03-trilhas');
      Editor:=TEditorAccess(Main.PCBEditor);Editor.ZoomToBoard;
      Click('Ligar terminais');Editor.ClickAt(Main.PCBDesign.Component(0).PadPos(1));Editor.ClickAt(Main.PCBDesign.Component(1).PadPos(1));
      Check(Main.PCBDesign.WireCount=2,'Interactive terminal connections');N:=Main.PCBDesign.TrackCount;
      Click('Rotear automaticamente');
      Check((Main.PCBDesign.TrackCount>N) and (Length(MPPendingConnections(Main.PCBDesign))=0),'UI autorouter preserves existing tracks and joins new net');
      Click('Trilha');N:=Main.PCBDesign.TrackCount;
      Editor.ClickAt(MPPoint(20,40));Editor.MoveAt(MPPoint(30,40));Editor.ClickAt(MPPoint(30,40));
      Editor.Finish;
      Check(Main.PCBDesign.TrackCount=N+1,'Manual drawing creates a track');
      Check(Main.PCBDesign.Track(N).Layer=mlTopCopper,'Manual drawing uses selected face');
      Click('Desfazer');Check(Main.PCBDesign.TrackCount=N,'Undo manual track');
      Click('Refazer');Check(Main.PCBDesign.TrackCount=N+1,'Redo manual track');
      Click('Desfazer');
      Click('4  Camadas e laser');Check(not Main.PCBEditor.Visible,'Laser uses original preview');
      Check(Main.Project.ComponentSetJSON<>'','Tracks synchronized to laser model');
      Check(Main.Project.CopperMask.CountSet>0,'Generated design feeds copper CAM');
      Check(Button('Marcar centros a laser').Parent=Button('Atualizar trajetorias').Parent,'Hole setup is inside layers');
      SetField('Potencia calibrada (S)','250');SetField('Velocidade calibrada (mm/min)','600');
      Click('Atualizar trajetorias');Snapshot('04-camadas');
      Click('Validar');Check(not Main.PCBEditor.Visible,'Validation shows laser preview');
      for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TSuiteBadge then
        Check(TSuiteBadge(Main.Components[I]).Caption='Trabalho valido','Native circuit and laser validation: '+TSuiteBadge(Main.Components[I]).Caption);
      Snapshot('05-validar');
      N:=Main.PCBDesign.TrackCount;Click('2  Posicionar componentes');Click('3  Trilhas');
      Check(Main.PCBDesign.TrackCount=N,'Navigating back preserves tracks');
      SetField('Folga minima (mm)','invalido');Click('Verificar trilhas');
      Click('Novo trabalho');Check(not Main.PCBEditor.Visible,'New work exits the editor despite an unfinished field');
      Main.OpenFile(FileName);Check(Main.PCBEditor.Visible,'PCB can reopen after clearing');
      Before:=Main.PCBDesign.ToJSON;
      Main.OpenFile('laserpcb/tests/data/demo-F_Cu.gtl');Click('3  Trilhas');
      Check(not Main.PCBEditor.Visible,'Imported Gerber is not routed as an empty board');
      Check(Main.PCBDesign.ToJSON=Before,'Imported file leaves editable design intact');

      BuildDesign(False);P.CreateBoard(80,60,2);Doc.DoubleSided:=True;Errors.Clear;
      R:=LPRoutePCBDesign(Doc,Lib,P,Errors);Check(R.Failed=0,'Double-face route');LPApplyComponents(Doc,P);
      P.ClearOperations;OpTop:=P.AddOperation(cmIsolation,'Top',1);OpTop.CopperLayer:=1;
      OpBottom:=P.AddOperation(cmIsolation,'Bottom',2);OpBottom.CopperLayer:=2;
      OpTop.Power:=200;OpTop.Feed:=600;OpBottom.Power:=300;OpBottom.Feed:=700;
      P.Profile.SpotMM:=0.2;P.SelectCopperLayer(1);P.GenerateOperations;
      Check(OpTop.Generated and not OpBottom.Generated,'Generate only selected Top');
      Job:=P.BuildOperationsJob;try Check(Job.Count>0,'Top produces G-code paths');finally Job.Free;end;
      P.SelectCopperLayer(2);P.GenerateOperations;
      Check(OpBottom.Generated and not OpTop.Generated,'Generate only selected Bottom');
      Errors.Clear;Check(P.ValidateOperations(Errors,True),'Bottom CAM validation: '+Errors.Text);
      WriteLn('PASS: five stages, theme, manual drawing, undo/redo, single Top/Bottom and double routing, DRC, roundtrip, components, CAM and per-face operations');
    finally Main.Free;Dialog.Free;Errors.Free;P.Free;Loaded.Free;Doc.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
