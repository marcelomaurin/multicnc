program test_avatar;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,Math,fpjson,jsonparser,
 multicad_types,multicad_mesh,multicad_rig,multicad_motion,multicad_rigscript,
 multicad_avatar,multicad_avatarimport,multicad_avatarmesh,multicad_skin,multicad_document,
 multicad_generatedmesh,multicad_export,multicad_rigai;
var Checks:Integer;
procedure Check(OK:Boolean;const Message:string);
begin Inc(Checks);if not OK then raise Exception.Create('FAIL: '+Message);end;
function Fixture(const Name:string):string;
begin Result:='multicad/tests/fixtures/'+Name;if not FileExists(Result) then Result:=ExtractFilePath(ParamStr(0))+'fixtures/'+Name;end;
function ReadText(const Path:string):string;
var L:TStringList;
begin L:=TStringList.Create;try L.LoadFromFile(Path);Result:=L.Text;finally L.Free;end;end;

procedure TestNative;
var A:TCadAvatarMesh;R,B:TCadRig;M,P:TCadMesh;S:TCadSkin;Motion:TCadMotion;Err,JSONText:string;
    Doc,Other:TCadDocument;I:Integer;O:TJSONData;OldWidth:Double;
begin
 CadGenerateHumanoid(1800,A,R);M:=nil;B:=nil;Motion:=nil;Doc:=TCadDocument.Create;Other:=TCadDocument.Create;
 try
  R.Validate;M:=A.BuildMesh;Check(Abs(BoxSize(M.Bounds).Y-1800)<1e-6,'altura nativa de 1800 mm');
  Check(M.VertCount>1000,'malha nativa criada');Check(R.Count>128,'esqueleto com mais de 128 segmentos');
  Check(R.ChannelIndex('finger5-3.R',jaX)>=0,'dedos articulados');Check(R.ChannelIndex('head',jaY)>=0,'cabeça possui canais X/Y separados');
  B:=R.Clone;Check(CompileCadMotion(R.Script,R,Motion,Err),'script simultâneo: '+Err);
  Motion.Evaluate(400,R,B);Check(Abs(R[R.ChannelIndex('upperarm01.L',jaZ)].Angle-32.5)<1e-8,'braço esquerdo na metade');
  Check(Abs(R[R.ChannelIndex('upperarm01.R',jaZ)].Angle+32.5)<1e-8,'braço direito simultâneo');
  Check(Motion.DurationMS=2000,'grupo paralelo não soma durações');
  S:=TCadSkin.Create(M,R);try P:=S.Pose(R);try Check(VDist(P.Verts[400],M.Verts[400])>1,'malha acompanha movimento');finally P.Free;end;finally S.Free;end;
  R.ResetPose;Motion.Free;Motion:=nil;B.Free;B:=nil;OldWidth:=BoxSize(M.Bounds).X;M.Free;M:=nil;
  CadResizeAvatar(A,R,900,True);M:=A.BuildMesh;
  Check(Abs(BoxSize(M.Bounds).Y-900)<1e-6,'ajuste por altura');Check(Abs(BoxSize(M.Bounds).X-OldWidth/2)<1e-6,'proporções preservadas');Check(Abs(M.Bounds.Min.Y)<1e-6,'base no chão');
  Check(Abs(R[R.IndexOf('root')].Pivot.Y-459)<1e-6,'esqueleto redimensionado junto');
  Doc.AddFeature(A);A:=nil;Doc.Rig.Assign(R);JSONText:=Doc.ToJSON;
  Check(Other.LoadFromJSON(JSONText,Err),'reabrir avatar: '+Err);Check(Other[4] is TCadAvatarMesh,'tipo de avatar persistido');
  P:=TCadAvatarMesh(Other[4]).BuildMesh;try Check(Abs(BoxSize(P.Bounds).Y-900)<1e-6,'altura persistida');Check(Length(P.SkinJoints)=Length(M.SkinJoints),'pesos persistidos');finally P.Free;end;
  O:=GetJSON(Other.Rig.AnimationsJSON);try Check(O.Count=4,'biblioteca nativa persistida');finally O.Free;end;
 finally Other.Free;Doc.Free;Motion.Free;B.Free;M.Free;R.Free;A.Free;end;
end;

