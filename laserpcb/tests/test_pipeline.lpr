program test_pipeline;
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multisuite_numfmt, laserpcb_types, laserpcb_job,
  laserpcb_svg, laserpcb_gcode, laserpcb_profile, laserpcb_layout,
  laserpcb_nesting, laserpcb_transform, laserpcb_geom, laserpcb_gerber,
  laserpcb_excellon, laserpcb_raster, laserpcb_cam, laserpcb_project, laserpcb_drill,
  laserart_model, laserart_svgimport, laserart_geom;
var Checks: Integer = 0; Dir,DataDir: string;
procedure Check(Ok: Boolean; const Msg: string);
begin Inc(Checks); if not Ok then begin Writeln('FAIL: ',Msg); Halt(1); end; end;
procedure Near(V,Expected: Double; const Msg: string);
begin Check(Abs(V-Expected)<1e-6,Msg+' actual='+FloatToStr(V,InvariantFS)); end;
procedure Save(const FN,S: string);
var L: TStringList;
begin L:=TStringList.Create; try L.Text:=S;L.SaveToFile(FN); finally L.Free; end; end;
function Box(X0,Y0,X1,Y1: Double): TLPRect;
begin Result.MinX:=X0;Result.MinY:=Y0;Result.MaxX:=X1;Result.MaxY:=Y1;Result.Valid:=True;end;
procedure CheckClipped(const Paths: TLPPaths; M: TLPMask; const Msg: string);
var I,J,K,N: Integer; P,Q,A: TLPPoint;
begin
  Check(Length(Paths)>0,Msg+' nonempty');
  for I:=0 to High(Paths) do for J:=1 to High(Paths[I]) do
  begin
    P:=Paths[I][J-1];Q:=Paths[I][J];N:=Max(1,Ceil(LPDist(P,Q)/(M.Res/5)));
    for K:=0 to N do
    begin
      A:=LPPoint(P.X+(Q.X-P.X)*K/N,P.Y+(Q.Y-P.Y)*K/N);
      Check(M.Get(M.ColOf(A.X),M.RowOf(A.Y))<>0,Msg+' entire segment inside');
    end;
  end;
end;

procedure TestSVG;
var J:TLaserPCBJob; D:TLADocument; R:TLASvgResult; Paths:TLAPaths;
begin
  J:=TLaserPCBJob.Create;D:=TLADocument.Create;
  try
    Save(Dir+'units.svg','<svg width="100mm" height="50mm" viewBox="0 0 1000 500"><line x1="0" y1="0" x2="1000" y2="500"/></svg>');
    Check(TSVGImporter.ImportFile(Dir+'units.svg',J),'SVG viewBox');
    Near(J.Width,100,'SVG width mm');Near(J.Height,50,'SVG height mm');
    Near(J.Point(0).X,0,'SVG start X');Near(J.Point(0).Y,50,'SVG start Y up');
    Near(J.Point(1).X,100,'SVG end X');Near(J.Point(1).Y,0,'SVG end Y up');
    Save(Dir+'group.svg','<svg width=''100mm'' height=''100mm'' viewBox=''0 0 100 100''><g transform=''translate(10,20)''><line x1=''1'' y1=''2'' x2=''3'' y2=''4''/></g></svg>');
    Check(TSVGImporter.ImportFile(Dir+'group.svg',J),'SVG single quotes + transform');
    Near(J.Point(0).X,11,'SVG translated X');Near(J.Point(0).Y,78,'SVG translated Y');
    Near(J.Point(1).X,13,'SVG second X');Near(J.Point(1).Y,76,'SVG second Y');
    Save(Dir+'inch.svg','<svg width="1in" height="1in" viewBox="0 0 96 96"><rect x="0" y="0" width="96" height="96"/></svg>');
    Check(TSVGImporter.ImportFile(Dir+'inch.svg',J),'SVG inches');
    Near(J.Width,25.4,'inch to mm');Check(J.Count=5,'rect closed');
    Save(Dir+'aspect.svg','<svg width="100mm" height="50mm" viewBox="0 0 100 100"><line x1="0" y1="0" x2="100" y2="100"/></svg>');
    TSVGImporter.ImportFile(Dir+'aspect.svg',J);Near(J.Point(0).X,25,'default meet centered');Near(J.Point(1).X,75,'default meet aspect');
    Save(Dir+'none.svg','<svg width="100mm" height="50mm" viewBox="0 0 100 100" preserveAspectRatio="none"><line x1="0" y1="0" x2="100" y2="100"/></svg>');
    TSVGImporter.ImportFile(Dir+'none.svg',J);Near(J.Point(0).X,0,'aspect none');Near(J.Point(1).X,100,'aspect none stretched');
    Save(Dir+'curve.svg','<svg width="40mm" height="20mm" viewBox="0 0 40 20"><path d="M0 10 C10 0 20 20 30 10 A5 5 0 0 1 40 10"/></svg>');
    Check(TSVGImporter.ImportFile(Dir+'curve.svg',J),'Bezier + arc');
    Check(J.Count>20,'curves flattened');Near(J.Point(J.Count-1).X,40,'curve endpoint');
    Near(J.Point(J.Count-1).Y,10,'arc endpoint');
    Save(Dir+'unsafe.svg','<svg width="10mm" height="10mm" viewBox="0 0 10 10"><line x1="0" y1="0" x2="10" y2="10" clip-path="url(#clip)"/></svg>');
    TSVGImporter.ImportFile(Dir+'unsafe.svg',J);Check(J.Warnings.Count>0,'unsupported clip warned');
    R:=ImportSVGString(D,'<svg width="10mm" height="10mm" viewBox="0 0 10 10"><line x1="-2" y1="0" x2="3" y2="10"/></svg>','legacy',0);
    Check(R.Shapes=1,'shared parser legacy');Paths:=ShapeWorldPaths(D.Shape(0));
    Near(Paths[0].Pts[0].X,10,'LaserArt default reposition retained');
    Near(Paths[0].Pts[0].Y,20,'LaserArt default Y retained');
  finally D.Free;J.Free;end;
