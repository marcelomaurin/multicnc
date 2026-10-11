program test_blend_sequence_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Graphics, SysUtils, multicad_main, multicad_feature,
  multicad_camera;
var F:TMainForm;I,Checks:Integer;V:Double;Err,Filename:string;
  B:TBitmap;P:TPortableNetworkGraphic;
procedure Check(OK:Boolean;const Msg:string);
begin Inc(Checks);if not OK then raise Exception.Create(Msg);end;
procedure Pump;
var J:Integer;
begin for J:=1 to 12 do begin Application.ProcessMessages;Sleep(10);end;end;
begin
  Checks:=0;RequireDerivedFormResource:=False;Application.Initialize;
  F:=TMainForm.Create(nil);
  try
    F.Position:=poDesigned;F.SetBounds(-2400,20,1360,860);F.Show;
    Filename:=ExtractFilePath(ParamStr(0))+'fixtures'+DirectorySeparator+'fillet-crossing-cuts.mcad';
    Check(F.OpenFile(Filename),'Open regression part in the real form');Pump;
    for I:=0 to F.Document.Count-1 do Check(F.Document.Feature(I).State<>fsError,'Feature without error: '+F.Document.Feature(I).Name);
    Check(F.Rebuilder.BodyCount=1,'One body in the viewport');
    Check(F.Rebuilder.Body(0).Mesh.CheckClosed(Err),'Closed viewport mesh: '+Err);
    V:=F.Rebuilder.TotalVolume;
    F.View3D.SetView(svIso);F.View3D.FitAll;Pump;
    if ParamCount>0 then begin
      B:=F.GetFormImage;P:=TPortableNetworkGraphic.Create;
      try P.Assign(B);P.SaveToFile(ParamStr(1));finally P.Free;B.Free;end;
    end;
    F.EditFeatureById(13);Pump;Check(F.PropManager.Visible,'Fillet property manager opens');
    F.CancelEdit;Pump;
    Check(F.Rebuilder.Body(0).Mesh.CheckClosed(Err),'Cancel retains closed solid');
    Check(Abs(F.Rebuilder.TotalVolume-V)<0.05,'Cancel retains accepted fillet geometry');
    F.Document.Modified:=False;
    Writeln('PASS: ',Checks,' checks; fillet part opens, renders, edits and cancels normally');
  finally F.Free;end;
end.
