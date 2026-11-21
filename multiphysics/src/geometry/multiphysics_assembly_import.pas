unit multiphysics_assembly_import;

{ Importa a montagem do MultiAssembly para o projeto do MultiPhysics (MP-2.1).

  Usa o nucleo do MultiAssembly (leitura do projeto JSON e geometria das
  pecas, sem interface). Para cada componente:
  - geometria = primitivas box/cyl/prism (decalques 'disk' ficam de fora),
    a mesma usada na vista do MultiAssembly (ComponentGeometry);
  - transformacao igual a da vista: geometria escalada para o tamanho da
    peca, girada (Z*Y*X) em torno do centro da caixa e deslocada;
  - material sugerido pelo texto do material/tipo (editavel depois);
  - componente fixo vira fixacao em todas as faces;
  - pecas cujas caixas se tocam viram contatos colados. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multiphysics_types, multiphysics_vector,
  multiphysics_geometry, multiphysics_materials, multiphysics_project,
  multiassembly_types, multiassembly_geometry, multiassembly_project,
  multiassembly_library;

{ substitui o conteudo de P pela montagem; Tol = folga para contato (m) }
function ImportAssembly(AP: TAssemblyProject; P: TPhysicsProject; Log: TStrings;
  Tol: Double = 0.0002): Boolean;
function ImportAssemblyFile(const FN: string; P: TPhysicsProject; Log: TStrings): Boolean;
{ material da biblioteca pelo texto do componente }
function GuessMaterial(const MaterialText, KindText: string): TMaterial;
{ caixas envolventes das pecas (m) e pares que se tocam -> contatos }
procedure DetectContacts(P: TPhysicsProject; Tol: Double; Log: TStrings);

implementation

function GuessMaterial(const MaterialText, KindText: string): TMaterial;
var
  S, Name: string;
begin
  S := LowerCase(MaterialText + ' ' + KindText);
  { eletronica primeiro: 'placa' contem 'pla' }
  if (Pos('fr4', S) > 0) or (Pos('fr-4', S) > 0) or (Pos('pcb', S) > 0) or (Pos('placa', S) > 0) or
    (Pos('controller', S) > 0) or (Pos('driver', S) > 0) then Name := 'FR-4 PCB'
  else if (Pos('inox', S) > 0) or (Pos('304', S) > 0) then Name := 'Aco inox 304'
  else if Pos('alum', S) > 0 then Name := 'Aluminio'
  else if Pos('latao', S) > 0 then Name := 'Latao'
  else if Pos('bronze', S) > 0 then Name := 'Bronze'
  else if Pos('cobre', S) > 0 then Name := 'Cobre'
  else if Pos('titan', S) > 0 then Name := 'Titanio'
  else if Pos('petg', S) > 0 then Name := 'PETG'
  else if Pos('pla', S) > 0 then Name := 'PLA'
  else if Pos('abs', S) > 0 then Name := 'ABS'
  else if Pos('nylon', S) > 0 then Name := 'Nylon PA'
  else if Pos('ptfe', S) > 0 then Name := 'PTFE / Teflon'
  else if Pos('pvc', S) > 0 then Name := 'PVC rigido'
  else if Pos('acril', S) > 0 then Name := 'Acrilico PMMA'
  else if (Pos('borracha', S) > 0) or (Pos('silicone', S) > 0) then Name := 'Borracha de silicone'
  else if Pos('vidro', S) > 0 then Name := 'Vidro soda-cal generico'
  else if Pos('madeira', S) > 0 then Name := 'Madeira generica'
  else if (Pos('aco', S) > 0) or (Pos('steel', S) > 0) then Name := 'Aco carbono'
  else Name := 'Aco carbono';
  if FindMaterial(Name) < 0 then
  begin
    { nome exato pode variar na biblioteca: procura por trecho }
    Result := MaterialByIndex(FindMaterial('Aco carbono'));
    Exit;
  end;
  Result := MaterialByIndex(FindMaterial(Name));
end;

function MM(V: Double): Double; inline;
begin
  Result := V / 1000;
end;

function ImportAssembly(AP: TAssemblyProject; P: TPhysicsProject; Log: TStrings; Tol: Double): Boolean;
var
  I, J, K2, NP, Skipped: Integer;
  C: TAssemblyComponent;
  G: TAssemblyGeometry;
  Msh: TAssemblyMesh;
  Part: TPhysicsPart;
  Prim: TGeoPrimitive;
  At: TVector3;
  GX, GY, GZ: Double;
  Poly: array of TVector2;
  B: TBoundaryCondition;
  Fixed: Integer;
begin
  P.Clear;
  P.Name := AP.Name;
  Fixed := 0; Skipped := 0;
  for I := 0 to AP.ComponentCount - 1 do
  begin
    C := AP.Component(I);
    G := ComponentGeometry(C);
    BuildMesh(G, Msh);
    Part := TPhysicsPart.Create;
    Part.ID := StringReplace(C.ID, '/', '_', [rfReplaceAll]);
    Part.Name := C.Name;
    Part.Kind := ComponentKindToStr(C.Kind);
    Part.GeometryFile := C.SourceRef;
    Part.Material := GuessMaterial(C.Material, Part.Kind + ' ' + C.Category + ' ' + C.Name);
    NP := 0;
    for J := 0 to High(G) do
    begin
      if G[J].Kind = agpDisk then Continue;
      { geometria com o canto minimo da envolvente em 0 }
      At := V3(MM(G[J].At.X - Msh.BoundsMin.X), MM(G[J].At.Y - Msh.BoundsMin.Y), MM(G[J].At.Z - Msh.BoundsMin.Z));
      case G[J].Kind of
        agpBox: Prim := BoxPrim('p' + IntToStr(NP), At, V3(MM(G[J].Size.X), MM(G[J].Size.Y), MM(G[J].Size.Z)));
        agpCylinder:
          begin
            if G[J].R2 < 0 then
              Prim := CylPrim('p' + IntToStr(NP), G[J].Axis, At, MM(G[J].R), MM(G[J].H), MM(G[J].Ri))
            else
              Prim := CylPrim('p' + IntToStr(NP), G[J].Axis, At, MM(G[J].R), MM(G[J].H), MM(G[J].Ri), MM(G[J].R2));
            Prim.Rot := G[J].RotDeg;
            if G[J].HasArc then begin Prim.Arc0 := G[J].ArcStart; Prim.Arc1 := G[J].ArcEnd; end;
            if (Prim.R <= Prim.RI) or (Prim.H <= 0) then Continue;
          end;
        else
        begin
          SetLength(Poly, Length(G[J].Poly));
          for K2 := 0 to High(Poly) do Poly[K2] := V2(MM(G[J].Poly[K2].U), MM(G[J].Poly[K2].V));
          Prim := PrismPrim('p' + IntToStr(NP), G[J].Axis, At, MM(G[J].H), Poly);
          if (Length(Poly) < 3) or (Prim.H <= 0) then Continue;
        end;
      end;
      Part.AddPrimitive(Prim);
      NP := Length(Part.Primitives);
    end;
    if Length(Part.Primitives) = 0 then
    begin
      Inc(Skipped);
      Log.Add(Format('Componente %s sem geometria solida: ignorado.', [C.ID]));
      Part.Free;
      Continue;
    end;
    GX := Msh.BoundsMax.X - Msh.BoundsMin.X;
    GY := Msh.BoundsMax.Y - Msh.BoundsMin.Y;
    GZ := Msh.BoundsMax.Z - Msh.BoundsMin.Z;
    Part.Scale := V3(IfThen(GX > 1e-6, C.Size.X / GX, 1), IfThen(GY > 1e-6, C.Size.Y / GY, 1), IfThen(GZ > 1e-6, C.Size.Z / GZ, 1));
    Part.Pivot := V3(MM(C.Size.X / 2), MM(C.Size.Y / 2), MM(C.Size.Z / 2));
    Part.Position := V3(MM(C.Position.X), MM(C.Position.Y), MM(C.Position.Z));
    Part.RotX := C.Rotation.X; Part.RotY := C.Rotation.Y; Part.RotZ := C.Rotation.Z;
    P.AddPart(Part);
    if C.Fixed then
    begin
      P.AddBC(NewBC('Fixo ' + Part.ID, Part.ID, '', bkFixed));
      Inc(Fixed);
    end;
  end;
  B := NewBC('Gravidade', '', '', bkGravity);
  B.Z := -9.80665;
  P.AddBC(B);
  DetectContacts(P, Tol, Log);
  Log.Add(Format('Montagem "%s": %d pecas importadas, %d sem geometria, %d fixas, %d contatos.',
    [AP.Name, P.PartCount, Skipped, Fixed, P.ContactCount]));
  if Fixed = 0 then Log.Add('Nenhum componente fixo na montagem: defina a fixacao na etapa Cargas.');
  P.Modified := True;
  Result := P.PartCount > 0;
end;

function ImportAssemblyFile(const FN: string; P: TPhysicsProject; Log: TStrings): Boolean;
var
  AP: TAssemblyProject;
begin
  AP := TAssemblyProject.Create;
  try
    AP.LoadFromFile(FN);
    Result := ImportAssembly(AP, P, Log);
    P.AssemblyFile := FN;
  finally
    AP.Free;
  end;
end;

{ envolvente da peca no mundo: cantos da caixa da geometria transformados }
procedure WorldBox(Part: TPhysicsPart; out Lo, Hi: TVector3);
var
  I, K: Integer;
  T: TGeoTransform;
  Mn, Mx, Q: TVector3;
  First: Boolean;
  Pr: TGeoPrimitive;
  Pts: array[0..1] of TVector3;
begin
  T := Part.Transform;
  First := True;
  Lo := V3(0, 0, 0); Hi := Lo;
  for K := 0 to High(Part.Primitives) do
  begin
    Pr := Part.Primitives[K];
    case Pr.Kind of
      gpBox: begin Mn := Pr.At; Mx := VAdd(Pr.At, Pr.Size); end;
      gpCyl:
        begin
          Mn := PrimLocalToPart(Pr, -Max(Pr.R, Pr.R2), -Max(Pr.R, Pr.R2), 0);
          Mx := PrimLocalToPart(Pr, Max(Pr.R, Pr.R2), Max(Pr.R, Pr.R2), Pr.H);
        end;
      else
      begin
        Mn := PrimLocalToPart(Pr, 1e30, 1e30, 0); Mx := PrimLocalToPart(Pr, -1e30, -1e30, Pr.H);
        for I := 0 to High(Pr.Poly) do
        begin
          Q := PrimLocalToPart(Pr, Pr.Poly[I].U, Pr.Poly[I].V, 0);
          Mn := V3(Min(Mn.X, Q.X), Min(Mn.Y, Q.Y), Min(Mn.Z, Q.Z));
          Q := PrimLocalToPart(Pr, Pr.Poly[I].U, Pr.Poly[I].V, Pr.H);
          Mx := V3(Max(Mx.X, Q.X), Max(Mx.Y, Q.Y), Max(Mx.Z, Q.Z));
        end;
      end;
    end;
    Pts[0] := V3(Min(Mn.X, Mx.X), Min(Mn.Y, Mx.Y), Min(Mn.Z, Mx.Z));
    Pts[1] := V3(Max(Mn.X, Mx.X), Max(Mn.Y, Mx.Y), Max(Mn.Z, Mx.Z));
    for I := 0 to 7 do
    begin
      Q := ApplyTransform(T, V3(Pts[I and 1].X, Pts[(I shr 1) and 1].Y, Pts[(I shr 2) and 1].Z));
      if First then begin Lo := Q; Hi := Q; First := False; end
      else
      begin
        Lo := V3(Min(Lo.X, Q.X), Min(Lo.Y, Q.Y), Min(Lo.Z, Q.Z));
        Hi := V3(Max(Hi.X, Q.X), Max(Hi.Y, Q.Y), Max(Hi.Z, Q.Z));
      end;
    end;
  end;
end;

procedure DetectContacts(P: TPhysicsProject; Tol: Double; Log: TStrings);
var
  Lo, Hi: array of TVector3;
  I, J, K, N: Integer;
  C: TContact;
  Exists: Boolean;
begin
  N := P.PartCount;
  SetLength(Lo, N); SetLength(Hi, N);
  for I := 0 to N - 1 do WorldBox(P.Part(I), Lo[I], Hi[I]);
  for I := 0 to N - 1 do
    for J := I + 1 to N - 1 do
    begin
      if (Lo[I].X > Hi[J].X + Tol) or (Lo[J].X > Hi[I].X + Tol) or
         (Lo[I].Y > Hi[J].Y + Tol) or (Lo[J].Y > Hi[I].Y + Tol) or
         (Lo[I].Z > Hi[J].Z + Tol) or (Lo[J].Z > Hi[I].Z + Tol) then Continue;
      Exists := False;
      for K := 0 to P.ContactCount - 1 do
        if (SameText(P.Contact(K).PartA, P.Part(I).ID) and SameText(P.Contact(K).PartB, P.Part(J).ID)) or
           (SameText(P.Contact(K).PartA, P.Part(J).ID) and SameText(P.Contact(K).PartB, P.Part(I).ID)) then Exists := True;
      if Exists then Continue;
      C.Name := P.Part(I).ID + '-' + P.Part(J).ID;
      C.PartA := P.Part(I).ID; C.PartB := P.Part(J).ID;
      C.FrictionCoefficient := 0; C.StaticFrictionCoefficient := 0;
      C.RollingFrictionCoefficient := 0; C.ThermalConductance := 0;
      P.AddContact(C);
    end;
  if Log <> nil then Log.Add(Format('Contatos detectados pelas caixas envolventes: %d', [P.ContactCount]));
end;

end.