end;

procedure TestMirrorExport;
var J:TLaserPCBJob; S:TStringList; Rejected:Boolean; I,Cuts:Integer;
begin
  J:=TLaserPCBJob.Create;S:=TStringList.Create;
  try
    J.Width:=100;J.AddPoint(10,20,False);J.AddPoint(30,20,True);J.Mirror:=True;
    J.ApplyBottomMirror;J.ApplyBottomMirror;
    Near(J.Point(0).X,90,'mirror idempotent');Near(J.RawPoint(0).X,10,'mirror raw untouched');
    J.Mirror:=False;Near(J.Point(0).X,10,'mirror toggle');
    J.Width:=0;J.Mirror:=True;Near(J.Point(0).X,30,'mirror extent fallback');
    J.Profile.Power:=250;J.Profile.Feed:=600;J.Profile.Passes:=0;
    Save(Dir+'protected.gcode','sentinel');
    Rejected:=False;try TLaserGCodeExporter.ExportJob(J,Dir+'protected.gcode');except on E:Exception do Rejected:=True;end;
    Check(Rejected,'reject zero passes');S.LoadFromFile(Dir+'protected.gcode');Check(Trim(S.Text)='sentinel','invalid export preserves file');
    J.Profile.Passes:=1;J.Profile.Power:=0.2;Rejected:=False;
    try TLaserGCodeExporter.ExportJob(J,Dir+'protected.gcode');except on E:Exception do Rejected:=True;end;
    Check(Rejected,'reject S0 rounding');
    J.Profile.Power:=1500;Rejected:=False;
    try TLaserGCodeExporter.ValidateJob(J);except on E:Exception do Rejected:=True;end;
    Check(Rejected,'reject power over S-max');
    J.Profile.Power:=250;J.Profile.Passes:=2;TLaserGCodeExporter.ExportJob(J,Dir+'mirror.gcode');
    S.LoadFromFile(Dir+'mirror.gcode');Cuts:=0;
    for I:=0 to S.Count-1 do
    begin
      if Pos('G1 ',S[I])=1 then begin Inc(Cuts);Check(Pos(',',S[I])=0,'locale independent G-code');end;
      if Pos('G0 ',S[I])=1 then Check((I>0) and (S[I-1]='M5'),'M5 before rapid');
    end;
    Check(Cuts=2,'passes executed once each');Check(S[S.Count-1]='M5','end laser off');
    TLaserGCodeExporter.ExportJob(J,Dir+'mirror2.gcode');Near(J.RawPoint(0).X,10,'repeat export raw untouched');
    TLaserProfileIO.Save(J.Profile,Dir+'profile.json');J.Profile:=TLaserProfileIO.Load(Dir+'profile.json');
    Near(J.Profile.Power,250,'profile power roundtrip');Near(J.Profile.SMax,1000,'profile Smax roundtrip');
  finally S.Free;J.Free;end;
