unit multislicer_project;

{ MultiSlicer - projeto .mslice (Etapa 8.5 do docs/PLANO_TAREFAS.md).

  JSON com:
    format, version          - "mslice", 1
    scene.objects[]          - arquivo do modelo (relativo ao projeto quando
                               possivel, e o absoluto), nome e transformacao
    scene.pillars[]          - hastes manuais (posicao absoluta + peca)
    scene.blockers[]         - bloqueadores de suporte
    settings                 - o que a tela guarda (impressora, material,
                               qualidade, suportes, aderencia, equipamento),
                               montado e lido pela tela

  A malha nao vai no projeto: ele aponta para o STL/3MF. Ao abrir, procura o
  arquivo primeiro pelo caminho relativo (pasta movida inteira) e depois
  pelo absoluto. Sem LCL. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, fpjson, jsonparser, multislicer_types, multislicer_mesh,
  multislicer_scene, multislicer_stl, multislicer_3mf, multislicer_userdata;

const
  MSLICE_FORMAT = 'mslice';
  MSLICE_VERSION = 1;
  MSLICE_EXT = '.mslice';

{ cena -> JSON (o chamador libera). ProjectFile define os caminhos relativos. }
function SceneToJSON(Scene: TSliceScene; const ProjectFile: string): TJSONObject;
{ JSON -> cena (a cena e limpa antes). Missing recebe os modelos nao achados. }
procedure SceneFromJSON(O: TJSONObject; Scene: TSliceScene; const ProjectFile: string; Missing: TStrings);
{ carrega um modelo STL/3MF; False se invalido }
function LoadModelFile(const FN: string; Mesh: TMesh): Boolean;
procedure SaveProject(const FN: string; Scene: TSliceScene; Settings: TJSONObject);
{ devolve as configuracoes (o chamador libera) }
function LoadProject(const FN: string; Scene: TSliceScene; Missing: TStrings): TJSONObject;

implementation

function LoadModelFile(const FN: string; Mesh: TMesh): Boolean;
begin
  Mesh.Clear;
  try
    if SameText(ExtractFileExt(FN), '.3mf') then Result := T3MFImporter.Load(FN, Mesh)
    else Result := TSTLImporter.Load(FN, Mesh);
  except
    Result := False;
  end;
  Result := Result and (Mesh.Count > 0);
end;

function SceneToJSON(Scene: TSliceScene; const ProjectFile: string): TJSONObject;
var
  Objs, Pils, Blks: TJSONArray;
  O: TJSONObject;
  I, K: Integer;
  St: TTransformState;
  X, Y, Z, D: Double;
  B: TSceneBlocker;
  Dir: string;
begin
  Dir := ExtractFilePath(ExpandFileName(ProjectFile));
  Result := TJSONObject.Create;
  Result.Add('bed_x', Scene.BedX);
  Result.Add('bed_y', Scene.BedY);
  Result.Add('bed_z', Scene.BedZ);
  Objs := TJSONArray.Create;
  Result.Add('objects', Objs);
  for I := 0 to Scene.Count - 1 do
  begin
    St := Scene[I].GetState;
    O := TJSONObject.Create;
    O.Add('name', Scene[I].Name);
    O.Add('file', ExtractRelativePath(Dir, Scene[I].SourceFile));
    O.Add('file_abs', Scene[I].SourceFile);
    O.Add('x', St.X); O.Add('y', St.Y); O.Add('lift', St.Lift);
    O.Add('rot_x', St.RotX); O.Add('rot_y', St.RotY); O.Add('rot_z', St.RotZ);
    O.Add('scale_x', St.ScaleX); O.Add('scale_y', St.ScaleY); O.Add('scale_z', St.ScaleZ);
    O.Add('mirror_x', St.MirrorX); O.Add('mirror_y', St.MirrorY); O.Add('mirror_z', St.MirrorZ);
    O.Add('locked', St.Locked);
    Objs.Add(O);
  end;
  Pils := TJSONArray.Create;
  Result.Add('pillars', Pils);
  for I := 0 to Scene.PillarCount - 1 do
    if Scene.PillarAbs(I, X, Y, Z, D) then
    begin
      K := Scene.Count - 1;
      while (K >= 0) and (Scene[K].Id <> Scene.Pillar(I).ObjId) do Dec(K);
      if K < 0 then Continue;
      O := TJSONObject.Create;
      O.Add('object', K);
      O.Add('x', X); O.Add('y', Y); O.Add('z_top', Z); O.Add('diameter', D);
      Pils.Add(O);
    end;
  Blks := TJSONArray.Create;
  Result.Add('blockers', Blks);
  for I := 0 to Scene.BlockerCount - 1 do
  begin
    B := Scene.Blocker(I);
    O := TJSONObject.Create;
    O.Add('cx', B.CX); O.Add('cy', B.CY); O.Add('w', B.W); O.Add('d', B.D); O.Add('h', B.H);
    Blks.Add(O);
  end;
end;

procedure SceneFromJSON(O: TJSONObject; Scene: TSliceScene; const ProjectFile: string; Missing: TStrings);
var
  Arr: TJSONArray;
  E: TJSONObject;
  I, K: Integer;
  Dir, FN: string;
  M: TMesh;
  Obj: TSliceObject;
  St: TTransformState;
  Map: array of TSliceObject;
  B: TSceneBlocker;
begin
  Dir := ExtractFilePath(ExpandFileName(ProjectFile));
  Scene.Clear;
  Scene.BedX := JFloat(O, 'bed_x', Scene.BedX);
  Scene.BedY := JFloat(O, 'bed_y', Scene.BedY);
  Scene.BedZ := JFloat(O, 'bed_z', Scene.BedZ);
  Map := nil;
  if O.Find('objects') is TJSONArray then
  begin
    Arr := TJSONArray(O.Find('objects'));
    SetLength(Map, Arr.Count);
    for I := 0 to Arr.Count - 1 do
    begin
      Map[I] := nil;
      if not (Arr[I] is TJSONObject) then Continue;
      E := TJSONObject(Arr[I]);
      { primeiro relativo (pasta do projeto movida inteira), depois o absoluto }
      FN := JStr(E, 'file', '');
      if FN <> '' then FN := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + FN);
      if (FN = '') or not FileExists(FN) then FN := JStr(E, 'file_abs', '');
      M := TMesh.Create;
      try
        if (FN = '') or not FileExists(FN) or not LoadModelFile(FN, M) then
        begin
          if Missing <> nil then Missing.Add(JStr(E, 'file_abs', JStr(E, 'file', '?')));
          Continue;
        end;
        Obj := TSliceObject.Create(M, JStr(E, 'name', ChangeFileExt(ExtractFileName(FN), '')), FN);
        M := nil;
      finally
        M.Free;
      end;
      Scene.AddObject(Obj, False);
      St := Obj.GetState;
      St.X := JFloat(E, 'x', St.X); St.Y := JFloat(E, 'y', St.Y); St.Lift := JFloat(E, 'lift', 0);
      St.RotX := JFloat(E, 'rot_x', 0); St.RotY := JFloat(E, 'rot_y', 0); St.RotZ := JFloat(E, 'rot_z', 0);
      St.ScaleX := JFloat(E, 'scale_x', 1); St.ScaleY := JFloat(E, 'scale_y', 1); St.ScaleZ := JFloat(E, 'scale_z', 1);
      St.MirrorX := JBool(E, 'mirror_x', False); St.MirrorY := JBool(E, 'mirror_y', False);
      St.MirrorZ := JBool(E, 'mirror_z', False);
      St.Locked := JBool(E, 'locked', False);
      Obj.SetState(St);
      Map[I] := Obj;
    end;
  end;
  if O.Find('pillars') is TJSONArray then
  begin
    Arr := TJSONArray(O.Find('pillars'));
    for I := 0 to Arr.Count - 1 do
      if Arr[I] is TJSONObject then
      begin
        E := TJSONObject(Arr[I]);
        K := JInt(E, 'object', -1);
        if (K < 0) or (K > High(Map)) or (Map[K] = nil) then Continue;
        Scene.AddPillar(Map[K], JFloat(E, 'x', 0), JFloat(E, 'y', 0), JFloat(E, 'z_top', 0),
          JFloat(E, 'diameter', 3));
      end;
  end;
  if O.Find('blockers') is TJSONArray then
  begin
    Arr := TJSONArray(O.Find('blockers'));
    for I := 0 to Arr.Count - 1 do
      if Arr[I] is TJSONObject then
      begin
        E := TJSONObject(Arr[I]);
        B.CX := JFloat(E, 'cx', 0); B.CY := JFloat(E, 'cy', 0);
        B.W := Max(1, JFloat(E, 'w', 10)); B.D := Max(1, JFloat(E, 'd', 10)); B.H := Max(0.2, JFloat(E, 'h', 10));
        Scene.AddBlocker(B);
      end;
  end;
  Scene.ClearHistory;
  Scene.Touch;
