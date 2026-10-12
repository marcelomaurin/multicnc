program test_sketch_text;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Math, multicad_types, multicad_sketch, multicad_sketchtext,
  multicad_fontoutlines, multicad_profile, multicad_solver, multicad_document,
  multicad_extrude, multicad_rebuild, multicad_occt;
var Checks:Integer;P:TCadTextSettings;Paths,Other:TCadTextContours;Ids:TCadIdArray;
  S:TCadSketch;D,D2:TCadDocument;R:TCadProfileResult;RB:TCadRebuilder;
  Error,Before,FileName,Font:string;I,J,SketchId:Integer;
  MinX,MaxX,MinY,MaxY,Area:Double;
procedure Check(OK:Boolean;const Msg:string);
begin Inc(Checks);if not OK then raise Exception.Create(Msg+': '+Error);end;
procedure Near(A,B:Double;const Msg:string;Tol:Double=1E-5);
begin Check(Abs(A-B)<Tol,Msg+Format(' (%g / %g)',[A,B]));end;
procedure Bounds(const C:TCadTextContours);
begin
  MinX:=1E100;MinY:=1E100;MaxX:=-1E100;MaxY:=-1E100;
  for I:=0 to High(C) do for J:=0 to High(C[I]) do begin
    MinX:=Min(MinX,C[I][J].X);MaxX:=Max(MaxX,C[I][J].X);
    MinY:=Min(MinY,C[I][J].Y);MaxY:=Max(MaxY,C[I][J].Y);
  end;
end;
procedure Generate(const Text:string);
begin
  P.Text:=Text;Check(CadFontOutlines(P,Paths,Error),'Font outlines '+Text);
  S.Clear;Check(CadInsertSketchText(S,Paths,Ids,Error),'Insert '+Text);
  R:=CadSketchProfiles(S);Check(R.Ok,'Closed profiles '+Text);
end;
procedure TestSolid(UseOcct:Boolean);
var Doc:TCadDocument;Rebuilder:TCadRebuilder;Sketch:TCadSketch;Ex:TCadExtrude;
  V:Double;K:Integer;Reg:TCadProfileResult;
begin
  Doc:=TCadDocument.Create;Rebuilder:=TCadRebuilder.Create(Doc);Rebuilder.UseOcct:=UseOcct;
  try
    Sketch:=Doc.AddSketch('plane:1');Sketch.AddRectangle(0,0,50,30);Ex:=Doc.AddExtrude(Sketch.Id,4);
    Check(Rebuilder.Rebuild=0,'Text base');
    Sketch:=Doc.AddSketch('face:'+Ex.Name+'/fim');
    Check(CadInsertSketchText(Sketch,Paths,Ids,Error),'Text on solid face');
    Reg:=CadSketchProfiles(Sketch);V:=0;for K:=0 to High(Reg.Regions) do V:=V+Reg.Regions[K].Area;
    Ex:=Doc.AddExtrude(Sketch.Id,1,True);Check(Rebuilder.Rebuild=0,'Text cut '+Ex.Message);
    Near(Rebuilder.TotalVolume,6000-V,'Engraved text volume',0.01);
    for K:=0 to Rebuilder.BodyCount-1 do Check(Rebuilder.Body(K).Mesh.CheckClosed(Error),'Engraving remains closed');
    Ex.Suppressed:=True;Ex:=Doc.AddExtrude(Sketch.Id,1);Check(Rebuilder.Rebuild=0,'Raised text '+Ex.Message);
    Near(Rebuilder.TotalVolume,6000+V,'Raised text volume',0.01);
    if UseOcct then Check(Rebuilder.OcctActive,'OpenCascade used for vector text');
    for K:=0 to Rebuilder.BodyCount-1 do Check(Rebuilder.Body(K).Mesh.CheckClosed(Error),'Raised text remains closed');
  finally Rebuilder.Free;Doc.Free;end;