end;

procedure TestLayout;
var L:TLaserBedLayout; Item,Fixed:TLaserLayoutItem; E:TStringList; P,Q:TPathPoint; X,Y:Double;
begin
  L:=TLaserBedLayout.Create;E:=TStringList.Create;
  try
    L.BedWidth:=200;L.BedHeight:=100;Item:=L.AddItem('rotated',50,30);Item.X:=5;Item.Y:=5;Item.Rotation:=90;
    Check(L.Validate(E),'rotated layout valid');
    P.X:=0;P.Y:=30;P.Power:=250;P.Feed:=600;P.LaserOn:=True;Q:=TLaserTransform.Apply(P,Item);
    Near(Q.X,5,'rotated corner X');Near(Q.Y,5,'rotated corner Y');
    Near(Q.Power,250,'transform power');Near(Q.Feed,600,'transform feed');Check(Q.LaserOn,'transform laser');
    Near(Item.PlacedWidth,30,'rotated bbox width');Near(Item.PlacedHeight,50,'rotated bbox height');
    Item.ScaleX:=-2;Item.ScaleY:=1.4;Item.Rotation:=33;Item.MirrorX:=True;Item.MirrorY:=True;
    Item.LocalToWorld(12,7,X,Y);Item.WorldToLocal(X,Y,X,Y);
    Near(X,12,'inverse negative scale mirror rotate X');Near(Y,7,'inverse negative scale mirror rotate Y');
    L.Clear;Fixed:=L.AddItem('fixed',50,30);Fixed.X:=5;Fixed.Y:=5;Fixed.Locked:=True;
    Item:=L.AddItem('movable',50,30);L.AddKeepOut(60,5,20,20);
    Check(TLaserNesting.ArrangeRows(L),'nest around locked and keepout');
    Check(L.Validate(E),'nested layout valid');Near(Fixed.X,5,'locked X retained');Near(Fixed.Y,5,'locked Y retained');
    L.AddItem('oversized',300,30);X:=Item.X;Y:=Item.Y;
    Check(not TLaserNesting.ArrangeRows(L),'reject oversized');
    Near(Item.X,X,'failed nesting rollback X');Near(Item.Y,Y,'failed nesting rollback Y');
  finally E.Free;L.Free;end;
end;

procedure TestGerberAndCAM;
const Header='%FSLAX46Y46*%%MOMM*%%LPD*%';
var L:TLPGerberLayer; M,B,Mismatch:TLPMask; P,One:TLPPaths; Q:TLPPath; Rejected:Boolean;
begin
  L:=TLPGerberLayer.Create;
  try
    Check(TLPGerberReader.LoadFromString(Header+'%ADD10C,2X1*%D10*X5000000Y5000000D03*M02*',L),'annulus Gerber');
    M:=TLPMask.Create(Box(0,0,10,10),0.05);
    try M.DrawGerber(L);Check(M.Get(M.ColOf(5),M.RowOf(5))=0,'annulus hole');
      Check(M.Get(M.ColOf(5.75),M.RowOf(5))=1,'annulus copper');finally M.Free;end;
    TLPGerberReader.LoadFromString(Header+'%ADD11C,0.4*%%ADD10C,2X1*%D11*X5000000Y5000000D03*D10*X5000000Y5000000D03*M02*',L);
    M:=TLPMask.Create(Box(0,0,10,10),0.05);
    try M.DrawGerber(L);Check(M.Get(M.ColOf(5),M.RowOf(5))=1,'aperture hole transparent');finally M.Free;end;
    TLPGerberReader.LoadFromString(Header+'%ADD10C,2*%%ADD11C,0.5*%D10*X5000000Y5000000D03*%LPC*%D11*X5000000Y5000000D03*M02*',L);
    M:=TLPMask.Create(Box(0,0,10,10),0.05);
    try M.DrawGerber(L);Check(M.Get(M.ColOf(5),M.RowOf(5))=0,'LPC subtracts copper');finally M.Free;end;
  finally L.Free;end;
  M:=TLPMask.Create(Box(-3,-3,13,13),0.05);B:=TLPMask.CreateLike(M);
  Mismatch:=TLPMask.Create(Box(0,0,16,16),0.05);
  try
    One:=nil;LPAddPath(One,LPRectPath(5,5,10,10));LPAddPath(One,LPRectPath(5,5,2,2));B.FillPathsEvenOdd(One);
    Check(B.Get(B.ColOf(5),B.RowOf(5))=0,'same-winding internal board cutout');
    Check(B.Get(B.ColOf(2),B.RowOf(5))=1,'board around internal cutout');
    B.Clear;One:=nil;LPAddPath(One,LPRectPath(5,5,10,10));B.FillPaths(One);
    One:=nil;LPAddPath(One,LPRectPath(5,5,2,10));B.FillPaths(One,0);
    Q:=nil;LPAddPoint(Q,-2,5);LPAddPoint(Q,12,5);P:=nil;LPAddPath(P,Q);
    P:=LPClipPathsToMask(P,B);Check(Length(P)=2,'clipping splits crossing hole');
    CheckClipped(P,B,'hole clipping');Near(LPPathsLength(P),8,'hole clipping length');
    B.Clear;One:=nil;LPAddPath(One,LPRectPath(5,5,10,10));B.FillPaths(One);
    One:=nil;LPAddPath(One,LPCircle(0.5,5,1,0.005));M.FillPaths(One);
    P:=LPIsolation(M,B,2,1,0,0.01);CheckClipped(P,B,'edge isolation clipped');
    Rejected:=False;try M.AndMask(Mismatch);except on E:Exception do Rejected:=True;end;
    Check(Rejected,'mask grid mismatch rejected');
  finally Mismatch.Free;B.Free;M.Free;end;
