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
  multicad_sweep, multicad_csg, multicad_bridge, multicad_triangulate;

type
  TCadBody = class
  public
    Name: string;
    Mesh: TCadMesh;
    constructor Create(const AName: string; AMesh: TCadMesh);
    destructor Destroy; override;
    function Clone: TCadBody;
  end;

  TCadRebuilder = class
  private
    FDoc: TCadDocument;
    FBodies: TFPObjectList;
    FSigs: TStringList;           { assinatura por indice }
    FSnaps: TFPObjectList;        { lista de corpos (TFPObjectList) por indice }
    FNextBody: Integer;
    FRecomputed: Integer;
    FChord: Double;
    procedure ClearBodies(L: TFPObjectList);
    function CloneBodies(L: TFPObjectList): TFPObjectList;
    function FeatureSig(F: TCadFeature): string;
    function NewBodyName: string;
    procedure BuildPlane(P: TCadPlane);
    procedure BuildAxis(A: TCadAxis);
    procedure BuildExtrude(X: TCadExtrude);
    procedure BuildRevolve(R: TCadRevolve);
    procedure ApplyTool(F: TCadFeature; Tool: TCadMesh; IsCut, Merge, FlipSide, ScopeAll: Boolean;
      const ScopeBodies: TCadStrArray);
    function ModelBounds: TCadBox3;
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
    { Operacoes recalculadas na ultima reconstrucao (o resto veio do cache). }
    property Recomputed: Integer read FRecomputed;
    property ChordTol: Double read FChord write FChord;
  end;

implementation

uses
  multicad_materials;

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
  inherited;
end;

function TCadBody.Clone: TCadBody;
begin
  Result := TCadBody.Create(Name, Mesh.Clone);
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
  FChord := 0.01;
end;

destructor TCadRebuilder.Destroy;
begin
  FSnaps.Free;
  FSigs.Free;
  FBodies.Free;
  inherited;
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
    Result := Result + Body(I).Mesh.Volume;
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
  Warn := '';
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
  Cav: TCadExtrudeDir;

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
  Tool := OneDir(X.Dir1, D, S0, X.Name, E);
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

{ ---------- reconstrucao ---------- }

function TCadRebuilder.Rebuild: Integer;
var
  I, Last, J: Integer;
  F: TCadFeature;
  Sig, Prev: string;
  Reuse: Boolean;
  Snap: TFPObjectList;
  NBodiesBefore: Integer;
begin
  Result := 0;
  FRecomputed := 0;
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
    if I > Last then
    begin
      F.SetState(fsOk, 'Abaixo da barra de retrocesso');
      Continue;
    end;
    Sig := MD5Print(MD5String(Prev + '|' + FeatureSig(F)));
    { esbocos dependem do proprio estado resolvido: assinatura inclui a geometria }
    Prev := Sig;
    if Reuse and (I < FSigs.Count) and (FSigs[I] = Sig) and (I < FSnaps.Count) and
      not (F is TCadSketch) then
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
      if F.State = fsError then
        Inc(Result);
      Continue;
    end;
    if not (F is TCadSketch) then
      Reuse := False;
    NBodiesBefore := FBodies.Count;
    if F.Suppressed then
      F.SetState(fsOk, 'Suprimido')
    else if F is TCadPlane then
      BuildPlane(TCadPlane(F))
    else if F is TCadAxis then
      BuildAxis(TCadAxis(F))
    else if F is TCadSketch then
    begin
      FDoc.SolveSketch(TCadSketch(F));
      { a geometria resolvida entra na assinatura das seguintes }
      Prev := MD5Print(MD5String(Prev + FeatureSig(F)));
      if not Reuse then
        Inc(FRecomputed);
    end
    else if F is TCadExtrude then
      BuildExtrude(TCadExtrude(F))
    else if F is TCadRevolve then
      BuildRevolve(TCadRevolve(F))
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
end;

end.