end;
begin
  S:=TCadSketch.Create;D:=nil;D2:=nil;RB:=nil;
  FileName:=GetTempFileName(GetTempDir,'txt');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      P:=DefaultSketchText;{$IFDEF MSWINDOWS}Font:='Arial';{$ELSE}Font:='DejaVu Sans';{$ENDIF}P.FontName:=Font;
      P.Text:='';Check(not CadFontOutlines(P,Paths,Error),'Empty rejected');
      P.Text:='H';P.Height:=0;Check(not CadFontOutlines(P,Paths,Error),'Zero height rejected');
      P.Height:=NaN;Check(not CadFontOutlines(P,Paths,Error),'NaN rejected');
      P.Height:=10;Generate('H');Bounds(Paths);Near(MaxY-MinY,10,'Physical cap height',0.01);
      Check(Length(R.Regions)=1,'H one region');
      Other:=Paths;P.Height:=20;Generate('H');Bounds(Paths);Near(MaxY-MinY,20,'Size scales geometry',0.02);
      Near(Paths[0][0].X,Other[0][0].X*2,'Size scales X',0.01);
      P.Height:=10;Generate('O');Check((Length(R.Regions)=1) and (Length(R.Regions[0].Holes)=1),'O keeps inner hole');
      Generate('B');Check((Length(R.Regions)=1) and (Length(R.Regions[0].Holes)=2),'B keeps two holes');
      Generate('A');Check(Length(R.Regions[0].Holes)=1,'A keeps hole');
      Generate('Á');Generate('ç');Check(Length(R.Regions)=1,'Cedilla joins its letter');
      Generate('ã');Check(Length(R.Regions)=2,'Tilde stays above letter');
      Generate('Áção 2014');Check(Length(R.Regions)>6,'UTF8 accents and digits');
      Generate('A O');Check(Length(R.Regions)=2,'Space advances without box');
      Other:=Paths;P.Origin:=V2(17,-8);P.Angle:=90;Generate('A O');
      Near(Paths[0][0].X,17-Other[0][0].Y,'Rotation X');
      Near(Paths[0][0].Y,-8+Other[0][0].X,'Rotation Y');
      P.Origin:=V2(0,0);P.Angle:=0;P.Alignment:=taRight;Generate('HH');Bounds(Paths);Check(MaxX<=0,'Right alignment');
      P.Alignment:=taCenter;Generate('HH');Bounds(Paths);Check((MinX<0) and (MaxX>0),'Center alignment');
      P.Alignment:=taLeft;Generate('H'+#10+'H');Check(Length(R.Regions)=2,'Multiline');Bounds(Paths);Check(MinY<0,'Second baseline below first');
      P.Bold:=True;P.Italic:=True;Generate('BO');Check(Length(R.Regions)=2,'Bold italic gives valid outlines');
      P.Bold:=False;P.Italic:=False;Generate('H');Area:=R.Regions[0].Area;
      {$IFDEF MSWINDOWS}P.FontName:='Times New Roman';{$ELSE}P.FontName:='DejaVu Serif';{$ENDIF}
      Generate('H');Check(Abs(R.Regions[0].Area-Area)>0.01,'Font choice changes vectors');
      P.FontName:=Font;Generate('BO');Area:=0;
      for I:=0 to High(R.Regions) do Area:=Area+R.Regions[I].Area;
      Check(CadSolveSketch(S).Converged,'Solver handles font without hundreds of automatic constraints');
      Check(S.ConstraintCount=0,'No raster tracing or artificial solver constraints');
      Before:=IntToStr(S.EntityCount);SetLength(Other,1);SetLength(Other[0],2);
      Check(not CadInsertSketchText(S,Other,Ids,Error),'Bad contour rejected');
      Check(IntToStr(S.EntityCount)=Before,'Bad contour is atomic');
      D:=TCadDocument.Create;S.Free;S:=D.AddSketch('plane:3');SketchId:=S.Id;
      Check(CadInsertSketchText(S,Paths,Ids,Error),'Insert on lateral plane');
      D.AddExtrude(S.Id,2);RB:=TCadRebuilder.Create(D);RB.UseOcct:=False;
      Check(RB.Rebuild=0,'Extrude text using Pascal kernel');Near(RB.TotalVolume,Area*2,'Text extruded volume',0.001);
      Check(D.SaveToFile(FileName,Error),'Save vectors');D2:=TCadDocument.Create;
      Check(D2.LoadFromFile(FileName,Error),'Reload vectors without regenerating font');
      S:=TCadSketch(D2.FindById(SketchId));Check(S.EntityCount=Length(Ids),'All segments persist');
      R:=CadSketchProfiles(S);Check(R.Ok and (Length(R.Regions)=2),'Persisted holes and regions');
      P.Origin:=V2(3,4);P.Text:='BO';Check(CadFontOutlines(P,Paths,Error),'Font for solid tests');
      TestSolid(False);if OcctAvailable then TestSolid(True) else WriteLn('SKIP OpenCascade: ',OcctLoadError);
      WriteLn('PASS: ',Checks,' sketch text checks (fonts, sizes, accents, holes, profiles, extrusion and persistence)');
    finally RB.Free;if D=nil then S.Free;D.Free;D2.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