end;

procedure TestProject;
var P:TLaserPCBProject; J1,J2:TLaserPCBJob; E:TStringList; I:Integer; Top:TLPPoint;
begin
  P:=TLaserPCBProject.Create;E:=TStringList.Create;
  try
    P.ImportFile(DataDir+'demo-F_Cu.gtl');P.ImportFile(DataDir+'demo-B_Cu.gbl');
    P.ImportFile(DataDir+'demo-Edge_Cuts.gm1');P.ImportFile(DataDir+'demo-F_Mask.gts');
    P.ImportFile(DataDir+'demo-F_Silkscreen.gto');P.ImportFile(DataDir+'demo-PTH.drl');
    P.ImportFile(DataDir+'demo-NPTH-slot.drl');
    Near(P.Width,40,'board centerline width');Near(P.Height,28,'board centerline height');
    Check(P.Drills.HoleCount=11,'merged holes');Check(P.Drills.Holes[9].Slot,'slot retained');
    Check(not P.Drills.Tools[P.Drills.Holes[9].Tool].Plated,'NPTH retained');
    P.Profile.Power:=250;P.Profile.Feed:=600;P.Profile.SpotMM:=0.2;P.Profile.Passes:=2;
    P.Generate;Check(Length(P.Paths)>0,'Gerber CAM integrated');
    Check(P.Validate(E,True),'complete valid pipeline '+E.Text);
    J1:=P.BuildJob;
    try Check(J1.Profile.Passes=1,'isolation rings not repeated twice');
      TLaserGCodeExporter.ExportJob(J1,Dir+'gerber.gcode');
      Top:=P.WorldPoint(P.Layout.Item(0),LPPoint(10,4));P.Side:=lsBottom;P.MirrorBottom:=True;
      Near(P.WorldPoint(P.Layout.Item(0),LPPoint(10,4)).X,35,'Bottom mirror x');Near(Top.X,15,'Top x unchanged');
      P.Generate;J2:=P.BuildJob;
      try TLaserGCodeExporter.ExportJob(J2,Dir+'bottom.gcode');
        for I:=0 to J2.Count-1 do
        begin Check((J2.Point(I).X>=5) and (J2.Point(I).X<=45),'Bottom inside board X');
          Check((J2.Point(I).Y>=5) and (J2.Point(I).Y<=33),'Bottom inside board Y');end;
      finally J2.Free;end;
    finally J1.Free;end;
    P.Side:=lsTop;P.Mode:=cmRemoveCopper;P.Generate;Check(Length(P.Paths)>0,'copper removal');
    P.Mode:=cmLayerHatch;P.SelectedLayer:=4;P.Generate;Check(Length(P.Paths)>0,'silk hatch');
    P.AddCopy;Check(TLaserNesting.ArrangeRows(P.Layout),'duplicate nesting integrated');
    Check(P.Validate(E,True),'duplicated project valid '+E.Text);
    P.Clear;P.ImportFile(Dir+'unsafe.svg');P.Profile.Power:=250;P.Profile.Feed:=600;P.Generate;
    Check(not P.Validate(E,True),'unsupported SVG export blocked');
  finally E.Free;P.Free;end;