end;

procedure SaveProject(const FN: string; Scene: TSliceScene; Settings: TJSONObject);
var Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', MSLICE_FORMAT);
    Root.Add('version', MSLICE_VERSION);
    Root.Add('scene', SceneToJSON(Scene, FN));
    if Settings <> nil then Root.Add('settings', Settings.Clone)
    else Root.Add('settings', TJSONObject.Create);
    SaveJSONObject(FN, Root);
  finally
    Root.Free;
  end;
end;

function LoadProject(const FN: string; Scene: TSliceScene; Missing: TStrings): TJSONObject;
var Root: TJSONObject;
begin
  Root := LoadJSONObject(FN);
  if Root = nil then raise Exception.Create('Projeto invalido: ' + FN);
  try
    if JStr(Root, 'format', '') <> MSLICE_FORMAT then
      raise Exception.Create('Nao e um projeto do MultiSlicer: ' + FN);
    if JInt(Root, 'version', 0) > MSLICE_VERSION then
      raise Exception.Create('Projeto de uma versao mais nova do MultiSlicer: ' + FN);
    if Root.Find('scene') is TJSONObject then
      SceneFromJSON(TJSONObject(Root.Find('scene')), Scene, FN, Missing)
    else
      Scene.Clear;
    if Root.Find('settings') is TJSONObject then
      Result := TJSONObject(Root.Find('settings').Clone)
    else
      Result := TJSONObject.Create;
  finally
    Root.Free;
  end;
end;

end.
