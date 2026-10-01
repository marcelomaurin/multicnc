unit multislicer_3mf;
{$mode objfpc}{$H+}
{ Importacao de 3MF (ISO/IEC 25422) - formato de projeto dos fatiadores atuais.
  Le todos os objetos de malha do 3D/3dmodel.model (vertices indexados) e
  converte a unidade do modelo para milimetros. Transformacoes de <build> e
  componentes aninhados ainda nao sao aplicados. }
interface
uses Classes, SysUtils, zipper, DOM, XMLRead, multislicer_types, multislicer_mesh;
type T3MFImporter = class
 public
  class function Load(const FN: string; M: TMesh): Boolean;
 end;
implementation

function InvFloat(const S: string): Double;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := StrToFloatDef(S, 0, FS);
end;

class function T3MFImporter.Load(const FN: string; M: TMesh): Boolean;
var
  Z: TUnZipper;
  Dir, ModelFile, ModelUnit: string;
  Doc: TXMLDocument;
  Objs, Verts, Tris: TDOMNodeList;
  I, K, Base: Integer;
  Scale: Double;
  V: array of TVec3;
  T: TTriangle;
  E: TDOMElement;
  Files: TStringList;
begin
  Result := False;
  if not FileExists(FN) then Exit;
  M.Clear;
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'ms3mf_' + IntToStr(GetProcessID) + '_' + IntToStr(Random(1000000));
  ForceDirectories(Dir);
  Z := TUnZipper.Create;
  Files := TStringList.Create;
  try
    Z.FileName := FN;
    Z.OutputPath := Dir;
    Files.Add('3D/3dmodel.model');
    try
      Z.UnZipFiles(Files);
    except
      Exit;
    end;
    ModelFile := IncludeTrailingPathDelimiter(Dir) + '3D' + PathDelim + '3dmodel.model';
    if not FileExists(ModelFile) then Exit;
    ReadXMLFile(Doc, ModelFile);
    try
      ModelUnit := LowerCase(string(Doc.DocumentElement.GetAttribute('unit')));
      if ModelUnit = 'micron' then Scale := 0.001
      else if ModelUnit = 'centimeter' then Scale := 10
      else if ModelUnit = 'inch' then Scale := 25.4
      else if ModelUnit = 'foot' then Scale := 304.8
      else if ModelUnit = 'meter' then Scale := 1000
      else Scale := 1;
      Objs := Doc.GetElementsByTagName('mesh');
      for I := 0 to Objs.Count - 1 do begin
        E := TDOMElement(Objs[I]);
        Verts := E.GetElementsByTagName('vertex');
        SetLength(V, Verts.Count);
        for K := 0 to Verts.Count - 1 do begin
          V[K].X := InvFloat(string(TDOMElement(Verts[K]).GetAttribute('x'))) * Scale;
          V[K].Y := InvFloat(string(TDOMElement(Verts[K]).GetAttribute('y'))) * Scale;
          V[K].Z := InvFloat(string(TDOMElement(Verts[K]).GetAttribute('z'))) * Scale;
        end;
        Tris := E.GetElementsByTagName('triangle');
        for K := 0 to Tris.Count - 1 do begin
          Base := StrToIntDef(string(TDOMElement(Tris[K]).GetAttribute('v1')), -1);
          if (Base < 0) or (Base > High(V)) then Continue;
          T.A := V[Base];
          Base := StrToIntDef(string(TDOMElement(Tris[K]).GetAttribute('v2')), -1);
          if (Base < 0) or (Base > High(V)) then Continue;
          T.B := V[Base];
          Base := StrToIntDef(string(TDOMElement(Tris[K]).GetAttribute('v3')), -1);
          if (Base < 0) or (Base > High(V)) then Continue;
          T.C := V[Base];
          M.Add(T);
        end;
        Tris.Free;
        Verts.Free;
      end;
      Objs.Free;
    finally
      Doc.Free;
    end;
    Result := M.Count > 0;
  finally
    Files.Free;
    Z.Free;
    DeleteFile(ModelFile);
    RemoveDir(IncludeTrailingPathDelimiter(Dir) + '3D');
    RemoveDir(Dir);
  end;
end;

end.
