program test_rig_motion;

{$mode objfpc}{$H+}{$codepage utf8}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, fpjson, jsonparser, multicad_types, multicad_rig,
  multicad_motion, multicad_rigscript, multicad_skin, multicad_mesh,
  multicad_document, multicad_generatedmesh, multicad_rigai;

var Checks: Integer;

procedure Check(Condition: Boolean; const Message: string);
begin
  Inc(Checks);
  if not Condition then raise Exception.Create('FALHOU: '+Message);
end;

function MakeRig: TCadRig;
var S: TCadRigSegment;
begin
  Result:=TCadRig.Create;
  S:=CadDefaultSegment('root'); S.Pivot:=V3(0,0,0); S.Tip:=V3(0,10,0); Result.Add(S);
  S:=CadDefaultSegment('arm'); S.ParentID:='root'; S.Pivot:=V3(0,10,0); S.Tip:=V3(10,10,0); Result.Add(S);
  Result.Validate;
end;

procedure TestRig;
var R,T: TCadRig; S: TCadRigSegment; M: TCadRigMatrices; P: TCadVec3;
    D: TJSONObject; Failed: Boolean;
begin
  R:=MakeRig; T:=TCadRig.Create;
  try
    R.SetAngle('root',90); R.SetAngle('arm',90); M:=R.Matrices;
    P:=MatPoint(M[1],V3(10,10,0));
    Check(VSame(P,V3(-20,0,0),1e-6),'hierarquia aplica pivô e rotação do pai');
    P:=MatPoint(R.Matrices[1],V3(10,10,0));
    Check(VSame(P,V3(-20,0,0),1e-6),'avaliação repetida não acumula rotações');
    R.ResetPose; Check(VSame(MatPoint(R.Matrices[1],V3(10,10,0)),V3(10,10,0)),'repouso conserva geometria');
    S:=R[1]; S.Axis:=jaX; S.MinAngle:=-10; S.MaxAngle:=40; R[1]:=S;
    Failed:=False; try R.SetAngle('arm',45); except Failed:=True; end;
    Check(Failed and (R[1].Angle=0),'limites recusam rotação sem alterar pose');
    R.SetAngle('arm',30); P:=MatPoint(R.Matrices[1],V3(0,11,0));
    Check((Abs(P.X)<1e-8) and (P.Z>0),'junta respeita eixo único X');
    D:=R.ToJSON;
    try T.LoadJSON(D); finally D.Free; end;
    Check((T.Count=2) and (T[1].Axis=jaX) and (T[1].Angle=30),'JSON preserva eixo e pose');
    S:=T[0]; S.ParentID:='arm'; T[0]:=S;
    Failed:=False; try T.Validate; except Failed:=True; end;
    Check(Failed,'ciclo é rejeitado');
    D:=R.ToJSON;
    try
      D.Arrays['segments'].Objects[1].Strings['parent']:='inexistente';
      Failed:=False; try R.LoadJSON(D); except Failed:=True; end;
      Check(Failed and (R[1].ParentID='root'),'JSON inválido não destrói esqueleto aberto');
      D.Arrays['segments'].Objects[1].Strings['parent']:='root';
      D.Arrays['segments'].Objects[1].Strings['id']:='root';
      Failed:=False; try R.LoadJSON(D); except Failed:=True; end;
      Check(Failed,'IDs duplicados rejeitados');
    finally D.Free; end;
    Failed:=False; try R.Delete(0); except Failed:=True; end;
    Check(Failed and (R.Count=2),'pai com filhos não é removido');
  finally R.Free; T.Free; end;
end;

