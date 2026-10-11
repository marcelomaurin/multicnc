program test_components;
{$mode objfpc}{$H+}
uses Interfaces,Forms,Controls,StdCtrls,ExtCtrls,Spin,Classes,SysUtils,Graphics,
 makepcb_model,makepcb_library,makepcb_fpeditor,laserpcb_project,laserpcb_types,
 laserpcb_geom,laserpcb_components,laserpcb_componentsform,multisuite_controls;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
type TDriver=class
 Timer:TTimer;Opened:Boolean;
 procedure CancelEditor(Sender:TObject);
end;
procedure TDriver.CancelEditor(Sender:TObject);
var I:Integer;
begin Timer.Enabled:=False;for I:=0 to Screen.FormCount-1 do
 if Screen.Forms[I] is TMPFootprintEditor then begin Opened:=True;Screen.Forms[I].ModalResult:=mrCancel;Exit;end;end;
var P:TLaserPCBProject;Doc,Loaded:TMPDocument;Lib:TMPLibrary;FP:TMPFootprint;
 F:TLPComponentsForm;C:TMPComponent;D:TDriver;H,TopShapes,SourceN:Integer;S,Temp:string;Failed:Boolean;
 B:TBitmap;PNG:TPortableNetworkGraphic;
begin
 try
 Application.Initialize;Temp:=IncludeTrailingPathDelimiter(GetTempDir(False))+'laserpcb-components-'+IntToStr(GetProcessID)+PathDelim;ForceDirectories(Temp);
 P:=TLaserPCBProject.Create;Doc:=TMPDocument.Create;Loaded:=TMPDocument.Create;Lib:=TMPLibrary.Create;F:=nil;D:=TDriver.Create;D.Timer:=TTimer.Create(nil);
 try
  Check(Pos('makepcb',LowerCase(LPSharedLibraryFile))>0,'Shared MakePCB config path');
  FP:=TMPFootprint.Create;FP.Name:='Teste compartilhado';FP.RefPrefix:='U';FP.AddPad('1',0,0,psSquare,2,2,0.8);FP.AddRect(-2,-2,2,2);FP.SetBody(bkIC,-2,-2,2,2,0);Lib.AddUser(FP);
  Lib.SaveUserFile(Temp+'library.json');
  Check(LPImportComponentLibrary(MakePCBLibrary,Temp+'library.json')=1,'Import full library');
  P.CreateBoard(80,60,2);P.ImportFile('laserpcb/tests/data/demo-PTH.drl');H:=P.Drills.HoleCount;
  Doc.BoardW:=80;Doc.BoardH:=60;Doc.DoubleSided:=True;
  C:=Doc.AddComponent(MakePCBLibrary.Find('Resistor 0.4 pol'),20,20);C.Rotation:=90;
  C:=Doc.AddComponent(MakePCBLibrary.Find('0805'),40,30);C.Flipped:=True;
  C:=Doc.AddComponent(MakePCBLibrary.Find('Teste compartilhado'),60,45);
  Doc.AddTrack(mlTopCopper,1).AddPoint(0,0);
  LPLoadComponentSet(Loaded,MakePCBLibrary,Doc.ToJSON);
  Check((Loaded.ComponentCount=3)and(Loaded.TrackCount=0),'Import only component forms');
  LPApplyComponents(Loaded,P);Check(P.Drills.HoleCount=H+3,'Component drills added alongside imported holes');
  SourceN:=P.SourceCount;S:=P.ComponentSetJSON;
  P.RebuildMasks;Check(P.CopperMask<>nil,'CAM masks from components');P.Generate;Check(Length(P.Paths)>0,'Component pads generate CAM paths');
  TopShapes:=Length(P.ReferencePaths);Check(TopShapes>0,'Top pads present');
  P.SelectCopperLayer(2);Check(Length(P.ReferencePaths)>TopShapes,'Bottom SMD only on its face');
  LPApplyComponents(Loaded,P);Check((P.Drills.HoleCount=H+3)and(P.SourceCount=SourceN),'Repeated apply does not duplicate layers or holes');
  Loaded.Component(0).X:=-100;Failed:=False;
  try LPApplyComponents(Loaded,P);except on E:Exception do Failed:=True;end;
  Check(Failed and(P.ComponentSetJSON=S),'Invalid placement leaves project intact');
  Loaded.Component(0).X:=25;LPApplyComponents(Loaded,P);
  Loaded.SaveToFile(Temp+'set.mpcb');
  F:=TLPComponentsForm.CreateFor(nil,P,Temp+'empty-library.json');F.Position:=poDesigned;F.SetBounds(-2400,20,1180,820);F.Show;Application.ProcessMessages;
  Check(TEdit(F.FindComponent('ComponentSearch')).Text='','Search initially empty');
  Check(TSuiteButton(F.FindComponent('ApplyComponents')).BoundsRect.Right<=F.ClientWidth,'Apply button visible');
  Check(TSuiteButton(F.FindComponent('CancelComponents')).BoundsRect.Right<=F.ClientWidth,'Cancel button visible');
  F.LoadSet(Temp+'set.mpcb');Check(F.Document.ComponentCount=3,'UI opens component set');
  TListBox(F.FindComponent('PlacedComponents')).ItemIndex:=0;TListBox(F.FindComponent('PlacedComponents')).OnClick(nil);
  TFloatSpinEdit(F.FindComponent('ComponentX')).Value:=30;
  TComboBox(F.FindComponent('ComponentRotation')).ItemIndex:=2;TComboBox(F.FindComponent('ComponentRotation')).OnChange(nil);
  Check((F.Document.Component(0).X=30)and(F.Document.Component(0).Rotation=180),'UI position and rotation');
  D.Timer.Enabled:=False;D.Timer.Interval:=50;D.Timer.OnTimer:=@D.CancelEditor;D.Timer.Enabled:=True;
  TSuiteButton(F.FindComponent('NewSharedComponent')).Click;Check(D.Opened,'Existing MakePCB component creator opened from LaserPCB');
  F.Repaint;Application.ProcessMessages;
  ForceDirectories('dist');B:=F.GetFormImage;PNG:=TPortableNetworkGraphic.Create;try PNG.Assign(B);PNG.SaveToFile('dist/laserpcb-components-preview.png');finally PNG.Free;B.Free;end;
  TSuiteButton(F.FindComponent('ApplyComponents')).Click;Check((F.ModalResult=mrOK)and(P.ComponentSetJSON<>S),'UI applies component geometry');
  FreeAndNil(F);
  Loaded.Clear;LPApplyComponents(Loaded,P);Check(P.Drills.HoleCount=H,'Removing assembly preserves imported drills');
  P.CreateBoard(80,60,6);C:=Loaded.AddComponent(MakePCBLibrary.Find('0805'),20,20);LPApplyComponents(Loaded,P);
  P.SelectCopperLayer(3);Check(Length(P.ReferencePaths)=0,'Components not added to inner copper');
  P.Clear;Check((P.ComponentSetJSON='')and(P.SourceCount=0),'New board clears assembly');
  WriteLn('PASS: shared library, component-only sets, Top/Bottom, rotation, CAM, drill preservation, creator and UI');
 finally F.Free;D.Timer.Free;D.Free;Lib.Free;Loaded.Free;Doc.Free;P.Free;end;
 except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