end;

procedure TestDrillProject;
var P:TLaserPCBProject; Plan:TLPDrillPlan; E,G:TStringList; I,J:Integer; H:TLPDrillHole;
  A,B:TLPPoint; Found:Boolean;
begin
  P:=TLaserPCBProject.Create;E:=TStringList.Create;Plan:=TLPDrillPlan.Create;
  try
    P.ImportFile(DataDir+'demo-F_Cu.gtl');P.ImportFile(DataDir+'demo-Edge_Cuts.gm1');
    P.ImportFile(DataDir+'demo-PTH.drl');P.ImportFile(DataDir+'demo-NPTH-slot.drl');
    P.Profile.Power:=250;P.Profile.Feed:=600;P.Profile.SpotMM:=0.1;
    { plano na mesa: mesma posicao das trajetorias do laser }
    P.BuildDrillPlan(Plan);Check(Plan.HoleCount=P.Drills.HoleCount,'drill plan holes');
    Check(Plan.SlotCount=1,'drill plan slot');
    A:=P.WorldPoint(P.Layout.Item(0),LPPoint(5,5));Found:=False;
    for I:=0 to Plan.GroupCount-1 do for J:=0 to High(Plan.Group(I).Holes) do
    begin H:=Plan.Group(I).Holes[J];if LPDist(LPPoint(H.X,H.Y),A)<1e-6 then Found:=True;end;
    Check(Found,'hole mapped with WorldPoint');
    P.Side:=lsBottom;P.MirrorBottom:=True;P.BuildDrillPlan(Plan);
    B:=P.WorldPoint(P.Layout.Item(0),LPPoint(5,5));Near(B.X,P.Layout.Item(0).X+35,'bottom drill mirrored');
    Found:=False;
    for I:=0 to Plan.GroupCount-1 do for J:=0 to High(Plan.Group(I).Holes) do
    begin H:=Plan.Group(I).Holes[J];if LPDist(LPPoint(H.X,H.Y),B)<1e-6 then Found:=True;end;
    Check(Found,'bottom drill at mirrored position');
    { copias e filtro }
    P.Side:=lsTop;P.AddCopy;Check(TLaserNesting.ArrangeRows(P.Layout),'drill copies nested');
    P.BuildDrillPlan(Plan);Check(Plan.HoleCount=2*P.Drills.HoleCount,'holes of every copy');
    P.DrillFilter.IncludeNonPlated:=False;P.BuildDrillPlan(Plan);
    Check(Plan.HoleCount=2*9,'NPTH filtered');P.DrillFilter.IncludeNonPlated:=True;
    { pinos de registro no eixo central de cada placa }
    P.RegistrationPins:=True;P.RegistrationOffset:=4;P.RegistrationDiameter:=3;
    P.Layout.Item(0).Y:=10;P.Layout.Item(1).Y:=10;
    Check(P.ValidateDrilling(E),'drilling valid '+E.Text);
    P.BuildDrillPlan(Plan);Check(Plan.HoleCount=2*P.Drills.HoleCount+4,'registration pins');
    Found:=False;
    for I:=0 to Plan.GroupCount-1 do if Abs(Plan.Group(I).Diameter-3)<1e-9 then
      for J:=0 to High(Plan.Group(I).Holes) do
        if Abs(Plan.Group(I).Holes[J].X-(P.Layout.Item(0).X+20))<1e-6 then Found:=True;
    Check(Found,'pin on board axis');
    G:=P.DrillProgram('teste');
    try Check(G[0]=LP_ROUTER_HEADER,'router header');Check(G[G.Count-1]='M30','router end');
      for I:=0 to G.Count-1 do
      begin Check(Length(G[I])<127,'router line length');
        if Copy(G[I],1,1)<>';' then Check(Pos(',',G[I])=0,'router invariant decimals');end;
    finally G.Free;end;
    P.Layout.Item(1).Rotation:=90;E.Clear;
    Check(not P.ValidateDrilling(E),'pins require 0/180 rotation');
    P.Layout.Item(1).Rotation:=0;P.Layout.Item(0).Y:=1;E.Clear;
    Check(not P.ValidateDrilling(E),'pins outside bed rejected');
    P.RegistrationPins:=False;P.Router.Depth:=1;E.Clear;
    Check(not P.ValidateDrilling(E),'positive depth rejected');P.Router.Depth:=-1.6;
    { marcacao a laser dos furos pelo fluxo normal do CAM }
    E.Clear;P.Layout.Item(0).Y:=10;P.Mode:=cmDrillMarks;P.MarkKind:=mkCenter;P.MarkDiameter:=0.4;
    P.Generate;Check(Length(P.Paths)=P.Drills.HoleCount,'one mark per hole');
    Check(P.Validate(E,True),'drill marks valid '+E.Text);
    P.MarkKind:=mkCutHole;P.Generate;Check(Length(P.Paths)>P.Drills.HoleCount,'cut holes rings');
    P.DrillFilter.MinDiameter:=99;E.Clear;
    try P.Generate;Check(False,'empty marks accepted');except on Ex:Exception do Check(True,'empty marks rejected');end;
  finally Plan.Free;E.Free;P.Free;end;
