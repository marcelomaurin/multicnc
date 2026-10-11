unit laserpcb_components;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils,Math,fpjson,jsonparser,makepcb_model,makepcb_library,
  laserpcb_project,laserpcb_geom,laserpcb_gerber,laserpcb_excellon;
function LPSharedLibraryFile:string;
function LPImportComponentLibrary(Lib:TMPLibrary;const FileName:string):Integer;
procedure LPLoadComponentSet(Doc:TMPDocument;Lib:TMPLibrary;const Text:string);
procedure LPApplyComponents(Doc:TMPDocument;Project:TLaserPCBProject);
implementation
uses makepcb_gerber;
function SharedAppName:string;
begin Result:='makepcb';end;
function LPSharedLibraryFile:string;
var Previous:TGetAppNameEvent;
begin
  Previous:=OnGetApplicationName;OnGetApplicationName:=@SharedAppName;
  try Result:=MPUserLibraryFile;finally OnGetApplicationName:=Previous;end;
end;
function LPImportComponentLibrary(Lib:TMPLibrary;const FileName:string):Integer;
var S:TStringList;D:TJSONData;A:TJSONArray;F:TMPFootprint;Pending:TList;I,J:Integer;
begin
  Result:=0;S:=TStringList.Create;Pending:=TList.Create;D:=nil;
  try
    S.LoadFromFile(FileName);D:=GetJSON(S.Text);
    if not(D is TJSONObject) then raise Exception.Create('Biblioteca de componentes invalida.');
    if TJSONObject(D).Get('format','')<>'makepcb-library' then
      raise Exception.Create('Selecione uma biblioteca makepcb-library (JSON).');
    if TJSONObject(D).Get('version',1)<>1 then raise Exception.Create('Versao de biblioteca nao suportada.');
    A:=TJSONObject(D).Get('footprints',TJSONArray(nil));
    if (A=nil) or (A.Count=0) then raise Exception.Create('Biblioteca sem componentes.');
    for I:=0 to A.Count-1 do begin
      if not(A.Items[I] is TJSONObject) then raise Exception.Create('Componente invalido.');
      F:=TMPFootprint.Create;Pending.Add(F);F.LoadFromJSON(A.Objects[I]);
      if Trim(F.Name)='' then raise Exception.Create('Componente sem nome.');
      if (Lib.Find(F.Name)<>nil) and not Lib.Find(F.Name).UserDefined then
        raise Exception.Create('Nome reservado pela biblioteca: '+F.Name);
      for J:=0 to I-1 do if SameText(TMPFootprint(Pending[J]).Name,F.Name) then
        raise Exception.Create('Nome repetido no conjunto: '+F.Name);
      for J:=0 to High(F.Pads) do with F.Pads[J] do
        if IsNan(X) or IsInfinite(X) or IsNan(Y) or IsInfinite(Y) or
          IsNan(W) or IsInfinite(W) or IsNan(H) or IsInfinite(H) or
          IsNan(Drill) or IsInfinite(Drill) or (W<=0) or(H<=0) or(Drill<0) then
          raise Exception.Create('Dimensoes invalidas: '+F.Name);
    end;
    Result:=Pending.Count;
    for I:=0 to Pending.Count-1 do begin F:=TMPFootprint(Pending[I]);Lib.AddUser(F);Pending[I]:=nil;end;
  finally for I:=0 to Pending.Count-1 do TObject(Pending[I]).Free;Pending.Free;D.Free;S.Free;end;
end;
procedure LPLoadComponentSet(Doc:TMPDocument;Lib:TMPLibrary;const Text:string);
var D:TJSONData;O:TJSONObject;Temp:TMPDocument;
begin
  D:=GetJSON(Text);Temp:=TMPDocument.Create;
  try
    if not(D is TJSONObject) then raise Exception.Create('Conjunto de componentes invalido.');
    O:=TJSONObject(D);
    O.Delete('tracks');O.Delete('areas');O.Delete('wires');O.Delete('texts');O.Delete('schematic');
    Temp.FromJSON(O.AsJSON,@Lib.Resolve);
    Doc.FromJSON(Temp.ToJSON,@Lib.Resolve);
  finally Temp.Free;D.Free;end;
