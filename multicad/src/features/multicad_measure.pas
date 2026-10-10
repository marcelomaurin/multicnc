unit multicad_measure;

{ MultiCAD - Medir (fase 4). Sem LCL.

  Recebe as referencias selecionadas ("face:...", "plane:<id>") e devolve as
  medidas em texto, como a ferramenta Medir do SolidWorks:
    1 face        area; plana: normal; cilindrica: diametro e eixo
    2 planos      paralelos: distancia; senao: angulo
    2 cilindros   paralelos: distancia entre eixos; senao: angulo
    plano+cilindro com eixo paralelo ao plano: distancia do eixo ao plano
  Varias faces: soma das areas. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multicad_types, multicad_units, multicad_mesh,
  multicad_rebuild;

type
  TCadMeasureKind = (mkNone, mkPlane, mkAxis, mkOther);

  TCadMeasureItem = record
    Kind: TCadMeasureKind;
    Name: string;
    P, D: TCadVec3;       { plano: ponto e normal; eixo: ponto e direcao }
    Radius: Double;
    Area: Double;          { faces; -1 = sem area (plano de referencia) }
  end;

  TCadMeasureResult = record
    Lines: TStringList;   { o chamador libera }
    Distance: Double;     { NaN se nao houver }
    Angle: Double;        { graus; NaN se nao houver }
    Area: Double;
  end;

function CadMeasureItem(RB: TCadRebuilder; const ARef: string; out It: TCadMeasureItem): Boolean;
function CadMeasure(RB: TCadRebuilder; ARefs: TStrings): TCadMeasureResult;

implementation

function CadMeasureItem(RB: TCadRebuilder; const ARef: string; out It: TCadMeasureItem): Boolean;
var
  B: TCadBody;
  F: Integer;
  Info: TCadFaceInfo;
  Fr: TCadFrame;
  Err: string;
begin
  It := Default(TCadMeasureItem);
  It.Name := ARef;
  It.Area := -1;
  Result := False;
  if Pos('face:', ARef) = 1 then
  begin
    if not RB.FindFace(Copy(ARef, 6, MaxInt), B, F) then
      Exit;
    Info := B.Mesh.Faces[F];
    It.Area := B.Mesh.FaceArea(F);
    It.P := Info.Origin;
    It.D := VNorm(Info.Axis);
    It.Radius := Info.Radius;
    case Info.Surf of
      skPlane: It.Kind := mkPlane;
      skCylinder: It.Kind := mkAxis;
    else
      It.Kind := mkOther;
    end;
    Exit(True);
  end;
  if Pos('plane:', ARef) = 1 then
  begin
    if not RB.ResolvePlane(ARef, Fr, Err) then
      Exit;
    It.Kind := mkPlane;
    It.P := Fr.Origin;
    It.D := Fr.Normal;
    Exit(True);
  end;
end;

function AxisDist(const P1, D1, P2: TCadVec3): Double;
var
  W: TCadVec3;
begin
  W := VSub(P2, P1);
  Result := VLen(VSub(W, VScale(D1, VDot(W, D1))));
end;

function CadMeasure(RB: TCadRebuilder; ARefs: TStrings): TCadMeasureResult;
var
  Items: array of TCadMeasureItem;
  I, N: Integer;
  A, B: TCadMeasureItem;
  C, Ang: Double;
  L: TStringList;
begin
  L := TStringList.Create;
  Result.Lines := L;
  Result.Distance := NaN;
  Result.Angle := NaN;
  Result.Area := 0;
  SetLength(Items, 0);
  for I := 0 to ARefs.Count - 1 do
  begin
    SetLength(Items, Length(Items) + 1);
    if not CadMeasureItem(RB, ARefs[I], Items[High(Items)]) then
      SetLength(Items, Length(Items) - 1);
  end;
  N := Length(Items);
  if N = 0 then
  begin
    L.Add('Selecione faces ou planos para medir.');
    Exit;
  end;
  for I := 0 to N - 1 do
    if Items[I].Area >= 0 then
      Result.Area := Result.Area + Items[I].Area;
  if N = 1 then
  begin
    A := Items[0];
    L.Add(A.Name);
    if A.Area >= 0 then
      L.Add('Área: ' + CadFmt(A.Area, 3) + ' mm²');
    case A.Kind of
      mkPlane: L.Add(Format('Normal: (%s; %s; %s)', [CadFmt(A.D.X, 4), CadFmt(A.D.Y, 4), CadFmt(A.D.Z, 4)]));
      mkAxis:
        begin
          L.Add('Diâmetro: ' + CadFmt(2 * A.Radius, 3) + ' mm  (raio ' + CadFmt(A.Radius, 3) + ')');
          L.Add(Format('Eixo: (%s; %s; %s)', [CadFmt(A.D.X, 4), CadFmt(A.D.Y, 4), CadFmt(A.D.Z, 4)]));
        end;
    end;
    Exit;
  end;
  if N = 2 then
  begin
    A := Items[0];
    B := Items[1];
    L.Add(A.Name + '  ×  ' + B.Name);
    if (A.Kind in [mkPlane, mkAxis]) and (B.Kind in [mkPlane, mkAxis]) then
    begin
      C := Abs(VDot(A.D, B.D));
      if (A.Kind = mkPlane) and (B.Kind = mkPlane) then
      begin
        if C > 1 - 1E-6 then
        begin
          Result.Distance := Abs(VDot(VSub(B.P, A.P), A.D));
          L.Add('Distância (planos paralelos): ' + CadFmt(Result.Distance, 3) + ' mm');
        end
        else
        begin
          Ang := RadToDeg(ArcCos(EnsureRange(VDot(A.D, B.D), -1, 1)));
          Result.Angle := Ang;
          L.Add('Ângulo entre as normais: ' + CadFmt(Ang, 3) + '°');
        end;
      end
      else if (A.Kind = mkAxis) and (B.Kind = mkAxis) then
      begin
        if C > 1 - 1E-6 then
        begin
          Result.Distance := AxisDist(A.P, A.D, B.P);
          L.Add('Distância entre eixos: ' + CadFmt(Result.Distance, 3) + ' mm');
        end
        else
        begin
          Result.Angle := RadToDeg(ArcCos(EnsureRange(C, 0, 1)));
          L.Add('Ângulo entre eixos: ' + CadFmt(Result.Angle, 3) + '°');
        end;
      end
      else
      begin
        if A.Kind = mkAxis then
        begin
          { troca para A = plano }
          A := Items[1];
          B := Items[0];
        end;
        if Abs(VDot(A.D, B.D)) < 1E-6 then
        begin
          Result.Distance := Abs(VDot(VSub(B.P, A.P), A.D));
          L.Add('Distância do eixo ao plano: ' + CadFmt(Result.Distance, 3) + ' mm');
        end
        else
        begin
          Result.Angle := 90 - RadToDeg(ArcCos(EnsureRange(Abs(VDot(A.D, B.D)), 0, 1)));
          L.Add('Ângulo entre eixo e plano: ' + CadFmt(Result.Angle, 3) + '°');
        end;
      end;
    end;
  end;
  if Result.Area > 0 then
    L.Add('Área total: ' + CadFmt(Result.Area, 3) + ' mm²');
end;

end.