end;

procedure TestOperations;
var P:TLaserPCBProject; E:TStringList; J:TLaserPCBJob; I,Iso,Outline,Before:Integer;
  Cut,Travel,Secs:Double; Has800,Has300:Boolean;
begin
  P:=TLaserPCBProject.Create;E:=TStringList.Create;
  try
    P.ImportFile(DataDir+'demo-F_Cu.gtl');P.ImportFile(DataDir+'demo-Edge_Cuts.gm1');
    P.ImportFile(DataDir+'demo-F_Mask.gts');P.ImportFile(DataDir+'demo-F_Silkscreen.gto');
    P.ImportFile(DataDir+'demo-PTH.drl');
    P.CreateDefaultOperations;
    Check(P.OperationCount=5,'default layers: '+IntToStr(P.OperationCount));
    Check(P.Operation(0).Mode=cmIsolation,'isolation first');
    Check(P.Operation(P.OperationCount-1).Mode=cmOutline,'outline last');
    Check(P.Operation(0).Output and not P.Operation(1).Output,'only isolation outputs by default');
    Check(P.Operation(0).Power=0,'new layer uncalibrated');
    P.CreateDefaultOperations;Check(P.OperationCount=5,'defaults not duplicated');
    P.Profile.SpotMM:=0.2;P.GenerateOperations;
    Check(P.Operation(0).Generated,'isolation generated');
    Check(not P.ValidateOperations(E,True),'uncalibrated layer blocked');
    Check(Pos('C01',E.Text)>0,'error cites layer: '+E.Text);
    Iso:=0;Outline:=P.OperationCount-1;
    P.Operation(Iso).Power:=300;P.Operation(Iso).Feed:=600;E.Clear;
    Check(P.ValidateOperations(E,True),'calibrated isolation valid '+E.Text);
    J:=P.BuildOperationsJob;try Before:=J.Count;finally J.Free;end;
    P.Operation(Outline).Output:=True;P.Operation(Outline).Power:=800;P.Operation(Outline).Feed:=300;
    P.Operation(Outline).Passes:=2;P.GenerateOperations;E.Clear;
    Check(P.ValidateOperations(E,True),'two layers valid '+E.Text);
    J:=P.BuildOperationsJob;
    try
      Check(J.Profile.Passes=1,'layers expand passes in the job');
      Check(J.Count=Before+2*Length(P.Operation(Outline).ItemPaths[0][0]),'outline repeated per pass');
      Has800:=False;Has300:=False;
      for I:=0 to J.Count-1 do if J.Point(I).LaserOn then
      begin
        if (J.Point(I).Power=800) and (J.Point(I).Feed=300) then Has800:=True;
        if (J.Point(I).Power=300) and (J.Point(I).Feed=600) then Has300:=True;
      end;
      Check(Has800 and Has300,'power and feed per layer');
      Check(not J.Point(J.Count-1).LaserOn or (J.Point(J.Count-1).Power=800),'outline cut last');
      TLaserGCodeExporter.ExportJob(J,Dir+'layers.gcode');
    finally J.Free;end;
    P.EstimateOperations(3000,Cut,Travel,Secs);
    Check((Cut>0) and (Secs>Cut/600*60),'estimate');
    P.Operation(2).Output:=True;P.GenerateOperations;E.Clear;
    Check(not P.ValidateOperations(E,True),'mask layer without power blocked');
    Check(Pos('C03',E.Text)>0,'mask error cites C03');
    P.Operation(2).Output:=False;
    P.MoveOperation(Outline,-1);Check(P.Operation(Outline-1).Mode=cmOutline,'move layer up');
    P.MoveOperation(0,-1);Check(P.Operation(0).Mode=cmIsolation,'move out of range ignored');
    P.DeleteOperation(Outline-1);Check(P.OperationCount=4,'delete layer');
    P.Profile.SpotMM:=0.3;P.InvalidateCAM;Check(not P.Operation(0).Generated,'invalidate clears layers');
    for I:=0 to P.OperationCount-1 do begin P.Operation(I).Output:=False;P.Operation(I).Show:=False;end;
    try P.GenerateOperations;Check(False,'no layer accepted');
    except on Ex:Exception do Check(Pos('Saida',Ex.Message)>0,'no layer rejected');end;
  finally E.Free;P.Free;end;
