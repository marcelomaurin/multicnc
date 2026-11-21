unit multiassembly_solver;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multiassembly_types, multiassembly_project, multiassembly_mates;

type
  TKinematicJointInfo = record
    RelationIndex: Integer;
    Name: string;
    ComponentA: string;
    ComponentB: string;
    Kind: TMechanicalRelationKind;
    Axis: TAssemblyVec3;
    MinLimit: Double;
    MaxLimit: Double;
    CurrentValue: Double;
    UnitStr: string;
  end;

  TCollisionItem = record
    CompA: string;
    CompB: string;
    OverlapVolume: Double;
  end;

  TKinematicJointArray = array of TKinematicJointInfo;
  TCollisionItemArray = array of TCollisionItem;

  TKinematicSolver = class
  private
    FProject: TAssemblyProject;
    FDOFs: array of TComponentDOF;
    FSolvedPositions: array of TAssemblyVec3;
    FSolvedRotations: array of TAssemblyVec3;
    FCollisions: array of TCollisionItem;
    FSimTime: Double;
    FSimActive: Boolean;

    procedure EnsureArrays;
    function FindRootFixedIndex: Integer;
    function AreMated(const ID1, ID2: string): Boolean;
    function Intersects(const PosA, SizeA, PosB, SizeB: TAssemblyVec3): Boolean;
  public
    constructor Create(AProject: TAssemblyProject);
    destructor Destroy; override;

    procedure AnalyzeDOFs;
    procedure Solve;
    procedure ResetToHome;
    procedure StepSimulation(DeltaSec: Double);

    function GetDOF(const CompID: string): TComponentDOF;
    function GetDOFByIndex(Index: Integer): TComponentDOF;
    function GetSolvedPosition(const CompID: string): TAssemblyVec3;
    function GetSolvedRotation(const CompID: string): TAssemblyVec3;

    function DragComponent(const CompID: string; const WorldDelta: TAssemblyVec3): Boolean;
    procedure SetJointValue(RelationIndex: Integer; Value: Double);

    function GetActiveJoints: TKinematicJointArray;
    function ActiveJointCount: Integer;

    function CheckCollisions: Integer;
    function CollisionCount: Integer;
    function Collision(Index: Integer): TCollisionItem;

    property Project: TAssemblyProject read FProject write FProject;
    property SimActive: Boolean read FSimActive write FSimActive;
    property SimTime: Double read FSimTime write FSimTime;
  end;

implementation

constructor TKinematicSolver.Create(AProject: TAssemblyProject);
begin
  inherited Create;
  FProject := AProject;
  FSimTime := 0;
  FSimActive := False;
end;

destructor TKinematicSolver.Destroy;
begin
  SetLength(FDOFs, 0);
  SetLength(FSolvedPositions, 0);
  SetLength(FSolvedRotations, 0);
  SetLength(FCollisions, 0);
  inherited Destroy;
end;

procedure TKinematicSolver.EnsureArrays;
var
  N, I: Integer;
begin
  if FProject = nil then
  begin
    SetLength(FDOFs, 0);
    SetLength(FSolvedPositions, 0);
    SetLength(FSolvedRotations, 0);
    Exit;
  end;

  N := FProject.ComponentCount;
  if Length(FSolvedPositions) <> N then
  begin
    SetLength(FDOFs, N);
    SetLength(FSolvedPositions, N);
    SetLength(FSolvedRotations, N);
    for I := 0 to N - 1 do
    begin
      FSolvedPositions[I] := FProject.Component(I).Position;
      FSolvedRotations[I] := FProject.Component(I).Rotation;
    end;
  end;
end;

function TKinematicSolver.FindRootFixedIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  if FProject = nil then Exit;
  for I := 0 to FProject.ComponentCount - 1 do
    if FProject.Component(I).Fixed then
      Exit(I);

  // Se nenhum estiver explicitamente marcado como Fixed, adota o primeiro (padrao SolidWorks)
  if FProject.ComponentCount > 0 then
    Result := 0;
end;

function TKinematicSolver.AreMated(const ID1, ID2: string): Boolean;
var
  I: Integer;
  R: TMechanicalRelation;
