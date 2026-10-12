program test_scene;
{$mode objfpc}{$H+}
{ MultiSlicer - cena com varias pecas (Etapa 3): posicionamento livre na mesa,
  transformacoes (rotacao, escala, espelho), assentar em Z = 0, arrastar,
  validacao e malha unica para o fatiamento. }
uses Classes, SysUtils, Math, multislicer_types, multislicer_mesh, multislicer_scene,
  multislicer_pipeline;

procedure Check(OK: Boolean; const Msg: string);
begin
  if not OK then begin Writeln('FAIL: ', Msg); Halt(1); end;
end;

function Box(X0, Y0, Z0, X1, Y1, Z1: Double): TMesh;
begin
  Result := TMesh.Create;
  AddBox(Result, X0, Y0, Z0, X1, Y1, Z1);
end;

function SignedVolume(M: TMesh): Double;
var I: Integer; T: TTriangle;
begin
  Result := 0;
  for I := 0 to M.Count - 1 do
  begin
    T := M.Triangle(I);
    Result := Result + (T.A.X * (T.B.Y * T.C.Z - T.B.Z * T.C.Y) - T.A.Y * (T.B.X * T.C.Z - T.B.Z * T.C.X) +
      T.A.Z * (T.B.X * T.C.Y - T.B.Y * T.C.X)) / 6;
  end;
end;

function Near(A, B: Double): Boolean;
begin
  Result := Abs(A - B) < 1e-6;
end;

var S2: TSliceScene; O: TSliceObject; I, K, Face: Integer; RX, RY, RZ: Double; Mt, Mt2: TMat3; Ok: Boolean;
  T: TTriangle; Nm: TVec3; St: TSliceSettings; Cur, L: Integer; Line: string; Bad: Boolean;
  XV: Double; P0, Checked: Integer;
var S: TSliceScene; A, B, C: TSliceObject; Sz: TVec3; Bx, Bx2: TBox3; E: TStringList;
  M: TMesh; Slicer: TModernSlicer; G: TStringList; R: TSliceReport; V0: Double;