procedure TestTiming;
var R,B:TCadRig;S:TCadRigSegment;M:TCadMotion;Err:string;
begin
 R:=TCadRig.Create;B:=nil;M:=nil;
 try
  S:=CadDefaultSegment('arm');R.Add(S);B:=R.Clone;
  Check(CompileCadMotion('begin Esperar(1000); DefinirAngulo(''arm'',30); DefinirAngulo(''arm'',60); end.',R,M,Err),Err);
  M.Evaluate(500,R,B);Check(R[0].Angle=0,'atribuições repetidas não antecipam espera');M.Evaluate(1000,R,B);Check(R[0].Angle=60,'última atribuição prevalece');M.Free;M:=nil;R.ResetPose;
  Check(not CompileCadMotion('begin IniciarSimultaneo; MoverSegmento(''arm'',20,100); end.',R,M,Err),'grupo incompleto rejeitado');
  Check(not CompileCadMotion('begin IniciarSimultaneo; MoverSegmento(''arm'',20,100); MoverSegmento(''arm'',40,100); FinalizarSimultaneo; end.',R,M,Err),'canais sobrepostos rejeitados');
  M:=TCadMotion.Create;M.ReturnToBase:=True;M.ReturnMS:=320;M.AddKey('arm',jaZ,0,0);M.AddKey('arm',jaZ,1000,60);
  M.Evaluate(1000,R,B);Check(Abs(R[0].Angle-60)<1e-8,'retorno não salta no último quadro');M.Evaluate(1160,R,B);Check(Abs(R[0].Angle-30)<1e-8,'retorno suave');M.Evaluate(1320,R,B);Check(R[0].Angle=0,'retorno concluído');
  M.Loop:=True;M.Smooth:=False;M.EntryMS:=320;M.Evaluate(1100,R,B);Check(Abs(R[0].Angle-6)<1e-8,'entrada suave acontece uma vez, sem reiniciar em cada ciclo');
 finally M.Free;B.Free;R.Free;end;
end;

procedure TestImport(const Path:string;Reference:Boolean);
var A:TCadAvatarMesh;R,B:TCadRig;M,P:TCadMesh;Skin:TCadSkin;LibraryData,D,Expected:TJSONData;Motion:TCadMotion;
    I,J,Wave:Integer;Notes,Err,ExportDir:string;Doc,Other:TCadDocument;F:TFileStream;V:TCadVec3;Q:TCadRigSegment;W:TCadVertexWeights;
begin
 A:=nil;R:=nil;B:=nil;M:=nil;Motion:=nil;Doc:=nil;Other:=nil;
 try
  CadImportAvatar(Path,A,R,Notes);R.Validate;M:=A.BuildMesh;B:=R.Clone;
  Check(Length(M.SkinVertices)>=M.VertCount,'pesos por vértice importados');
  Skin:=TCadSkin.Create(M,R);try P:=Skin.Pose(R);try for I:=0 to M.VertCount-1 do Check(VDist(P.Verts[I],M.Verts[I])<0.01,'pose neutra conserva vértice');finally P.Free;end;finally Skin.Free;end;
  LibraryData:=GetJSON(R.AnimationsJSON);
  try
   if Reference then Check(LibraryData.Count=1,'animação do fixture') else Check(LibraryData.Count=65,'65 animações do Assistente');
   Wave:=0;if not Reference then for I:=0 to LibraryData.Count-1 do if TJSONObject(LibraryData.Items[I]).Get('name','')='wave' then Wave:=I;
   D:=CadAnimationData(LibraryData.Items[Wave]);Motion:=TCadMotion.Create;
   try Motion.LoadJSON(D,R);finally D.Free;end;
  finally LibraryData.Free;end;
  Motion.EntryMS:=0;Motion.ReturnToBase:=False;Motion.Evaluate(1000,R,B);Skin:=TCadSkin.Create(M,R);
  try
   P:=Skin.Pose(R);
   try
    if Reference then begin
     Expected:=GetJSON(ReadText(Fixture('avatar-small.expected.json')));
     try for I:=0 to Expected.Count-1 do begin V:=V3(Expected.Items[I].Items[0].AsFloat,Expected.Items[I].Items[1].AsFloat,Expected.Items[I].Items[2].AsFloat);Check(VDist(P.Verts[I],V)<0.001,'quatro pesos, base girada e translação com escala');end;finally Expected.Free;end;
    end else begin
     ExportDir:=GetEnvironmentVariable('MULTICAD_AVATAR_PROBE_DIR');
     if ExportDir<>'' then begin F:=TFileStream.Create(IncludeTrailingPathDelimiter(ExportDir)+ExtractFileName(ExtractFileDir(Path))+'.posed.bin',fmCreate);
      try for I:=0 to P.VertCount-1 do begin V:=P.Verts[I];F.WriteBuffer(V,SizeOf(V));end;finally F.Free;end;
     end;
    end;
   finally P.Free;end;
  finally Skin.Free;end;
  R.ResetPose;Motion.Free;Motion:=nil;B.Free;B:=nil;
  if Reference then begin
   CadResizeAvatar(A,R,500,True);M.Free;M:=A.BuildMesh;Check(Abs(BoxSize(M.Bounds).Y-500)<1e-5,'altura glTF redimensionada');
   LibraryData:=GetJSON(R.AnimationsJSON);D:=CadAnimationData(LibraryData.Items[0]);Motion:=TCadMotion.Create;B:=R.Clone;
   try Motion.LoadJSON(D,R);Motion.EntryMS:=0;Motion.ReturnToBase:=False;Motion.Evaluate(1000,R,B);Check(Abs(R[R.ChannelIndex('arm',jaY,jkTranslation)].Angle-1000)<0.001,'translação acompanha nova altura');
   finally D.Free;LibraryData.Free;end;
   R.ResetPose;Doc:=TCadDocument.Create;Other:=TCadDocument.Create;Doc.AddFeature(A);A:=nil;Doc.Rig.Assign(R);
   Check(Other.LoadFromJSON(Doc.ToJSON,Err),'glTF incorporado reabre: '+Err);P:=TCadAvatarMesh(Other[4]).BuildMesh;
   try Check(P.SkinVertices[0].HasBindPoints,'matrizes de vínculo persistidas');finally P.Free;end;
  end;
  WriteLn('PASS import: ',Path,'; segments=',R.Count,'; height_mm=',BoxSize(M.Bounds).Y:0:2,'; notes=',Notes);
 finally Other.Free;Doc.Free;Motion.Free;B.Free;M.Free;R.Free;A.Free;end;