begin
  Result := False;
  if FProject = nil then Exit;
  for I := 0 to FProject.RelationCount - 1 do
  begin
    R := FProject.Relation(I);
    if ((SameText(R.A, ID1) and SameText(R.B, ID2)) or
        (SameText(R.A, ID2) and SameText(R.B, ID1))) then
      Exit(True);
  end;
end;

function TKinematicSolver.Intersects(const PosA, SizeA, PosB, SizeB: TAssemblyVec3): Boolean;
var
  MinA, MaxA, MinB, MaxB: TAssemblyVec3;
begin
  MinA := PosA;
  MaxA := Vec3Add(PosA, SizeA);
  MinB := PosB;
  MaxB := Vec3Add(PosB, SizeB);

  Result := (MinA.X < MaxB.X) and (MaxA.X > MinB.X) and
            (MinA.Y < MaxB.Y) and (MaxA.Y > MinB.Y) and
            (MinA.Z < MaxB.Z) and (MaxA.Z > MinB.Z);
end;

procedure TKinematicSolver.AnalyzeDOFs;
var
  I, J, Count: Integer;
  C: TAssemblyComponent;
  R: TMechanicalRelation;
  HasFixedMate: Boolean;
begin
  EnsureArrays;
  if FProject = nil then Exit;

  for I := 0 to FProject.ComponentCount - 1 do
  begin
    C := FProject.Component(I);

    if C.Fixed or (I = 0) then
    begin
      FDOFs[I].Tx := False; FDOFs[I].Ty := False; FDOFs[I].Tz := False;
      FDOFs[I].Rx := False; FDOFs[I].Ry := False; FDOFs[I].Rz := False;
      FDOFs[I].FreeCount := 0;
      FDOFs[I].Status := adsFixed;
      FDOFs[I].StatusText := '(f) Base Fixa';
      Continue;
    end;

    // Componente flutuante inicial: 6 GL livres
    FDOFs[I].Tx := True; FDOFs[I].Ty := True; FDOFs[I].Tz := True;
    FDOFs[I].Rx := True; FDOFs[I].Ry := True; FDOFs[I].Rz := True;
    FDOFs[I].Status := adsUnderdefined;
    HasFixedMate := False;

    // Reduz GL conforme juncoes conectadas
    for J := 0 to FProject.RelationCount - 1 do
    begin
      R := FProject.Relation(J);
      if SameText(R.A, C.ID) or SameText(R.B, C.ID) then
      begin
        case R.Kind of
          mrFixed, mrCoupled:
          begin
            FDOFs[I].Tx := False; FDOFs[I].Ty := False; FDOFs[I].Tz := False;
            FDOFs[I].Rx := False; FDOFs[I].Ry := False; FDOFs[I].Rz := False;
            HasFixedMate := True;
          end;
          mrSlider:
          begin
            // Permite translacao apenas no eixo definido
            FDOFs[I].Rx := False; FDOFs[I].Ry := False; FDOFs[I].Rz := False;
            if Abs(R.Axis.X) > 0.5 then
            begin
              FDOFs[I].Tx := True; FDOFs[I].Ty := False; FDOFs[I].Tz := False;
            end
            else if Abs(R.Axis.Y) > 0.5 then
            begin
              FDOFs[I].Tx := False; FDOFs[I].Ty := True; FDOFs[I].Tz := False;
            end
            else
            begin
              FDOFs[I].Tx := False; FDOFs[I].Ty := False; FDOFs[I].Tz := True;
            end;
          end;
          mrHinge:
          begin
            // Permite apenas rotacao em torno do eixo
            FDOFs[I].Tx := False; FDOFs[I].Ty := False; FDOFs[I].Tz := False;
            if Abs(R.Axis.X) > 0.5 then
            begin
              FDOFs[I].Rx := True; FDOFs[I].Ry := False; FDOFs[I].Rz := False;
            end
            else if Abs(R.Axis.Y) > 0.5 then
            begin
              FDOFs[I].Rx := False; FDOFs[I].Ry := True; FDOFs[I].Rz := False;
            end
            else
            begin
              FDOFs[I].Rx := False; FDOFs[I].Ry := False; FDOFs[I].Rz := True;
            end;
          end;
          mrLeadScrew:
          begin
            // Vincula translacao ao fuso
            FDOFs[I].Rx := False; FDOFs[I].Ry := False; FDOFs[I].Rz := False;
            if Abs(R.Axis.X) > 0.5 then
            begin
              FDOFs[I].Tx := True; FDOFs[I].Ty := False; FDOFs[I].Tz := False;
            end
            else if Abs(R.Axis.Y) > 0.5 then
            begin
              FDOFs[I].Tx := False; FDOFs[I].Ty := True; FDOFs[I].Tz := False;
            end
            else
            begin
              FDOFs[I].Tx := False; FDOFs[I].Ty := False; FDOFs[I].Tz := True;
            end;
          end;
          mrConcentric:
          begin
            // Restringe 2 translacoes e 2 rotacoes transversais
            if Abs(R.Axis.Z) > 0.5 then
            begin
              FDOFs[I].Tx := False; FDOFs[I].Ty := False;
              FDOFs[I].Rx := False; FDOFs[I].Ry := False;
            end
            else if Abs(R.Axis.X) > 0.5 then
            begin
              FDOFs[I].Ty := False; FDOFs[I].Tz := False;
              FDOFs[I].Ry := False; FDOFs[I].Rz := False;
            end
            else
            begin
              FDOFs[I].Tx := False; FDOFs[I].Tz := False;
              FDOFs[I].Rx := False; FDOFs[I].Rz := False;
            end;
          end;
          mrInsert:
          begin
            // Concentrico + coincidente: resta apenas o giro em torno do eixo
            FDOFs[I].Tx := False; FDOFs[I].Ty := False; FDOFs[I].Tz := False;
            FDOFs[I].Rx := Abs(R.Axis.X) > 0.5;
            FDOFs[I].Ry := Abs(R.Axis.Y) > 0.5;
            FDOFs[I].Rz := Abs(R.Axis.Z) > 0.5;
          end;
          mrCoincident, mrDistance:
          begin
            // Restringe a translacao normal e inclinacoes
            if Abs(R.Axis.Z) > 0.5 then
            begin
              FDOFs[I].Tz := False; FDOFs[I].Rx := False; FDOFs[I].Ry := False;
            end
            else if Abs(R.Axis.Y) > 0.5 then
            begin
              FDOFs[I].Ty := False; FDOFs[I].Rx := False; FDOFs[I].Rz := False;
            end
            else
            begin
              FDOFs[I].Tx := False; FDOFs[I].Ry := False; FDOFs[I].Rz := False;
            end;
          end;
        end;
      end;
    end;

    // Calcula quantidade total de GL restantes
    Count := 0;
    if FDOFs[I].Tx then Inc(Count);
    if FDOFs[I].Ty then Inc(Count);
    if FDOFs[I].Tz then Inc(Count);
    if FDOFs[I].Rx then Inc(Count);
    if FDOFs[I].Ry then Inc(Count);
    if FDOFs[I].Rz then Inc(Count);
    FDOFs[I].FreeCount := Count;

    if HasFixedMate or (Count = 0) then
    begin
      FDOFs[I].Status := adsFullyDefined;
      FDOFs[I].StatusText := '( ) Totalmente Definido';
    end
    else
    begin
      FDOFs[I].Status := adsUnderdefined;
      if (Count = 1) and FDOFs[I].Tx then
        FDOFs[I].StatusText := '(-) 1 GL (Linear X)'
      else if (Count = 1) and FDOFs[I].Ty then
        FDOFs[I].StatusText := '(-) 1 GL (Linear Y)'
      else if (Count = 1) and FDOFs[I].Tz then
        FDOFs[I].StatusText := '(-) 1 GL (Linear Z)'
      else if (Count = 1) and (FDOFs[I].Rx or FDOFs[I].Ry or FDOFs[I].Rz) then
        FDOFs[I].StatusText := '(-) 1 GL (Rotativo)'
      else
        FDOFs[I].StatusText := Format('(-) %d GL Livres', [Count]);
    end;
  end;
