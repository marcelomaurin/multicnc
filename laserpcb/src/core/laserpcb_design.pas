unit laserpcb_design;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils,Math,makepcb_model,makepcb_library,makepcb_route,
  makepcb_drc,laserpcb_project,laserpcb_roles,laserpcb_types;

function ReadDesignFile(const FileName:string):string;
procedure LPOpenPCBDesign(const FileName:string;Lib:TMPLibrary;Project:TLaserPCBProject;Doc:TMPDocument);
procedure LPSavePCBDesign(const FileName:string;Project:TLaserPCBProject;Doc:TMPDocument);
function LPCanEditDesign(Project:TLaserPCBProject):Boolean;
function LPCheckPCBDesign(Doc:TMPDocument;Project:TLaserPCBProject;Errors:TStrings):Boolean;
function LPRoutePCBDesign(Doc:TMPDocument;Lib:TMPLibrary;Project:TLaserPCBProject;
  Failed:TStrings):TMPRouteResult;

implementation
uses fpjson,jsonparser;
function ReadDesignFile(const FileName:string):string;
var S:TStringList;
begin
  S:=TStringList.Create;
  try S.LoadFromFile(FileName);Result:=S.Text;finally S.Free;end;
end;

procedure LPOpenPCBDesign(const FileName:string;Lib:TMPLibrary;Project:TLaserPCBProject;Doc:TMPDocument);
var Temp:TMPDocument;Data:TJSONData;Layers:Integer;SingleBottom:Boolean;Text:string;
begin
  Text:=ReadDesignFile(FileName);Temp:=TMPDocument.Create;Data:=nil;
  try
    Temp.FromJSON(Text,@Lib.Resolve);Data:=GetJSON(Text);
    Layers:=TJSONObject(Data).Get('laserpcb_layers',1+Ord(Temp.DoubleSided));
    SingleBottom:=TJSONObject(Data).Get('laserpcb_single_bottom',True);
    if IsNan(Temp.BoardW) or IsInfinite(Temp.BoardW) or IsNan(Temp.BoardH) or IsInfinite(Temp.BoardH) or
      (Temp.BoardW<=0) or (Temp.BoardH<=0) or (Layers<1) or (Layers>64) or
      (Temp.BoardW>Project.Layout.BedWidth-2*Project.Layout.Margin) or
      (Temp.BoardH>Project.Layout.BedHeight-2*Project.Layout.Margin) then
      raise Exception.Create('Dimensoes ou camadas do projeto PCB invalidas para esta mesa.');
    Project.CreateBoard(Temp.BoardW,Temp.BoardH,Layers,SingleBottom);
    Doc.FromJSON(Temp.ToJSON,@Lib.Resolve);
  finally Data.Free;Temp.Free;end;
end;

procedure LPSavePCBDesign(const FileName:string;Project:TLaserPCBProject;Doc:TMPDocument);
var Data:TJSONObject;S:TStringList;Bottom:Boolean;
begin
  Data:=TJSONObject(GetJSON(Doc.ToJSON));S:=TStringList.Create;
  try
    Bottom:=(Project.CopperLayerCount=1) and (Project.CopperSource(1).Role=lrBottomCopper);
    Data.Add('laserpcb_layers',Project.CopperLayerCount);
    Data.Add('laserpcb_single_bottom',Bottom);
    S.Text:=Data.AsJSON;S.SaveToFile(FileName);
  finally S.Free;Data.Free;end;
end;

function LPCanEditDesign(Project:TLaserPCBProject):Boolean;
var I:Integer;S:TLPSource;
begin
  Result:=not Project.HasSVG and (Project.Width>0) and (Project.Height>0);
  if not Result then Exit;
  { Gerber guarda a arte pronta. Sem as redes originais, o editor/roteador
    nao pode considerar essa geometria como uma placa vazia. }
  for I:=0 to Project.SourceCount-1 do
  begin
    S:=Project.Source(I);
    if not S.Template and not S.ComponentGeometry and
      ((S.CopperIndex>0) or (S.Role in [lrTopCopper,lrBottomCopper])) then Exit(False);
  end;
end;

