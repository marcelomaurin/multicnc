unit multiphysics_analysis;

{ Executa as analises do projeto: gera a malha das pecas, traduz as
  condicoes de contorno em cargas do FEM, resolve e decide a fidelidade.

  Fidelidade (README / AI_GUIDE):
  - ENGENHARIA: malha sem elemento invertido e estudo de convergencia com
    variacao < 5% da grandeza principal entre a malha h e a malha h/1,5;
  - ESTIMATIVA: convergencia nao verificada ou acima de 5%, ou malha ruim;
  - VALIDADO: nunca e atribuido automaticamente.

  Contato entre pecas: as pecas sao malhadas separadamente e cada contato
  do projeto vira amarracao colada (multiphysics_contact, penalidade no
  FEM), como o *TIE do CalculiX. Sem atrito nem separacao. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, multiphysics_types, multiphysics_vector,
  multiphysics_geometry, multiphysics_mesh, multiphysics_sparse, multiphysics_fem,
  multiphysics_project, multiphysics_scenario, multiphysics_contact, multiphysics_ccx;

type
  TAnalysisKind = (akStatic, akThermal, akThermoMechanical, akModal);

  TAnalysisRun = class
  private
    FProject: TPhysicsProject;
    function BuildMesh(M: TFEMMesh; H: Double): Boolean;
    function ResolveTags(M: TFEMMesh; const B: TBoundaryCondition): TIntArray;
    procedure SetupModel(F: TFEMModel; M: TFEMMesh; ThermalLoads: Boolean);
    function SolveOnce(M: TFEMMesh; H: Double; Kind: TAnalysisKind; out Main: Double): Boolean;
    function BuildTies(M: TFEMMesh; H: Double; Verbose: Boolean): TMeshTies;
    function SolveCCX(F: TFEMModel; M: TFEMMesh; Kind: TAnalysisKind; out Main: Double): Boolean;
    function DoRun(AKind: TAnalysisKind): Boolean;
  public
    CCXExe: string;                 { caminho do ccx (Settings.Solver = 1) }
    CCXTimeout: Integer;            { s }
    Mesh: TFEMMesh;                 { malha do ultimo resultado }
    Kind: TAnalysisKind;
    Ok: Boolean;
    Message: string;
    Log: TStringList;
    Fidelity: TFidelityLevel;
    FidelityReason: string;
    Convergence: Double;            { variacao relativa entre malhas; -1 = nao verificada }
    StaticRes: TStaticResult;
    ThermalRes: TThermalResult;
    ModalRes: TModalResult;
    ElapsedMs: Int64;
    constructor Create(AProject: TPhysicsProject);
    destructor Destroy; override;
    function Run(AKind: TAnalysisKind): Boolean;
    { so a malha (para conferir antes de resolver) }
    function MeshOnly(out Q: TMeshQuality): Boolean;
    function Summary: TPhysicsResult;
  end;

function AnalysisKindName(K: TAnalysisKind): string;
function ToFEMMaterial(const M: TMaterial): TFEMMaterial;

implementation

uses DateUtils;

function AnalysisKindName(K: TAnalysisKind): string;
begin
  case K of
    akStatic: Result := 'Estatica linear';
    akThermal: Result := 'Termica permanente';
    akThermoMechanical: Result := 'Termomecanica';
    else Result := 'Modal';
  end;
end;

function ToFEMMaterial(const M: TMaterial): TFEMMaterial;
begin
  Result := FEMMaterial(M.Name, M.YoungModulus, M.Poisson, M.Density,
    M.ThermalConductivity, M.ThermalExpansion, M.YieldStrength);
end;

constructor TAnalysisRun.Create(AProject: TPhysicsProject);
begin
  inherited Create;
  FProject := AProject;
  Log := TStringList.Create;
  Mesh := TFEMMesh.Create;
  Convergence := -1;
  CCXExe := FindCCX;
  CCXTimeout := 900;
end;

{ resolve pelo CalculiX: mesmo modelo (malha, cargas, amarracoes) escrito em
  .inp, executado e lido do .frd }
function TAnalysisRun.SolveCCX(F: TFEMModel; M: TFEMMesh; Kind: TAnalysisKind; out Main: Double): Boolean;
var
  Dir, Inp: string;
  R: TFRDResult;
  I, E, A, NN: Integer;
  V, Y: Double;
  Cnt: array of Integer;

  function RunStep(Step: TCCXStep; const Name: string; out FR: TFRDResult): Boolean;
  begin
    Inp := Dir + Name + '.inp';
    DeleteFile(ChangeFileExt(Inp, '.frd'));
    Result := WriteDeck(F, Step, FProject.Settings.Modes, Inp, Log) and RunCCX(CCXExe, Inp, CCXTimeout, Log);
    if Result then
    begin
      FR := ReadFRD(ChangeFileExt(Inp, '.frd'), M.NodeCount);
      Result := FR.Ok;
      if not Result then Message := 'CalculiX: ' + FR.Message;
    end
    else
      Message := 'CalculiX nao resolveu (veja o registro). ccx: ' + IfThen(CCXExe = '', 'nao encontrado', CCXExe);
  end;

begin
  Result := False;
  Main := 0;
  NN := M.NodeCount;
  Dir := GetTempDir + 'multiphysics_ccx' + PathDelim + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  if Kind in [akThermal, akThermoMechanical] then
  begin
    SetupModel(F, M, True);
    if not RunStep(csHeat, 'termico', R) or (Length(R.Temp) <> NN) then Exit;
    FillChar(ThermalRes, SizeOf(ThermalRes), 0);
    ThermalRes.T := Copy(R.Temp);
    ThermalRes.MaxT := -MaxDouble; ThermalRes.MinT := MaxDouble;
    for I := 0 to NN - 1 do
    begin
      ThermalRes.MaxT := Max(ThermalRes.MaxT, R.Temp[I]);
      ThermalRes.MinT := Min(ThermalRes.MinT, R.Temp[I]);
    end;
    ThermalRes.Ok := True;
    ThermalRes.Message := 'Termico permanente pelo CalculiX';
    Main := ThermalRes.MaxT - ThermalRes.MinT;
    Message := ThermalRes.Message;
    if Kind = akThermal then Exit(True);
  end;
  SetupModel(F, M, False);
  if Kind = akThermoMechanical then F.Temperature := ThermalRes.T;
  if Kind = akModal then
  begin
    if not RunStep(csFrequency, 'modal', R) then Exit;
    FillChar(ModalRes, SizeOf(ModalRes), 0);
    ModalRes.Freq := Copy(R.Freq);
    SetLength(ModalRes.Shapes, Length(R.Disp));
    for I := 0 to High(R.Disp) do ModalRes.Shapes[I] := Copy(R.Disp[I]);
    ModalRes.Ok := True;
    ModalRes.Message := Format('Modal pelo CalculiX: %d modos', [Length(R.Freq)]);
    Message := ModalRes.Message;
    if Length(R.Freq) > 0 then Main := R.Freq[0];
    Exit(True);
  end;
  if not RunStep(csStatic, 'estatico', R) then Exit;
  FillChar(StaticRes, SizeOf(StaticRes), 0);
  StaticRes.U := Copy(R.Disp[High(R.Disp)]);
  SetLength(StaticRes.VonMises, NN);
  StaticRes.MinSafety := MaxDouble;
  if Length(R.Stress) > 0 then
    for I := 0 to NN - 1 do
      StaticRes.VonMises[I] := VonMisesOf(Copy(R.Stress[High(R.Stress)], 6 * I, 6));
  { fator de seguranca pelo material das pecas que usam o no }
  SetLength(Cnt, NN);
  for E := 0 to M.ElemCount - 1 do
  begin
    if M.Elems[E].Part > High(F.Materials) then Continue;
    Y := F.Materials[M.Elems[E].Part].Yield;
    if Y <= 0 then Continue;
    for A := 0 to M.NodesPerElement - 1 do
      StaticRes.MinSafety := Min(StaticRes.MinSafety, Y / Max(StaticRes.VonMises[M.Elems[E].N[A]], 1e-30));
  end;
  for I := 0 to NN - 1 do
  begin
    V := Sqrt(Sqr(StaticRes.U[3 * I]) + Sqr(StaticRes.U[3 * I + 1]) + Sqr(StaticRes.U[3 * I + 2]));
    if V > StaticRes.MaxDisp then begin StaticRes.MaxDisp := V; StaticRes.MaxDispNode := I; end;
    if StaticRes.VonMises[I] > StaticRes.MaxVonMises then
    begin
      StaticRes.MaxVonMises := StaticRes.VonMises[I];
      StaticRes.MaxVonMisesNode := I;
    end;
  end;
  StaticRes.Ok := True;
  StaticRes.Dofs := 3 * NN;
  StaticRes.Solve.Method := 'CalculiX (ccx)';
  StaticRes.Message := Format('Estatico linear pelo CalculiX: %d nos, %d elementos', [NN, M.ElemCount]);
  Message := StaticRes.Message;
  Main := StaticRes.MaxDisp;
  Result := True;
end;

destructor TAnalysisRun.Destroy;
begin
  Mesh.Free;
  Log.Free;
  inherited Destroy;
end;

function TAnalysisRun.BuildMesh(M: TFEMMesh; H: Double): Boolean;
var
  I, J, PI_: Integer;
  P: TPhysicsPart;
  Hp: Double;
  T: TGeoTransform;
begin
  M.Clear;
  for I := 0 to FProject.PartCount - 1 do
  begin
    P := FProject.Part(I);
    PI_ := M.AddPart(P.ID);
    if P.Suppressed then Continue;
    if P.MeshSize > 0 then Hp := Min(P.MeshSize, H * P.MeshSize / FProject.Settings.MeshSize) else Hp := H;
    T := P.Transform;
    for J := 0 to High(P.Primitives) do
      M.AddPrimitive(PI_, P.Primitives[J], T, Hp);
  end;
  M.Finalize;
  if FProject.Settings.Quadratic then M.ConvertToTet10;
  Result := M.ElemCount > 0;
end;

{ faces alvo de uma condicao: 'PECA/prim/face' exata, 'PECA/face' em todas
  as primitivas, ou todas as faces da peca }
function TAnalysisRun.ResolveTags(M: TFEMMesh; const B: TBoundaryCondition): TIntArray;
var
  I, N: Integer;
  Name, PartPrefix: string;
  Hit: Boolean;
begin
  Result := nil;
  N := 0;
  PartPrefix := B.TargetID + '/';
  for I := 0 to M.FaceNames.Count - 1 do
  begin
    Name := M.FaceNames[I];
    if not SameText(Copy(Name, 1, Length(PartPrefix)), PartPrefix) then Continue;
    if B.TargetFace = '' then
      Hit := True
    else if Pos('/', B.TargetFace) > 0 then
      Hit := SameText(Name, B.TargetFace)
    else
      { so o nome da face: vale em todas as primitivas da peca }
      Hit := SameText(Copy(Name, LastDelimiter('/', Name) + 1, MaxInt), B.TargetFace);
    if Hit then
    begin
      SetLength(Result, N + 1);
      Result[N] := I;
      Inc(N);
    end;
  end;
end;

procedure TAnalysisRun.SetupModel(F: TFEMModel; M: TFEMMesh; ThermalLoads: Boolean);
var
  I, J, Pi_: Integer;
  B: TBoundaryCondition;
  Tags: TIntArray;
  L: TFEMLoad;
  Total: Double;
begin
  SetLength(F.Materials, FProject.PartCount);
  for I := 0 to FProject.PartCount - 1 do
    F.Materials[I] := ToFEMMaterial(FProject.Part(I).Material);
  F.ClearLoads;
  F.Gravity := V3(0, 0, 0);
  F.RefTemperature := FProject.Environment.AmbientTemperature;
  for I := 0 to FProject.BCCount - 1 do
  begin
    B := FProject.BC(I);
    if B.Kind = bkGravity then
    begin
      if not ThermalLoads then F.Gravity := V3(B.X, B.Y, B.Z);
      Continue;
    end;
    if B.Kind = bkHeatPower then
    begin
      Pi_ := FProject.FindPart(B.TargetID);
      if ThermalLoads and (Pi_ >= 0) then F.AddLoad(HeatPowerLoad(Pi_, B.Value));
      Continue;
    end;
    if ThermalLoads <> (B.Kind in [bkTemperature, bkHeatFlux, bkConvection]) then Continue;
    Tags := ResolveTags(M, B);
    if Length(Tags) = 0 then
    begin
      Log.Add(Format('Aviso: condicao "%s" nao encontrou a face "%s" da peca %s.', [B.Name, B.TargetFace, B.TargetID]));
      Continue;
    end;
    Total := 0;
    for J := 0 to High(Tags) do Total := Total + M.TagArea(Tags[J]);
    for J := 0 to High(Tags) do
    begin
      case B.Kind of
        bkFixed:
          begin
            L := FixLoad(Tags[J]);
            if B.DofMask <> 0 then
            begin
              L.Mask[0] := (B.DofMask and 1) <> 0;
              L.Mask[1] := (B.DofMask and 2) <> 0;
              L.Mask[2] := (B.DofMask and 4) <> 0;
            end;
          end;
        bkDisplacement:
          begin
            L := FixLoad(Tags[J]);
            L.Kind := flDisplacement;
            L.Vec := V3(B.X, B.Y, B.Z);
            if B.DofMask <> 0 then
            begin
              L.Mask[0] := (B.DofMask and 1) <> 0;
              L.Mask[1] := (B.DofMask and 2) <> 0;
              L.Mask[2] := (B.DofMask and 4) <> 0;
            end;
          end;
        { forca total repartida pela area de cada face }
        bkForce: L := ForceLoad(Tags[J], VScale(V3(B.X, B.Y, B.Z), M.TagArea(Tags[J]) / Max(Total, 1e-300)));
        bkPressure: L := PressureLoad(Tags[J], B.Value);
        bkTemperature: L := TemperatureLoad(Tags[J], B.Value);
        bkHeatFlux: L := HeatFluxLoad(Tags[J], B.Value);
        bkConvection: L := ConvectionLoad(Tags[J], B.Value, B.Value2);
        else Continue;
      end;
      F.AddLoad(L);
    end;
  end;
end;

{ amarracoes dos contatos colados do projeto: a peca com mais nos na
  interface vira a escrava }
function TAnalysisRun.BuildTies(M: TFEMMesh; H: Double; Verbose: Boolean): TMeshTies;
var
  I, J, A, B, N: Integer;
  C: TContact;
  T, T2: TMeshTies;
  Tol: Double;
begin
  Tol := 0.1 * H + 1e-6;
  { primitivas da mesma peca (corpo e eixo, por exemplo) sempre coladas }
  Result := IntraPartTies(M, Tol);
  if Verbose and (Length(Result) > 0) then
    Log.Add(Format('Primitivas da mesma peca coladas: %d nos amarrados', [Length(Result)]));
  for I := 0 to FProject.ContactCount - 1 do
  begin
    C := FProject.Contact(I);
    A := FProject.FindPart(C.PartA);
    B := FProject.FindPart(C.PartB);
    if (A < 0) or (B < 0) or (A = B) or FProject.Part(A).Suppressed or FProject.Part(B).Suppressed then Continue;
    { nos dois sentidos (ver IntraPartTies) }
    T := FindTies(M, A, B, Tol);
    T2 := FindTies(M, B, A, Tol);
    AppendTies(T, T2);
    if Verbose then
    begin
      if Length(T) = 0 then
        Log.Add(Format('Aviso: contato "%s" (%s-%s) nao encontrou faces encostadas (folga > %.3g mm).',
          [C.Name, C.PartA, C.PartB, Tol * 1000]))
      else
        Log.Add(Format('Contato colado "%s": %d nos amarrados', [C.Name, Length(T)]));
    end;
    N := Length(Result);
    SetLength(Result, N + Length(T));
    for J := 0 to High(T) do Result[N + J] := T[J];
  end;
end;

function TAnalysisRun.SolveOnce(M: TFEMMesh; H: Double; Kind: TAnalysisKind; out Main: Double): Boolean;
var
  F: TFEMModel;
  TR: TThermalResult;
begin
  Main := 0;
  Result := False;
  if not BuildMesh(M, H) then
  begin
    Message := 'Nenhuma peca com geometria para malhar.';
    Exit;
  end;
  F := TFEMModel.Create(M);
  try
    F.Ties := BuildTies(M, H, M = Mesh);
    if FProject.Settings.Solver = 1 then
    begin
      Result := SolveCCX(F, M, Kind, Main);
      Exit;
    end;
    case Kind of
      akThermal:
        begin
          SetupModel(F, M, True);
          Result := F.SolveThermal(ThermalRes);
          Message := ThermalRes.Message;
          Main := ThermalRes.MaxT - ThermalRes.MinT;
        end;
      akStatic, akThermoMechanical:
        begin
          if Kind = akThermoMechanical then
          begin
            SetupModel(F, M, True);
            if not F.SolveThermal(TR) then
            begin
              Message := 'Etapa termica: ' + TR.Message;
              Exit;
            end;
            ThermalRes := TR;
            F.Temperature := TR.T;
          end;
          SetupModel(F, M, False);
          if Kind = akThermoMechanical then F.Temperature := ThermalRes.T;
          Result := F.SolveStatic(StaticRes);
          Message := StaticRes.Message;
          Main := StaticRes.MaxDisp;
        end;
      akModal:
        begin
          SetupModel(F, M, False);
          Result := F.SolveModal(Max(1, FProject.Settings.Modes), ModalRes);
          Message := ModalRes.Message;
          if Result and (Length(ModalRes.Freq) > 0) then Main := ModalRes.Freq[0];
        end;
    end;
  finally
    F.Free;
  end;
end;

function TAnalysisRun.MeshOnly(out Q: TMeshQuality): Boolean;
begin
  Result := BuildMesh(Mesh, FProject.Settings.MeshSize);
  Q := Mesh.Quality;
end;

function TAnalysisRun.Run(AKind: TAnalysisKind): Boolean;
begin
  FEMCancelRequested := False;
  try
    Result := DoRun(AKind);
  except
    on E: EAbort do
    begin
      Ok := False;
      Message := 'Calculo cancelado pelo usuario.';
      Log.Add(Message);
      Result := False;
    end;
    on E: Exception do
    begin
      Ok := False;
      Message := 'Erro no calculo: ' + E.Message;
      Log.Add(Message);
      Result := False;
    end;
  end;
end;

function TAnalysisRun.DoRun(AKind: TAnalysisKind): Boolean;
var
  T0: TDateTime;
  H, Coarse, Fine: Double;
  CM: TFEMMesh;
  Q: TMeshQuality;
  SaveStatic: TStaticResult;
  SaveThermal: TThermalResult;
  SaveModal: TModalResult;
begin
  T0 := Now;
  Kind := AKind;
  Ok := False;
  Log.Clear;
  Fidelity := flEstimate;
  FidelityReason := '';
  Convergence := -1;
  if not FProject.Validate(Log) then
  begin
    Message := 'Projeto incompleto: ' + Log.Text;
    Exit(False);
  end;
  H := FProject.Settings.MeshSize;
  if not SolveOnce(Mesh, H, AKind, Fine) then
  begin
    Log.Add(Message);
    ElapsedMs := MilliSecondsBetween(Now, T0);
    Exit(False);
  end;
  Ok := True;
  Q := Mesh.Quality;
  Log.Add(Format('Malha: %d nos, %d elementos TET%d, forma minima %.2f, %d ruins',
    [Mesh.NodeCount, Mesh.ElemCount, Mesh.NodesPerElement, Q.MinShape, Q.Poor]));
  Log.Add(Message);
  if Q.Inverted > 0 then
    FidelityReason := 'malha com elementos invertidos'
  else if not FProject.Settings.CheckConvergence then
    FidelityReason := 'convergencia de malha nao verificada'
  else if Mesh.NodeCount * 1.5 * 1.5 * 1.5 > 400000 then
    FidelityReason := 'modelo grande demais para o estudo de convergencia automatico'
  else
  begin
    { malha mais grossa (1,5 h) para comparar; o resultado exibido e o da malha h }
    SaveStatic := StaticRes; SaveThermal := ThermalRes; SaveModal := ModalRes;
    CheckCancel;
    CM := TFEMMesh.Create;
    try
      if SolveOnce(CM, H * 1.5, AKind, Coarse) and (Abs(Fine) > 1e-300) then
      begin
        Convergence := Abs(Fine - Coarse) / Abs(Fine);
        Log.Add(Format('Convergencia: grandeza principal %.6g (h) x %.6g (1,5 h): variacao %.2f%%',
          [Fine, Coarse, Convergence * 100]));
        if Convergence < 0.05 then Fidelity := flEngineering
        else FidelityReason := Format('variacao de %.1f%% entre malhas (refine a malha)', [Convergence * 100]);
      end
      else
        FidelityReason := 'estudo de convergencia nao pode ser feito';
    finally
      CM.Free;
    end;
    StaticRes := SaveStatic; ThermalRes := SaveThermal; ModalRes := SaveModal;
  end;
  if Fidelity = flEngineering then
    Log.Add('Fidelidade: ENGENHARIA (FEM com malha verificada e convergencia < 5%)')
  else
    Log.Add('Fidelidade: ESTIMATIVA (' + FidelityReason + ')');
  ElapsedMs := MilliSecondsBetween(Now, T0);
  Result := True;
end;

function TAnalysisRun.Summary: TPhysicsResult;
begin
  Result.Solved := Ok;
  Result.MaxDisplacement := StaticRes.MaxDisp;
  Result.MaxVonMises := StaticRes.MaxVonMises;
  Result.MaxTemperature := ThermalRes.MaxT;
  Result.MinTemperature := ThermalRes.MinT;
  Result.MaxStrain := 0;
  Result.MaxContactPressure := 0;
  if Length(ModalRes.Freq) > 0 then Result.FundamentalFrequency := ModalRes.Freq[0] else Result.FundamentalFrequency := 0;
  Result.MaxDragForce := 0;
  Result.Message := Message;
  Result.Fidelity := FidelityName(Fidelity);
  Result.MeshNodes := Mesh.NodeCount;
  Result.MeshElements := Mesh.ElemCount;
  if FProject.Settings.Solver = 1 then Result.SolverName := 'CalculiX (C3D' + IntToStr(Mesh.NodesPerElement) + ')'
  else Result.SolverName := 'MultiPhysics FEM (TET' + IntToStr(Mesh.NodesPerElement) + ')';
end;

end.