end;

procedure TKinematicSolver.Solve;
var
  I, J, Pass, ParentIdx, ChildIdx, Iter: Integer;
  R: TMechanicalRelation;
  Displ, AngleDeg: Double;
  Solved: array of Boolean;
  SolvedBy, AppliedParent, AppliedChild: array of Integer;
  AnyProgress, CanApply: Boolean;
  ChildComp, ParentComp: TAssemblyComponent;

  { uniao por referencia: reposiciona o filho sobre a face/eixo do pai }
  procedure ApplyGeometricMate(const RR: TMechanicalRelation; PIdx, CIdx: Integer);
  var
    FChild, FParent, PW: TMateFeature;
    NP, NR: TAssemblyVec3;
    PC, CC: TAssemblyComponent;
  begin
    PC := FProject.Component(PIdx);
    CC := FProject.Component(CIdx);
    if SameText(CC.ID, RR.A) then
    begin
      FChild := RR.RefA;
      FParent := RR.RefB;
    end
    else
    begin
      FChild := RR.RefB;
      FParent := RR.RefA;
    end;
    PW := FeatureToWorld(PC, FSolvedPositions[PIdx], FSolvedRotations[PIdx], FParent);
    if SolveMatePose(CC, FSolvedPositions[CIdx], FSolvedRotations[CIdx], FChild, PW, RR.Kind,
      RR.Flipped, RR.SpinDeg, RR.Distance, NP, NR) then
    begin
      FSolvedPositions[CIdx] := NP;
      FSolvedRotations[CIdx] := NR;
    end;
  end;

