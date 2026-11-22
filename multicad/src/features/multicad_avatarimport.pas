unit multicad_avatarimport;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,multicad_avatarmesh,multicad_rig;
{ Imports a self-contained .gltf/.glb or an Assistente avatar.json.
  Geometry, skin weights and animation clips become part of the .mcad. }
procedure CadImportAvatar(const FileName:string;out Avatar:TCadAvatarMesh;out Rig:TCadRig;out Notes:string);
implementation
uses Classes,Math,Base64,fpjson,jsonparser,multicad_types,multicad_mesh,multicad_motion,multicad_posemath;
const MaxFile=96*1024*1024;
type
  TNumbers=array of Double;
  TAccessor=record Count,Width:Integer;Values:TNumbers;end;
  TNode=record
    ID:string;Parent:Integer;State:Byte;Active:Boolean;
    World,Local:TCadMat4;RestQ:TCadQuat;RestP:TCadVec3;
  end;
  TReader=class
  private
    Root:TJSONObject;BaseDir:string;Buffers:array of RawByteString;Nodes:array of TNode;
    Accessors:array of TAccessor;Cached:array of Boolean;
    function ReadAccessor(Index:Integer):TAccessor;
    procedure ReadNodes;
    procedure ReadGeometry(M:TCadMesh);
    procedure ReadAnimations(Rig:TCadRig);
  public
    Notes:string;
    constructor Create(const FileName:string);
    destructor Destroy;override;
    procedure Build(out Avatar:TCadAvatarMesh;out Rig:TCadRig);
  end;

function ObjectOf(D:TJSONData;const Name:string):TJSONObject;
begin if not (D is TJSONObject) then raise Exception.Create(Name+': objeto inválido.');Result:=TJSONObject(D);end;
function ArrayOf(D:TJSONData;const Name:string):TJSONArray;
begin if not (D is TJSONArray) then raise Exception.Create(Name+': lista inválida.');Result:=TJSONArray(D);end;
function Item(A:TJSONArray;I:Integer):TJSONData;
begin if (I<0) or (I>=A.Count) then raise Exception.Create('Índice fora da lista glTF.');Result:=A.Items[I];end;
function ReadBytes(const Path:string):RawByteString;
var S:TFileStream;
begin
 S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
 try if S.Size>MaxFile then raise Exception.Create('Arquivo de avatar excede 96 MB.');SetLength(Result,S.Size);if S.Size>0 then S.ReadBuffer(Result[1],S.Size);finally S.Free;end;