end;
procedure LPApplyComponents(Doc:TMPDocument;Project:TLaserPCBProject);
var Top,Bottom,SilkTop,SilkBottom,L:TLPGerberLayer;Holes,D:TLPDrillFile;
  I,J,Count:Integer;C:TMPComponent;B:TMPRect;Q:TMPPoint;P:TLPPath;
  Shape:TLPGShape;K:TMPSilk;
  procedure Stroke(const Local:TLPPath;Width:Double);
  var A:Integer;W:TLPPath;
  begin
    W:=nil;
    for A:=0 to High(Local) do begin Q:=C.LocalToWorld(Local[A].X,Local[A].Y);LPAddPoint(W,Q.X+Project.OriginX,Q.Y+Project.OriginY);end;
    L.AddTrace(W,Width);
    for A:=1 to High(W) do begin
      Shape.Dark:=True;SetLength(Shape.Items,1);Shape.Items[0].Dark:=True;
      Shape.Items[0].Paths:=nil;
      LPAddPath(Shape.Items[0].Paths,LPCapsule(W[A-1].X,W[A-1].Y,W[A].X,W[A].Y,Width,0.01));L.AddShape(Shape);
    end;
  end;
begin
  if Project.HasSVG or(Project.Width<=0) then raise Exception.Create('Crie ou importe uma placa antes dos componentes.');
  for I:=0 to Doc.ComponentCount-1 do begin
    C:=Doc.Component(I);
    if (C.Footprint=nil) or IsNan(C.X) or IsInfinite(C.X) or IsNan(C.Y) or IsInfinite(C.Y) or
      (C.Rotation mod 90<>0) then raise Exception.Create('Posicao ou rotacao invalida: '+C.Ref);
    B:=C.Bounds;
    if not B.Valid or (B.MinX<0) or(B.MinY<0) or(B.MaxX>Project.Width) or(B.MaxY>Project.Height) then
      raise Exception.Create('Componente fora da placa: '+C.Ref);
    for J:=0 to High(C.Footprint.Pads) do with C.Footprint.Pads[J] do
      if IsNan(W) or IsInfinite(W) or IsNan(H) or IsInfinite(H) or(W<=0) or(H<=0) or
        IsNan(Drill) or IsInfinite(Drill) or(Drill<0) then raise Exception.Create('Pad invalido: '+C.Ref);
  end;
  Top:=TLPGerberLayer.Create;Bottom:=TLPGerberLayer.Create;
  SilkTop:=TLPGerberLayer.Create;SilkBottom:=TLPGerberLayer.Create;
  Holes:=TLPDrillFile.Create;D:=TLPDrillFile.Create;
  try
    TLPGerberReader.LoadFromString(MPCopperGerber(Doc,mlTopCopper),Top);
    TLPGerberReader.LoadFromString(MPCopperGerber(Doc,mlBottomCopper),Bottom);
    Top.Transform(LPTranslate(Project.OriginX,Project.OriginY));
    Bottom.Transform(LPTranslate(Project.OriginX,Project.OriginY));
    for I:=0 to 1 do begin
      D.Clear;TLPExcellonReader.LoadFromString(MPDrillFile(Doc,I=0,Count),D);
      D.Plated:=I=0;for J:=0 to High(D.Tools) do D.Tools[J].Plated:=I=0;
      Holes.Merge(D);
    end;
    Holes.Transform(LPTranslate(Project.OriginX,Project.OriginY));
    for I:=0 to Doc.ComponentCount-1 do begin
      C:=Doc.Component(I);if C.Flipped then L:=SilkBottom else L:=SilkTop;
      for J:=0 to High(C.Footprint.Silk) do begin
        K:=C.Footprint.Silk[J];P:=nil;
        case K.Kind of
          skLine:begin LPAddPoint(P,K.X1,K.Y1);LPAddPoint(P,K.X2,K.Y2);end;
          skRect:P:=LPRectPath((K.X1+K.X2)/2,(K.Y1+K.Y2)/2,Abs(K.X2-K.X1),Abs(K.Y2-K.Y1));
          skCircle:P:=LPCircle(K.X1,K.Y1,K.R,0.01);
        end;
        Stroke(P,MP_SILK_WIDTH);
      end;
    end;
    Project.SetComponentGeometry(Top,Bottom,SilkTop,SilkBottom,Holes,Doc.ToJSON);
  finally D.Free;Holes.Free;SilkBottom.Free;SilkTop.Free;Bottom.Free;Top.Free;end;
end;
end.