begin
  EnsureArrays;
  if FProject = nil then Exit;
  AnalyzeDOFs;

  SetLength(Solved, FProject.ComponentCount);
  SetLength(SolvedBy, FProject.ComponentCount);
  SetLength(AppliedParent, FProject.RelationCount);
  SetLength(AppliedChild, FProject.RelationCount);
  for J := 0 to FProject.RelationCount - 1 do
  begin
    AppliedParent[J] := -1;
    AppliedChild[J] := -1;
  end;
  for I := 0 to FProject.ComponentCount - 1 do
  begin
    SolvedBy[I] := -1;
    // Inicializa com a posicao base do componente
    FSolvedPositions[I] := FProject.Component(I).Position;
    FSolvedRotations[I] := FProject.Component(I).Rotation;
    Solved[I] := FProject.Component(I).Fixed or (I = 0);
  end;

  // Propagacao cinematica top-down atraves das relacoes/mates
  for Pass := 1 to FProject.ComponentCount + 2 do
  begin
    AnyProgress := False;
    for J := 0 to FProject.RelationCount - 1 do
    begin
      R := FProject.Relation(J);
      ParentIdx := FProject.FindComponent(R.B);
      ChildIdx := FProject.FindComponent(R.A);

      // Se A estiver resolvido e B nao, inverte a ordem hierarquica
      if (ParentIdx < 0) or (ChildIdx < 0) then Continue;

      if AppliedChild[J] >= 0 then Continue;

      if (not Solved[ParentIdx] and Solved[ChildIdx]) or
         (R.HasRefs and Solved[ParentIdx] and Solved[ChildIdx] and (SolvedBy[ParentIdx] = ChildIdx)) then
      begin
        // Inverte papeis
        ParentIdx := FProject.FindComponent(R.A);
        ChildIdx := FProject.FindComponent(R.B);
      end;

      { varias unioes por referencia entre o mesmo par sao aplicadas em sequencia }
      CanApply := Solved[ParentIdx] and (not Solved[ChildIdx] or
        (R.HasRefs and (SolvedBy[ChildIdx] = ParentIdx)));

      if CanApply and R.HasRefs then
      begin
        ApplyGeometricMate(R, ParentIdx, ChildIdx);
        Solved[ChildIdx] := True;
        SolvedBy[ChildIdx] := ParentIdx;
        AppliedParent[J] := ParentIdx;
        AppliedChild[J] := ChildIdx;
        AnyProgress := True;
      end
      else if CanApply then
      begin
        ChildComp := FProject.Component(ChildIdx);
        Displ := R.CurrentValue;
        if (R.MinLimit <> 0) or (R.MaxLimit <> 0) then
          Displ := EnsureRange(Displ, Min(R.MinLimit, R.MaxLimit), Max(R.MinLimit, R.MaxLimit));

        ParentComp := FProject.Component(ParentIdx);
        case R.Kind of
          mrCoincident:
          begin
            // Posiciona Child em contato com a superficie de Parent (apoiado no topo Z por padrao)
            FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + (ParentComp.Size.X - ChildComp.Size.X) * 0.5 + R.Offset.X;
            FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + (ParentComp.Size.Y - ChildComp.Size.Y) * 0.5 + R.Offset.Y;
            if (R.Offset.Z <> 0) or (R.Distance <> 0) then
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + ParentComp.Size.Z + R.Offset.Z + R.Distance
            else
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + ParentComp.Size.Z;
            FSolvedRotations[ChildIdx] := FSolvedRotations[ParentIdx];
          end;

          mrConcentric:
          begin
            // Alinha eixos geometricos centrais
            FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + (ParentComp.Size.X - ChildComp.Size.X) * 0.5 + R.Offset.X;
            FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + (ParentComp.Size.Y - ChildComp.Size.Y) * 0.5 + R.Offset.Y;
            FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + R.Offset.Z + Displ;
            FSolvedRotations[ChildIdx] := FSolvedRotations[ParentIdx];
          end;

          mrSlider, mrAxis:
          begin
            if Abs(R.Axis.X) > 0.5 then
            begin
              FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + R.Offset.X + Displ;
              FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + (ParentComp.Size.Y - ChildComp.Size.Y) * 0.5 + R.Offset.Y;
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + ParentComp.Size.Z + R.Offset.Z;
            end
            else if Abs(R.Axis.Y) > 0.5 then
            begin
              FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + (ParentComp.Size.X - ChildComp.Size.X) * 0.5 + R.Offset.X;
              FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + R.Offset.Y + Displ;
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + ParentComp.Size.Z + R.Offset.Z;
            end
            else
            begin
              FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + (ParentComp.Size.X - ChildComp.Size.X) * 0.5 + R.Offset.X;
              FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + ParentComp.Size.Y + R.Offset.Y;
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + R.Offset.Z + Displ;
            end;
            FSolvedRotations[ChildIdx] := FSolvedRotations[ParentIdx];
          end;

          mrLeadScrew:
          begin
            if Abs(R.Axis.X) > 0.5 then
            begin
              FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + R.Offset.X + Displ;
              FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + (ParentComp.Size.Y - ChildComp.Size.Y) * 0.5 + R.Offset.Y;
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + ParentComp.Size.Z + R.Offset.Z;
            end
            else if Abs(R.Axis.Y) > 0.5 then
            begin
              FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + (ParentComp.Size.X - ChildComp.Size.X) * 0.5 + R.Offset.X;
              FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + R.Offset.Y + Displ;
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + ParentComp.Size.Z + R.Offset.Z;
            end
            else
            begin
              FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + (ParentComp.Size.X - ChildComp.Size.X) * 0.5 + R.Offset.X;
              FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + ParentComp.Size.Y + R.Offset.Y;
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + R.Offset.Z + Displ;
            end;
            if Abs(R.PitchMM) > 1e-4 then
              AngleDeg := (Displ / R.PitchMM) * 360.0
            else
              AngleDeg := Displ * 180.0;
            FSolvedRotations[ParentIdx] := Vec3Add(
              FProject.Component(ParentIdx).Rotation,
              Vec3Mul(R.Axis, AngleDeg)
            );
          end;

          mrHinge:
          begin
            FSolvedPositions[ChildIdx] := Vec3Add(FSolvedPositions[ParentIdx], R.Offset);
            FSolvedRotations[ChildIdx] := Vec3Add(
              FSolvedRotations[ParentIdx],
              Vec3Mul(R.Axis, Displ)
            );
          end;

          mrFixed, mrCoupled:
          begin
            if (R.Offset.X = 0) and (R.Offset.Y = 0) and (R.Offset.Z = 0) then
            begin
              FSolvedPositions[ChildIdx].X := FSolvedPositions[ParentIdx].X + (ParentComp.Size.X - ChildComp.Size.X) * 0.5;
              FSolvedPositions[ChildIdx].Y := FSolvedPositions[ParentIdx].Y + (ParentComp.Size.Y - ChildComp.Size.Y) * 0.5;
              FSolvedPositions[ChildIdx].Z := FSolvedPositions[ParentIdx].Z + ParentComp.Size.Z;
            end
            else
              FSolvedPositions[ChildIdx] := Vec3Add(FSolvedPositions[ParentIdx], R.Offset);
            FSolvedRotations[ChildIdx] := FSolvedRotations[ParentIdx];
          end;

          mrDistance:
          begin
            FSolvedPositions[ChildIdx] := Vec3Add(
              FSolvedPositions[ParentIdx],
              Vec3Add(R.Offset, Vec3Mul(R.Axis, R.Distance))
            );
          end;
        end;

        Solved[ChildIdx] := True;
        SolvedBy[ChildIdx] := ParentIdx;
        AppliedParent[J] := ParentIdx;
        AppliedChild[J] := ChildIdx;
        AnyProgress := True;
      end;
    end;
    if not AnyProgress then Break;
  end;

  { refinamento: reaplica as unioes por referencia para que combinacoes
    (ex.: concentrico + coincidente) convirjam }
  for Iter := 1 to 3 do
    for J := 0 to FProject.RelationCount - 1 do
    begin
      R := FProject.Relation(J);
      if R.HasRefs and (AppliedChild[J] >= 0) then
        ApplyGeometricMate(R, AppliedParent[J], AppliedChild[J]);
    end;

  // Atualiza as posicoes de volta para o projeto para persistencia e renderizacao
  for I := 0 to FProject.ComponentCount - 1 do
  begin
    ChildComp := FProject.Component(I);
    ChildComp.Position := FSolvedPositions[I];
    ChildComp.Rotation := FSolvedRotations[I];
    FProject.UpdateComponent(I, ChildComp);
  end;