procedure TestSkin;
var R: TCadRig; Mesh,Posed: TCadMesh; Skin: TCadSkin; S: TCadRigSegment;
begin
  R:=TCadRig.Create; Mesh:=CadMakeBox(V3(0,0,0),V3(10,10,10),'piece');
  try
    S:=CadDefaultSegment('hinge'); S.FacePrefixes:='piece/'; R.Add(S);
    Skin:=TCadSkin.Create(Mesh,R);
    try
      R.SetAngle('hinge',90); Posed:=Skin.Pose(R);
      try
        Check(VSame(Posed.Verts[0],MatPoint(R.Matrices[0],Mesh.Verts[0])),'faces vinculadas movem com segmento');
        Check(Abs(Posed.Volume-Mesh.Volume)<1e-6,'rotação rígida conserva volume');
        Check(VSame(Mesh.Bounds.Min,V3(0,0,0)) and VSame(Mesh.Bounds.Max,V3(10,10,10)),'CAD original não foi deformado');
      finally Posed.Free; end;
    finally Skin.Free; end;
  finally R.Free; Mesh.Free; end;
end;

procedure TestMotion;
var R,B: TCadRig; M,N: TCadMotion; D: TJSONObject; Failed: Boolean;
begin
  R:=MakeRig; B:=R.Clone; M:=TCadMotion.Create; N:=TCadMotion.Create;
  try
    M.AddKey('arm',jaZ,0,0); M.AddKey('arm',jaZ,1000,90); M.Validate(R);
    M.Evaluate(500,R,B); Check(Abs(R[1].Angle-45)<1e-6,'interpolação no tempo absoluto');
    M.Loop:=True; M.Evaluate(1500,R,B); Check(Abs(R[1].Angle-45)<1e-6,'ciclo independente dos quadros');
    M.Loop:=False; M.ReturnToBase:=True; M.Evaluate(1000,R,B);
    Check(R[1].Angle=0,'retorno à pose base');
    D:=M.ToJSON;
    try
      N.LoadJSON(D,R); Check((Length(N.Tracks)=1) and (N.DurationMS=1000),'formato Assistente preservado');
      D.Arrays['tracks'].Objects[0].Strings['axis']:='x';
      Failed:=False; try N.LoadJSON(D,R); except Failed:=True; end;
      Check(Failed,'movimento não contorna o eixo fixo');
      D.Arrays['tracks'].Objects[0].Strings['axis']:='z';
      D.Arrays['tracks'].Objects[0].Strings['bone']:='missing';
      Failed:=False; try N.LoadJSON(D,R); except Failed:=True; end;
      Check(Failed,'ossos desconhecidos não são ignorados');
    finally D.Free; end;
  finally R.Free; B.Free; M.Free; N.Free; end;
end;

procedure TestPascal;
var R,B: TCadRig; M: TCadMotion; Err: string;
begin
  R:=MakeRig; B:=R.Clone;
  try
    Check(CompileCadMotion('var I: Integer; begin for I:=1 to 3 do begin MoverSegmento(''arm'',30,100); MoverSegmento(''arm'',0,100); end; Esperar(100); end.',R,M,Err),'Pascal real com variáveis e laços: '+Err);
    try
      Check(M.DurationMS=700,'duração da sequência Pascal');
      M.Evaluate(50,R,B); Check(Abs(R[1].Angle-15)<1e-6,'Pascal produz movimento interpolado');
    finally M.Free; end;
    R.ResetPose;
    Check(CompileCadMotion('begin Esperar(1000); DefinirAngulo(''arm'',30); end.',R,M,Err),'atribuição de ângulo após espera compila');
    try
      M.Evaluate(500,R,B); Check(R[1].Angle=0,'DefinirAngulo não transforma espera anterior em movimento');
      M.Evaluate(1000,R,B); Check(R[1].Angle=30,'DefinirAngulo aplica no instante solicitado');
    finally M.Free; end;
    R.ResetPose;
    Check(not CompileCadMotion('begin while True do ; end.',R,M,Err),'laço infinito interrompido');
    Check(Pos('limite',Err)>0,'limite de execução tem diagnóstico');
    Check(not CompileCadMotion('begin DefinirAngulo(''arm'',400); end.',R,M,Err),'scripts respeitam limites da junta');
    Check(R[1].Angle=0,'erro no script preserva pose do projeto');
    Check(not CompileCadMotion('begin DeleteFile(''arquivo''); end.',R,M,Err),'API de scripts não expõe arquivos');
  finally R.Free; B.Free; end;
