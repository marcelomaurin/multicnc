unit multicad_avatarmesh;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils,fpjson,multicad_types,multicad_feature,multicad_mesh,multicad_generatedmesh;
type
  TCadAvatarMesh=class(TCadGeneratedMesh)
  private
    FMesh: TCadMesh;
  public
    SourceName: string;
    constructor Create; override;
    destructor Destroy; override;
    procedure SetMesh(Mesh: TCadMesh);
    function BuildMesh: TCadMesh; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
  end;
implementation
uses Math,Base64;
const MaxAvatarBytes=96*1024*1024;
constructor TCadAvatarMesh.Create;
begin inherited Create;SetKind(cfAvatarMesh);end;
destructor TCadAvatarMesh.Destroy;
begin FMesh.Free;inherited Destroy;end;
procedure TCadAvatarMesh.SetMesh(Mesh: TCadMesh);
var M: TCadMesh;
begin M:=Mesh.Clone;FMesh.Free;FMesh:=M;end;
function TCadAvatarMesh.BuildMesh: TCadMesh;
begin if FMesh=nil then raise Exception.Create('Avatar sem malha.');Result:=FMesh.Clone;end;
procedure TCadAvatarMesh.SaveParams(O: TJSONObject);
var S:TMemoryStream;I,J:Integer;T:TCadTri;W:TCadVertexWeights;Data:RawByteString;
  procedure U(V:LongWord);begin V:=NtoLE(V);S.WriteBuffer(V,4);end;
  procedure D(V:Double);var B:QWord;begin Move(V,B,8);B:=NtoLE(B);S.WriteBuffer(B,8);end;
  procedure Str(const V:string);begin U(Length(V));if V<>'' then S.WriteBuffer(V[1],Length(V));end;
begin
  if FMesh=nil then raise Exception.Create('Avatar sem malha.');
  S:=TMemoryStream.Create;
  try
    S.WriteBuffer('MCAV1',5);U(Length(FMesh.SkinJoints));U(FMesh.FaceCount);U(FMesh.VertCount);U(FMesh.TriCount);
    for I:=0 to High(FMesh.SkinJoints) do Str(FMesh.SkinJoints[I]);
    for I:=0 to FMesh.FaceCount-1 do Str(FMesh.Faces[I].Name);
    for I:=0 to FMesh.VertCount-1 do begin
      D(FMesh.Verts[I].X);D(FMesh.Verts[I].Y);D(FMesh.Verts[I].Z);
      W:=FMesh.SkinVertices[I];for J:=0 to 3 do begin U(W.Joints[J]);D(W.Weights[J]);end;
      U(Ord(W.HasBindPoints));if W.HasBindPoints then for J:=0 to 3 do begin D(W.BindPoints[J].X);D(W.BindPoints[J].Y);D(W.BindPoints[J].Z);end;
    end;
    for I:=0 to FMesh.TriCount-1 do begin T:=FMesh.Tris[I];U(T.A);U(T.B);U(T.C);U(T.Face);end;
    SetLength(Data,S.Size);if S.Size>0 then Move(S.Memory^,Data[1],S.Size);
    O.Add('source',SourceName);O.Add('geometry',EncodeStringBase64(Data));
  finally S.Free;end;
end;
procedure TCadAvatarMesh.LoadParams(O: TJSONObject);
var S:TMemoryStream;Data,Magic:RawByteString;M:TCadMesh;NJ,NF,NV,NT,I,J:Integer;
    P:TCadVec3;W:TCadVertexWeights;A,B,C,F:LongWord;
  function U:LongWord;var V:LongWord;begin S.ReadBuffer(V,4);Result:=LEtoN(V);end;
  function D:Double;var V:QWord;begin S.ReadBuffer(V,8);V:=LEtoN(V);Move(V,Result,8);
    if IsNan(Result) or IsInfinite(Result) or (Abs(Result)>1e9) then raise Exception.Create('Coordenada/peso inválido no avatar.');end;
  function Str:string;var N:LongWord;begin N:=U;if (N>512) or (N>S.Size-S.Position) then raise Exception.Create('Nome inválido no avatar.');
    SetLength(Result,N);if N>0 then S.ReadBuffer(Result[1],N);end;
begin
  Data:=O.Get('geometry','');if Length(Data)>MaxAvatarBytes*4 div 3+4 then raise Exception.Create('Avatar excede 96 MB.');
  Data:=DecodeStringBase64(Data,True);if Length(Data)>MaxAvatarBytes then raise Exception.Create('Avatar excede 96 MB.');
  S:=TMemoryStream.Create;M:=TCadMesh.Create;
  try
    if Data<>'' then S.WriteBuffer(Data[1],Length(Data));S.Position:=0;
    SetLength(Magic,5);S.ReadBuffer(Magic[1],5);if Magic<>'MCAV1' then raise Exception.Create('Formato da malha de avatar inválido.');
    NJ:=U;NF:=U;NV:=U;NT:=U;
    if (NJ<1) or (NJ>2048) or (NF<1) or (NF>4096) or (NV<3) or (NV>500000) or (NT<1) or (NT>500000) or
       (Int64(NV)*76+Int64(NT)*16>S.Size-S.Position) then raise Exception.Create('Dimensões da malha de avatar inválidas.');
    SetLength(M.SkinJoints,NJ);for I:=0 to NJ-1 do M.SkinJoints[I]:=Str;
    for I:=0 to NF-1 do M.AddFace(CadFaceInfo(Str,skOther,V3(0,0,0),V3(0,0,0)));
    for I:=0 to NV-1 do begin
      P.X:=D;P.Y:=D;P.Z:=D;M.AddVertexRaw(P);
      W:=Default(TCadVertexWeights);for J:=0 to 3 do begin W.Joints[J]:=U;W.Weights[J]:=D;end;
      W.HasBindPoints:=U<>0;if W.HasBindPoints then for J:=0 to 3 do begin W.BindPoints[J].X:=D;W.BindPoints[J].Y:=D;W.BindPoints[J].Z:=D;end;M.SetVertexSkin(I,W);
    end;
    for I:=0 to NT-1 do begin
      A:=U;B:=U;C:=U;F:=U;if (A>=LongWord(NV)) or (B>=LongWord(NV)) or (C>=LongWord(NV)) or (F>=LongWord(NF)) then raise Exception.Create('Índice inválido na malha de avatar.');
      M.AddTri(A,B,C,F);
    end;
    if S.Position<>S.Size then raise Exception.Create('Dados adicionais na malha de avatar.');
    FMesh.Free;FMesh:=M;M:=nil;SourceName:=O.Get('source','');
  finally M.Free;S.Free;end;
end;
initialization RegisterCadFeature(cfAvatarMesh,TCadAvatarMesh);
end.