end;

procedure TKinematicSolver.ResetToHome;
var
  I: Integer;
  R: TMechanicalRelation;
begin
  if FProject = nil then Exit;
  for I := 0 to FProject.RelationCount - 1 do
  begin
    R := FProject.Relation(I);
    R.CurrentValue := R.MinLimit;
    // se MinLimit for negativo ou zero, adota 0 se dentro da faixa
    if (R.MinLimit <= 0) and (R.MaxLimit >= 0) then
      R.CurrentValue := 0;
    // grava de volta a relacao atualizada
    FProject.Relate(R); // Atualiza
  end;
  FSimTime := 0;
  Solve;
end;

procedure TKinematicSolver.StepSimulation(DeltaSec: Double);
var
  I: Integer;
  R: TMechanicalRelation;
  RangeSpan, Mid, Wave, TargetVal: Double;
begin
  if FProject = nil then Exit;
  FSimTime := FSimTime + DeltaSec;

  for I := 0 to FProject.RelationCount - 1 do
  begin
    R := FProject.Relation(I);
    if (R.Kind in [mrSlider, mrLeadScrew, mrHinge, mrConcentric]) and (R.MaxLimit > R.MinLimit) then
    begin
      RangeSpan := R.MaxLimit - R.MinLimit;
      Mid := (R.MinLimit + R.MaxLimit) * 0.5;
      // Onda senoidal suave com fases ligeiramente deslocadas para criar movimento harmonico realista
      Wave := Sin(FSimTime * 1.5 + I * 0.8);
      TargetVal := Mid + Wave * (RangeSpan * 0.45);
      R.CurrentValue := TargetVal;
      // Atualiza relacao
      FProject.RemoveRelation(I);
      FProject.Relate(R);
    end;
  end;

  Solve;
  CheckCollisions;