function LPCheckPCBDesign(Doc:TMPDocument;Project:TLaserPCBProject;Errors:TStrings):Boolean;
var N,I,J:Integer;Issues:TMPDrcIssues;Single:TMPLayer;
begin
  N:=Errors.Count;
  Issues:=MPCheckDesign(Doc,Doc.TrackWidth);
  for I:=0 to High(Issues) do Errors.Add(Issues[I].Text);
  if (Doc.ComponentCount>1) and (Doc.WireCount=0) then
    Errors.Add('Defina as ligacoes entre terminais para conferir o circuito.');
  if Project.CopperLayerCount=1 then
  begin
    if Project.CopperSource(1).Role=lrTopCopper then Single:=mlTopCopper else Single:=mlBottomCopper;
    for I:=0 to Doc.TrackCount-1 do
      if Doc.Track(I).Layer<>Single then Errors.Add('Trilha em uma face que a placa nao possui.');
    for I:=0 to Doc.AreaCount-1 do
      if Doc.Area(I).Layer<>Single then Errors.Add('Area de cobre em uma face que a placa nao possui.');
    for I:=0 to Doc.ComponentCount-1 do
    begin
      if SameText(Doc.Component(I).Footprint.Name,'Via') then Errors.Add('Via exige duas faces de cobre.');
      for J:=0 to Doc.Component(I).PadCount-1 do
        if not Doc.Component(I).PadOnLayer(J,Single) then
        begin Errors.Add(Doc.Component(I).Ref+': componente SMD em uma face que a placa nao possui.');Break;end;
    end;
  end;
  Result:=Errors.Count=N;
end;

function LPRoutePCBDesign(Doc:TMPDocument;Lib:TMPLibrary;Project:TLaserPCBProject;
  Failed:TStrings):TMPRouteResult;
var Work:TMPDocument;Router:TMPRouter;I,J,Before:Integer;TopOnly:Boolean;T,NewTrack:TMPTrack;
begin
  if not LPCanEditDesign(Project) then raise Exception.Create('Abra um projeto PCB editavel para rotear.');
  Work:=TMPDocument.Create;
  try
    Work.FromJSON(Doc.ToJSON,@Lib.Resolve);
    Work.DoubleSided:=Project.CopperLayerCount>1;
    TopOnly:=(Project.CopperLayerCount=1) and (Project.CopperSource(1).Role=lrTopCopper);
    { O roteador compartilhado usa Bottom para face simples. Normalizamos
      apenas a copia de trabalho e devolvemos as trilhas para a face Top. }
    if TopOnly then
    begin
      for I:=0 to Work.ComponentCount-1 do
      begin
        Work.Component(I).X:=Work.BoardW-Work.Component(I).X;
        Work.Component(I).Rotation:=(360-Work.Component(I).Rotation) mod 360;
        Work.Component(I).Flipped:=not Work.Component(I).Flipped;
      end;
      for I:=0 to Work.TrackCount-1 do
      begin
        if Work.Track(I).Layer=mlTopCopper then Work.Track(I).Layer:=mlBottomCopper;
        for J:=0 to High(Work.Track(I).Points) do Work.Track(I).Points[J].X:=Work.BoardW-Work.Track(I).Points[J].X;
      end;
      for I:=0 to Work.AreaCount-1 do
      begin
        if Work.Area(I).Layer=mlTopCopper then Work.Area(I).Layer:=mlBottomCopper;
        for J:=0 to High(Work.Area(I).Points) do Work.Area(I).Points[J].X:=Work.BoardW-Work.Area(I).Points[J].X;
      end;
    end;
    Work.Changed;Before:=Work.TrackCount;
    Router:=TMPRouter.Create(Work,Doc.TrackWidth,Doc.Clearance);
    try Result:=Router.RouteAll(-1,Failed);finally Router.Free;end;
    for I:=Before to Work.TrackCount-1 do
    begin
      T:=Work.Track(I);
      if TopOnly then NewTrack:=Doc.AddTrack(mlTopCopper,T.Width)
      else NewTrack:=Doc.AddTrack(T.Layer,T.Width);
      NewTrack.Points:=Copy(T.Points);
      if TopOnly then for J:=0 to High(NewTrack.Points) do NewTrack.Points[J].X:=Doc.BoardW-NewTrack.Points[J].X;
    end;
    { Vias sao componentes no modelo compartilhado. }
    for I:=Doc.ComponentCount to Work.ComponentCount-1 do
    begin
      J:=Doc.ComponentCount;
      Doc.AddComponent(Work.Component(I).Footprint,Work.Component(I).X,Work.Component(I).Y);
      Doc.Component(J).Rotation:=Work.Component(I).Rotation;
      Doc.Component(J).Flipped:=Work.Component(I).Flipped;
      Doc.Component(J).Ref:=Work.Component(I).Ref;
    end;
    Doc.Changed;
  finally Work.Free;end;
end;
end.
