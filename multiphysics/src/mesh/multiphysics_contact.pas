unit multiphysics_contact;

{ Contato colado ("bonded") entre corpos malhados separadamente: pecas
  diferentes (contatos do projeto) e primitivas da mesma peca (corpo e eixo
  de um motor, por exemplo).

  Cada no do contorno de um corpo escravo vira uma amarracao
  u_escravo = soma w_a u_a quando:
  - fica dentro de um tetraedro mestre (corpos que se sobrepoem): w = funcoes
    de forma do tetraedro (4 ou 10 nos) no ponto;
  - ou fica a menos de Tol de uma face de contorno mestre (corpos que se
    encostam): w = funcoes de forma do triangulo (3 ou 6 nos) no ponto mais
    proximo.
  O FEM impoe as amarracoes por penalidade. Equivale ao *TIE do CalculiX:
  sem atrito, sem separacao. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multiphysics_vector, multiphysics_geometry, multiphysics_mesh;

type
  TMeshTie = record
    Slave: Integer;
    NM: Integer;
    Masters: array[0..9] of Integer;
    W: array[0..9] of Double;
    Gap: Double;
  end;
  TMeshTies = array of TMeshTie;
  TBoolArray = array of Boolean;

{ amarra os corpos marcados em SlaveBody nos corpos marcados em MasterBody }
function FindTiesBodies(M: TFEMMesh; const MasterBody, SlaveBody: TBoolArray; Tol: Double): TMeshTies;
{ todos os corpos da peca SlavePart nos corpos da peca MasterPart }
function FindTies(M: TFEMMesh; MasterPart, SlavePart: Integer; Tol: Double): TMeshTies;
{ primitivas da mesma peca que se tocam ou se sobrepoem }
function IntraPartTies(M: TFEMMesh; Tol: Double): TMeshTies;
function BodiesTouch(M: TFEMMesh; A, B: Integer; Tol: Double): Boolean;
{ ponto mais proximo do triangulo ABC a P: coordenadas baricentricas }
procedure ClosestOnTriangle(const P, A, B, C: TVector3; out L0, L1, L2: Double);
procedure AppendTies(var Dst: TMeshTies; const Src: TMeshTies);

implementation

procedure AppendTies(var Dst: TMeshTies; const Src: TMeshTies);
var
  N, I: Integer;
begin
  N := Length(Dst);
  SetLength(Dst, N + Length(Src));
  for I := 0 to High(Src) do Dst[N + I] := Src[I];
end;

procedure ClosestOnTriangle(const P, A, B, C: TVector3; out L0, L1, L2: Double);
var
  AB, AC, AP, BP, CP: TVector3;
  D1, D2, D3, D4, D5, D6, Va, Vb, Vc, V, W, Den: Double;
begin
  { Ericson, Real-Time Collision Detection, 5.1.5 }
  AB := VSub(B, A); AC := VSub(C, A); AP := VSub(P, A);
  D1 := VDot(AB, AP); D2 := VDot(AC, AP);
  if (D1 <= 0) and (D2 <= 0) then begin L0 := 1; L1 := 0; L2 := 0; Exit; end;
  BP := VSub(P, B);
  D3 := VDot(AB, BP); D4 := VDot(AC, BP);
  if (D3 >= 0) and (D4 <= D3) then begin L0 := 0; L1 := 1; L2 := 0; Exit; end;
  Vc := D1 * D4 - D3 * D2;
  if (Vc <= 0) and (D1 >= 0) and (D3 <= 0) then
  begin
    V := D1 / (D1 - D3);
    L0 := 1 - V; L1 := V; L2 := 0; Exit;
  end;
  CP := VSub(P, C);
  D5 := VDot(AB, CP); D6 := VDot(AC, CP);
  if (D6 >= 0) and (D5 <= D6) then begin L0 := 0; L1 := 0; L2 := 1; Exit; end;
  Vb := D5 * D2 - D1 * D6;
  if (Vb <= 0) and (D2 >= 0) and (D6 <= 0) then
  begin
    W := D2 / (D2 - D6);
    L0 := 1 - W; L1 := 0; L2 := W; Exit;
  end;
  Va := D3 * D6 - D5 * D4;
  if (Va <= 0) and ((D4 - D3) >= 0) and ((D5 - D6) >= 0) then
  begin
    W := (D4 - D3) / ((D4 - D3) + (D5 - D6));
    L0 := 0; L1 := 1 - W; L2 := W; Exit;
  end;
  Den := 1 / (Va + Vb + Vc);
  V := Vb * Den; W := Vc * Den;
  L0 := 1 - V - W; L1 := V; L2 := W;
end;

procedure BodyBounds(M: TFEMMesh; Body: Integer; out Lo, Hi: TVector3);
var
  E, K: Integer;
  P: TVector3;
  First: Boolean;
begin
  First := True;
  Lo := V3(0, 0, 0); Hi := Lo;
  for E := 0 to M.ElemCount - 1 do
    if M.Elems[E].Body = Body then
      for K := 0 to 3 do
      begin
        P := M.Nodes[M.Elems[E].N[K]];
        if First then begin Lo := P; Hi := P; First := False; end
        else
        begin
          Lo := V3(Min(Lo.X, P.X), Min(Lo.Y, P.Y), Min(Lo.Z, P.Z));
          Hi := V3(Max(Hi.X, P.X), Max(Hi.Y, P.Y), Max(Hi.Z, P.Z));
        end;
      end;
end;

function BodiesTouch(M: TFEMMesh; A, B: Integer; Tol: Double): Boolean;
var
  LA, HA, LB, HB: TVector3;
begin
  BodyBounds(M, A, LA, HA);
  BodyBounds(M, B, LB, HB);
  Result := (A <> B) and
            (LA.X <= HB.X + Tol) and (LB.X <= HA.X + Tol) and
            (LA.Y <= HB.Y + Tol) and (LB.Y <= HA.Y + Tol) and
            (LA.Z <= HB.Z + Tol) and (LB.Z <= HA.Z + Tol);
end;

{ coordenadas baricentricas de P no tetraedro E }
procedure TetBary(M: TFEMMesh; E: Integer; const P: TVector3; out L: array of Double);
var
  X0, A, B, C, D: TVector3;
  Det: Double;
begin
  X0 := M.Nodes[M.Elems[E].N[0]];
  A := VSub(M.Nodes[M.Elems[E].N[1]], X0);
  B := VSub(M.Nodes[M.Elems[E].N[2]], X0);
  C := VSub(M.Nodes[M.Elems[E].N[3]], X0);
  D := VSub(P, X0);
  Det := VDot(A, VCross(B, C));
  if Det = 0 then begin L[0] := -1; L[1] := -1; L[2] := -1; L[3] := -1; Exit; end;
  L[1] := VDot(D, VCross(B, C)) / Det;
  L[2] := VDot(A, VCross(D, C)) / Det;
  L[3] := VDot(A, VCross(B, D)) / Det;
  L[0] := 1 - L[1] - L[2] - L[3];
end;

function FindTiesBodies(M: TFEMMesh; const MasterBody, SlaveBody: TBoolArray; Tol: Double): TMeshTies;
const
  TE: array[0..5, 0..1] of Integer = ((0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3));
type
  TBox = record
    Lo, Hi: TVector3;
  end;
var
  MTets, MFaces: array of Integer;
  FBox: array of TBox;
  Mark: array of Boolean;
  CellStart, CellItems: array of Integer;
  GLo, GHi, P, A, B, C, Cl, TLo, THi: TVector3;
  CellSize, D, BestD, L0, L1, L2, BL0, BL1, BL2, BestMin, Eps: Double;
  NX, NY, NZ, NT, E, F, K, I, J, Q, Cx, Cy, Cz, X0, X1, Y0, Y1, Z0, Z1, X, Y, Z, Cell, BestE, BestF: Integer;
  L, BL: array[0..3] of Double;
  T: TMeshTie;
  Vol: Double;

  function CellOf(const V: TVector3; out Ix, Iy, Iz: Integer): Boolean;
  begin
    Ix := Floor((V.X - GLo.X) / CellSize);
    Iy := Floor((V.Y - GLo.Y) / CellSize);
    Iz := Floor((V.Z - GLo.Z) / CellSize);
    Result := (Ix >= 0) and (Iy >= 0) and (Iz >= 0) and (Ix < NX) and (Iy < NY) and (Iz < NZ);
  end;

  procedure TetBox(E: Integer; out Lo, Hi: TVector3);
  var
    K2: Integer;
    V: TVector3;
  begin
    Lo := M.Nodes[M.Elems[E].N[0]]; Hi := Lo;
    for K2 := 1 to 3 do
    begin
      V := M.Nodes[M.Elems[E].N[K2]];
      Lo := V3(Min(Lo.X, V.X), Min(Lo.Y, V.Y), Min(Lo.Z, V.Z));
      Hi := V3(Max(Hi.X, V.X), Max(Hi.Y, V.Y), Max(Hi.Z, V.Z));
    end;
  end;

begin
  Result := nil;
  { tetraedros mestre em uma grade uniforme }
  NT := 0; Vol := 0;
  SetLength(MTets, M.ElemCount);
  for E := 0 to M.ElemCount - 1 do
    if MasterBody[M.Elems[E].Body] then
    begin
      MTets[NT] := E;
      Inc(NT);
      Vol := Vol + Abs(M.ElemVolume(E));
    end;
  SetLength(MTets, NT);
  if NT = 0 then Exit;
  TetBox(MTets[0], GLo, GHi);
  for I := 1 to NT - 1 do
  begin
    TetBox(MTets[I], TLo, THi);
    GLo := V3(Min(GLo.X, TLo.X), Min(GLo.Y, TLo.Y), Min(GLo.Z, TLo.Z));
    GHi := V3(Max(GHi.X, THi.X), Max(GHi.Y, THi.Y), Max(GHi.Z, THi.Z));
  end;
  GLo := VSub(GLo, V3(Tol, Tol, Tol)); GHi := VAdd(GHi, V3(Tol, Tol, Tol));
  CellSize := Max(2 * Power(Vol / NT, 1 / 3), 1e-9);
  CellSize := Max(CellSize, Max(GHi.X - GLo.X, Max(GHi.Y - GLo.Y, GHi.Z - GLo.Z)) / 120);
  NX := Max(1, Ceil((GHi.X - GLo.X) / CellSize));
  NY := Max(1, Ceil((GHi.Y - GLo.Y) / CellSize));
  NZ := Max(1, Ceil((GHi.Z - GLo.Z) / CellSize));
  SetLength(CellStart, NX * NY * NZ + 1);
  { contagem e preenchimento (CSR) }
  for Q := 0 to 1 do
  begin
    if Q = 1 then
    begin
      for I := 1 to High(CellStart) do CellStart[I] := CellStart[I] + CellStart[I - 1];
      SetLength(CellItems, CellStart[High(CellStart)]);
      for I := High(CellStart) downto 1 do CellStart[I] := CellStart[I - 1];
      CellStart[0] := 0;
    end;
    for I := 0 to NT - 1 do
    begin
      TetBox(MTets[I], TLo, THi);
      CellOf(TLo, X0, Y0, Z0); CellOf(THi, X1, Y1, Z1);
      X0 := EnsureRange(X0, 0, NX - 1); X1 := EnsureRange(X1, 0, NX - 1);
      Y0 := EnsureRange(Y0, 0, NY - 1); Y1 := EnsureRange(Y1, 0, NY - 1);
      Z0 := EnsureRange(Z0, 0, NZ - 1); Z1 := EnsureRange(Z1, 0, NZ - 1);
      for Z := Z0 to Z1 do
        for Y := Y0 to Y1 do
          for X := X0 to X1 do
          begin
            Cell := X + NX * (Y + NY * Z);
            if Q = 0 then Inc(CellStart[Cell + 1])
            else
            begin
              CellItems[CellStart[Cell + 1]] := MTets[I];
              Inc(CellStart[Cell + 1]);
            end;
          end;
    end;
  end;
  { faces de contorno mestre (para nos encostados por fora) }
  SetLength(MFaces, M.FaceCount); SetLength(FBox, M.FaceCount);
  NT := 0;
  for F := 0 to M.FaceCount - 1 do
    if MasterBody[M.Elems[M.Faces[F].Elem].Body] then
    begin
      A := M.Nodes[M.Faces[F].N[0]]; B := M.Nodes[M.Faces[F].N[1]]; C := M.Nodes[M.Faces[F].N[2]];
      MFaces[NT] := F;
      FBox[NT].Lo := V3(Min(A.X, Min(B.X, C.X)) - Tol, Min(A.Y, Min(B.Y, C.Y)) - Tol, Min(A.Z, Min(B.Z, C.Z)) - Tol);
      FBox[NT].Hi := V3(Max(A.X, Max(B.X, C.X)) + Tol, Max(A.Y, Max(B.Y, C.Y)) + Tol, Max(A.Z, Max(B.Z, C.Z)) + Tol);
      Inc(NT);
    end;
  SetLength(MFaces, NT); SetLength(FBox, NT);
  Eps := 1e-7;
  SetLength(Mark, M.NodeCount);
  Q := 0;
  for F := 0 to M.FaceCount - 1 do
  begin
    if not SlaveBody[M.Elems[M.Faces[F].Elem].Body] then Continue;
    for K := 0 to 5 do
    begin
      I := M.Faces[F].N[K];
      if (I < 0) or Mark[I] then Continue;
      Mark[I] := True;
      P := M.Nodes[I];
      if (P.X < GLo.X) or (P.Y < GLo.Y) or (P.Z < GLo.Z) or (P.X > GHi.X) or (P.Y > GHi.Y) or (P.Z > GHi.Z) then Continue;
      { 1) dentro de um tetraedro mestre }
      BestE := -1; BestMin := -Eps;
      if CellOf(P, Cx, Cy, Cz) then
      begin
        Cell := Cx + NX * (Cy + NY * Cz);
        for J := CellStart[Cell] to CellStart[Cell + 1] - 1 do
        begin
          E := CellItems[J];
          TetBary(M, E, P, L);
          if Min(Min(L[0], L[1]), Min(L[2], L[3])) >= BestMin then
          begin
            BestMin := Min(Min(L[0], L[1]), Min(L[2], L[3]));
            BestE := E;
            BL[0] := L[0]; BL[1] := L[1]; BL[2] := L[2]; BL[3] := L[3];
          end;
        end;
      end;
      if BestE >= 0 then
      begin
        T.Slave := I; T.Gap := 0;
        for J := 0 to 3 do BL[J] := Max(0, BL[J]);
        if M.Order = 2 then
        begin
          T.NM := 10;
          for J := 0 to 3 do T.W[J] := BL[J] * (2 * BL[J] - 1);
          for J := 0 to 5 do T.W[4 + J] := 4 * BL[TE[J, 0]] * BL[TE[J, 1]];
        end
        else
        begin
          T.NM := 4;
          for J := 0 to 3 do T.W[J] := BL[J];
        end;
        for J := 0 to T.NM - 1 do T.Masters[J] := M.Elems[BestE].N[J];
      end
      else
      begin
        { 2) encostado em uma face mestre }
        BestF := -1; BestD := Tol; BL0 := 0; BL1 := 0; BL2 := 0;
        for J := 0 to High(MFaces) do
        begin
          if (P.X < FBox[J].Lo.X) or (P.X > FBox[J].Hi.X) or (P.Y < FBox[J].Lo.Y) or
             (P.Y > FBox[J].Hi.Y) or (P.Z < FBox[J].Lo.Z) or (P.Z > FBox[J].Hi.Z) then Continue;
          A := M.Nodes[M.Faces[MFaces[J]].N[0]];
          B := M.Nodes[M.Faces[MFaces[J]].N[1]];
          C := M.Nodes[M.Faces[MFaces[J]].N[2]];
          ClosestOnTriangle(P, A, B, C, L0, L1, L2);
          Cl := VAdd(VAdd(VScale(A, L0), VScale(B, L1)), VScale(C, L2));
          D := VLength(VSub(P, Cl));
          if D <= BestD then
          begin
            BestD := D; BestF := MFaces[J];
            BL0 := L0; BL1 := L1; BL2 := L2;
          end;
        end;
        if BestF < 0 then Continue;
        T.Slave := I; T.Gap := BestD;
        if M.Order = 2 then
        begin
          T.NM := 6;
          T.W[0] := BL0 * (2 * BL0 - 1); T.W[1] := BL1 * (2 * BL1 - 1); T.W[2] := BL2 * (2 * BL2 - 1);
          T.W[3] := 4 * BL0 * BL1; T.W[4] := 4 * BL1 * BL2; T.W[5] := 4 * BL2 * BL0;
        end
        else
        begin
          T.NM := 3;
          T.W[0] := BL0; T.W[1] := BL1; T.W[2] := BL2;
        end;
        for J := 0 to T.NM - 1 do T.Masters[J] := M.Faces[BestF].N[J];
      end;
      for J := T.NM to 9 do begin T.Masters[J] := -1; T.W[J] := 0; end;
      if Q >= Length(Result) then SetLength(Result, Max(64, 2 * Length(Result)));
      Result[Q] := T;
      Inc(Q);
    end;
  end;
  SetLength(Result, Q);