end;

function TKinematicSolver.GetDOF(const CompID: string): TComponentDOF;
var
  Idx: Integer;
begin
  EnsureArrays;
  Idx := FProject.FindComponent(CompID);
  if (Idx >= 0) and (Idx < Length(FDOFs)) then
    Result := FDOFs[Idx]
  else
  begin
    Result.Tx := True; Result.Ty := True; Result.Tz := True;
    Result.Rx := True; Result.Ry := True; Result.Rz := True;
    Result.FreeCount := 6;
    Result.Status := adsUnderdefined;
    Result.StatusText := '(-) 6 GL Livres';
  end;
end;

function TKinematicSolver.GetDOFByIndex(Index: Integer): TComponentDOF;
begin
  EnsureArrays;
  if (Index >= 0) and (Index < Length(FDOFs)) then
    Result := FDOFs[Index]
  else
  begin
    Result.Tx := False; Result.Ty := False; Result.Tz := False;
    Result.Rx := False; Result.Ry := False; Result.Rz := False;
    Result.FreeCount := 0;
    Result.Status := adsFixed;
    Result.StatusText := '(f) Fixo';
  end;
end;

function TKinematicSolver.GetSolvedPosition(const CompID: string): TAssemblyVec3;
var
  Idx: Integer;
begin
  EnsureArrays;
  Idx := FProject.FindComponent(CompID);
  if (Idx >= 0) and (Idx < Length(FSolvedPositions)) then
    Result := FSolvedPositions[Idx]
  else
    Result := Vec3(0, 0, 0);