end;
function LocalPath(const Base,Relative:string):string;
begin
 if (Relative='') or (Pos(':',Relative)>0) or (Relative[1]='/') or (Relative[1]='\') then raise Exception.Create('Use um arquivo local na pasta do avatar.');
 Result:=ExpandFileName(IncludeTrailingPathDelimiter(Base)+StringReplace(Relative,'/',PathDelim,[rfReplaceAll]));
 if Copy(Result,1,Length(IncludeTrailingPathDelimiter(Base)))<>IncludeTrailingPathDelimiter(Base) then raise Exception.Create('Arquivo fora da pasta do avatar.');
end;
function VectorOf(O:TJSONObject;const Key:string;const Default:TCadVec3):TCadVec3;
begin if O.Find(Key)=nil then Result:=Default else Result:=CadRigVector(O,Key);end;
function QuatOf(D:TJSONData):TCadQuat;
var A:TJSONArray;
begin
 if D=nil then Exit(CadQuat(0,0,0,1));A:=ArrayOf(D,'rotation');if A.Count<>4 then raise Exception.Create('Quaternion inválido.');
 Result:=CadQuat(A.Floats[0],A.Floats[1],A.Floats[2],A.Floats[3]);
end;
function BasisOf(const M:TCadMat4):TCadMat4;
var C,R:Integer;V:TCadVec3;LX,LY,LZ:Double;
begin
 LX:=VLen(MatDir(M,V3(1,0,0)));LY:=VLen(MatDir(M,V3(0,1,0)));LZ:=VLen(MatDir(M,V3(0,0,1)));
 if Max(LX,Max(LY,LZ))-Min(LX,Min(LY,LZ))>Max(LX,Max(LY,LZ))*1e-5 then raise Exception.Create('Aplique a escala não uniforme no editor de origem antes de importar o esqueleto.');
 Result:=MatIdentity;
 for C:=0 to 2 do begin V:=V3(M[0,C],M[1,C],M[2,C]);if VLen(V)<1e-10 then raise Exception.Create('Escala nula no avatar.');V:=VNorm(V);Result[0,C]:=V.X;Result[1,C]:=V.Y;Result[2,C]:=V.Z;end;
end;

constructor TReader.Create(const FileName:string);
var Data,Binary,URI,Path:RawByteString;D:TJSONData;O:TJSONObject;A:TJSONArray;
    I,J,Offset,LengthGLB,ChunkType,ChunkLen:LongWord;Total:Int64;
  function U32(Pos:Integer):LongWord;
  begin if (Pos<1) or (Pos>Length(Data)-3) then raise Exception.Create('GLB incompleto.');Move(Data[Pos],Result,4);Result:=LEtoN(Result);end;
begin
 inherited Create;Path:=ExpandFileName(FileName);BaseDir:=ExtractFileDir(Path);Data:=ReadBytes(Path);
 if SameText(ExtractFileName(Path),'avatar.json') then begin
   D:=GetJSON(Data,True);try O:=ObjectOf(D,'avatar.json');Path:=LocalPath(BaseDir,O.Get('model',''));finally D.Free;end;
   Data:=ReadBytes(Path);BaseDir:=ExtractFileDir(Path);
 end;
 if SameText(ExtractFileExt(Path),'.glb') then begin
   if (Length(Data)<20) or (U32(1)<>$46546C67) or (U32(5)<>2) or (U32(9)<>LongWord(Length(Data))) then raise Exception.Create('Use GLB versão 2 completo.');
   Offset:=13;URI:='';
   while Offset<=LongWord(Length(Data))-7 do begin
     ChunkLen:=U32(Offset);ChunkType:=U32(Offset+4);Inc(Offset,8);
     if (ChunkLen>LongWord(Length(Data))-Offset+1) or (ChunkLen mod 4<>0) then raise Exception.Create('Chunk GLB inválido.');
     if ChunkType=$4E4F534A then begin if URI<>'' then raise Exception.Create('JSON GLB duplicado.');URI:=Copy(Data,Offset,ChunkLen);end
     else if ChunkType=$004E4942 then begin if Binary<>'' then raise Exception.Create('Buffer GLB duplicado.');Binary:=Copy(Data,Offset,ChunkLen);end;
     Inc(Offset,ChunkLen);
   end;
   if Offset<>LongWord(Length(Data))+1 then raise Exception.Create('GLB incompleto.');Data:=URI;
 end;
 D:=GetJSON(Data,True);Root:=ObjectOf(D,'glTF');
 if ObjectOf(Root.Find('asset'),'asset').Get('version','')<>'2.0' then raise Exception.Create('Use glTF versão 2.0.');
 if (Root.Find('extensionsRequired')<>nil) and (ArrayOf(Root.Find('extensionsRequired'),'extensionsRequired').Count>0) then raise Exception.Create('Converta extensões/compressões glTF para geometria padrão antes de importar.');
 A:=ArrayOf(Root.Find('buffers'),'buffers');if A.Count>64 then raise Exception.Create('Buffers demais no avatar.');SetLength(Buffers,A.Count);Total:=0;
 for I:=0 to A.Count-1 do begin
   O:=ObjectOf(A.Items[I],'buffer');URI:=O.Get('uri','');
   if URI='' then begin if I<>0 then raise Exception.Create('Buffer binário ausente.');Buffers[I]:=Binary;end
   else if Copy(URI,1,5)='data:' then begin J:=Pos(';base64,',URI);if J=0 then raise Exception.Create('Buffer embutido precisa usar base64.');Buffers[I]:=DecodeStringBase64(Copy(URI,J+8,Length(URI)),True);end
   else Buffers[I]:=ReadBytes(LocalPath(BaseDir,URI));
   Inc(Total,Length(Buffers[I]));if Total>MaxFile then raise Exception.Create('Buffers do avatar excedem 96 MB.');
   if (O.Get('byteLength',Int64(-1))<0) or (Length(Buffers[I])<O.Get('byteLength',Int64(-1))) then raise Exception.Create('Buffer glTF incompleto.');
 end;
 A:=ArrayOf(Root.Find('accessors'),'accessors');if A.Count>20000 then raise Exception.Create('Accessors demais no avatar.');SetLength(Accessors,A.Count);SetLength(Cached,A.Count);
 ReadNodes;
end;
destructor TReader.Destroy;
begin Root.Free;inherited Destroy;end;

function TReader.ReadAccessor(Index:Integer):TAccessor;
var A,V:TJSONObject;TypeName:string;Component,Bytes,Stride,I,J,N,BufferIndex:Integer;
    Start,EndPos,Offset,ViewEnd:Int64;U:LongWord;H:Word;F:Single;Norm:Boolean;
begin
 if (Index<0) or (Index>=Length(Accessors)) then raise Exception.Create('Accessor glTF inexistente.');
 if Cached[Index] then Exit(Accessors[Index]);
 A:=ObjectOf(Item(Root.Arrays['accessors'],Index),'accessor');
 if A.Find('sparse')<>nil then raise Exception.Create('Converta accessors sparse antes de importar.');
 V:=ObjectOf(Item(ArrayOf(Root.Find('bufferViews'),'bufferViews'),A.Get('bufferView',-1)),'bufferView');
 BufferIndex:=V.Get('buffer',-1);if (BufferIndex<0) or (BufferIndex>=Length(Buffers)) then raise Exception.Create('Buffer inexistente.');
 N:=A.Get('count',0);TypeName:=A.Get('type','');
 if TypeName='SCALAR' then Result.Width:=1 else if TypeName='VEC2' then Result.Width:=2 else if TypeName='VEC3' then Result.Width:=3
 else if TypeName='VEC4' then Result.Width:=4 else if TypeName='MAT4' then Result.Width:=16 else raise Exception.Create('Tipo de accessor não suportado.');
 if (N<1) or (N>500000) then raise Exception.Create('Quantidade inválida no accessor.');Result.Count:=N;
 Component:=A.Get('componentType',0);case Component of 5121:Bytes:=1;5123:Bytes:=2;5125,5126:Bytes:=4;else raise Exception.Create('Tipo numérico glTF não suportado.');end;
 Norm:=A.Get('normalized',False);Stride:=V.Get('byteStride',Bytes*Result.Width);
 if (Stride<Bytes*Result.Width) or (Stride>252) or (Stride mod Bytes<>0) then raise Exception.Create('Passo de accessor inválido.');
 Start:=V.Get('byteOffset',Int64(0));ViewEnd:=Start+V.Get('byteLength',Int64(-1));Offset:=A.Get('byteOffset',Int64(0));
 if (Start<0) or (ViewEnd<Start) or (ViewEnd>Length(Buffers[BufferIndex])) or (Offset<0) then raise Exception.Create('Limites de buffer inválidos.');
 Inc(Start,Offset);EndPos:=Start+Int64(N-1)*Stride+Result.Width*Bytes;
 if (EndPos>ViewEnd) or (Start>EndPos) then raise Exception.Create('Accessor fora do buffer.');SetLength(Result.Values,N*Result.Width);
 for I:=0 to N-1 do for J:=0 to Result.Width-1 do begin
   Offset:=Start+Int64(I)*Stride+J*Bytes+1;
   case Component of
    5121:begin Result.Values[I*Result.Width+J]:=Byte(Buffers[BufferIndex][Offset]);if Norm then Result.Values[I*Result.Width+J]:=Result.Values[I*Result.Width+J]/255;end;
    5123:begin Move(Buffers[BufferIndex][Offset],H,2);Result.Values[I*Result.Width+J]:=LEtoN(H);if Norm then Result.Values[I*Result.Width+J]:=Result.Values[I*Result.Width+J]/65535;end;
    5125:begin Move(Buffers[BufferIndex][Offset],U,4);Result.Values[I*Result.Width+J]:=LEtoN(U);end;
    5126:begin Move(Buffers[BufferIndex][Offset],U,4);U:=LEtoN(U);Move(U,F,4);Result.Values[I*Result.Width+J]:=F;end;
   end;
   if IsNan(Result.Values[I*Result.Width+J]) or IsInfinite(Result.Values[I*Result.Width+J]) or (Abs(Result.Values[I*Result.Width+J])>1e9) then raise Exception.Create('Valor não finito no avatar.');
 end;
 Cached[Index]:=True;Accessors[Index]:=Result;
end;

procedure TReader.ReadNodes;
var A,C:TJSONArray;O:TJSONObject;I,J,K,P:Integer;T,S:TCadVec3;Q:TCadQuat;Names:TStringList;
  procedure World(N:Integer);
  begin
   if Nodes[N].State=2 then Exit;if Nodes[N].State=1 then raise Exception.Create('Ciclo na hierarquia glTF.');Nodes[N].State:=1;
   P:=Nodes[N].Parent;if P>=0 then begin World(P);Nodes[N].World:=MatMul(Nodes[Nodes[N].Parent].World,Nodes[N].Local);end else Nodes[N].World:=Nodes[N].Local;Nodes[N].State:=2;
  end;
  procedure Active(N:Integer);
  var C:TJSONArray;I:Integer;O:TJSONObject;
  begin
   if (N<0) or (N>=Length(Nodes)) then raise Exception.Create('Nó da cena inválido.');if Nodes[N].Active then Exit;Nodes[N].Active:=True;
   O:=ObjectOf(A.Items[N],'node');if O.Find('children')<>nil then begin C:=ArrayOf(O.Find('children'),'children');for I:=0 to C.Count-1 do Active(C.Integers[I]);end;
  end;
begin
 A:=ArrayOf(Root.Find('nodes'),'nodes');if (A.Count=0) or (A.Count>CadRigMaxSegments div 6) then raise Exception.Create('Use um avatar com até 341 nós.');
 SetLength(Nodes,A.Count);Names:=TStringList.Create;Names.Sorted:=True;Names.CaseSensitive:=False;
 try
  for I:=0 to A.Count-1 do begin
   O:=ObjectOf(A.Items[I],'node');Nodes[I].Parent:=-1;Nodes[I].ID:=O.Get('name','node'+IntToStr(I));
   if Nodes[I].ID='' then Nodes[I].ID:='node'+IntToStr(I);
   if Names.IndexOf(Nodes[I].ID)>=0 then Nodes[I].ID:=Nodes[I].ID+'#'+IntToStr(I);Names.Add(Nodes[I].ID);
   if Length(Nodes[I].ID)>100 then raise Exception.Create('Nome de osso excede 100 caracteres.');
   Q:=QuatOf(O.Find('rotation'));Nodes[I].RestQ:=Q;T:=VectorOf(O,'translation',V3(0,0,0));S:=VectorOf(O,'scale',V3(1,1,1));
   Nodes[I].Local:=CadQMatrix(Q);for J:=0 to 2 do begin Nodes[I].Local[J,0]:=Nodes[I].Local[J,0]*S.X;Nodes[I].Local[J,1]:=Nodes[I].Local[J,1]*S.Y;Nodes[I].Local[J,2]:=Nodes[I].Local[J,2]*S.Z;end;
   Nodes[I].Local[0,3]:=T.X;Nodes[I].Local[1,3]:=T.Y;Nodes[I].Local[2,3]:=T.Z;
   if O.Find('matrix')<>nil then begin C:=ArrayOf(O.Find('matrix'),'matrix');if C.Count<>16 then raise Exception.Create('Matriz glTF inválida.');
    for J:=0 to 3 do for K:=0 to 3 do Nodes[I].Local[J,K]:=C.Floats[K*4+J];Nodes[I].RestQ:=CadQFromMatrix(BasisOf(Nodes[I].Local));end;
   Nodes[I].RestP:=V3(Nodes[I].Local[0,3],Nodes[I].Local[1,3],Nodes[I].Local[2,3]);
  end;
  for I:=0 to A.Count-1 do begin O:=ObjectOf(A.Items[I],'node');if O.Find('children')=nil then Continue;C:=ArrayOf(O.Find('children'),'children');
   for J:=0 to C.Count-1 do begin K:=C.Integers[J];if (K<0) or (K>=A.Count) or (Nodes[K].Parent>=0) then raise Exception.Create('Hierarquia glTF inválida.');Nodes[K].Parent:=I;end;
  end;
  for I:=0 to A.Count-1 do World(I);
  if Root.Find('scenes')<>nil then begin O:=ObjectOf(Item(ArrayOf(Root.Find('scenes'),'scenes'),Root.Get('scene',0)),'scene');C:=ArrayOf(O.Find('nodes'),'scene.nodes');for I:=0 to C.Count-1 do Active(C.Integers[I]);end
  else for I:=0 to A.Count-1 do if Nodes[I].Parent<0 then Active(I);
 finally Names.Free;end;
end;

procedure TReader.ReadGeometry(M:TCadMesh);
var N,P,I,J,K,Offset,Face,MeshIndex,SkinIndex,NodeIndex,Vertex,Count:Integer;
    Node,Mesh,Primitive,Attributes,Skin:TJSONObject;Primitives,Joints:TJSONArray;
    Positions,Indices,Weights,JointIDs,IB:TAccessor;W:TCadVertexWeights;Point,BP,Rest:TCadVec3;
    Bind:array of TCadMat4;Matrix:TCadMat4;HasSkin:Boolean;A,B,C:Integer;WeightSum:Double;
begin
 SetLength(M.SkinJoints,Length(Nodes));for I:=0 to High(Nodes) do M.SkinJoints[I]:=Nodes[I].ID;
 for N:=0 to High(Nodes) do begin
  if not Nodes[N].Active then Continue;Node:=ObjectOf(Root.Arrays['nodes'].Items[N],'node');MeshIndex:=Node.Get('mesh',-1);if MeshIndex<0 then Continue;
  Mesh:=ObjectOf(Item(ArrayOf(Root.Find('meshes'),'meshes'),MeshIndex),'mesh');Primitives:=ArrayOf(Mesh.Find('primitives'),'primitives');SkinIndex:=Node.Get('skin',-1);HasSkin:=SkinIndex>=0;
  if HasSkin then begin
   Skin:=ObjectOf(Item(ArrayOf(Root.Find('skins'),'skins'),SkinIndex),'skin');Joints:=ArrayOf(Skin.Find('joints'),'skin.joints');
   SetLength(Bind,Joints.Count);IB:=Default(TAccessor);if Skin.Find('inverseBindMatrices')<>nil then IB:=ReadAccessor(Skin.Get('inverseBindMatrices',-1));
   if (IB.Count>0) and ((IB.Width<>16) or (IB.Count<>Joints.Count)) then raise Exception.Create('Matrizes de vínculo incompatíveis.');
   for I:=0 to Joints.Count-1 do begin
    NodeIndex:=Joints.Integers[I];if (NodeIndex<0) or (NodeIndex>=Length(Nodes)) then raise Exception.Create('Osso do skin inexistente.');Matrix:=MatIdentity;
    if IB.Count>0 then for J:=0 to 3 do for K:=0 to 3 do Matrix[J,K]:=IB.Values[I*16+K*4+J];Bind[I]:=MatMul(Nodes[NodeIndex].World,Matrix);
   end;
  end;
  for P:=0 to Primitives.Count-1 do begin
   Primitive:=ObjectOf(Primitives.Items[P],'primitive');if Primitive.Get('mode',4)<>4 then raise Exception.Create('Triangule a malha antes de importar.');
   Attributes:=ObjectOf(Primitive.Find('attributes'),'attributes');Positions:=ReadAccessor(Attributes.Get('POSITION',-1));if Positions.Width<>3 then raise Exception.Create('Posições glTF inválidas.');
   if M.VertCount+Positions.Count>500000 then raise Exception.Create('Avatar excede 500.000 vértices.');
   JointIDs:=Default(TAccessor);Weights:=Default(TAccessor);
   if HasSkin then begin
    if Attributes.Find('JOINTS_1')<>nil then raise Exception.Create('Use até quatro influências por vértice.');
    JointIDs:=ReadAccessor(Attributes.Get('JOINTS_0',-1));Weights:=ReadAccessor(Attributes.Get('WEIGHTS_0',-1));
    if (JointIDs.Width<>4) or (Weights.Width<>4) or (JointIDs.Count<>Positions.Count) or (Weights.Count<>Positions.Count) then raise Exception.Create('Pesos glTF incompatíveis.');
   end;
   Offset:=M.VertCount;Face:=M.AddFace(CadFaceInfo(Nodes[N].ID+'/'+IntToStr(P),skOther,V3(0,0,0),V3(0,0,0)));
   for I:=0 to Positions.Count-1 do begin
    Point:=V3(Positions.Values[I*3],Positions.Values[I*3+1],Positions.Values[I*3+2]);W:=Default(TCadVertexWeights);Rest:=V3(0,0,0);
    if HasSkin then begin
     W.HasBindPoints:=True;WeightSum:=0;
     for J:=0 to 3 do begin
      K:=Round(JointIDs.Values[I*4+J]);if (K<0) or (K>=Joints.Count) or (JointIDs.Values[I*4+J]<>K) then raise Exception.Create('Índice de osso inválido.');
      W.Joints[J]:=Joints.Integers[K];W.Weights[J]:=Weights.Values[I*4+J];if W.Weights[J]<0 then raise Exception.Create('Peso negativo no avatar.');WeightSum:=WeightSum+W.Weights[J];
      W.BindPoints[J]:=VScale(MatPoint(Bind[K],Point),1000);
     end;
     if WeightSum<1e-10 then raise Exception.Create('Vértice sem pesos.');for J:=0 to 3 do begin W.Weights[J]:=W.Weights[J]/WeightSum;Rest:=VAdd(Rest,VScale(W.BindPoints[J],W.Weights[J]));end;
    end else begin W.Joints[0]:=N;W.Weights[0]:=1;Rest:=VScale(MatPoint(Nodes[N].World,Point),1000);end;
    Vertex:=M.AddVertexRaw(Rest);M.SetVertexSkin(Vertex,W);
   end;
   Indices:=Default(TAccessor);if Primitive.Find('indices')<>nil then begin Indices:=ReadAccessor(Primitive.Get('indices',-1));if Indices.Width<>1 then raise Exception.Create('Índices glTF inválidos.');Count:=Indices.Count;end else Count:=Positions.Count;
   if Count mod 3<>0 then raise Exception.Create('Triângulo incompleto no avatar.');if M.TriCount+Count div 3>500000 then raise Exception.Create('Avatar excede 500.000 triângulos.');
   for I:=0 to Count div 3-1 do begin
    if Indices.Count>0 then begin A:=Round(Indices.Values[I*3]);B:=Round(Indices.Values[I*3+1]);C:=Round(Indices.Values[I*3+2]);end else begin A:=I*3;B:=A+1;C:=A+2;end;
    if (A<0) or (B<0) or (C<0) or (A>=Positions.Count) or (B>=Positions.Count) or (C>=Positions.Count) then raise Exception.Create('Índice de vértice inválido.');M.AddTri(Offset+A,Offset+B,Offset+C,Face);
   end;
  end;
 end;
 if M.TriCount=0 then raise Exception.Create('Avatar sem triângulos.');
end;

procedure TReader.ReadAnimations(Rig:TCadRig);
var Clips:TJSONArray;A,Channels,Samplers:TJSONArray;O,Ch,Samp,Target:TJSONObject;
    Motion:TCadMotion;Times,Values:TAccessor;I,J,K,N,T,Previous,TrackNo:Integer;
    Path,Interpolation:string;V:TCadVec3;PS:TCadMat4;Q:TCadQuat;Track:TCadMotionTrack;NonZero:Boolean;
begin
 if Root.Find('animations')=nil then Exit;A:=ArrayOf(Root.Find('animations'),'animations');if A.Count>128 then raise Exception.Create('Avatar excede 128 animações.');Clips:=TJSONArray.Create;
 try
  for I:=0 to A.Count-1 do begin
   O:=ObjectOf(A.Items[I],'animation');Motion:=TCadMotion.Create;
   try
    Motion.Name:=O.Get('name','Animação '+IntToStr(I+1));Motion.Smooth:=False;Motion.EntryMS:=320;Motion.ReturnMS:=320;Motion.ReturnToBase:=True;
    Channels:=ArrayOf(O.Find('channels'),'channels');Samplers:=ArrayOf(O.Find('samplers'),'samplers');
    for J:=0 to Channels.Count-1 do begin
     Ch:=ObjectOf(Channels.Items[J],'channel');Target:=ObjectOf(Ch.Find('target'),'target');N:=Target.Get('node',-1);Path:=Target.Get('path','');
     if (N<0) or (N>=Length(Nodes)) then raise Exception.Create('Nó da animação inexistente.');if not Nodes[N].Active then Continue;
     Samp:=ObjectOf(Item(Samplers,Ch.Get('sampler',-1)),'sampler');Interpolation:=Samp.Get('interpolation','LINEAR');
     Times:=ReadAccessor(Samp.Get('input',-1));Values:=ReadAccessor(Samp.Get('output',-1));
     if (Times.Width<>1) or (Times.Count>2048) then raise Exception.Create('Tempos de animação inválidos.');
     if not (Path='rotation') and not (Path='translation') then begin
      NonZero:=False;for K:=0 to High(Values.Values) do if Abs(Values.Values[K])>1e-8 then NonZero:=True;
      if NonZero then Notes:='Canais de escala/morph não são reproduzidos nesta versão.';Continue;
     end;
     if Interpolation<>'LINEAR' then raise Exception.Create('Converta animações STEP/CUBICSPLINE para LINEAR antes de importar.');
     if (Values.Count<>Times.Count) or ((Path='rotation') and (Values.Width<>4)) or ((Path='translation') and (Values.Width<>3)) then raise Exception.Create('Quadros da animação incompatíveis.');
     Track:=Default(TCadMotionTrack);Track.SegmentID:=Nodes[N].ID;Track.XYZ:=True;if Path='translation' then Track.Kind:=jkTranslation;
     SetLength(Track.Keys,Times.Count);Previous:=-1;TrackNo:=0;
     for K:=0 to Times.Count-1 do begin
      T:=Round(Times.Values[K]*1000);if (T<0) or (T>CadMotionMaxDuration) or ((K>0) and (Times.Values[K]<=Times.Values[K-1])) then raise Exception.Create('Tempo glTF inválido.');
      if Path='rotation' then begin Q:=CadQuat(Values.Values[K*4],Values.Values[K*4+1],Values.Values[K*4+2],Values.Values[K*4+3]);V:=CadQAngles(CadQMul(CadQInverse(Nodes[N].RestQ),Q));end
      else begin
        V:=VSub(V3(Values.Values[K*3],Values.Values[K*3+1],Values.Values[K*3+2]),Nodes[N].RestP);PS:=MatIdentity;
        if Nodes[N].Parent>=0 then PS:=Nodes[Nodes[N].Parent].World;
        V:=V3(V.X*1000*VLen(MatDir(PS,V3(1,0,0))),V.Y*1000*VLen(MatDir(PS,V3(0,1,0))),V.Z*1000*VLen(MatDir(PS,V3(0,0,1))));
      end;
      if T=Previous then Dec(TrackNo);Track.Keys[TrackNo].TimeMS:=T;Track.Keys[TrackNo].Value:=V;Inc(TrackNo);Previous:=T;Motion.DurationMS:=Max(Motion.DurationMS,T);
     end;
     SetLength(Track.Keys,TrackNo);SetLength(Motion.Tracks,Length(Motion.Tracks)+1);Motion.Tracks[High(Motion.Tracks)]:=Track;
    end;
    if Length(Motion.Tracks)>0 then begin Motion.Validate(Rig);Clips.Add(CadPackAnimation(Motion));end;
   finally Motion.Free;end;
  end;
  Rig.AnimationsJSON:=UTF8Encode(Clips.AsJSON);
 finally Clips.Free;end;
end;

procedure TReader.Build(out Avatar:TCadAvatarMesh;out Rig:TCadRig);
var M:TCadMesh;I,J:Integer;Pivot,Tip:TCadVec3;Parent:string;Basis,PB:TCadMat4;
begin
 Avatar:=nil;Rig:=TCadRig.Create;M:=TCadMesh.Create;
 try
  for I:=0 to High(Nodes) do begin
   Pivot:=VScale(MatPoint(Nodes[I].World,V3(0,0,0)),1000);Tip:=VAdd(Pivot,V3(0,10,0));
   for J:=0 to High(Nodes) do if Nodes[J].Parent=I then begin Tip:=VScale(MatPoint(Nodes[J].World,V3(0,0,0)),1000);if VDist(Tip,Pivot)>CAD_TOL then Break;end;
   if VDist(Tip,Pivot)<CAD_TOL then Tip:=VAdd(Pivot,V3(0,10,0));Parent:='';PB:=MatIdentity;
   if Nodes[I].Parent>=0 then begin Parent:=Nodes[Nodes[I].Parent].ID;PB:=BasisOf(Nodes[Nodes[I].Parent].World);end;
   Basis:=BasisOf(Nodes[I].World);CadAddBone(Rig,Nodes[I].ID,Parent,Pivot,Tip,Basis,PB);
  end;
  Rig.Validate;ReadGeometry(M);ReadAnimations(Rig);Avatar:=TCadAvatarMesh.Create;Avatar.SetMesh(M);Avatar.SourceName:='glTF 2.0';Avatar.Name:='Avatar importado';
 except M.Free;Avatar.Free;Avatar:=nil;Rig.Free;Rig:=nil;raise;end;
 M.Free;
end;

procedure CadImportAvatar(const FileName:string;out Avatar:TCadAvatarMesh;out Rig:TCadRig;out Notes:string);
var Reader:TReader;
begin
 Avatar:=nil;Rig:=nil;Notes:='';Reader:=TReader.Create(FileName);
 try Reader.Build(Avatar,Rig);Avatar.SourceName:=ExtractFileName(FileName);Notes:=Reader.Notes;finally Reader.Free;end;
end;
end.