end;

procedure TestPhysicalSpotAfterScale;
const Header='%FSLAX46Y46*%%MOMM*%%LPD*%';
var P:TLaserPCBProject; Paths:TLPPaths; I,J:Integer; B:TLPRect; Q:TLPPoint;
begin
  Save(Dir+'scaled-F_Cu.gtl',Header+'%ADD10C,2*%D10*X5000000Y5000000D03*M02*');
  Save(Dir+'scaled-Edge_Cuts.gm1',Header+'%ADD10C,0.1*%D10*X0Y0D02*X10000000Y0D01*X10000000Y10000000D01*X0Y10000000D01*X0Y0D01*M02*');
  P:=TLaserPCBProject.Create;
  try
    P.ImportFile(Dir+'scaled-F_Cu.gtl');P.ImportFile(Dir+'scaled-Edge_Cuts.gm1');
    P.Profile.SpotMM:=0.4;P.Resolution:=0.01;P.Layout.Item(0).ScaleX:=2;P.Layout.Item(0).ScaleY:=1;
    P.Generate;Paths:=P.PathsForItem(P.Layout.Item(0));B:=LPEmptyRect;
    for I:=0 to High(Paths) do for J:=0 to High(Paths[I]) do
    begin Q:=P.WorldPoint(P.Layout.Item(0),Paths[I][J]);LPRectInclude(B,Q.X,Q.Y);end;
    Check(Abs(LPRectWidth(B)-4.4)<0.05,'scaled copper + constant physical spot X');
    Check(Abs(LPRectHeight(B)-2.4)<0.05,'scaled copper + constant physical spot Y');
    P.Layout.Item(0).ScaleX:=-2;P.Generate;Paths:=P.PathsForItem(P.Layout.Item(0));B:=LPEmptyRect;
    for I:=0 to High(Paths) do for J:=0 to High(Paths[I]) do
    begin Q:=P.WorldPoint(P.Layout.Item(0),Paths[I][J]);LPRectInclude(B,Q.X,Q.Y);end;
    Check(Abs(LPRectWidth(B)-4.4)<0.05,'negative scale constant physical spot');
  finally P.Free;end;
end;
begin
  DataDir:='laserpcb/tests/data/';
  if not FileExists(DataDir+'demo-F_Cu.gtl') then
    DataDir:=IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+'data'+PathDelim;
  DefaultFormatSettings.DecimalSeparator:=',';DefaultFormatSettings.ThousandSeparator:='.';
  Dir:=IncludeTrailingPathDelimiter(GetTempDir)+'laserpcb_regressions_'+IntToStr(GetProcessID)+PathDelim;
  ForceDirectories(Dir);
  TestSVG;TestMirrorExport;TestLayout;TestGerberAndCAM;TestProject;TestDrillProject;TestOperations;TestPhysicalSpotAfterScale;
  Writeln('PASS: ',Checks,' checks (SVG, mirror, export, geometry, nesting, Gerber, Excellon, CAM, drilling, layers)');
end.