end;

function TKinematicSolver.GetSolvedRotation(const CompID: string): TAssemblyVec3;
var
  Idx: Integer;
begin
  EnsureArrays;
  Idx := FProject.FindComponent(CompID);
  if (Idx >= 0) and (Idx < Length(FSolvedRotations)) then
    Result := FSolvedRotations[Idx]
  else
    Result := Vec3(0, 0, 0);
end;

function TKinematicSolver.DragComponent(const CompID: string; const WorldDelta: TAssemblyVec3): Boolean;
var
  I, Idx: Integer;
  R: TMechanicalRelation;
  FoundJoint: Boolean;
  DotDelta, NewVal: Double;
  C: TAssemblyComponent;
begin
  Result := False;
  if FProject = nil then Exit;
  Idx := FProject.FindComponent(CompID);
  if Idx < 0 then Exit;

  // Se o componente for fixo, nao pode ser arrastado
  if FProject.Component(Idx).Fixed or (FDOFs[Idx].Status = adsFixed) then
    Exit(False);

  FoundJoint := False;
  // Procura se tem relacao cinemática com grau de liberdade
  for I := 0 to FProject.RelationCount - 1 do
  begin
    R := FProject.Relation(I);
    if SameText(R.A, CompID) and (R.Kind in [mrSlider, mrLeadScrew, mrHinge, mrConcentric]) then
    begin
      DotDelta := Vec3Dot(WorldDelta, R.Axis);
      NewVal := R.CurrentValue + DotDelta;
      if (R.MinLimit <> 0) or (R.MaxLimit <> 0) then
        NewVal := EnsureRange(NewVal, Min(R.MinLimit, R.MaxLimit), Max(R.MinLimit, R.MaxLimit));

      R.CurrentValue := NewVal;
      FProject.RemoveRelation(I);
      FProject.Relate(R);
      FoundJoint := True;
      Break;
    end;
  end;

  // Se nao tiver junta formal, mas for flutuante livre, move a posicao base
  if not FoundJoint and (FDOFs[Idx].Status = adsUnderdefined) then
  begin
    C := FProject.Component(Idx);
    C.Position := Vec3Add(C.Position, WorldDelta);
    FProject.UpdateComponent(Idx, C);
  end;

  Solve;
  CheckCollisions;
  Result := True;
end;

procedure TKinematicSolver.SetJointValue(RelationIndex: Integer; Value: Double);
var
  R: TMechanicalRelation;