end;

function FindTies(M: TFEMMesh; MasterPart, SlavePart: Integer; Tol: Double): TMeshTies;
var
  MB, SB: TBoolArray;
  I: Integer;
begin
  SetLength(MB, M.BodyCount); SetLength(SB, M.BodyCount);
  for I := 0 to M.BodyCount - 1 do
  begin
    MB[I] := M.BodyPart[I] = MasterPart;
    SB[I] := M.BodyPart[I] = SlavePart;
  end;
  Result := FindTiesBodies(M, MB, SB, Tol);
end;

function IntraPartTies(M: TFEMMesh; Tol: Double): TMeshTies;
var
  A, B: Integer;
  MB, SB: TBoolArray;
begin
  Result := nil;
  SetLength(MB, M.BodyCount); SetLength(SB, M.BodyCount);
  for A := 0 to M.BodyCount - 1 do
    for B := A + 1 to M.BodyCount - 1 do
    begin
      if M.BodyPart[A] <> M.BodyPart[B] then Continue;
      if not BodiesTouch(M, A, B, Tol) then Continue;
      { nos dois sentidos: um disco largo sobre uma haste fina so teria o no
        central amarrado se so os nos do disco fossem escravos }
      MB[A] := True; SB[B] := True;
      AppendTies(Result, FindTiesBodies(M, MB, SB, Tol));
      MB[A] := False; SB[B] := False;
      MB[B] := True; SB[A] := True;
      AppendTies(Result, FindTiesBodies(M, MB, SB, Tol));
      MB[B] := False; SB[A] := False;
    end;
end;

end.