end;

procedure TestAIEdit;
var A:TCadAvatarMesh;R,T:TCadRig;Reply,Cell,Message:TJSONObject;Choices:TJSONArray;Failed:Boolean;
begin
 CadGenerateHumanoid(1800,A,R);T:=nil;Reply:=TJSONObject.Create;
 try
  Message:=TJSONObject.Create;Message.Add('content','{"format":"multicad-rig-edit","version":1,"changes":[{"bone":"head","axis":"y","angle":25}]}');
  Cell:=TJSONObject.Create;Cell.Add('message',Message);Choices:=TJSONArray.Create;Choices.Add(Cell);Reply.Add('choices',Choices);
  T:=ParseCadRigAIResponse(Reply.AsJSON,R);
  Check((T.Count=R.Count) and (T.AnimationsJSON=R.AnimationsJSON),'IA preserva hierarquia e biblioteca');
  Check(T[T.ChannelIndex('head',jaY)].Angle=25,'IA ajusta eixo indicado');Check(R[R.ChannelIndex('head',jaY)].Angle=0,'proposta de IA não altera original');
  T.Free;T:=nil;Message.Strings['content']:='{"format":"multicad-rig-edit","version":1,"changes":[{"bone":"inexistente","axis":"y","angle":25}]}';
  Failed:=False;try T:=ParseCadRigAIResponse(Reply.AsJSON,R);except Failed:=True;end;Check(Failed,'IA não cria referência a osso inexistente');
 finally Reply.Free;T.Free;R.Free;A.Free;end;
end;

procedure TestHeightReference;
var M,P:TCadMesh;F:TCadGeneratedMesh;Path,Err:string;S:TFileStream;Raw:RawByteString;
begin
 M:=CadMakeBox(V3(0,0,0),V3(400,100,200),'wide');F:=TCadGeneratedMesh.Create;Path:=GetTempDir+'multicad-avatar-size-'+IntToStr(GetTickCount64)+'.stl';
 try
  Check(CadExportSTL([M],Path,True,soYToZ,V3(0,0,0),'size',Err),Err);
  S:=TFileStream.Create(Path,fmOpenRead);try SetLength(Raw,S.Size);S.ReadBuffer(Raw[1],S.Size);finally S.Free;end;
  F.SetSTL(Raw);F.SizeMM:=1800;F.SizeReference:='height';P:=F.BuildMesh;
  try Check(Abs(BoxSize(P.Bounds).Y-1800)<1e-5,'altura definida pelo Y, não pela largura');Check(Abs(BoxSize(P.Bounds).X-7200)<1e-5,'escala uniforme preserva proporção 4:1');finally P.Free;end;
  F.SizeReference:='max';P:=F.BuildMesh;try Check(Abs(BoxSize(P.Bounds).Y-450)<1e-5,'referência antiga continua compatível');finally P.Free;end;
 finally DeleteFile(Path);F.Free;M.Free;end;
end;
var I:Integer;
begin
 try
  TestNative;TestTiming;TestHeightReference;TestAIEdit;TestImport(Fixture('avatar-small.gltf'),True);TestImport(Fixture('avatar-small.glb'),True);
  for I:=1 to ParamCount do TestImport(ParamStr(I),False);
  WriteLn('PASS: ',Checks,' avatar, skin, motion, persistence and relative-height checks.');
 except on E:Exception do begin WriteLn(E.Message);Halt(1);end;end;
end.