end;

procedure TestDocument;
var Doc,Other: TCadDocument; R: TCadRig; Err,JSONText: string; D: TJSONData;
begin
  Doc:=TCadDocument.Create; Other:=TCadDocument.Create; R:=MakeRig;
  try
    Doc.Rig.Assign(R); Doc.Rig.Script:=CadMotionScriptExample('arm');
    JSONText:=Doc.ToJSON;
    Check(Other.LoadFromJSON(JSONText,Err),'documento com rig abre: '+Err);
    Check((Other.Rig.Count=2) and (Other.Rig.Script=Doc.Rig.Script),'documento conserva esqueleto e script');
    D:=GetJSON(JSONText);
    try
      TJSONObject(D).Objects['rig'].Arrays['segments'].Objects[0].Strings['parent']:='arm';
      Check(not Other.LoadFromJSON(D.AsJSON,Err),'documento com ciclo rejeitado');
      Check((Other.Count=4) and (Other.Rig.Count=2) and (Other.Rig[0].ParentID=''),'carga inválida é transacional');
      TJSONObject(D).Delete('rig');
      Check(Other.LoadFromJSON(D.AsJSON,Err) and (Other.Rig.Count=0),'documentos antigos sem rig continuam válidos');
    finally D.Free; end;
  finally Doc.Free; Other.Free; R.Free; end;
end;

procedure TestAI;
var R,T: TCadRig; O,Reply: TJSONObject; A: TJSONArray; Mesh: TCadMesh;
    D: TJSONData; Failed: Boolean; Job: TCadRigAIJob;
begin
  R:=MakeRig; Reply:=TJSONObject.Create;
  try
    O:=R.ToJSON;
    try
      A:=TJSONArray.Create; Reply.Add('choices',A);
      A.Add(TJSONObject.Create(['message',TJSONObject.Create(['content','```json'+#10+O.AsJSON+#10+'```'])]));
      T:=ParseCadRigAIResponse(Reply.AsJSON);
      try Check(T.Count=2,'IA entrega proposta JSON validada'); finally T.Free; end;
      O.Arrays['segments'].Objects[1].Strings['parent']:='missing';
      Reply.Arrays['choices'].Objects[0].Objects['message'].Strings['content']:=O.AsJSON;
      Failed:=False; try T:=ParseCadRigAIResponse(Reply.AsJSON); T.Free; except Failed:=True; end;
      Check(Failed,'IA não injeta uma hierarquia inválida');
    finally O.Free; end;
    Mesh:=CadMakeBox(V3(-1,0,-1),V3(1,10,1),'avatar');
    try
      D:=GetJSON(CadRigGeometryContext([Mesh]));
      try
        Check((D.FindPath('up_axis').AsString='y') and (D.FindPath('units').AsString='mm'),'IA recebe coordenadas e unidades explícitas');
        Check(D.FindPath('bodies[0].sampled_vertices').Count<=256,'geometria enviada é amostrada');
        Check(D.FindPath('bodies[0].face_names').Count=6,'IA recebe nomes de faces existentes para vincular partes');
      finally D.Free; end;
      if ParamCount>0 then
      begin
        Job:=TCadRigAIJob.Create(CadRigGeometryContext([Mesh]),'braço articulado',ParamStr(1),'','fixture-model');
        try
          Job.Start; Job.WaitFor;
          Check(Job.ErrorMessage='','requisição IA local: '+Job.ErrorMessage);
          T:=Job.TakeRig;
          try Check((T<>nil) and (T.Count=2),'resposta HTTP vira esqueleto utilizável'); finally T.Free; end;
        finally Job.Free; end;
      end;
    finally Mesh.Free; end;
  finally R.Free; Reply.Free; end;
end;

begin
  try
    TestRig; TestSkin; TestMotion; TestPascal; TestDocument; TestAI;
    WriteLn('PASS: ',Checks,' verificações de esqueleto, malha, Pascal, movimento, persistência e IA.');
  except
    on E: Exception do begin WriteLn(E.Message); Halt(1); end;
  end;
end.
