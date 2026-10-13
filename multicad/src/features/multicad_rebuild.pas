unit multicad_rebuild;

{ MultiCAD - reconstrucao da arvore de operacoes (ARCHITECTURE 5).

  Percorre as operacoes em ordem (ate a barra de retrocesso): resolve
  planos e eixos, resolve os esbocos (expressoes + solver), e aplica as
  operacoes de solido (ressalto/corte extrudado e revolucionado) aos corpos.
  - Cada operacao recebe os corpos da anterior e devolve os novos; erro marca
    a operacao (vermelha) e a reconstrucao segue com os corpos de antes.
  - Cache: assinatura de cada operacao (parametros + as anteriores); so
    recalcula a partir da primeira operacao alterada.
  - Referencias (texto estavel):
      plano:  "plane:<id>"  "face:<nome>"  (face plana do modelo)
      reta:   "sketch:<id>/<entidade>"  "axis:<id>"
      ponto:  "sketch:<id>/<entidade>.<ponto>"  "origin"
      corpo:  "body:<nome>"
  Limites desta versao (TAREFA.md): "Ate o proximo" e "Ate o corpo" em face
  curva terminam num plano (aviso); vertices e arestas do solido ainda nao
  sao referencias. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, contnrs, md5, fpjson, multicad_types, multicad_feature,
  multicad_document, multicad_refgeom, multicad_sketch, multicad_solver,
  multicad_profile, multicad_extrude, multicad_revolve, multicad_mesh,
  multicad_sweep, multicad_csg, multicad_bridge, multicad_triangulate,
  multicad_hole, multicad_pattern, multicad_blend, multicad_blendgeom, multicad_occt, multicad_import;

type
  TCadBody = class
  public
    Name: string;
    Mesh: TCadMesh;
    Shape: TOcctShape;   { solido exato (nucleo OpenCascade); nil no nucleo Pascal }
    constructor Create(const AName: string; AMesh: TCadMesh);
    destructor Destroy; override;
    function Clone: TCadBody;
  end;

  { Ferramenta aplicada por uma operacao (para padroes e espelho). }
  TCadToolRec = class
  public
    Mesh: TCadMesh;
    Shape: TOcctShape;
    IsCut, Merge, FlipSide: Boolean;
    destructor Destroy; override;
  end;

  { Rosca cosmetica de um furo roscado (a vista desenha o circulo nominal). }
  TCadThreadMark = record
    Center, Axis: TCadVec3;   { Axis: para fora da peca }
    Radius, Length: Double;
  end;
  TCadThreadMarks = array of TCadThreadMark;

  TCadThreadRec = class
  public
    Marks: TCadThreadMarks;
  end;

  TCadBlendItem = record
    Body: Integer;
    Tool: TCadMesh;
    IsCut: Boolean;
  end;
  TCadBlendItems = array of TCadBlendItem;

  TCadRebuilder = class
  private
    FTools: TStringList;      { Id -> TCadToolRec (ultima ferramenta) }
    FThreadMap: TStringList;  { Id do furo -> TCadThreadRec }
    FDoc: TCadDocument;
    FBodies: TFPObjectList;
    FSigs: TStringList;           { assinatura por indice }
    FSnaps: TFPObjectList;        { lista de corpos (TFPObjectList) por indice }
    FNextBody: Integer;
    FRecomputed: Integer;
    FChord: Double;
    { nucleo OpenCascade (fase 8) }
    FUseOcct, FOcct, FLastOcct: Boolean;
    FExact: array of TOcctShape;   { solidos exatos da ferramenta em montagem }
    FExactBroken: Boolean;         { a ferramenta tem algo que so existe em malha }
    FToolShape: TOcctShape;        { ferramenta exata em aplicacao }
    procedure ExactReset;
    procedure ExactAdd(S: TOcctShape);
    procedure ExactBreak;
    function TakeToolShape(Tool: TCadMesh; out AError: string): TOcctShape;
    function ShapeMesh(S: TOcctShape; out AError: string): TCadMesh;
    procedure ApplyToolOcct(F: TCadFeature; Tool: TCadMesh; IsCut, Merge, FlipSide, ScopeAll: Boolean;
      const ScopeBodies: TCadStrArray);
    procedure ClearBodies(L: TFPObjectList);
    function CloneBodies(L: TFPObjectList): TFPObjectList;
    function FeatureSig(F: TCadFeature): string;
    function NewBodyName: string;
    procedure BuildPlane(P: TCadPlane);
    function RefreshSketchReferences(S: TCadSketch; out Err: string): Boolean;
    procedure BuildAxis(A: TCadAxis);
    procedure BuildExtrude(X: TCadExtrude);
    procedure BuildRevolve(R: TCadRevolve);
    procedure BuildHole(H: TCadHole);
    procedure BuildPattern(P: TCadPatternBase);
    procedure BuildBlend(F: TCadBlendBase);
    function BlendFallbackOcct(F: TCadBlendBase; B: TCadBody; const NA, NB: TCadStrArray;
      out AError: string): TOcctShape;
    function CollectBlend(F: TCadBlendBase; out Items: TCadBlendItems; out Skipped: Integer;
      out FirstErr: string): Boolean;
    procedure BuildShell(S: TCadShell);
    procedure BuildImport(F: TCadImportStep);
    procedure StoreTool(F: TCadFeature; Tool: TCadMesh; IsCut, Merge, FlipSide: Boolean);
    function ResolveDir(const ARef: string; out D: TCadVec3; out AError: string): Boolean;
    function ResolveAxis(const ARef: string; out A, U: TCadVec3; out AError: string): Boolean;
    procedure ApplyTool(F: TCadFeature; Tool: TCadMesh; IsCut, Merge, FlipSide, ScopeAll: Boolean;
      const ScopeBodies: TCadStrArray);
    function ModelBounds: TCadBox3;
    procedure EvalExprs(F: TCadFeature);
  public
    constructor Create(ADoc: TCadDocument);
    destructor Destroy; override;
    { Reconstroi. Devolve o numero de operacoes com erro. }
    function Rebuild: Integer;
    { Descarta o cache (forca reconstruir tudo). }
    procedure Invalidate;
    function BodyCount: Integer;
    function Body(I: Integer): TCadBody;
    function FindBody(const AName: string): TCadBody;
    function FindFace(const AName: string; out ABody: TCadBody; out AFace: Integer): Boolean;
    function TotalVolume: Double;
    function MassKg: Double;
    { Referencial do esboco (plano ou face plana). }
    function SketchFrame(S: TCadSketch; out Fr: TCadFrame; out AError: string): Boolean;
    function ResolvePlane(const ARef: string; out Fr: TCadFrame; out AError: string): Boolean;
    function ResolvePoint(const ARef: string; out P: TCadVec3; out AError: string): Boolean;
    function ResolveLine(const ARef: string; out A, B: TCadVec3; out AError: string): Boolean;
    { Eixo da alca de profundidade, resolvido nos corpos anteriores ao recurso. }
    function ExtrudeHandle(X: TCadExtrude; Direction: Integer;
      out Anchor, Axis: TCadVec3; out DepthFactor: Double): Boolean;
    { Operacoes recalculadas na ultima reconstrucao (o resto veio do cache). }
    property Recomputed: Integer read FRecomputed;
    property ChordTol: Double read FChord write FChord;
    { Usar o OpenCascade quando a biblioteca existir (padrao: sim). }
    property UseOcct: Boolean read FUseOcct write FUseOcct;
    { O nucleo da ultima reconstrucao foi o OpenCascade. }
    property OcctActive: Boolean read FOcct;
    { Solidos exatos dos corpos (para STEP); vazio no nucleo Pascal. }
    function BodyShape(I: Integer): TOcctShape;
    { Roscas cosmeticas dos furos roscados ativos. }
    function ThreadMarks: TCadThreadMarks;
    { Previa do filete/chanfro: ferramentas juntas sobre os corpos atuais
      (chamar com a operacao fora da reconstrucao). nil se nenhuma aresta. }
    function BlendPreview(F: TCadBlendBase; out AnyCut: Boolean; out AError: string): TCadMesh;
  end;

implementation

uses
  multicad_materials, multicad_log;

{ ---------- corpo ---------- }

constructor TCadBody.Create(const AName: string; AMesh: TCadMesh);
begin
  inherited Create;
  Name := AName;
  Mesh := AMesh;
end;

destructor TCadBody.Destroy;
begin
  Mesh.Free;
  OcctFree(Shape);
  inherited;
end;

function TCadBody.Clone: TCadBody;
begin
  Result := TCadBody.Create(Name, Mesh.Clone);
  Result.Shape := OcctCopy(Shape);
end;

{ ---------- utilitarios ---------- }

function ParseSketchRef(const ARef: string; out SId, EId, Pt: Integer): Boolean;
var
  S: string;
  P, Q: Integer;
begin
  Result := False;
  SId := 0; EId := 0; Pt := 0;
  if Copy(ARef, 1, 7) <> 'sketch:' then
    Exit;
  S := Copy(ARef, 8, MaxInt);
  P := Pos('/', S);
  if P = 0 then
    Exit;
  SId := StrToIntDef(Copy(S, 1, P - 1), 0);
  S := Copy(S, P + 1, MaxInt);
  Q := Pos('.', S);
  if Q > 0 then
  begin
    EId := StrToIntDef(Copy(S, 1, Q - 1), 0);
    Pt := StrToIntDef(Copy(S, Q + 1, MaxInt), 0);
  end
  else
    EId := StrToIntDef(S, 0);
  Result := (SId > 0) and (EId > 0);
end;

function RayTri(const O, D, A, B, C: TCadVec3; out T: Double): Boolean;
var
  E1, E2, P, Q, S: TCadVec3;
  Det, U, V: Double;
begin
  Result := False;
  E1 := VSub(B, A);
  E2 := VSub(C, A);
  P := VCross(D, E2);
  Det := VDot(E1, P);
  if Abs(Det) < 1E-14 then
    Exit;
  S := VSub(O, A);
  U := VDot(S, P) / Det;
  if (U < -1E-9) or (U > 1 + 1E-9) then
    Exit;
  Q := VCross(S, E1);
  V := VDot(D, Q) / Det;
  if (V < -1E-9) or (U + V > 1 + 1E-9) then
    Exit;
  T := VDot(E2, Q) / Det;
  Result := True;
end;

{ Caixa enorme do lado do semiespaco: plano Fr, lado = +normal se Side > 0. }
function HalfSpaceMesh(const Fr: TCadFrame; Side: Double; L: Double; const AName: string): TCadMesh;
var
  P: array[0..7] of TCadVec3;
  F: Integer;
  Z1: Double;
  function W(X, Y, Z: Double): TCadVec3;
  begin
    Result := VAdd(VAdd(VAdd(Fr.Origin, VScale(Fr.XDir, X)), VScale(Fr.YDir, Y)), VScale(Fr.Normal, Z));
  end;
begin
  if Side >= 0 then Z1 := L else Z1 := -L;
  P[0] := W(-L, -L, 0); P[1] := W(L, -L, 0); P[2] := W(L, L, 0); P[3] := W(-L, L, 0);
  P[4] := W(-L, -L, Z1); P[5] := W(L, -L, Z1); P[6] := W(L, L, Z1); P[7] := W(-L, L, Z1);
  Result := TCadMesh.Create;
  F := Result.AddPlaneFace(AName, Fr.Origin, VScale(Fr.Normal, -Sign(Side)));
  Result.AddQuadP(P[0], P[3], P[2], P[1], F);
  Result.AddQuadP(P[4], P[5], P[6], P[7], F);
  Result.AddQuadP(P[0], P[1], P[5], P[4], F);
  Result.AddQuadP(P[3], P[7], P[6], P[2], F);
  Result.AddQuadP(P[0], P[4], P[7], P[3], F);
  Result.AddQuadP(P[1], P[2], P[6], P[5], F);
  if Result.Volume < 0 then
    Result.Flip;
end;

{ ---------- rebuilder ---------- }

constructor TCadRebuilder.Create(ADoc: TCadDocument);
begin
  inherited Create;
  FDoc := ADoc;
  FBodies := TFPObjectList.Create(True);
  FSigs := TStringList.Create;
  FSnaps := TFPObjectList.Create(True);
  FTools := TStringList.Create;
  FTools.OwnsObjects := True;
  FThreadMap := TStringList.Create;
  FThreadMap.OwnsObjects := True;
  FChord := 0.01;
  FUseOcct := True;
end;

destructor TCadRebuilder.Destroy;
begin
  FSnaps.Free;
  FSigs.Free;
  FBodies.Free;
  FTools.Free;
  FThreadMap.Free;
  inherited;
end;

destructor TCadToolRec.Destroy;
begin
  Mesh.Free;
  OcctFree(Shape);
  inherited Destroy;
end;

procedure TCadRebuilder.StoreTool(F: TCadFeature; Tool: TCadMesh; IsCut, Merge, FlipSide: Boolean);
var
  I: Integer;
  R: TCadToolRec;
begin
  if (F is TCadPatternBase) or (Tool = nil) then
    Exit;
  R := TCadToolRec.Create;
  R.Mesh := Tool.Clone;
  R.Shape := OcctCopy(FToolShape);
  R.IsCut := IsCut;
  R.Merge := Merge;
  R.FlipSide := FlipSide;
  I := FTools.IndexOf(IntToStr(F.Id));
  if I >= 0 then
    FTools.Delete(I);
  FTools.AddObject(IntToStr(F.Id), R);
end;

function TCadRebuilder.ThreadMarks: TCadThreadMarks;
var
  I, K, Last: Integer;
  F: TCadFeature;
  R: TCadThreadRec;
begin
  Result := nil;
  Last := FDoc.Count - 1;
  if (FDoc.RollbackIndex >= 0) and (FDoc.RollbackIndex <= FDoc.Count) then
    Last := FDoc.RollbackIndex - 1;
  for I := 0 to Last do
  begin
    F := FDoc.Feature(I);
    if not (F is TCadHole) or F.Suppressed or (F.State = fsError) then
      Continue;
    K := FThreadMap.IndexOf(IntToStr(F.Id));
    if K < 0 then
      Continue;
    R := TCadThreadRec(FThreadMap.Objects[K]);
    for K := 0 to High(R.Marks) do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := R.Marks[K];
    end;
  end;
end;

procedure TCadRebuilder.Invalidate;
begin
  FSigs.Clear;
  FSnaps.Clear;
end;

procedure TCadRebuilder.ClearBodies(L: TFPObjectList);
begin
  L.Clear;
end;

function TCadRebuilder.CloneBodies(L: TFPObjectList): TFPObjectList;
var
  I: Integer;
begin
  Result := TFPObjectList.Create(True);
  for I := 0 to L.Count - 1 do
    Result.Add(TCadBody(L[I]).Clone);
end;

function TCadRebuilder.FeatureSig(F: TCadFeature): string;
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    F.SaveParams(O);
    Result := IntToStr(F.Id) + ':' + CAD_FEATURE_CODES[F.Kind] + ':' + F.Name + ':' +
      BoolToStr(F.Suppressed, True) + ':' + O.AsJSON;
  finally
    O.Free;
  end;
end;

function TCadRebuilder.NewBodyName: string;
begin
  Inc(FNextBody);
  Result := 'Corpo' + IntToStr(FNextBody);
end;

function TCadRebuilder.BodyCount: Integer;
begin
  Result := FBodies.Count;
end;

function TCadRebuilder.Body(I: Integer): TCadBody;
begin
  Result := TCadBody(FBodies[I]);
end;

function TCadRebuilder.FindBody(const AName: string): TCadBody;
var
  I: Integer;
begin
  for I := 0 to FBodies.Count - 1 do
    if SameText(Body(I).Name, AName) then
      Exit(Body(I));
  Result := nil;
end;

function TCadRebuilder.FindFace(const AName: string; out ABody: TCadBody; out AFace: Integer): Boolean;
var
  I, F: Integer;
begin
  for I := 0 to FBodies.Count - 1 do
  begin
    F := Body(I).Mesh.FaceIndex(AName);
    if (F >= 0) and (Body(I).Mesh.FaceTriCount(F) > 0) then
    begin
      ABody := Body(I);
      AFace := F;
      Exit(True);
    end;
  end;
  ABody := nil;
  AFace := -1;
  Result := False;
end;

function TCadRebuilder.TotalVolume: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FBodies.Count - 1 do
    if Body(I).Shape <> nil then
      Result := Result + OcctVolume(Body(I).Shape)   { volume exato do B-Rep }
    else
      Result := Result + Body(I).Mesh.Volume;
end;

function TCadRebuilder.ExtrudeHandle(X: TCadExtrude; Direction: Integer;
  out Anchor, Axis: TCadVec3; out DepthFactor: Double): Boolean;
var
  Saved: TFPObjectList;
  S: TCadSketch;
  F: TCadFeature;
  Fr, StartFr: TCadFrame;
  D: TCadExtrudeDir;
  E: TSketchEntity;
  B: TCadBox3;
  A, Z, N: TCadVec3;
  I, Index: Integer;
  Offset, Radius: Double;
  Err: string;
begin
  Result:=False;Anchor:=V3(0,0,0);Axis:=V3(0,0,1);DepthFactor:=1;
  if (X=nil) or not (Direction in [1,2]) then Exit;
  if Direction=2 then begin if not X.UseDir2 then Exit;D:=X.Dir2;end else D:=X.Dir1;
  if not CadEndNeedsDepth(D.EndCond) then Exit;
  Index:=FDoc.IndexOfId(X.Id);
  Saved:=FBodies;
  try
    { A operacao editada pode ter removido a face do esboco. A referencia
      precisa vir da mesma etapa usada ao construir a extrusao. }
    if (Index>0) and (Index-1<FSnaps.Count) then FBodies:=TFPObjectList(FSnaps[Index-1]);
    F:=FDoc.FindById(X.SketchId);if not (F is TCadSketch) then Exit;
    S:=TCadSketch(F);if not SketchFrame(S,Fr,Err) then Exit;
    N:=Fr.Normal;Axis:=N;if X.IsCut then Axis:=VNeg(Axis);
    if Direction=2 then Axis:=VNeg(Axis);
    if D.DirRef<>'' then
    begin
      if not ResolveLine(D.DirRef,A,Z,Err) then Exit;
      Z:=VNorm(VSub(Z,A));if VDot(Z,Axis)<0 then Z:=VNeg(Z);Axis:=Z;
    end;
    if D.Reverse then Axis:=VNeg(Axis);
    if VLen(Axis)<CAD_EPS then Exit;
    Offset:=0;
    case X.StartKind of
      esOffset:begin Offset:=X.StartOffset;if X.StartReverse then Offset:=-Offset;end;
      esSurface:begin
        if not ResolvePlane(X.StartRef,StartFr,Err) then Exit;
        if Abs(Abs(VDot(StartFr.Normal,N))-1)>1E-9 then Exit;
        Offset:=VDot(VSub(StartFr.Origin,Fr.Origin),N);
      end;
      esVertex:begin if not ResolvePoint(X.StartRef,A,Err) then Exit;Offset:=VDot(VSub(A,Fr.Origin),N);end;
    end;
    B:=BoxEmpty;
    for I:=0 to S.EntityCount-1 do
    begin
      E:=S.Entity(I);if E.Construction or E.Centerline or (E.Kind=sePoint) then Continue;
      Radius:=0;if E.Kind in [seCircle,seArc] then Radius:=E.Radius;
      BoxAdd(B,V3(E.P1.X-Radius,E.P1.Y-Radius,0));
      BoxAdd(B,V3(E.P1.X+Radius,E.P1.Y+Radius,0));
      if E.Kind=seLine then BoxAdd(B,V3(E.P2.X,E.P2.Y,0));
    end;
    if B.Empty then Exit;
    Anchor:=VAdd(FrameToWorld(Fr,V2((B.Min.X+B.Max.X)/2,(B.Min.Y+B.Max.Y)/2)),VScale(Axis,Offset));
    if D.EndCond=ecMidPlane then DepthFactor:=0.5;
    Result:=True;
  finally FBodies:=Saved;end;
end;

function TCadRebuilder.MassKg: Double;
begin
  Result := CadMassKg(FDoc.MaterialData, TotalVolume);
end;

function TCadRebuilder.ModelBounds: TCadBox3;
var
  I: Integer;
  B: TCadBox3;
begin
  Result := BoxEmpty;
  for I := 0 to FBodies.Count - 1 do
  begin
    B := Body(I).Mesh.Bounds;
    if not B.Empty then
    begin
      BoxAdd(Result, B.Min);
      BoxAdd(Result, B.Max);
    end;
  end;
end;

{ ---------- referencias ---------- }

function TCadRebuilder.ResolvePlane(const ARef: string; out Fr: TCadFrame; out AError: string): Boolean;
var
  F: TCadFeature;
  B: TCadBody;
  FI: Integer;
  Info: TCadFaceInfo;
  N: TCadVec3;
begin
  Result := False;
  AError := '';
  Fr := StdFrame(spFrontal);
  if Copy(ARef, 1, 6) = 'plane:' then
  begin
    F := FDoc.FindById(StrToIntDef(Copy(ARef, 7, MaxInt), 0));
    if not (F is TCadPlane) then
    begin
      AError := 'Plano de referência não encontrado: ' + ARef;
      Exit;
    end;
    if not TCadPlane(F).FrameValid then
    begin
      AError := 'Plano "' + F.Name + '" com erro';
      Exit;
    end;
    Fr := TCadPlane(F).Frame;
    Exit(True);
  end;
  if Copy(ARef, 1, 5) = 'face:' then
  begin
    if not FindFace(Copy(ARef, 6, MaxInt), B, FI) then
    begin
      AError := 'Referência perdida: a face "' + Copy(ARef, 6, MaxInt) + '" não existe mais';
      Exit;
    end;
    Info := B.Mesh.Faces[FI];
    if Info.Surf <> skPlane then
    begin
      AError := 'A face "' + Info.Name + '" não é plana';
      Exit;
    end;
    { regra da face: origem = projecao da origem global; x = projecao do X }
    N := VNorm(Info.Axis);
    Fr := FrameFromNormal(VScale(N, VDot(N, Info.Origin)), N);
    Exit(True);
  end;
  AError := 'Referência de plano inválida: ' + ARef;
end;

function TCadRebuilder.SketchFrame(S: TCadSketch; out Fr: TCadFrame; out AError: string): Boolean;
begin
  Result := ResolvePlane(S.PlaneRef, Fr, AError);
end;

function TCadRebuilder.ResolvePoint(const ARef: string; out P: TCadVec3; out AError: string): Boolean;
var
  SId, EId, Pt: Integer;
  F: TCadFeature;
  S: TCadSketch;
  Fr: TCadFrame;
  P2: TCadVec2;
begin
  Result := False;
  AError := '';
  P := V3(0, 0, 0);
  if ARef = 'origin' then
    Exit(True);
  if not ParseSketchRef(ARef, SId, EId, Pt) then
  begin
    AError := 'Referência de ponto inválida: ' + ARef + ' (use sketch:<id>/<entidade>.<ponto>)';
    Exit;
  end;
  F := FDoc.FindById(SId);
  if not (F is TCadSketch) then
  begin
    AError := 'Esboço não encontrado: ' + ARef;
    Exit;
  end;
  S := TCadSketch(F);
  if not S.PointOf(EId, Max(Pt, 1), P2) or (S.EntityIndex(EId) < 0) then
  begin
    AError := 'Ponto não encontrado: ' + ARef;
    Exit;
  end;
  if not SketchFrame(S, Fr, AError) then
    Exit;
  P := FrameToWorld(Fr, P2);
  Result := True;
end;

function TCadRebuilder.ResolveLine(const ARef: string; out A, B: TCadVec3; out AError: string): Boolean;
var
  SId, EId, Pt, I: Integer;
  F: TCadFeature;
  S: TCadSketch;
  Fr: TCadFrame;
  E: TSketchEntity;
begin
  Result := False;
  AError := '';
  A := V3(0, 0, 0);
  B := V3(0, 0, 1);
  if Copy(ARef, 1, 5) = 'axis:' then
  begin
    F := FDoc.FindById(StrToIntDef(Copy(ARef, 6, MaxInt), 0));
    if not (F is TCadAxis) or not TCadAxis(F).Valid then
    begin
      AError := 'Eixo não encontrado ou com erro: ' + ARef;
      Exit;
    end;
    A := TCadAxis(F).Origin;
    B := VAdd(A, TCadAxis(F).Direction);
    Exit(True);
  end;
  if not ParseSketchRef(ARef, SId, EId, Pt) then
  begin
    AError := 'Referência de reta inválida: ' + ARef;
    Exit;
  end;
  F := FDoc.FindById(SId);
  if not (F is TCadSketch) then
  begin
    AError := 'Esboço não encontrado: ' + ARef;
    Exit;
  end;
  S := TCadSketch(F);
  I := S.EntityIndex(EId);
  if (I < 0) or (S.Entity(I).Kind <> seLine) then
  begin
    AError := 'A referência não é uma linha: ' + ARef;
    Exit;
  end;
  E := S.Entity(I);
  if not SketchFrame(S, Fr, AError) then
    Exit;
  A := FrameToWorld(Fr, E.P1);
  B := FrameToWorld(Fr, E.P2);
  Result := VDist(A, B) > CAD_TOL;
  if not Result then
    AError := 'Linha de comprimento nulo: ' + ARef;
end;

{ ---------- planos e eixos ---------- }

function TCadRebuilder.RefreshSketchReferences(S: TCadSketch; out Err: string): Boolean;
var I,OwnerId,EntityId,Pt:Integer;F:TCadFeature;E:TSketchEntity;P:TCadVec2;Source,Target:TCadFrame;
begin
  Result:=False;Err:='';
  for I:=0 to S.EntityCount-1 do begin
    E:=S.Entity(I);if E.SourceRef='' then Continue;
    if not ParseSketchPointRef(E.SourceRef,OwnerId,EntityId,Pt) then begin Err:='Referência externa inválida: '+E.SourceRef;Exit;end;
    F:=FDoc.FindById(OwnerId);
    if not (F is TCadSketch) or (FDoc.IndexOfId(OwnerId)>=FDoc.IndexOfId(S.Id)) then begin Err:='Referência externa precisa de um esboço anterior: '+E.SourceRef;Exit;end;
    if F.Suppressed or (F.State=fsError) then begin Err:='Esboço de referência indisponível: '+F.Name;Exit;end;
    if not SketchReferencePoint(TCadSketch(F),EntityId,Pt,P) then begin Err:='Ponto de referência perdido: '+E.SourceRef;Exit;end;
    if not SketchFrame(TCadSketch(F),Source,Err) or not SketchFrame(S,Target,Err) then Exit;
    E.P1:=FrameToLocal(Target,FrameToWorld(Source,P));S.SetEntity(I,E);
  end;
  Result:=True;
end;

procedure TCadRebuilder.BuildPlane(P: TCadPlane);
var
  F0, F1: TCadFrame;
  A, B, C, N, O, U: TCadVec3;
  E: string;
  Bd: TCadBody;
  FI: Integer;
  Info: TCadFaceInfo;
  S: Double;
  procedure Fail(const Msg: string);
  begin
    P.FrameValid := False;
    P.SetState(fsError, Msg);
  end;
begin
  if P.PlaneType = ptStandard then
  begin
    P.Frame := StdFrame(P.Std);
    P.FrameValid := True;
    Exit;
  end;
  P.FrameValid := False;
  E := P.Validate;
  if E <> '' then
  begin
    Fail(E);
    Exit;
  end;
  case P.PlaneType of
    ptOffset, ptCoincident:
      begin
        if not ResolvePlane(P.Refs[0], F0, E) then begin Fail(E); Exit; end;
        if P.PlaneType = ptOffset then
        begin
          if P.Flip then S := -P.Distance else S := P.Distance;
          P.Frame := FrameOffset(F0, S);
        end
        else
          P.Frame := F0;
      end;
    ptParallelPoint:
      begin
        if not ResolvePlane(P.Refs[0], F0, E) then begin Fail(E); Exit; end;
        if not ResolvePoint(P.Refs[1], A, E) then begin Fail(E); Exit; end;
        P.Frame := F0;
        P.Frame.Origin := A;
      end;
    ptAngle:
      begin
        if not ResolvePlane(P.Refs[0], F0, E) then begin Fail(E); Exit; end;
        if not ResolveLine(P.Refs[1], A, B, E) then begin Fail(E); Exit; end;
        U := VNorm(VSub(B, A));
        if P.Flip then S := -P.Angle else S := P.Angle;
        N := MatDir(MatRotate(U, S), F0.Normal);
        P.Frame := FrameFromNormal(A, N);
      end;
    ptMidPlane:
      begin
        if not ResolvePlane(P.Refs[0], F0, E) then begin Fail(E); Exit; end;
        if not ResolvePlane(P.Refs[1], F1, E) then begin Fail(E); Exit; end;
        if Abs(Abs(VDot(F0.Normal, F1.Normal)) - 1) < 1E-9 then
        begin
          { paralelos: no meio, com a normal do primeiro }
          S := VDot(VSub(F1.Origin, F0.Origin), F0.Normal);
          P.Frame := FrameOffset(F0, S / 2);
        end
        else
        begin
          { bissetor: contem a reta de intersecao }
          N := VNorm(VAdd(F0.Normal, F1.Normal));
          U := VCross(F0.Normal, F1.Normal);
          { ponto da intersecao: resolve n0.x = d0, n1.x = d1 com x no plano de U }
          O := VScale(VAdd(VScale(VCross(F1.Normal, U), VDot(F0.Normal, F0.Origin)),
            VScale(VCross(U, F0.Normal), VDot(F1.Normal, F1.Origin))), 1 / VDot(U, U));
          P.Frame := FrameFromNormal(O, N);
        end;
      end;
    ptThreePoints:
      begin
        if not ResolvePoint(P.Refs[0], A, E) then begin Fail(E); Exit; end;
        if not ResolvePoint(P.Refs[1], B, E) then begin Fail(E); Exit; end;
        if not ResolvePoint(P.Refs[2], C, E) then begin Fail(E); Exit; end;
        N := VCross(VSub(B, A), VSub(C, A));
        if VLen(N) < 1E-9 then begin Fail('Os três pontos estão alinhados'); Exit; end;
        P.Frame := FrameFromNormal(A, N);
      end;
    ptLinePoint:
      begin
        if not ResolveLine(P.Refs[0], A, B, E) then begin Fail(E); Exit; end;
        if not ResolvePoint(P.Refs[1], C, E) then begin Fail(E); Exit; end;
        N := VCross(VSub(B, A), VSub(C, A));
        if VLen(N) < 1E-9 then begin Fail('O ponto está sobre a linha'); Exit; end;
        P.Frame := FrameFromNormal(A, N);
      end;
    ptNormalCurve:
      begin
        if not ResolveLine(P.Refs[0], A, B, E) then begin Fail(E); Exit; end;
        if not ResolvePoint(P.Refs[1], C, E) then begin Fail(E); Exit; end;
        P.Frame := FrameFromNormal(C, VSub(B, A));
      end;
    ptTangent:
      begin
        if (Copy(P.Refs[0], 1, 5) <> 'face:') or
          not FindFace(Copy(P.Refs[0], 6, MaxInt), Bd, FI) then
        begin
          Fail('Escolha uma face cilíndrica existente');
          Exit;
        end;
        Info := Bd.Mesh.Faces[FI];
        if Info.Surf <> skCylinder then begin Fail('A face não é cilíndrica'); Exit; end;
        if not ResolvePlane(P.Refs[1], F0, E) then begin Fail(E); Exit; end;
        if Abs(VDot(F0.Normal, Info.Axis)) > 1E-6 then
        begin
          Fail('O plano de referência precisa ser paralelo ao eixo do cilindro');
          Exit;
        end;
        N := F0.Normal;
        if P.Flip then N := VNeg(N);
        P.Frame := FrameFromNormal(VAdd(Info.Origin, VScale(N, Info.Radius)), F0.Normal);
      end;
  end;
  P.FrameValid := True;
  P.SetState(fsOk, '');
end;

procedure TCadRebuilder.BuildAxis(A: TCadAxis);
var
  E: string;
  P0, P1, Q: TCadVec3;
  F0, F1: TCadFrame;
  Bd: TCadBody;
  FI: Integer;
  Info: TCadFaceInfo;
  U: TCadVec3;
  procedure Fail(const Msg: string);
  begin
    A.Valid := False;
    A.SetState(fsError, Msg);
  end;
begin
  A.Valid := False;
  E := A.Validate;
  if E <> '' then begin Fail(E); Exit; end;
  case A.AxisType of
    atCylinder:
      begin
        if (Copy(A.Refs[0], 1, 5) <> 'face:') or
          not FindFace(Copy(A.Refs[0], 6, MaxInt), Bd, FI) then
        begin
          Fail('Escolha uma face cilíndrica ou cônica existente');
          Exit;
        end;
        Info := Bd.Mesh.Faces[FI];
        if not (Info.Surf in [skCylinder, skCone]) then begin Fail('A face não é cilíndrica'); Exit; end;
        A.Origin := Info.Origin;
        A.Direction := VNorm(Info.Axis);
      end;
    atEdge:
      begin
        if not ResolveLine(A.Refs[0], P0, P1, E) then begin Fail(E); Exit; end;
        A.Origin := P0;
        A.Direction := VNorm(VSub(P1, P0));
      end;
    atTwoPlanes:
      begin
        if not ResolvePlane(A.Refs[0], F0, E) then begin Fail(E); Exit; end;
        if not ResolvePlane(A.Refs[1], F1, E) then begin Fail(E); Exit; end;
        U := VCross(F0.Normal, F1.Normal);
        if VLen(U) < 1E-9 then begin Fail('Os planos são paralelos'); Exit; end;
        A.Origin := VScale(VAdd(VScale(VCross(F1.Normal, U), VDot(F0.Normal, F0.Origin)),
          VScale(VCross(U, F0.Normal), VDot(F1.Normal, F1.Origin))), 1 / VDot(U, U));
        A.Direction := VNorm(U);
      end;
    atTwoPoints:
      begin
        if not ResolvePoint(A.Refs[0], P0, E) then begin Fail(E); Exit; end;
        if not ResolvePoint(A.Refs[1], P1, E) then begin Fail(E); Exit; end;
        if VDist(P0, P1) < CAD_TOL then begin Fail('Os pontos coincidem'); Exit; end;
        A.Origin := P0;
        A.Direction := VNorm(VSub(P1, P0));
      end;
    atPointFace:
      begin
        if not ResolvePoint(A.Refs[0], Q, E) then begin Fail(E); Exit; end;
        if not ResolvePlane(A.Refs[1], F0, E) then begin Fail(E); Exit; end;
        A.Origin := Q;
        A.Direction := F0.Normal;
      end;
  end;
  A.Valid := True;
  A.SetState(fsOk, '');
end;

{ ---------- regioes do perfil ---------- }

{ Regiao de recurso fino a partir de um laco fechado (anti-horario):
  externo deslocado para fora e interno para dentro. }
function ThinClosed(const L: TCadLoop; TOut, TIn: Double; out R: TCadSweepRegion;
  out AError: string): Boolean;
var
  Src, OuterP, InnerP: TCadPoly2;
  I, N: Integer;
begin
  Result := False;
  AError := '';
  N := Length(L.Poly);
  SetLength(Src, N);
  for I := 0 to N - 1 do
    Src[I] := L.Poly[I];
  if CadPoly2Area(Src) < 0 then
  begin
    AError := 'Contorno do recurso fino com orientação inválida';
    Exit;
  end;
  if not CadOffsetLoop(Src, -TOut, OuterP) or not CadOffsetLoop(Src, TIn, InnerP) then
  begin
    AError := 'Espessura do recurso fino grande demais para o contorno';
    Exit;
  end;
  R.Outer.Poly := OuterP;
  R.Outer.SegEntity := Copy(L.SegEntity);
  SetLength(R.Outer.SegSuffix, N);
  for I := 0 to N - 1 do
    R.Outer.SegSuffix[I] := '/out';
  SetLength(R.Holes, 1);
  SetLength(R.Holes[0].SegSuffix, N);
  for I := 0 to N - 1 do
    R.Holes[0].SegSuffix[I] := '/in';
  { ilha horaria: inverte a ordem }
  SetLength(R.Holes[0].Poly, N);
  SetLength(R.Holes[0].SegEntity, N);
  for I := 0 to N - 1 do
  begin
    R.Holes[0].Poly[I] := InnerP[N - 1 - I];
    R.Holes[0].SegEntity[I] := L.SegEntity[(2 * N - 2 - I) mod N];
  end;
  { rotulo das laterais: in/out vem do nome da face (ver BuildExtrude) }
  Result := True;
end;

{ Faixa de recurso fino a partir de contorno aberto: lado esquerdo a TLeft,
  direito a TRight; pontas retas. }
function ThinOpen(const L: TCadLoop; TLeft, TRight: Double; out R: TCadSweepRegion;
  out AError: string): Boolean;
var
  N, I, K: Integer;
  Lf, Rt: TCadPoly2;
  function Normal(I: Integer): TCadVec2;
  var
    DX, DY, Len: Double;
  begin
    DX := L.Poly[I + 1].X - L.Poly[I].X;
    DY := L.Poly[I + 1].Y - L.Poly[I].Y;
    Len := Sqrt(DX * DX + DY * DY);
    Result := V2(-DY / Len, DX / Len);
  end;
  function OffsetPt(I: Integer; D: Double): TCadVec2;
  var
    N0, N1: TCadVec2;
    Den: Double;
  begin
    if I = 0 then
    begin
      N0 := Normal(0);
      Exit(V2(L.Poly[0].X + N0.X * D, L.Poly[0].Y + N0.Y * D));
    end;
    if I = High(L.Poly) then
    begin
      N0 := Normal(I - 1);
      Exit(V2(L.Poly[I].X + N0.X * D, L.Poly[I].Y + N0.Y * D));
    end;
    N0 := Normal(I - 1);
    N1 := Normal(I);
    Den := 1 + N0.X * N1.X + N0.Y * N1.Y;
    if Den < 1E-6 then Den := 1E-6;
    Result := V2(L.Poly[I].X + (N0.X + N1.X) * D / Den, L.Poly[I].Y + (N0.Y + N1.Y) * D / Den);
  end;
begin
  Result := False;
  AError := '';
  N := Length(L.Poly);
  if N < 2 then
  begin
    AError := 'Contorno aberto vazio';
    Exit;
  end;
  SetLength(Lf, N);
  SetLength(Rt, N);
  for I := 0 to N - 1 do
  begin
    Lf[I] := OffsetPt(I, TLeft);
    Rt[I] := OffsetPt(I, -TRight);
  end;
  { contorno: direita do inicio ao fim, esquerda do fim ao inicio (anti-horario) }
  SetLength(R.Outer.Poly, 2 * N);
  SetLength(R.Outer.SegEntity, 2 * N);
  SetLength(R.Outer.SegSuffix, 2 * N);
  K := 0;
  for I := 0 to N - 1 do
  begin
    R.Outer.Poly[K] := Rt[I];
    if I < N - 1 then R.Outer.SegEntity[K] := L.SegEntity[I] else R.Outer.SegEntity[K] := -2;
    R.Outer.SegSuffix[K] := '/in';
    Inc(K);
  end;
  for I := N - 1 downto 0 do
  begin
    R.Outer.Poly[K] := Lf[I];
    if I > 0 then R.Outer.SegEntity[K] := L.SegEntity[I - 1] else R.Outer.SegEntity[K] := -1;
    R.Outer.SegSuffix[K] := '/out';
    Inc(K);
  end;
  R.Holes := nil;
  if CadPoly2Area(R.Outer.Poly) <= 0 then
  begin
    AError := 'Faixa do recurso fino inválida';
    Exit;
  end;
  Result := True;
end;

{ ---------- aplicar ferramenta aos corpos ---------- }

function BoxesOverlap(const A, B: TCadBox3): Boolean;
const
  E = 1E-4;
begin
  Result := not (A.Empty or B.Empty) and
    (A.Min.X <= B.Max.X + E) and (B.Min.X <= A.Max.X + E) and
    (A.Min.Y <= B.Max.Y + E) and (B.Min.Y <= A.Max.Y + E) and
    (A.Min.Z <= B.Max.Z + E) and (B.Min.Z <= A.Max.Z + E);
end;

{ ---------- nucleo OpenCascade ---------- }

procedure TCadRebuilder.ExactReset;
var
  I: Integer;
begin
  for I := 0 to High(FExact) do
    OcctFree(FExact[I]);
  FExact := nil;
  FExactBroken := False;
end;

procedure TCadRebuilder.ExactAdd(S: TOcctShape);
begin
  if S = nil then
  begin
    { a parte exata falhou: a ferramenta vai pela malha }
    FExactBroken := True;
    Exit;
  end;
  SetLength(FExact, Length(FExact) + 1);
  FExact[High(FExact)] := S;
end;

procedure TCadRebuilder.ExactBreak;
begin
  FExactBroken := True;
end;

function TCadRebuilder.TakeToolShape(Tool: TCadMesh; out AError: string): TOcctShape;
var
  I: Integer;
  R: TOcctShape;
begin
  AError := '';
  Result := nil;
  if not FExactBroken and (Length(FExact) > 0) then
  begin
    { ferramenta exata: junta as partes (regioes, direcao 2, furos) }
    Result := FExact[0];
    FExact[0] := nil;
    for I := 1 to High(FExact) do
    begin
      R := OcctBoolean(Result, FExact[I], 0, AError);
      if R = nil then
      begin
        OcctFree(Result);
        Break;
      end;
      OcctFree(Result);
      Result := R;
    end;
  end;
  ExactReset;
  if (Result = nil) and (Tool <> nil) then
    { so em malha (inclinacao, recorte, tampas): solido poliedrico }
    Result := OcctFromMesh(Tool, AError);
end;

function TCadRebuilder.ShapeMesh(S: TOcctShape; out AError: string): TCadMesh;
begin
  Result := OcctToMesh(S, FChord, AError);
end;

function TCadRebuilder.BodyShape(I: Integer): TOcctShape;
begin
  Result := Body(I).Shape;
end;

procedure TCadRebuilder.ApplyToolOcct(F: TCadFeature; Tool: TCadMesh; IsCut, Merge, FlipSide,
  ScopeAll: Boolean; const ScopeBodies: TCadStrArray);
var
  I, K, Touched, NC: Integer;
  B: TCadBody;
  TS, R, Merged, Part: TOcctShape;
  E, Warn, MergedName: string;
  InScope: Boolean;
  V0: Double;
  NewList: TFPObjectList;
  TB: TCadBox3;

  function MakeBody(const AName: string; S: TOcctShape): TCadBody;
  var
    Er: string;
    Ms: TCadMesh;
  begin
    Ms := ShapeMesh(S, Er);
    if Ms = nil then
      Ms := TCadMesh.Create;
    Result := TCadBody.Create(AName, Ms);
    Result.Shape := S;
  end;

begin
  Warn := '';
  TS := TakeToolShape(Tool, E);
  if TS = nil then
  begin
    Tool.Free;
    F.SetState(fsError, 'Ferramenta inválida no OpenCascade: ' + E);
    Exit;
  end;
  FToolShape := TS;
  try
    StoreTool(F, Tool, IsCut, Merge, FlipSide);
  finally
    FToolShape := nil;
  end;
  TB := Tool.Bounds;
  Tool.Free;
  if not IsCut then
  begin
    if (FBodies.Count = 0) or not Merge then
    begin
      FBodies.Add(MakeBody(NewBodyName, TS));
      if (FBodies.Count > 1) and not Merge then
        Warn := 'Mesclar resultado desligado: novo corpo';
      if Warn <> '' then F.SetState(fsWarning, Warn) else F.SetState(fsOk, '');
      Exit;
    end;
    Merged := TS;
    MergedName := '';
    I := 0;
    while I < FBodies.Count do
    begin
      B := Body(I);
      InScope := ScopeAll;
      for K := 0 to High(ScopeBodies) do
        if SameText(ScopeBodies[K], 'body:' + B.Name) then
          InScope := True;
      if not InScope or (B.Shape = nil) then
      begin
        Inc(I);
        Continue;
      end;
      R := OcctBoolean(B.Shape, Merged, 0, E);
      if R = nil then
      begin
        OcctFree(Merged);
        F.SetState(fsError, 'Falha na união (OpenCascade): ' + E);
        Exit;
      end;
      if OcctComponents(R) < OcctComponents(B.Shape) + OcctComponents(Merged) then
      begin
        { encostou: funde }
        if MergedName = '' then MergedName := B.Name;
        OcctFree(Merged);
        Merged := R;
        FBodies.Delete(I);
      end
      else
      begin
        OcctFree(R);
        Inc(I);
      end;
    end;
    if MergedName = '' then
    begin
      MergedName := NewBodyName;
      Warn := 'O ressalto não toca nenhum corpo: criou um corpo separado';
    end;
    FBodies.Add(MakeBody(MergedName, Merged));
    if Warn <> '' then F.SetState(fsWarning, Warn) else F.SetState(fsOk, '');
    Exit;
  end;
  { corte }
  if FBodies.Count = 0 then
  begin
    OcctFree(TS);
    F.SetState(fsError, 'Corte sem corpo: crie um ressalto antes');
    Exit;
  end;
  Touched := 0;
  NewList := TFPObjectList.Create(True);
  try
    for I := 0 to FBodies.Count - 1 do
    begin
      B := Body(I);
      InScope := ScopeAll;
      for K := 0 to High(ScopeBodies) do
        if SameText(ScopeBodies[K], 'body:' + B.Name) then
          InScope := True;
      if not InScope or (B.Shape = nil) or
        (not FlipSide and not BoxesOverlap(B.Mesh.Bounds, TB)) then
      begin
        NewList.Add(B.Clone);
        Continue;
      end;
      V0 := OcctVolume(B.Shape);
      if FlipSide then
        R := OcctBoolean(B.Shape, TS, 2, E)
      else
        R := OcctBoolean(B.Shape, TS, 1, E);
      if R = nil then
      begin
        OcctFree(TS);
        F.SetState(fsError, 'Falha no corte (OpenCascade): ' + E);
        Exit;
      end;
      if Abs(OcctVolume(R) - V0) > 1E-6 * Max(1, V0) then
        Inc(Touched);
      NC := OcctComponents(R);
      if NC = 0 then
      begin
        OcctFree(R);
        Continue;   { corpo consumido }
      end;
      if NC > 1 then
      begin
        for K := 0 to NC - 1 do
        begin
          Part := OcctComponent(R, K);
          if K = 0 then
            NewList.Add(MakeBody(B.Name, Part))
          else
            NewList.Add(MakeBody(NewBodyName, Part));
        end;
        OcctFree(R);
        Warn := 'O corte separou o corpo em partes';
      end
      else
        NewList.Add(MakeBody(B.Name, R));
    end;
    OcctFree(TS);
    FBodies.Clear;
    for I := 0 to NewList.Count - 1 do
      FBodies.Add(NewList[I]);
    NewList.OwnsObjects := False;
  finally
    NewList.Free;
  end;
  if Touched = 0 then
    F.SetState(fsWarning, 'O corte não intercepta o modelo')
  else if Warn <> '' then
    F.SetState(fsWarning, Warn)
  else
    F.SetState(fsOk, '');
end;

procedure TCadRebuilder.ApplyTool(F: TCadFeature; Tool: TCadMesh; IsCut, Merge, FlipSide,
  ScopeAll: Boolean; const ScopeBodies: TCadStrArray);
var
  I, K, Touched, CompB, CompT: Integer;
  B: TCadBody;
  R: TCadMesh;
  E, Warn: string;
  Parts: TList;
  InScope: Boolean;
  Merged: TCadMesh;
  MergedName: string;
  V0: Double;
  NewList: TFPObjectList;
begin
  if FOcct then
  begin
    ApplyToolOcct(F, Tool, IsCut, Merge, FlipSide, ScopeAll, ScopeBodies);
    Exit;
  end;
  Warn := '';
  StoreTool(F, Tool, IsCut, Merge, FlipSide);
  if not IsCut then
  begin
    if (FBodies.Count = 0) or not Merge then
    begin
      FBodies.Add(TCadBody.Create(NewBodyName, Tool));
      if (FBodies.Count > 1) and not Merge then
        Warn := 'Mesclar resultado desligado: novo corpo';
      if Warn <> '' then F.SetState(fsWarning, Warn) else F.SetState(fsOk, '');
      Exit;
    end;
    Merged := Tool;
    MergedName := '';
    CompT := CadMeshComponents(Tool);
    I := 0;
    while I < FBodies.Count do
    begin
      B := Body(I);
      InScope := ScopeAll;
      for K := 0 to High(ScopeBodies) do
        if SameText(ScopeBodies[K], 'body:' + B.Name) then
          InScope := True;
      if not InScope then
      begin
        Inc(I);
        Continue;
      end;
      CompB := CadMeshComponents(B.Mesh);
      R := CadBoolean(B.Mesh, Merged, boUnion, E);
      if R = nil then
      begin
        if Merged <> Tool then Merged.Free;
        Tool.Free;
        F.SetState(fsError, 'Falha na união: ' + E);
        Exit;
      end;
      if CadMeshComponents(R) < CompB + CompT then
      begin
        { encostou: funde }
        if MergedName = '' then MergedName := B.Name;
        if Merged <> Tool then Merged.Free;
        Merged := R;
        CompT := CadMeshComponents(Merged);
        FBodies.Delete(I);
      end
      else
      begin
        R.Free;
        Inc(I);
      end;
    end;
    if MergedName = '' then
    begin
      MergedName := NewBodyName;
      Warn := 'O ressalto não toca nenhum corpo: criou um corpo separado';
    end;
    if Merged <> Tool then
      Tool.Free;
    FBodies.Add(TCadBody.Create(MergedName, Merged));
    if Warn <> '' then F.SetState(fsWarning, Warn) else F.SetState(fsOk, '');
    Exit;
  end;
  { corte }
  if FBodies.Count = 0 then
  begin
    Tool.Free;
    F.SetState(fsError, 'Corte sem corpo: crie um ressalto antes');
    Exit;
  end;
  Touched := 0;
  NewList := TFPObjectList.Create(True);
  try
    for I := 0 to FBodies.Count - 1 do
    begin
      B := Body(I);
      InScope := ScopeAll;
      for K := 0 to High(ScopeBodies) do
        if SameText(ScopeBodies[K], 'body:' + B.Name) then
          InScope := True;
      if not InScope then
      begin
        NewList.Add(B.Clone);
        Continue;
      end;
      { ferramenta longe do corpo: nada a cortar (e evita a booleana) }
      if not FlipSide and not BoxesOverlap(B.Mesh.Bounds, Tool.Bounds) then
      begin
        NewList.Add(B.Clone);
        Continue;
      end;
      V0 := B.Mesh.Volume;
      if FlipSide then
        R := CadBoolean(B.Mesh, Tool, boIntersection, E)
      else
        R := CadBoolean(B.Mesh, Tool, boDifference, E);
      if R = nil then
      begin
        Tool.Free;
        F.SetState(fsError, 'Falha no corte: ' + E);
        Exit;
      end;
      if Abs(R.Volume - V0) > 1E-6 * Max(1, V0) then
        Inc(Touched);
      if R.TriCount = 0 then
      begin
        R.Free;
        Continue;   { corpo consumido }
      end;
      if CadMeshComponents(R) > 1 then
      begin
        Parts := CadSplitComponents(R);
        try
          for K := 0 to Parts.Count - 1 do
            if K = 0 then
              NewList.Add(TCadBody.Create(B.Name, TCadMesh(Parts[K])))
            else
              NewList.Add(TCadBody.Create(NewBodyName, TCadMesh(Parts[K])));
        finally
          Parts.Free;
        end;
        R.Free;
        Warn := 'O corte separou o corpo em partes';
      end
      else
        NewList.Add(TCadBody.Create(B.Name, R));
    end;
    Tool.Free;
    FBodies.Clear;
    for I := 0 to NewList.Count - 1 do
      FBodies.Add(NewList[I]);
    NewList.OwnsObjects := False;
  finally
    NewList.Free;
  end;
  if Touched = 0 then
    F.SetState(fsWarning, 'O corte não intercepta o modelo')
  else if Warn <> '' then
    F.SetState(fsWarning, Warn)
  else
    F.SetState(fsOk, '');
end;

{ ---------- extrusao ---------- }

procedure TCadRebuilder.BuildExtrude(X: TCadExtrude);
var
  S: TCadSketch;
  Fr, TF: TCadFrame;
  E, Warn: string;
  Prof: TCadProfileResult;
  Chain: TCadLoop;
  Regions: array of TCadSweepRegion;
  Surfs: TCadSegSurfaces;
  D, N, P, Hit: TCadVec3;
  S0, L, Side, T, TBest, TMax, TOut, TIn: Double;
  I, K, J: Integer;
  Tool, M2, Tmp: TCadMesh;
  Bx: TCadBox3;
  Found, AllSame, Ok: Boolean;
  HitFace: string;
  Bd: TCadBody;
  FI: Integer;
  Samples: array of TCadVec3;
  Caps, CavR: array of TCadSweepRegion;
  Cav, CutDir: TCadExtrudeDir;

  { ha material (caixa de algum corpo) alem do plano por Org, no sentido Dir? }
  function MaterialAhead(const Org, Dir: TCadVec3): Boolean;
  var BI, C: Integer; Bb: TCadBox3; Q: TCadVec3;
  begin
    Result := False;
    for BI := 0 to FBodies.Count - 1 do
    begin
      Bb := Body(BI).Mesh.Bounds;
      for C := 0 to 7 do
      begin
        if C and 1 = 0 then Q.X := Bb.Min.X else Q.X := Bb.Max.X;
        if C and 2 = 0 then Q.Y := Bb.Min.Y else Q.Y := Bb.Max.Y;
        if C and 4 = 0 then Q.Z := Bb.Min.Z else Q.Z := Bb.Max.Z;
        if VDot(VSub(Q, Org), Dir) > 1E-6 then Exit(True);
      end;
    end;
  end;

  function DirOf(const Dir: TCadExtrudeDir; Base: TCadVec3; out ADir: TCadVec3; out AErr: string): Boolean;
  var
    A, B: TCadVec3;
  begin
    Result := True;
    AErr := '';
    ADir := Base;
    if Dir.DirRef <> '' then
    begin
      Result := ResolveLine(Dir.DirRef, A, B, AErr);
      if not Result then Exit;
      ADir := VNorm(VSub(B, A));
      if VDot(ADir, Base) < 0 then ADir := VNeg(ADir);
    end;
    if Dir.Reverse then
      ADir := VNeg(ADir);
  end;

  { Profundidade ate o plano TF (paralelo ao esboco) ou -1 se nao paralelo. }
  function DepthToPlane(const AFr: TCadFrame; const ADir: TCadVec3; AStart: Double): Double;
  var
    Den: Double;
  begin
    Den := VDot(ADir, AFr.Normal);
    if Abs(Den) < 1E-9 then
      Exit(-2);
    { ponto do esboco na origem do referencial }
    Result := VDot(VSub(AFr.Origin, VAdd(Fr.Origin, VScale(ADir, AStart))), AFr.Normal) / Den;
    if Abs(Abs(VDot(AFr.Normal, Fr.Normal)) - 1) > 1E-9 then
      Result := -1 - Abs(Result);   { marca: nao paralelo (o valor e so referencia) }
  end;

  { Constroi a ferramenta de uma direcao. Devolve nil e AErr em falha. }
  function OneDir(const Dir: TCadExtrudeDir; const BaseDir: TCadVec3; AStart: Double;
    const APrefix: string; out AErr: string): TCadMesh;
  var
    ADir: TCadVec3;
    Depth, St: Double;
    R: Integer;
    Part, Acc, U: TCadMesh;
    OErr: string;
    ClipFr: TCadFrame;
    NeedClip: Boolean;
    OffS: Double;
    HitT: Double;
    Q, BK, BJ: Integer;
    TT: TCadTri;
  begin
    Result := nil;
    AErr := '';
    if not DirOf(Dir, BaseDir, ADir, AErr) then
      Exit;
    St := AStart;
    NeedClip := False;
    Depth := Dir.Depth;
    case Dir.EndCond of
      ecBlind: ;
      ecMidPlane:
        begin
          St := AStart - Dir.Depth / 2;
          Depth := Dir.Depth;
        end;
      ecThroughAll:
        Depth := L;
      ecThroughAllBoth:
        begin
          St := AStart - L;
          Depth := 2 * L;
        end;
      ecUpToVertex:
        begin
          if not ResolvePoint(Dir.Target, P, AErr) then Exit;
          Depth := VDot(VSub(P, VAdd(Fr.Origin, VScale(ADir, AStart))), Fr.Normal) / VDot(ADir, Fr.Normal);
        end;
      ecUpToSurface, ecOffsetFromSurface, ecUpToNext, ecUpToBody:
        begin
          if Dir.EndCond in [ecUpToSurface, ecOffsetFromSurface] then
          begin
            if not ResolvePlane(Dir.Target, ClipFr, AErr) then Exit;
          end
          else
          begin
            { raio a partir das amostras do perfil }
            TMax := -1;
            HitFace := '';
            AllSame := True;
            for Q := 0 to High(Samples) do
            begin
              TBest := 1E300;
              Found := False;
              for BK := 0 to FBodies.Count - 1 do
              begin
                if (Dir.EndCond = ecUpToBody) and not SameText('body:' + Body(BK).Name, Dir.Target) then
                  Continue;
                for BJ := 0 to Body(BK).Mesh.TriCount - 1 do
                begin
                  TT := Body(BK).Mesh.Tris[BJ];
                  if RayTri(VAdd(Samples[Q], VScale(ADir, AStart)), ADir, Body(BK).Mesh.Verts[TT.A],
                    Body(BK).Mesh.Verts[TT.B], Body(BK).Mesh.Verts[TT.C], HitT) and
                    (HitT > 1E-6) and (HitT < TBest) then
                  begin
                    TBest := HitT;
                    Found := True;
                    if Q = 0 then
                      HitFace := Body(BK).Mesh.Faces[TT.Face].Name
                    else if Body(BK).Mesh.Faces[TT.Face].Name <> HitFace then
                      AllSame := False;
                  end;
                end;
              end;
              if not Found then
              begin
                AErr := 'Não há face à frente de todo o perfil nessa direção (inverta a direção)';
                Exit;
              end;
              TMax := Max(TMax, TBest);
            end;
            if AllSame and FindFace(HitFace, Bd, FI) and (Bd.Mesh.Faces[FI].Surf = skPlane) then
            begin
              ClipFr := FrameFromNormal(Bd.Mesh.Faces[FI].Origin, Bd.Mesh.Faces[FI].Axis);
            end
            else
            begin
              { face curva ou varias faces: fim plano na maior distancia }
              ClipFr := FrameFromNormal(VAdd(VAdd(Fr.Origin, VScale(ADir, AStart)), VScale(ADir, TMax)), Fr.Normal);
              Warn := 'Fim em superfície curva aproximado por um plano';
            end;
          end;
          if Dir.EndCond = ecOffsetFromSurface then
          begin
            { deslocamento: volta em direcao ao esboco (Inverter passa da face) }
            OffS := Dir.Offset;
            if VDot(ClipFr.Normal, ADir) > 0 then OffS := -OffS;
            if Dir.OffsetReverse then OffS := -OffS;
            ClipFr := FrameOffset(ClipFr, OffS);
          end;
          Depth := DepthToPlane(ClipFr, ADir, AStart);
          if Depth = -2 then
          begin
            AErr := 'A superfície final é paralela à direção da extrusão';
            Exit;
          end;
          if Depth < -1 then
          begin
            { plano inclinado: varre ate alem do plano (maior distancia das
              amostras ate ele) e recorta pelo semiespaco }
            NeedClip := True;
            Depth := -1;
            for Q := 0 to High(Samples) do
            begin
              HitT := VDot(VSub(ClipFr.Origin, VAdd(Samples[Q], VScale(ADir, AStart))), ClipFr.Normal) /
                VDot(ADir, ClipFr.Normal);
              Depth := Max(Depth, HitT);
            end;
            if Depth <= CAD_TOL then
            begin
              AErr := 'A superfície final está atrás do perfil (inverta a direção)';
              Exit;
            end;
            Depth := Depth + 1;
          end;
        end;
    end;
    if Depth <= CAD_TOL then
    begin
      AErr := 'A profundidade resultante é nula ou negativa (inverta a direção ou escolha outra referência)';
      Exit;
    end;
    Acc := nil;
    for R := 0 to High(Regions) do
    begin
      Part := CadSweepExtrude(Fr, Regions[R], Surfs, ADir, St, Depth, Dir.Draft, Dir.DraftOutward,
        APrefix, AErr);
      if FOcct and (Part <> nil) then
      begin
        if Abs(Dir.Draft) > 1E-9 then
          ExactBreak
        else
          ExactAdd(OcctPrism(Fr, Regions[R], Surfs, ADir, St, Depth, APrefix, OErr));
      end;
      if Part = nil then
      begin
        Acc.Free;
        Exit;
      end;
      if Acc = nil then
        Acc := Part
      else
      begin
        Acc.Append(Part);
        Part.Free;
      end;
    end;
    if NeedClip then
    begin
      ExactBreak;
      { lado do semiespaco que contem o inicio do perfil }
      Side := VDot(VSub(VAdd(Fr.Origin, VScale(ADir, St)), ClipFr.Origin), ClipFr.Normal);
      U := HalfSpaceMesh(ClipFr, Sign(Side + 1E-12), 4 * L + 1000, APrefix + '/fim');
      try
        Part := CadBoolean(Acc, U, boIntersection, AErr);
      finally
        U.Free;
      end;
      Acc.Free;
      Acc := Part;
      if (Acc <> nil) and (Acc.TriCount = 0) then
      begin
        FreeAndNil(Acc);
        AErr := 'A superfície final não corta a extrusão nessa direção';
      end;
    end;
    Result := Acc;
  end;

begin
  Warn := '';
  E := X.Validate;
  if E <> '' then begin X.SetState(fsError, E); Exit; end;
  if not (FDoc.FindById(X.SketchId) is TCadSketch) then
  begin
    X.SetState(fsError, 'Esboço não encontrado');
    Exit;
  end;
  S := TCadSketch(FDoc.FindById(X.SketchId));
  if S.State = fsError then begin X.SetState(fsError, 'O esboço tem erro: ' + S.Message); Exit; end;
  if not SketchFrame(S, Fr, E) then begin X.SetState(fsError, E); Exit; end;
  Surfs := CadSketchSurfaces(S);
  Regions := nil;
  { perfil }
  if X.Thin then
  begin
    case X.ThinType of
      ttOneDirection:
        if X.ThinReverse then begin TOut := 0; TIn := X.ThinT1; end
        else begin TOut := X.ThinT1; TIn := 0; end;
      ttMidPlane: begin TOut := X.ThinT1 / 2; TIn := X.ThinT1 / 2; end;
    else
      begin TOut := X.ThinT1; TIn := X.ThinT2; end;
    end;
    if CadSketchOpenChain(S, Chain, E, FChord) then
    begin
      SetLength(Regions, 1);
      { aberto: esquerda = "para fora" por convencao }
      if not ThinOpen(Chain, TOut, TIn, Regions[0], E) then begin X.SetState(fsError, E); Exit; end;
    end
    else
    begin
      Prof := CadSketchProfiles(S, FChord);
      if not Prof.Ok then begin X.SetState(fsError, Prof.Message); Exit; end;
      SetLength(Regions, Length(Prof.Regions));
      for I := 0 to High(Prof.Regions) do
        if not ThinClosed(Prof.Regions[I].Outer, TOut, TIn, Regions[I], E) then
        begin
          X.SetState(fsError, E);
          Exit;
        end;
    end;
  end
  else
  begin
    Prof := CadSketchProfiles(S, FChord);
    if not Prof.Ok then
    begin
      if Length(Prof.OpenPoints) > 0 then
        X.SetState(fsError, Prof.Message + ' (perfil aberto só com Recurso fino)')
      else
        X.SetState(fsError, Prof.Message);
      Exit;
    end;
    K := 0;
    SetLength(Regions, Length(Prof.Regions));
    for I := 0 to High(Prof.Regions) do
    begin
      Ok := Length(X.Contours) = 0;
      for J := 0 to High(X.Contours) do
        if X.Contours[J] = Prof.Regions[I].Id then
          Ok := True;
      if Ok then
      begin
        Regions[K] := CadRegionToSweep(Prof.Regions[I]);
        Inc(K);
      end;
    end;
    SetLength(Regions, K);
    if K = 0 then
    begin
      X.SetState(fsError, 'Nenhum dos contornos selecionados existe no esboço');
      Exit;
    end;
  end;
  { amostras (para "ate o proximo") }
  Samples := nil;
  for I := 0 to High(Regions) do
    for J := 0 to High(Regions[I].Outer.Poly) do
    begin
      SetLength(Samples, Length(Samples) + 1);
      Samples[High(Samples)] := FrameToWorld(Fr, Regions[I].Outer.Poly[J]);
    end;
  { inicio }
  N := Fr.Normal;
  S0 := 0;
  case X.StartKind of
    esOffset:
      if X.StartReverse then S0 := -X.StartOffset else S0 := X.StartOffset;
    esSurface:
      begin
        if not ResolvePlane(X.StartRef, TF, E) then begin X.SetState(fsError, E); Exit; end;
        if Abs(Abs(VDot(TF.Normal, N)) - 1) > 1E-9 then
        begin
          X.SetState(fsError, 'Início em superfície não paralela ao esboço ainda não é suportado');
          Exit;
        end;
        S0 := VDot(VSub(TF.Origin, Fr.Origin), N);
      end;
    esVertex:
      begin
        if not ResolvePoint(X.StartRef, P, E) then begin X.SetState(fsError, E); Exit; end;
        S0 := VDot(VSub(P, Fr.Origin), N);
      end;
  end;
  { comprimento "passante": maior que o modelo todo }
  Bx := ModelBounds;
  for I := 0 to High(Samples) do
    BoxAdd(Bx, Samples[I]);
  L := VLen(BoxSize(Bx)) * 2 + Abs(S0) + 10;
  { direcao 1 (e 2) }
  { como no SolidWorks: ressalto sai pela normal do esboço, corte entra na
    peca (sentido contrario); "Inverter direcao" troca }
  if X.IsCut then
    D := VNeg(N)
  else
    D := N;
  { corte sem material no sentido escolhido (ex.: esboço no mesmo plano da
    base, que sai pela normal): inverte sozinho se houver material do outro
    lado, como a previa do SolidWorks sugere. So para Cego/Passante/Ate o
    proximo, sem direcao 2, sem direcao de referencia e sem "inverter lado". }
  CutDir := X.Dir1;
  if X.IsCut and not X.UseDir2 and not X.FlipSide and (X.Dir1.DirRef = '') and
    (X.Dir1.EndCond in [ecBlind, ecThroughAll, ecUpToNext]) and (FBodies.Count > 0) then
  begin
    if X.Dir1.Reverse then P := VNeg(D) else P := D;
    if not MaterialAhead(VAdd(Fr.Origin, VScale(N, S0)), P) and
      MaterialAhead(VAdd(Fr.Origin, VScale(N, S0)), VNeg(P)) then
    begin
      CutDir.Reverse := not CutDir.Reverse;
      Warn := 'Direção do corte invertida automaticamente: não havia material no sentido escolhido';
    end;
  end;
  Tool := OneDir(CutDir, D, S0, X.Name, E);
  if Tool = nil then begin X.SetState(fsError, E); Exit; end;
  { tampar extremidades: solido do contorno externo menos a cavidade interna
    encurtada pela espessura da tampa nas duas pontas }
  if X.Thin and X.CapEnds and (Length(Regions) > 0) and (Length(Regions[0].Holes) = 1) then
  begin
    if X.UseDir2 or not (X.Dir1.EndCond in [ecBlind, ecMidPlane]) or (X.Dir1.Draft <> 0) then
    begin
      Tool.Free;
      X.SetState(fsError, 'Tampar extremidades: use Cego ou Plano médio, sem Direção 2 e sem inclinação');
      Exit;
    end;
    if 2 * X.CapThickness >= X.Dir1.Depth then
    begin
      Tool.Free;
      X.SetState(fsError, 'Espessura das tampas maior que a profundidade');
      Exit;
    end;
    Tool.Free;
    Tool := nil;
    ExactBreak;
    Caps := Copy(Regions);
    SetLength(CavR, Length(Caps));
    for I := 0 to High(Regions) do
    begin
      Regions[I].Holes := nil;
      CavR[I] := Default(TCadSweepRegion);
    end;
    for I := 0 to High(Caps) do
    begin
      K := Length(Caps[I].Holes[0].Poly);
      SetLength(CavR[I].Outer.Poly, K);
      SetLength(CavR[I].Outer.SegEntity, K);
      SetLength(CavR[I].Outer.SegSuffix, K);
      for J := 0 to K - 1 do
      begin
        CavR[I].Outer.Poly[J] := Caps[I].Holes[0].Poly[K - 1 - J];
        CavR[I].Outer.SegEntity[J] := Caps[I].Holes[0].SegEntity[(2 * K - 2 - J) mod K];
        CavR[I].Outer.SegSuffix[J] := '/in';
      end;
    end;
    Tool := OneDir(X.Dir1, D, S0, X.Name, E);
    if Tool = nil then begin X.SetState(fsError, E); Exit; end;
    Regions := CavR;
    Cav := X.Dir1;
    Cav.Depth := X.Dir1.Depth - 2 * X.CapThickness;
    if X.Dir1.EndCond = ecBlind then
      M2 := OneDir(Cav, D, S0 + X.CapThickness, X.Name + '/cav', E)
    else
      M2 := OneDir(Cav, D, S0, X.Name + '/cav', E);
    if M2 = nil then begin Tool.Free; X.SetState(fsError, E); Exit; end;
    Tmp := CadBoolean(Tool, M2, boDifference, E);
    Tool.Free;
    M2.Free;
    if Tmp = nil then begin X.SetState(fsError, E); Exit; end;
    Tool := Tmp;
  end;
  if X.UseDir2 then
  begin
    M2 := OneDir(X.Dir2, VNeg(D), -S0, X.Name + '/d2', E);
    if M2 = nil then
    begin
      Tool.Free;
      X.SetState(fsError, 'Direção 2: ' + E);
      Exit;
    end;
    { a direcao 2 parte do mesmo plano (inicio de uma = inicio da outra) }
    Tmp := CadBoolean(Tool, M2, boUnion, E);
    Tool.Free;
    M2.Free;
    if Tmp = nil then begin X.SetState(fsError, E); Exit; end;
    Tool := Tmp;
  end;
  ApplyTool(X, Tool, X.IsCut, X.Merge, X.FlipSide, X.ScopeAll or X.ScopeAuto, X.ScopeBodies);
  if (Warn <> '') and (X.State = fsOk) then
    X.SetState(fsWarning, Warn);
end;

{ ---------- revolucao ---------- }

procedure TCadRebuilder.BuildRevolve(R: TCadRevolve);
var
  S: TCadSketch;
  Fr: TCadFrame;
  E: string;
  Prof: TCadProfileResult;
  Surfs: TCadSegSurfaces;
  AxA, AxB: TCadVec2;
  A3, B3: TCadVec3;
  I, J: Integer;
  Found, Ok: Boolean;
  St, Ang: Double;
  Tool, Part: TCadMesh;
  Ent: TSketchEntity;
  SId, EId, Pt: Integer;
  OErr: string;
begin
  E := R.Validate;
  if E <> '' then begin R.SetState(fsError, E); Exit; end;
  if not (FDoc.FindById(R.SketchId) is TCadSketch) then
  begin
    R.SetState(fsError, 'Esboço não encontrado');
    Exit;
  end;
  S := TCadSketch(FDoc.FindById(R.SketchId));
  if S.State = fsError then begin R.SetState(fsError, 'O esboço tem erro: ' + S.Message); Exit; end;
  if not SketchFrame(S, Fr, E) then begin R.SetState(fsError, E); Exit; end;
  { eixo no plano do esboco }
  Found := False;
  if R.AxisRef = '' then
  begin
    for I := 0 to S.EntityCount - 1 do
      if S.Entity(I).Centerline then
      begin
        AxA := S.Entity(I).P1;
        AxB := S.Entity(I).P2;
        Found := True;
        Break;
      end;
    if not Found then
    begin
      R.SetState(fsError, 'Desenhe uma linha de centro no esboço ou escolha o eixo');
      Exit;
    end;
  end
  else if ParseSketchRef(R.AxisRef, SId, EId, Pt) and (SId = S.Id) then
  begin
    I := S.EntityIndex(EId);
    if (I < 0) or (S.Entity(I).Kind <> seLine) then
    begin
      R.SetState(fsError, 'O eixo escolhido não é uma linha do esboço');
      Exit;
    end;
    Ent := S.Entity(I);
    AxA := Ent.P1;
    AxB := Ent.P2;
  end
  else
  begin
    if not ResolveLine(R.AxisRef, A3, B3, E) then begin R.SetState(fsError, E); Exit; end;
    if (Abs(FrameDistance(Fr, A3)) > CAD_TOL) or (Abs(FrameDistance(Fr, B3)) > CAD_TOL) then
    begin
      R.SetState(fsError, 'O eixo precisa estar no plano do esboço');
      Exit;
    end;
    AxA := FrameToLocal(Fr, A3);
    AxB := FrameToLocal(Fr, B3);
  end;
  Prof := CadSketchProfiles(S, FChord);
  if not Prof.Ok then begin R.SetState(fsError, Prof.Message); Exit; end;
  Surfs := CadSketchSurfaces(S);
  { angulos }
  case R.Cond of
    rcMidPlane:
      begin
        St := -R.Angle / 2;
        Ang := R.Angle;
      end;
  else
    begin
      St := 0;
      Ang := R.Angle;
      if R.UseDir2 then
      begin
        St := -R.Angle2;
        Ang := R.Angle + R.Angle2;
      end;
      if R.Reverse then
        St := -St - Ang;
    end;
  end;
  Tool := nil;
  for I := 0 to High(Prof.Regions) do
  begin
    Ok := Length(R.Contours) = 0;
    for J := 0 to High(R.Contours) do
      if R.Contours[J] = Prof.Regions[I].Id then
        Ok := True;
    if not Ok then
      Continue;
    Part := CadSweepRevolve(Fr, CadRegionToSweep(Prof.Regions[I]), Surfs, AxA, AxB, St,
      Min(Ang, 360), R.Name, E);
    if FOcct and (Part <> nil) then
      ExactAdd(OcctRevolve(Fr, CadRegionToSweep(Prof.Regions[I]), Surfs, AxA, AxB, St,
        Min(Ang, 360), R.Name, OErr));
    if Part = nil then
    begin
      Tool.Free;
      R.SetState(fsError, E);
      Exit;
    end;
    if Tool = nil then
      Tool := Part
    else
    begin
      Tool.Append(Part);
      Part.Free;
    end;
  end;
  if Tool = nil then
  begin
    R.SetState(fsError, 'Nenhum dos contornos selecionados existe no esboço');
    Exit;
  end;
  ApplyTool(R, Tool, R.IsCut, R.Merge, R.FlipSide, True, nil);
end;

{ ---------- furo ---------- }

{ Solido de revolucao do perfil (r, z) em torno do eixo Z do referencial. }
function RevolveProfile(const Prof: TCadHoleProfile; const C, X, Y, Z: TCadVec3;
  const APrefix: string; ASegs: Integer): TCadMesh;
var
  I, K, Face: Integer;
  S: TCadHoleSeg;
  Info: TCadFaceInfo;
  A0, A1: Double;
  PA, PB, PC, PD: TCadVec3;
  Err: string;

  function P(R, H, Ang: Double): TCadVec3;
  begin
    Result := VAdd(C, VAdd(VAdd(VScale(X, R * Cos(Ang)), VScale(Y, R * Sin(Ang))), VScale(Z, H)));
  end;

begin
  Result := TCadMesh.Create;
  for I := 0 to High(Prof) do
  begin
    S := Prof[I];
    if (S.R0 < 1E-9) and (S.R1 < 1E-9) then
      Continue;
    Info := Default(TCadFaceInfo);
    Info.Name := APrefix + '/' + S.Name;
    Info.Origin := VAdd(C, VScale(Z, S.Z0));
    Info.Axis := Z;
    if Abs(S.R0 - S.R1) < 1E-9 then
    begin
      Info.Surf := skCylinder;
      Info.Origin := C;
      Info.Radius := S.R0;
    end
    else if Abs(S.Z0 - S.Z1) < 1E-9 then
      Info.Surf := skPlane
    else
    begin
      Info.Surf := skCone;
      Info.Origin := C;
      Info.Radius := S.R0;
      Info.Radius2 := RadToDeg(ArcTan2(Abs(S.R1 - S.R0), Abs(S.Z1 - S.Z0)));
    end;
    Face := Result.AddFace(Info);
    for K := 0 to ASegs - 1 do
    begin
      A0 := 2 * Pi * K / ASegs;
      A1 := 2 * Pi * (K + 1) / ASegs;
      PA := P(S.R0, S.Z0, A0);
      PB := P(S.R1, S.Z1, A0);
      PC := P(S.R1, S.Z1, A1);
      PD := P(S.R0, S.Z0, A1);
      if S.R0 < 1E-9 then
        Result.AddTriP(PA, PB, PC, Face)
      else if S.R1 < 1E-9 then
        Result.AddTriP(PA, PB, PD, Face)
      else
        Result.AddQuadP(PA, PB, PC, PD, Face);
    end;
  end;
  { orientacao: normais para fora (volume positivo) }
  if Result.Volume < 0 then
    Result.Flip;
  Result.RefreshPlaneNormals;
  if not Result.CheckClosed(Err) then;
end;

procedure TCadRebuilder.BuildHole(H: TCadHole);
var
  S: TCadSketch;
  F: TCadFeature;
  Fr: TCadFrame;
  E, Err: string;
  I, K, Segs: Integer;
  Ent: TSketchEntity;
  Pts: array of TCadVec2;
  Prof: TCadHoleProfile;
  B: TCadBox3;
  Through, Rmax: Double;
  C, X, Y, Z: TCadVec3;
  Tool, One: TCadMesh;
  Rec: TCadThreadRec;
  TL: Double;
  OErr: string;
  J: Integer;
  HR0, HZ0, HR1, HZ1: array of Double;
  HNm: array of string;
begin
  F := FDoc.FindById(H.SketchId);
  if not (F is TCadSketch) then
  begin
    H.SetState(fsError, 'Esboço dos furos não encontrado');
    Exit;
  end;
  S := TCadSketch(F);
  if not SketchFrame(S, Fr, E) then
  begin
    H.SetState(fsError, E);
    Exit;
  end;
  { centros: pontos do esboco; sem pontos, centros dos circulos }
  SetLength(Pts, 0);
  for I := 0 to S.EntityCount - 1 do
  begin
    Ent := S.Entity(I);
    if (Ent.Kind = sePoint) and not Ent.Construction then
    begin
      SetLength(Pts, Length(Pts) + 1);
      Pts[High(Pts)] := Ent.P1;
    end;
  end;
  if Length(Pts) = 0 then
    for I := 0 to S.EntityCount - 1 do
    begin
      Ent := S.Entity(I);
      if (Ent.Kind = seCircle) and not Ent.Construction then
      begin
        SetLength(Pts, Length(Pts) + 1);
        Pts[High(Pts)] := Ent.P1;
      end;
    end;
  if Length(Pts) = 0 then
  begin
    H.SetState(fsError, 'O esboço não tem pontos para os furos');
    Exit;
  end;
  B := ModelBounds;
  if B.Empty then
  begin
    H.SetState(fsError, 'Furo sem corpo: crie um ressalto antes');
    Exit;
  end;
  Through := VLen(BoxSize(B)) * 2 + 10;
  Prof := H.Profile(Through);
  if Length(Prof) = 0 then
  begin
    H.SetState(fsError, 'Tamanho de furo inválido');
    Exit;
  end;
  Rmax := 0;
  for I := 0 to High(Prof) do
    Rmax := Max(Rmax, Max(Prof[I].R0, Prof[I].R1));
  Segs := EnsureRange(Ceil(Pi / ArcCos(EnsureRange(1 - Max(FChord, 0.005) / Max(Rmax, 0.1), -1, 0.9999))), 24, 96);
  Z := Fr.Normal;
  X := Fr.XDir;
  Y := Fr.YDir;
  if H.Reverse then
  begin
    Z := VNeg(Z);
    Y := VNeg(Y);
  end;
  Tool := TCadMesh.Create;
  Rec := TCadThreadRec.Create;
  try
    for K := 0 to High(Pts) do
    begin
      C := FrameToWorld(Fr, Pts[K]);
      One := RevolveProfile(Prof, C, X, Y, Z, H.Name + '/' + IntToStr(K + 1), Segs);
      if FOcct then
      begin
        SetLength(HR0, Length(Prof)); SetLength(HZ0, Length(Prof));
        SetLength(HR1, Length(Prof)); SetLength(HZ1, Length(Prof)); SetLength(HNm, Length(Prof));
        for J := 0 to High(Prof) do
        begin
          HR0[J] := Prof[J].R0; HZ0[J] := Prof[J].Z0; HR1[J] := Prof[J].R1; HZ1[J] := Prof[J].Z1;
          HNm[J] := H.Name + '/' + IntToStr(K + 1) + '/' + Prof[J].Name;
        end;
        ExactAdd(OcctRevolveRZ(C, X, Z, HR0, HZ0, HR1, HZ1, HNm, OErr));
      end;
      try
        Tool.Append(One);
      finally
        One.Free;
      end;
      if H.HoleType = htTapped then
      begin
        SetLength(Rec.Marks, Length(Rec.Marks) + 1);
        Rec.Marks[High(Rec.Marks)].Center := C;
        Rec.Marks[High(Rec.Marks)].Axis := Z;
        Rec.Marks[High(Rec.Marks)].Radius := H.ThreadDiameter / 2;
        if H.EndCond = heThroughAll then
          TL := Through
        else
          TL := H.Depth;
        if (H.ThreadDepth > 0) and (H.ThreadDepth < TL) then
          TL := H.ThreadDepth;
        Rec.Marks[High(Rec.Marks)].Length := TL;
      end;
    end;
    I := FThreadMap.IndexOf(IntToStr(H.Id));
    if I >= 0 then
      FThreadMap.Delete(I);
    FThreadMap.AddObject(IntToStr(H.Id), Rec);
    Rec := nil;
  finally
    Rec.Free;
  end;
  if not Tool.CheckClosed(Err) then
  begin
    Tool.Free;
    H.SetState(fsError, 'Ferramenta do furo inválida: ' + Err);
    Exit;
  end;
  ApplyTool(H, Tool, True, False, False, True, nil);
end;

{ ---------- padroes e espelho ---------- }

function TCadRebuilder.ResolveDir(const ARef: string; out D: TCadVec3; out AError: string): Boolean;
var
  R: string;
  Fr: TCadFrame;
  A, B: TCadVec3;
begin
  Result := True;
  AError := '';
  R := LowerCase(Trim(ARef));
  if R = 'x' then D := V3(1, 0, 0)
  else if R = 'y' then D := V3(0, 1, 0)
  else if R = 'z' then D := V3(0, 0, 1)
  else if (Pos('plane:', R) = 1) or (Pos('face:', ARef) = 1) then
  begin
    Result := ResolvePlane(ARef, Fr, AError);
    D := Fr.Normal;
  end
  else
  begin
    Result := ResolveLine(ARef, A, B, AError);
    D := VNorm(VSub(B, A));
  end;
end;

function TCadRebuilder.ResolveAxis(const ARef: string; out A, U: TCadVec3; out AError: string): Boolean;
var
  R: string;
  Bd: TCadBody;
  F: Integer;
  B: TCadVec3;
begin
  Result := True;
  AError := '';
  A := V3(0, 0, 0);
  R := LowerCase(Trim(ARef));
  if R = 'x' then U := V3(1, 0, 0)
  else if R = 'y' then U := V3(0, 1, 0)
  else if R = 'z' then U := V3(0, 0, 1)
  else if Pos('face:', ARef) = 1 then
  begin
    Result := FindFace(Copy(ARef, 6, MaxInt), Bd, F) and
      (Bd.Mesh.Faces[F].Surf in [skCylinder, skCone]);
    if not Result then
    begin
      AError := 'Escolha uma face cilíndrica para o eixo: ' + ARef;
      Exit;
    end;
    A := Bd.Mesh.Faces[F].Origin;
    U := VNorm(Bd.Mesh.Faces[F].Axis);
  end
  else
  begin
    Result := ResolveLine(ARef, A, B, AError);
    U := VNorm(VSub(B, A));
  end;
end;

procedure TCadRebuilder.BuildPattern(P: TCadPatternBase);
var
  Mats: array of TCadMat4;
  I, J, K, Idx, Inst: Integer;
  Rec: TCadToolRec;
  D1, D2, A, U, V: TCadVec3;
  Fr: TCadFrame;
  E: string;
  L: TCadLinearPattern;
  C: TCadCircularPattern;
  N2: Integer;
  M: TCadMat4;
  T: TCadMesh;
  Seed: TCadFeature;
  Nm: Double;
  Mirror: Boolean;
  Outside: Integer;
  LastWarn: string;
begin
  E := '';
  Outside := 0;
  LastWarn := '';
  SetLength(Mats, 0);
  Mirror := P is TCadMirror;
  if P is TCadLinearPattern then
  begin
    L := TCadLinearPattern(P);
    if not ResolveDir(L.Dir1, D1, E) then
    begin
      P.SetState(fsError, 'Direção 1: ' + E);
      Exit;
    end;
    if L.Reverse1 then D1 := VNeg(D1);
    N2 := 1;
    D2 := V3(0, 0, 0);
    if L.UseDir2 then
    begin
      if not ResolveDir(L.Dir2, D2, E) then
      begin
        P.SetState(fsError, 'Direção 2: ' + E);
        Exit;
      end;
      if L.Reverse2 then D2 := VNeg(D2);
      N2 := L.Count2;
    end;
    for I := 0 to L.Count1 - 1 do
      for J := 0 to N2 - 1 do
        if (I > 0) or (J > 0) then
        begin
          V := VAdd(VScale(D1, I * L.Spacing1), VScale(D2, J * L.Spacing2));
          SetLength(Mats, Length(Mats) + 1);
          Mats[High(Mats)] := MatTranslate(V.X, V.Y, V.Z);
        end;
  end
  else if P is TCadCircularPattern then
  begin
    C := TCadCircularPattern(P);
    if not ResolveAxis(C.AxisRef, A, U, E) then
    begin
      P.SetState(fsError, 'Eixo: ' + E);
      Exit;
    end;
    for I := 1 to C.Count - 1 do
    begin
      SetLength(Mats, Length(Mats) + 1);
      Mats[High(Mats)] := MatMul(MatTranslate(A.X, A.Y, A.Z),
        MatMul(MatRotate(U, C.StepAngle * I), MatTranslate(-A.X, -A.Y, -A.Z)));
    end;
  end
  else if Mirror then
  begin
    if not ResolvePlane(TCadMirror(P).PlaneRef, Fr, E) then
    begin
      P.SetState(fsError, 'Plano do espelho: ' + E);
      Exit;
    end;
    { reflexao: p' = p - 2 n (n.(p - o)) }
    V := Fr.Normal;
    Nm := VDot(V, Fr.Origin);
    M := MatIdentity;
    M[0, 0] := 1 - 2 * V.X * V.X; M[0, 1] := -2 * V.X * V.Y; M[0, 2] := -2 * V.X * V.Z;
    M[1, 0] := -2 * V.Y * V.X; M[1, 1] := 1 - 2 * V.Y * V.Y; M[1, 2] := -2 * V.Y * V.Z;
    M[2, 0] := -2 * V.Z * V.X; M[2, 1] := -2 * V.Z * V.Y; M[2, 2] := 1 - 2 * V.Z * V.Z;
    M[0, 3] := 2 * Nm * V.X;
    M[1, 3] := 2 * Nm * V.Y;
    M[2, 3] := 2 * Nm * V.Z;
    SetLength(Mats, 1);
    Mats[0] := M;
  end;
  if Length(Mats) = 0 then
  begin
    P.SetState(fsError, 'O padrão não tem cópias');
    Exit;
  end;
  { cada semente deve vir antes e ter geometria }
  for K := 0 to High(P.Seeds) do
  begin
    Seed := FDoc.FindById(P.Seeds[K]);
    if (Seed = nil) or (FDoc.IndexOfId(Seed.Id) >= FDoc.IndexOfId(P.Id)) then
    begin
      P.SetState(fsError, 'Operação a repetir não encontrada (ou depois do padrão)');
      Exit;
    end;
    if Seed.Suppressed or (Seed.State = fsError) or (FTools.IndexOf(IntToStr(Seed.Id)) < 0) then
    begin
      P.SetState(fsError, '"' + Seed.Name + '" não tem geometria para repetir');
      Exit;
    end;
  end;
  Inst := 0;
  for I := 0 to High(Mats) do
    for K := 0 to High(P.Seeds) do
    begin
      Inc(Inst);
      Seed := FDoc.FindById(P.Seeds[K]);
      Idx := FTools.IndexOf(IntToStr(Seed.Id));
      Rec := TCadToolRec(FTools.Objects[Idx]);
      T := Rec.Mesh.Clone;
      T.Transform(Mats[I]);
      if Mirror then
        T.Flip;
      T.RefreshPlaneNormals;
      for J := 0 to T.FaceCount - 1 do
        T.SetFaceName(J, P.Name + '/' + IntToStr(I + 1) + '/' + T.Faces[J].Name);
      ExactReset;
      if FOcct and (Rec.Shape <> nil) then
        ExactAdd(OcctTransform(Rec.Shape, Mats[I], '', P.Name + '/' + IntToStr(I + 1) + '/'));
      P.SetState(fsOk, '');
      ApplyTool(P, T, Rec.IsCut, Rec.Merge, Rec.FlipSide, True, nil);
      if P.State = fsError then
        Exit;
      if P.State = fsWarning then
      begin
        Inc(Outside);
        LastWarn := P.Message;
      end;
    end;
  if Outside > 0 then
    P.SetState(fsWarning, Format('%d de %d cópia(s) com aviso: %s', [Outside, Inst, LastWarn]))
  else
    P.SetState(fsOk, '');
end;

{ ---------- reconstrucao ---------- }

{ Profundidades digitadas como expressao ("D1@Esboço1*2", "1in") sao
  recalculadas a cada reconstrucao (o valor numerico entra na assinatura). }
procedure TCadRebuilder.EvalExprs(F: TCadFeature);
var
  X: TCadExtrude;
  V: Double;
  Err: string;
begin
  if not (F is TCadExtrude) then
    Exit;
  X := TCadExtrude(F);
  if (X.Dir1.DepthExpr <> '') and FDoc.Eval(X.Dir1.DepthExpr, V, Err) then
    X.Dir1.Depth := V;
  if (X.Dir2.DepthExpr <> '') and FDoc.Eval(X.Dir2.DepthExpr, V, Err) then
    X.Dir2.Depth := V;
end;

{ ---------- filete, chanfro e casca (fase 6) ---------- }

function BodyIndexOfFace(L: TFPObjectList; const AName: string; out AFace: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do
  begin
    AFace := TCadBody(L[I]).Mesh.FaceIndex(AName);
    if AFace >= 0 then
      Exit(I);
  end;
  AFace := -1;
  Result := -1;
end;

function TCadRebuilder.CollectBlend(F: TCadBlendBase; out Items: TCadBlendItems;
  out Skipped: Integer; out FirstErr: string): Boolean;
type
  TPair = record
    Body, FA, FB: Integer;
  end;
var
  Pairs: array of TPair;
  I, J, K, Bi, Bj, FA, FB: Integer;
  A, B, Err: string;
  Nb: TCadIdArray;
  M, Tool: TCadMesh;
  Chains: TCadEdgeChains;
  P: TCadBlendParams;
  IsCut: Boolean;

  procedure AddPair(ABody, X, Y: Integer);
  var
    Q: Integer;
  begin
    for Q := 0 to High(Pairs) do
      if (Pairs[Q].Body = ABody) and (((Pairs[Q].FA = X) and (Pairs[Q].FB = Y)) or
        ((Pairs[Q].FA = Y) and (Pairs[Q].FB = X))) then
        Exit;
    SetLength(Pairs, Length(Pairs) + 1);
    Pairs[High(Pairs)].Body := ABody;
    Pairs[High(Pairs)].FA := X;
    Pairs[High(Pairs)].FB := Y;
  end;

begin
  Items := nil;
  Pairs := nil;
  FirstErr := '';
  Skipped := 0;
  P := Default(TCadBlendParams);
  P.ChordTol := FChord;
  if F is TCadFillet3D then
  begin
    P.Kind := bkFillet;
    P.Radius := TCadFillet3D(F).Radius;
  end
  else
  begin
    P.Kind := bkChamfer;
    TCadChamfer3D(F).Distances(P.D1, P.D2);
  end;
  for I := 0 to High(F.Edges) do
    if CadParseEdgeRef(F.Edges[I], A, B) then
    begin
      Bi := BodyIndexOfFace(FBodies, A, FA);
      Bj := BodyIndexOfFace(FBodies, B, FB);
      if (Bi < 0) or (Bi <> Bj) then
      begin
        Inc(Skipped);
        if FirstErr = '' then FirstErr := 'aresta não encontrada: ' + A + ' | ' + B;
        Continue;
      end;
      AddPair(Bi, FA, FB);
    end
    else if Copy(F.Edges[I], 1, 5) = 'face:' then
    begin
      Bi := BodyIndexOfFace(FBodies, Copy(F.Edges[I], 6, MaxInt), FA);
      if Bi < 0 then
      begin
        Inc(Skipped);
        if FirstErr = '' then FirstErr := 'face não encontrada: ' + Copy(F.Edges[I], 6, MaxInt);
        Continue;
      end;
      M := Body(Bi).Mesh;
      Nb := CadFaceNeighbors(M, FA);
      for K := 0 to High(Nb) do
        { costura entre faces coplanares nao e aresta }
        if not ((M.Faces[FA].Surf = skPlane) and (M.Faces[Nb[K]].Surf = skPlane) and
          (VDot(M.Faces[FA].Axis, M.Faces[Nb[K]].Axis) > 0.99999)) then
          AddPair(Bi, FA, Nb[K]);
    end;
  for I := 0 to High(Pairs) do
  begin
    M := Body(Pairs[I].Body).Mesh;
    Chains := CadEdgeChains(M, Pairs[I].FA, Pairs[I].FB);
    for J := 0 to High(Chains) do
    begin
      Tool := CadBlendTool(M, Pairs[I].FA, Pairs[I].FB, Chains[J], P,
        F.Name + '/' + IntToStr(Length(Items) + 1), IsCut, Err);
      if Tool = nil then
      begin
        Inc(Skipped);
        if FirstErr = '' then
          FirstErr := M.Faces[Pairs[I].FA].Name + ' | ' + M.Faces[Pairs[I].FB].Name + ': ' + Err;
        Continue;
      end;
      SetLength(Items, Length(Items) + 1);
      Items[High(Items)].Body := Pairs[I].Body;
      Items[High(Items)].Tool := Tool;
      Items[High(Items)].IsCut := IsCut;
    end;
  end;
  Result := Length(Items) > 0;
end;

function TCadRebuilder.BlendPreview(F: TCadBlendBase; out AnyCut: Boolean; out AError: string): TCadMesh;
var
  Items: TCadBlendItems;
  Skipped, I: Integer;
begin
  Result := nil;
  AnyCut := False;
  if not CollectBlend(F, Items, Skipped, AError) then
    Exit;
  Result := TCadMesh.Create;
  for I := 0 to High(Items) do
  begin
    Result.Append(Items[I].Tool);
    AnyCut := AnyCut or Items[I].IsCut;
    Items[I].Tool.Free;
  end;
end;

procedure BlendNames(F: TCadBlendBase; B: TCadBody; out FA, FB: TCadStrArray);
var
  I, K, Fi: Integer;
  A, Bn: string;
  M: TCadMesh;
  Nb: TCadIdArray;
begin
  FA := nil;
  FB := nil;
  M := B.Mesh;
  for I := 0 to High(F.Edges) do
    if CadParseEdgeRef(F.Edges[I], A, Bn) then
    begin
      if (M.FaceIndex(A) < 0) or (M.FaceIndex(Bn) < 0) then
        Continue;
      SetLength(FA, Length(FA) + 1);
      SetLength(FB, Length(FB) + 1);
      FA[High(FA)] := A;
      FB[High(FB)] := Bn;
    end
    else if Copy(F.Edges[I], 1, 5) = 'face:' then
    begin
      Fi := M.FaceIndex(Copy(F.Edges[I], 6, MaxInt));
      if Fi < 0 then
        Continue;
      Nb := CadFaceNeighbors(M, Fi);
      for K := 0 to High(Nb) do
      begin
        SetLength(FA, Length(FA) + 1);
        SetLength(FB, Length(FB) + 1);
        FA[High(FA)] := M.Faces[Fi].Name;
        FB[High(FB)] := M.Faces[Nb[K]].Name;
      end;
    end;
end;

function TCadRebuilder.BlendFallbackOcct(F: TCadBlendBase; B: TCadBody; const NA, NB: TCadStrArray;
  out AError: string): TOcctShape;
var
  K, J, FA, FB: Integer;
  Cur, R, Tool: TOcctShape;
  M: TCadMesh;
  P: TCadBlendParams;
  Chains: TCadEdgeChains;
  Fr: TCadFrame;
  Segs: TCadSectionSegs;
  Len, D1, D2: Double;
  IsCut: Boolean;
  E: string;
  Ident: TCadMat4;
begin
  AError := '';
  P := Default(TCadBlendParams);
  P.ChordTol := FChord;
  if F is TCadFillet3D then
  begin
    P.Kind := bkFillet;
    P.Radius := TCadFillet3D(F).Radius;
  end
  else
  begin
    P.Kind := bkChamfer;
    TCadChamfer3D(F).Distances(D1, D2);
    P.D1 := D1;
    P.D2 := D2;
  end;
  Ident := MatIdentity;
  Cur := OcctCopy(B.Shape);
  for K := 0 to High(NA) do
  begin
    { 1) so esta aresta pelo OCCT }
    if P.Kind = bkFillet then
      R := OcctFillet(Cur, [NA[K]], [NB[K]], P.Radius, F.Name + '#', E)
    else
      R := OcctChamfer(Cur, [NA[K]], [NB[K]], P.D1, P.D2, F.Name + '#', E);
    if R <> nil then
    begin
      Tool := OcctTransform(R, Ident, F.Name + '#/1', F.Name + '/' + IntToStr(K + 1));
      OcctFree(R);
      OcctFree(Cur);
      Cur := Tool;
      Continue;
    end;
    { 2) ferramenta de secao exata (aresta reta entre planos) }
    M := ShapeMesh(Cur, E);
    if M = nil then
    begin
      OcctFree(Cur);
      AError := E;
      Exit(nil);
    end;
    try
      FA := M.FaceIndex(NA[K]);
      FB := M.FaceIndex(NB[K]);
      if (FA < 0) or (FB < 0) then
        Continue;
      if (M.Faces[FA].Surf <> skPlane) or (M.Faces[FB].Surf <> skPlane) then
      begin
        OcctFree(Cur);
        AError := 'o OpenCascade não conseguiu fazer a aresta ' + NA[K] + ' | ' + NB[K] +
          ' (entre faces curvas): tente outro raio ou inclua as arestas vizinhas na mesma operação';
        Exit(nil);
      end;
      Chains := CadEdgeChains(M, FA, FB);
      for J := 0 to High(Chains) do
      begin
        if not CadBlendSection(M, Chains[J], P, Fr, Segs, Len, IsCut, E) then
        begin
          OcctFree(Cur);
          AError := NA[K] + ' | ' + NB[K] + ': ' + E;
          Exit(nil);
        end;
        Tool := OcctBlendTool(Fr, Segs, Len, F.Name + '/' + IntToStr(K + 1), E);
        if Tool = nil then
        begin
          OcctFree(Cur);
          AError := E;
          Exit(nil);
        end;
        if IsCut then
          R := OcctBoolean(Cur, Tool, 1, E)
        else
          R := OcctBoolean(Cur, Tool, 0, E);
        OcctFree(Tool);
        if R = nil then
        begin
          OcctFree(Cur);
          AError := E;
          Exit(nil);
        end;
        OcctFree(Cur);
        Cur := R;
      end;
    finally
      M.Free;
    end;
  end;
  Result := Cur;
end;

procedure TCadRebuilder.BuildBlend(F: TCadBlendBase);
var
  NA, NB: TCadStrArray;
  RS: TOcctShape;
  D1, D2: Double;
  Items: TCadBlendItems;
  Ops: TCadBoolOperands;
  I, K, Bi, Done, Skipped: Integer;
  Err, FirstErr: string;
  Cur, R: TCadMesh;
  Any: Boolean;
begin
  if FBodies.Count = 0 then
  begin
    F.SetState(fsError, CAD_FEATURE_NAMES[F.Kind] + ' sem corpo: crie um ressalto antes');
    Exit;
  end;
  if FOcct then
  begin
    { OpenCascade: filete/chanfro exatos em qualquer aresta }
    Done := 0;
    FirstErr := '';
    for Bi := 0 to FBodies.Count - 1 do
    begin
      if Body(Bi).Shape = nil then
        Continue;
      BlendNames(F, Body(Bi), NA, NB);
      if Length(NA) = 0 then
        Continue;
      if F is TCadFillet3D then
        RS := OcctFillet(Body(Bi).Shape, NA, NB, TCadFillet3D(F).Radius, F.Name, Err)
      else
      begin
        TCadChamfer3D(F).Distances(D1, D2);
        RS := OcctChamfer(Body(Bi).Shape, NA, NB, D1, D2, F.Name, Err);
      end;
      if RS = nil then
      begin
        { o OCCT nao fez o conjunto (ex.: aresta que termina em filete anterior
          do mesmo raio): aresta por aresta, e se ainda falhar, ferramenta de
          secao exata varrida na aresta (corte/uniao) }
        RS := BlendFallbackOcct(F, Body(Bi), NA, NB, Err);
        if RS = nil then
        begin
          F.SetState(fsError, 'Falha no ' + LowerCase(CAD_FEATURE_NAMES[F.Kind]) + ': ' + Err);
          Exit;
        end;
      end;
      if Err <> '' then
        FirstErr := Err;
      Cur := ShapeMesh(RS, Err);
      if Cur = nil then
      begin
        OcctFree(RS);
        F.SetState(fsError, 'Falha na tesselagem: ' + Err);
        Exit;
      end;
      OcctFree(Body(Bi).Shape);
      Body(Bi).Shape := RS;
      Body(Bi).Mesh.Free;
      Body(Bi).Mesh := Cur;
      Inc(Done);
    end;
    if Done = 0 then
      F.SetState(fsError, 'Nenhuma aresta válida')
    else if FirstErr <> '' then
      F.SetState(fsWarning, FirstErr)
    else
      F.SetState(fsOk, '');
    Exit;
  end;
  if not CollectBlend(F, Items, Skipped, FirstErr) then
  begin
    F.SetState(fsError, 'Nenhuma aresta válida (' + FirstErr + ')');
    Exit;
  end;
  Done := 0;
  try
    for Bi := 0 to FBodies.Count - 1 do
    begin
      Any := False;
      for I := 0 to High(Items) do
        if Items[I].Body = Bi then
          Any := True;
      if not Any then
        Continue;
      Ops := nil;
      for K := 0 to 1 do
        for I := 0 to High(Items) do
          if (Items[I].Body = Bi) and (Items[I].IsCut = (K = 0)) then
          begin
            SetLength(Ops, Length(Ops) + 1);
            Ops[High(Ops)].Mesh := Items[I].Tool;
            if Items[I].IsCut then Ops[High(Ops)].Op := boDifference
            else Ops[High(Ops)].Op := boUnion;
          end;
      if Length(Ops) > 1 then
      begin
        CadLog('BLEND.SEQUENCE.START', Format('id=%d body=%d tools=%d', [F.Id, Bi, Length(Ops)]));
        R := CadBooleanBlendSequence(Body(Bi).Mesh, Ops, Err);
        if R <> nil then
        begin
          CadLog('BLEND.SEQUENCE.END', Format('id=%d body=%d triangles=%d volume=%.6f',
            [F.Id, Bi, R.TriCount, R.Volume]));
          Body(Bi).Mesh.Free; Body(Bi).Mesh := R;
          Inc(Done, Length(Ops)); Continue;
        end;
        CadLog('BLEND.SEQUENCE.FALLBACK', Format('id=%d body=%d error=%s', [F.Id, Bi, Err]));
      end;
      Cur := Body(Bi).Mesh.Clone;
      { cortes (arestas convexas) antes das unioes (concavas): a booleana
        fica mais estavel nessa ordem }
      for K := 0 to 1 do
        for I := 0 to High(Items) do
        begin
          if (Items[I].Body <> Bi) or (Items[I].IsCut <> (K = 0)) then
            Continue;
          if Items[I].IsCut then
            R := CadBooleanBlend(Cur, Items[I].Tool, boDifference, Err)
          else
            R := CadBooleanBlend(Cur, Items[I].Tool, boUnion, Err);
          if R = nil then
          begin
            Cur.Free;
            F.SetState(fsError, 'Falha na booleana do ' + LowerCase(CAD_FEATURE_NAMES[F.Kind]) +
              ': ' + Err + ' (tente um valor menor)');
            Exit;
          end;
          Cur.Free;
          Cur := R;
          Inc(Done);
        end;
      Body(Bi).Mesh.Free;
      Body(Bi).Mesh := Cur;
    end;
  finally
    for I := 0 to High(Items) do
      Items[I].Tool.Free;
  end;
  if Done = 0 then
    F.SetState(fsError, 'Nenhuma aresta aplicada (' + FirstErr + ')')
  else if Skipped > 0 then
    F.SetState(fsWarning, Format('%d aresta(s) ignorada(s): %s', [Skipped, FirstErr]))
  else
    F.SetState(fsOk, '');
end;

procedure TCadRebuilder.BuildImport(F: TCadImportStep);
var
  Fn, E: string;
  S, Part: TOcctShape;
  M: TCadMesh;
  I, N: Integer;
begin
  if not FOcct then
  begin
    F.SetState(fsError, 'Importar STEP precisa do núcleo OpenCascade (' + OcctLoadError + ')');
    Exit;
  end;
  Fn := F.ResolvedPath(FDoc.FileName);
  if not FileExists(Fn) then
  begin
    F.SetState(fsError, 'Arquivo não encontrado: ' + Fn);
    Exit;
  end;
  S := OcctStepRead(Fn, F.Name, E);
  if S = nil then
  begin
    F.SetState(fsError, E);
    Exit;
  end;
  N := OcctComponents(S);
  if N = 0 then
  begin
    OcctFree(S);
    F.SetState(fsError, 'O arquivo STEP não tem sólidos');
    Exit;
  end;
  for I := 0 to N - 1 do
  begin
    Part := OcctComponent(S, I);
    M := ShapeMesh(Part, E);
    if M = nil then
    begin
      OcctFree(Part);
      Continue;
    end;
    FBodies.Add(TCadBody.Create(NewBodyName, M));
    Body(FBodies.Count - 1).Shape := Part;
  end;
  OcctFree(S);
  F.SetState(fsOk, '');
end;

procedure TCadRebuilder.BuildShell(S: TCadShell);
var
  I, K, Fi, Done: Integer;
  Targets: array of Boolean;
  Removed: array of Boolean;
  M, Outer, Inner, R: TCadMesh;
  Err, FName: string;
  Any: Boolean;
  Names: TCadStrArray;
  RS: TOcctShape;
begin
  if FBodies.Count = 0 then
  begin
    S.SetState(fsError, 'Casca sem corpo: crie um ressalto antes');
    Exit;
  end;
  SetLength(Targets, FBodies.Count);
  Any := False;
  for I := 0 to High(S.Faces) do
  begin
    FName := S.Faces[I];
    if Copy(FName, 1, 5) = 'face:' then
      FName := Copy(FName, 6, MaxInt);
    K := BodyIndexOfFace(FBodies, FName, Fi);
    if K < 0 then
    begin
      S.SetState(fsError, 'Face não encontrada: ' + FName);
      Exit;
    end;
    Targets[K] := True;
    Any := True;
  end;
  if not Any then
    for I := 0 to High(Targets) do
      Targets[I] := True;
  Done := 0;
  for I := 0 to FBodies.Count - 1 do
  begin
    if not Targets[I] then
      Continue;
    M := Body(I).Mesh;
    if FOcct and (Body(I).Shape <> nil) then
    begin
      Names := nil;
      for K := 0 to High(S.Faces) do
      begin
        FName := S.Faces[K];
        if Copy(FName, 1, 5) = 'face:' then
          FName := Copy(FName, 6, MaxInt);
        if M.FaceIndex(FName) >= 0 then
        begin
          SetLength(Names, Length(Names) + 1);
          Names[High(Names)] := FName;
        end;
      end;
      if S.Outward then
        RS := OcctShell(Body(I).Shape, Names, S.Thickness, S.Name, Err)
      else
        RS := OcctShell(Body(I).Shape, Names, -S.Thickness, S.Name, Err);
      if RS = nil then
      begin
        S.SetState(fsError, 'Falha na casca: ' + Err);
        Exit;
      end;
      R := ShapeMesh(RS, Err);
      if R = nil then
      begin
        OcctFree(RS);
        S.SetState(fsError, 'Falha na tesselagem: ' + Err);
        Exit;
      end;
      OcctFree(Body(I).Shape);
      Body(I).Shape := RS;
      Body(I).Mesh.Free;
      Body(I).Mesh := R;
      Inc(Done);
      Continue;
    end;
    SetLength(Removed, M.FaceCount);
    for K := 0 to High(Removed) do
      Removed[K] := False;
    for K := 0 to High(S.Faces) do
    begin
      FName := S.Faces[K];
      if Copy(FName, 1, 5) = 'face:' then
        FName := Copy(FName, 6, MaxInt);
      Fi := M.FaceIndex(FName);
      if Fi >= 0 then
        Removed[Fi] := True;
    end;
    if S.Outward then
    begin
      Outer := CadOffsetMesh(M, S.Thickness, 0, Removed, Err);
      Inner := CadOffsetMesh(M, 0, S.Thickness, Removed, Err);
    end
    else
    begin
      Outer := M.Clone;
      Inner := CadOffsetMesh(M, -S.Thickness, S.Thickness, Removed, Err);
    end;
    try
      for K := 0 to Inner.FaceCount - 1 do
        Inner.SetFaceName(K, S.Name + '/' + Inner.Faces[K].Name);
      if (Inner.Volume <= 0) or (Inner.Volume >= Outer.Volume) or not Inner.CheckClosed(Err) then
      begin
        S.SetState(fsError, 'Espessura grande demais para esta peça');
        Exit;
      end;
      R := CadBoolean(Outer, Inner, boDifference, Err);
      if R = nil then
      begin
        S.SetState(fsError, 'Falha na casca: ' + Err + ' (tente uma espessura menor)');
        Exit;
      end;
      Body(I).Mesh.Free;
      Body(I).Mesh := R;
      Inc(Done);
    finally
      Outer.Free;
      Inner.Free;
    end;
  end;
  if Done = 0 then
    S.SetState(fsError, 'Nenhum corpo para a casca')
  else
    S.SetState(fsOk, '');
end;

{ ---------- reconstrucao ---------- }

function TCadRebuilder.Rebuild: Integer;
var
  I, Last, J: Integer;
  F: TCadFeature;
  Sig, Prev, RefError: string;
  Reuse: Boolean;
  Snap: TFPObjectList;
  NBodiesBefore: Integer;
  Started: QWord;
begin
  Result := 0;
  Started:=GetTickCount64;
  CadLog('REBUILD.START',Format('features=%d rollback=%d',[FDoc.Count,FDoc.RollbackIndex]));
  F:=nil;
  try
  FRecomputed := 0;
  FOcct := FUseOcct and OcctAvailable;
  if FOcct <> FLastOcct then
  begin
    { trocou o nucleo: nada do cache serve }
    FSigs.Clear;
    FSnaps.Clear;
    FLastOcct := FOcct;
  end;
  FBodies.Clear;
  FNextBody := 0;
  Last := FDoc.Count - 1;
  if (FDoc.RollbackIndex >= 0) and (FDoc.RollbackIndex <= FDoc.Count) then
    Last := FDoc.RollbackIndex - 1;
  Prev := '';
  Reuse := True;
  for I := 0 to FDoc.Count - 1 do
  begin
    F := FDoc[I];
    CadLog('REBUILD.FEATURE',Format('id=%d name=%s params=%s',[F.Id,F.Name,FeatureSig(F)]));
    if I > Last then
    begin
      F.SetState(fsOk, 'Abaixo da barra de retrocesso');
      Continue;
    end;
    EvalExprs(F);
    Sig := MD5Print(MD5String(Prev + '|' + FeatureSig(F)));
    { esbocos dependem do proprio estado resolvido: assinatura inclui a geometria }
    Prev := Sig;
    { LoadParams also invalidates derived plane/axis geometry when Cancel
      restores identical parameters. Body snapshots do not store that geometry. }
    if Reuse and (I < FSigs.Count) and (FSigs[I] = Sig) and (I < FSnaps.Count) and
      not (F is TCadSketch) and
      not ((F is TCadPlane) and not TCadPlane(F).FrameValid) and
      not ((F is TCadAxis) and not TCadAxis(F).Valid) then
    begin
      { cache: corpos depois desta operacao }
      FBodies.Clear;
      Snap := TFPObjectList(FSnaps[I]);
      for J := 0 to Snap.Count - 1 do
        FBodies.Add(TCadBody(Snap[J]).Clone);
      { nomes de corpo seguem do cache }
      FNextBody := Max(FNextBody, FBodies.Count);
      for J := 0 to FBodies.Count - 1 do
        FNextBody := Max(FNextBody, StrToIntDef(Copy(Body(J).Name, 6, MaxInt), 0));
      CadLog('REBUILD.CACHE',Format('id=%d state=%d message=%s',[F.Id,Ord(F.State),F.Message]));
      if F.State = fsError then
        Inc(Result);
      Continue;
    end;
    if not (F is TCadSketch) then
      Reuse := False;
    NBodiesBefore := FBodies.Count;
    ExactReset;
    if F.Suppressed then
      F.SetState(fsOk, 'Suprimido')
    else if F is TCadPlane then
      BuildPlane(TCadPlane(F))
    else if F is TCadAxis then
      BuildAxis(TCadAxis(F))
    else if F is TCadSketch then
    begin
      if RefreshSketchReferences(TCadSketch(F),RefError) then FDoc.SolveSketch(TCadSketch(F))
      else F.SetState(fsError,RefError);
      { a geometria resolvida entra na assinatura das seguintes }
      Prev := MD5Print(MD5String(Prev + FeatureSig(F)));
      if not Reuse then
        Inc(FRecomputed);
    end
    else if F is TCadExtrude then
      BuildExtrude(TCadExtrude(F))
    else if F is TCadRevolve then
      BuildRevolve(TCadRevolve(F))
    else if F is TCadHole then
      BuildHole(TCadHole(F))
    else if F is TCadPatternBase then
      BuildPattern(TCadPatternBase(F))
    else if F is TCadBlendBase then
      BuildBlend(TCadBlendBase(F))
    else if F is TCadShell then
      BuildShell(TCadShell(F))
    else if F is TCadImportStep then
      BuildImport(TCadImportStep(F))
    else if F.Kind = cfOrigin then
      F.SetState(fsOk, '')
    else
      F.SetState(fsError, 'Operação ainda não implementada: ' + CAD_FEATURE_NAMES[F.Kind]);
    if not (F is TCadSketch) then
      Inc(FRecomputed);
    if F.State = fsError then
      Inc(Result);
    { guarda o cache desta posicao }
    while FSigs.Count <= I do FSigs.Add('');
    while FSnaps.Count <= I do FSnaps.Add(TFPObjectList.Create(True));
    FSigs[I] := Sig;
    FSnaps[I] := CloneBodies(FBodies);
  end;
  { descarta cache alem do fim }
  while FSigs.Count > FDoc.Count do FSigs.Delete(FSigs.Count - 1);
  while FSnaps.Count > FDoc.Count do FSnaps.Delete(FSnaps.Count - 1);
  CadLog('REBUILD.END',Format('errors=%d recomputed=%d bodies=%d elapsed_ms=%d',
    [Result,FRecomputed,BodyCount,GetTickCount64-Started]));
  except on E:Exception do
  begin
    if F<>nil then CadLog('REBUILD.FAILED',Format('id=%d name=%s',[F.Id,F.Name]));
    CadLogException('reconstrucao',E);Invalidate;raise;
  end;end;
end;

end.