begin
  if (FProject = nil) or (RelationIndex < 0) or (RelationIndex >= FProject.RelationCount) then Exit;
  R := FProject.Relation(RelationIndex);
  if (R.MinLimit <> 0) or (R.MaxLimit <> 0) then
    R.CurrentValue := EnsureRange(Value, Min(R.MinLimit, R.MaxLimit), Max(R.MinLimit, R.MaxLimit))
  else
    R.CurrentValue := Value;

  FProject.RemoveRelation(RelationIndex);
  FProject.Relate(R);
  Solve;
  CheckCollisions;
end;

function TKinematicSolver.GetActiveJoints: TKinematicJointArray;
var
  I, Count: Integer;
  R: TMechanicalRelation;
begin
  SetLength(Result, 0);
  if FProject = nil then Exit;

  Count := 0;
  for I := 0 to FProject.RelationCount - 1 do
  begin
    R := FProject.Relation(I);
    if R.Kind in [mrSlider, mrLeadScrew, mrHinge, mrConcentric] then
      Inc(Count);
  end;

  SetLength(Result, Count);
  Count := 0;
  for I := 0 to FProject.RelationCount - 1 do
  begin
    R := FProject.Relation(I);
    if R.Kind in [mrSlider, mrLeadScrew, mrHinge, mrConcentric] then
    begin
      Result[Count].RelationIndex := I;
      Result[Count].ComponentA := R.A;
      Result[Count].ComponentB := R.B;
      Result[Count].Kind := R.Kind;
      Result[Count].Axis := R.Axis;
      Result[Count].MinLimit := R.MinLimit;
      Result[Count].MaxLimit := R.MaxLimit;
      Result[Count].CurrentValue := R.CurrentValue;

      case R.Kind of
        mrSlider:
        begin
          Result[Count].Name := Format('Deslizador %s -> %s', [R.A, R.B]);
          Result[Count].UnitStr := 'mm';
        end;
        mrLeadScrew:
        begin
          Result[Count].Name := Format('Fuso %s -> %s (P: %.1fmm)', [R.A, R.B, R.PitchMM]);
          Result[Count].UnitStr := 'mm';
        end;
        mrHinge:
        begin
          Result[Count].Name := Format('Articulação %s -> %s', [R.A, R.B]);
          Result[Count].UnitStr := '°';
        end;
        mrConcentric:
        begin
          Result[Count].Name := Format('Concêntrico %s -> %s', [R.A, R.B]);
          Result[Count].UnitStr := 'mm';
        end;
      else
        Result[Count].Name := Format('Junta %s -> %s', [R.A, R.B]);
        Result[Count].UnitStr := '';
      end;

      Inc(Count);
    end;
  end;
end;

function TKinematicSolver.ActiveJointCount: Integer;
begin
  Result := Length(GetActiveJoints);
end;

function TKinematicSolver.CheckCollisions: Integer;
var
  I, J, Count: Integer;
  CA, CB: TAssemblyComponent;
begin
  SetLength(FCollisions, 0);
  if FProject = nil then Exit(0);

  Count := 0;
  for I := 0 to FProject.ComponentCount - 1 do
  begin
    CA := FProject.Component(I);
    for J := I + 1 to FProject.ComponentCount - 1 do
    begin
      CB := FProject.Component(J);
      // Nao acusa colisao se componentes estiverem acoplados de modo fixo ou coincidente
      if AreMated(CA.ID, CB.ID) then Continue;

      if Intersects(FSolvedPositions[I], CA.Size, FSolvedPositions[J], CB.Size) then
      begin
        SetLength(FCollisions, Count + 1);
        FCollisions[Count].CompA := CA.ID;
        FCollisions[Count].CompB := CB.ID;
        FCollisions[Count].OverlapVolume := 1.0;
        Inc(Count);
      end;
    end;
  end;
  Result := Count;
end;

function TKinematicSolver.CollisionCount: Integer;
begin
  Result := Length(FCollisions);
end;

function TKinematicSolver.Collision(Index: Integer): TCollisionItem;
begin
  if (Index >= 0) and (Index < Length(FCollisions)) then
    Result := FCollisions[Index]
  else
  begin
    Result.CompA := '';
    Result.CompB := '';
    Result.OverlapVolume := 0;
  end;
end;

end.
