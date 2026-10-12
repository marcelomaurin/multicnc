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
    Writeln('MultiSlicer cena: OK (centralizar, lugar livre, rotacao, espelho, escala, arrastar, validacao, duplicar, malha unica)');
  finally
    E.Free; S.Free;
  end;
end.