begin
  S := TSliceScene.Create; E := TStringList.Create;
  try
    { peca fora da mesa e acima de Z = 0 entra centralizada e assentada }
    A := S.Add(Box(500, 600, 30, 510, 620, 35), 'a', 'a.stl');
    Bx := A.WorldBox;
    Check(Near(Bx.Min.X, 105) and Near(Bx.Max.Y, 120) and Near(Bx.Min.Z, 0), 'first part centered and on the bed');
    V0 := SignedVolume(A.WorldMesh);
    Check(V0 > 0, 'source winding is outward');
    { a segunda peca vai para um lugar livre }
    B := S.Add(Box(0, 0, 0, 10, 20, 5), 'b', 'b.stl');
    Check(not S.Overlaps(0, 1) and S.Inside(1), 'second part placed without overlap');
    Check(S.Validate(E), 'two parts validate: ' + E.Text);
    { rotacao 90 graus em X: 10 x 20 x 5 vira 10 x 5 x 20, ainda na mesa }
    A.RotX := 90;
    Sz := A.Size;
    Check(Near(Sz.X, 10) and Near(Sz.Y, 5) and Near(Sz.Z, 20) and Near(A.WorldBox.Min.Z, 0),
      'rotation X 90 swaps Y/Z and drops to bed');
    Check(Near(SignedVolume(A.WorldMesh), V0), 'rotation keeps volume');
    { espelho mantem as normais para fora }
    A.MirrorX := True;
    Check(Near(SignedVolume(A.WorldMesh), V0), 'mirror keeps outward winding');
    A.MirrorX := False; A.RotX := 0;
    { escala uniforme }
    A.SetScaleUniform(2);
    Sz := A.Size;
    Check(Near(Sz.X, 20) and Near(Sz.Y, 40) and Near(Sz.Z, 10), 'uniform scale x2');
    Check(Near(SignedVolume(A.WorldMesh), V0 * 8), 'scale changes volume by s^3');
    A.SetScaleUniform(1);
    { arrastar = mesma malha que recalcular do zero }
    Bx := A.WorldBox;
    A.MoveBy(-60, 15);
    Bx2 := A.WorldBox;
    Check(Near(Bx2.Min.X, Bx.Min.X - 60) and Near(Bx2.Max.Y, Bx.Max.Y + 15), 'move shifts the box');
    C := A.Clone;
    try
      Check(Near(C.WorldMesh.Triangle(0).A.X, A.WorldMesh.Triangle(0).A.X) and
        Near(C.WorldMesh.Triangle(5).C.Y, A.WorldMesh.Triangle(5).C.Y), 'in-place move equals rebuild');
    finally
      C.Free;
    end;
    { validacao: fora da mesa e sobreposicao }
    A.X := -20; E.Clear;
    Check(not S.Validate(E) and (Pos('sai da mesa', E.Text) > 0), 'part off the bed fails validation');
    A.X := B.X; A.Y := B.Y; E.Clear;
    Check(not S.Validate(E) and (Pos('sobrepoem', E.Text) > 0), 'overlapping parts fail validation');
    S.CenterObject(0);
    B.X := 30; B.Y := 30; E.Clear;
    Check(S.Validate(E), 'separated again: ' + E.Text);
    { duplicar e remover }
    S.Duplicate(1);
    Check((S.Count = 3) and not S.Overlaps(1, 2), 'duplicate goes to a free spot');
    S.SelectOnly(2); S.DeleteSelected;
    Check(S.Count = 2, 'delete selected');
    { malha unica para o fatiamento: as duas pecas na mesma camada }
    M := TMesh.Create; Slicer := TModernSlicer.Create; G := TStringList.Create;
    try
      S.MergedMesh(M);
      Check(M.Count = A.Source.Count + B.Source.Count, 'merged mesh has every triangle');
      R := Slicer.Slice(M, DefaultSliceSettings, G);
      Check((R.Layers > 0) and (Length(Slicer.Layers[0].Loops) = 2), 'both parts sliced in the first layer');
    finally
      M.Free; Slicer.Free; G.Free;
    end;
    { rotulo por peca no G-code (cancelar uma peca no meio da impressao) }
    M := TMesh.Create; Slicer := TModernSlicer.Create; G := TStringList.Create;
    try
      S.MergedMesh(M);
      St := DefaultSliceSettings;
      SetLength(St.Objects, S.Count);
      for I := 0 to S.Count - 1 do
      begin
        Bx := S[I].WorldBox;
        St.Objects[I].Name := S[I].Name;
        St.Objects[I].MinX := Bx.Min.X; St.Objects[I].MinY := Bx.Min.Y;
        St.Objects[I].MaxX := Bx.Max.X; St.Objects[I].MaxY := Bx.Max.Y;
      end;
      Slicer.Slice(M, St, G);
      Check((Pos('M486 T2', G.Text) > 0) and (Pos('M486 S1', G.Text) > 0), 'Marlin labels two objects');
      { toda extrusao entre M486 S0 e M486 S-1 fica na caixa da peca 0 }
      Cur := -1; Bad := False; Checked := 0;
      for L := 0 to G.Count - 1 do
      begin
        Line := G[L];
        if Line = 'M486 S0' then Cur := 0
        else if Line = 'M486 S1' then Cur := 1
        else if Line = 'M486 S-1' then Cur := -1
        else if (Cur >= 0) and (Copy(Line, 1, 3) = 'G1 ') and (Pos(' E', Line) > 0) then
        begin
          P0 := Pos('X', Line);
          if P0 > 0 then
          begin
            XV := StrToFloatDef(Copy(Line, P0 + 1, Pos(' ', Copy(Line, P0, 99) + ' ') - 2), -999,
              DefaultFormatSettings);
            if Pos('.', Copy(Line, P0, 20)) > 0 then
              XV := StrToFloatDef(StringReplace(Copy(Line, P0 + 1, Pos(' ', Copy(Line, P0, 99) + ' ') - 2), '.',
                DefaultFormatSettings.DecimalSeparator, []), -999);
            if (XV < St.Objects[Cur].MinX - 1) or (XV > St.Objects[Cur].MaxX + 1) then Bad := True;
            Inc(Checked);
          end;
        end;
      end;
      Check(not Bad and (Checked > 50), Format('extrusions inside each label stay within that object (%d checked)', [Checked]));
      St.Flavor := sfKlipper;
      Slicer.Slice(M, St, G);
      Check((Pos('EXCLUDE_OBJECT_DEFINE NAME=a_1', G.Text) > 0) and (Pos('EXCLUDE_OBJECT_DEFINE NAME=b_2', G.Text) > 0) and
        (Pos('EXCLUDE_OBJECT_START NAME=b_2', G.Text) > 0), 'Klipper defines and starts each object');
    finally
      M.Free; Slicer.Free; G.Free;
    end;
    { ---- Etapa 4 ---- }
    { Euler <-> matriz ida e volta }
    Mt := EulerToMatrix(23, -61, 140);
    MatrixToEuler(Mt, RX, RY, RZ);
    Mt2 := EulerToMatrix(RX, RY, RZ);
    Ok := True;
    for I := 0 to 2 do for K := 0 to 2 do if Abs(Mt[I, K] - Mt2[I, K]) > 1e-9 then Ok := False;
    Check(Ok, 'Euler round trip');
    S2 := TSliceScene.Create;
    try
      { deitar face: caixa 10 x 20 x 5 girada 37 graus fica apoiada numa aresta }
      O := S2.Add(Box(0, 0, 0, 10, 20, 5), 'c', 'c.stl');
      O.RotX := 37;
      Check(O.ContactArea < 1, 'tilted box has no flat contact');
      Check(O.LayFlatAuto and Near(O.ContactArea, 200) and Near(O.WorldBox.Min.Z, 0),
        'auto lay flat finds the 10 x 20 face');
      Check(not O.LayFlatAuto, 'auto lay flat again changes nothing');
      { deitar o triangulo clicado: escolhe um da face 10 x 5 (normal em +Y ou -Y) }
      Face := -1;
      for I := 0 to O.WorldMesh.Count - 1 do
      begin
        T := O.WorldMesh.Triangle(I);
        Nm := TriNormal(T);
        if Near(TriArea(T), 25) then begin Face := I; Break; end;
      end;
      Check(Face >= 0, 'found a triangle of the 10 x 5 face');
      O.LayFlatTriangle(Face);
      Check(Near(O.ContactArea, 50) and Near(O.Size.Z, 20), 'clicked 10 x 5 face lies on the bed (part stands 20 mm)');
      { desfazer / refazer }
      S2.PushUndo;
      O.RotZ := 45;
      Check(S2.Undo and Near(O.Size.Z, 20) and (O.RotZ <> 45), 'undo restores the previous rotation');
      Check(S2.Redo and Near(O.RotZ, 45), 'redo applies it again');
      Check(not S2.Redo and S2.CanUndo, 'redo stack empty after redo');
      { auto-arranjo: 6 caixas empilhadas no centro + uma travada no canto }
      S2.Clear;
      for I := 1 to 6 do
      begin
        O := S2.AddObject(TSliceObject.Create(Box(0, 0, 0, 40, 30, 10), 'p' + IntToStr(I), ''), False);
        O.X := 110; O.Y := 110;
      end;
      O := S2.AddObject(TSliceObject.Create(Box(0, 0, 0, 20, 20, 10), 'fixa', ''), False);
      O.X := 15; O.Y := 15; O.Locked := True;
      E.Clear;
      Check(not S2.Validate(E), 'stacked parts overlap before arranging');
      Check(S2.Arrange, 'arrange fits every part');
      E.Clear;
      Check(S2.Validate(E), 'arranged parts validate: ' + E.Text);
      Check(Near(O.X, 15) and Near(O.Y, 15), 'locked part stays in place');
      Check(S2.DuplicateN(0, 3) = 3, 'three copies fit');
      E.Clear;
      Check((S2.Count = 10) and S2.Validate(E), 'copies placed without overlap: ' + E.Text);
    finally
      S2.Free;
    end;
    Writeln('MultiSlicer cena: OK (centralizar, lugar livre, rotacao, espelho, escala, arrastar, validacao, duplicar, malha unica, rotulo por peca, deitar na mesa, desfazer, organizar, copias, travar)');
  finally
    E.Free; S.Free;
  end;
end.
