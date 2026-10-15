program test_commercial_materials;
{$mode objfpc}{$H+}
uses SysUtils, fpjson, multislicer_materials, multislicer_userdata;
var A, B: TMaterialDefs; M, Restored: TMaterialDef; O: TJSONObject; I, J, Count: Integer; Dir: string;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
    A := BuiltinMaterials; Count := 0;
    Check((A[0].HotendFirst=205) and (A[0].Hotend=200) and (A[0].BedFirst=60) and (A[0].Bed=60), 'legacy PLA defaults');
    Check((A[2].HotendFirst=245) and (A[2].Hotend=240) and (A[2].BedFirst=105) and (A[2].Bed=100), 'legacy ABS defaults');
    for I := 0 to High(A) do
    begin
      for J := I+1 to High(A) do Check(A[I].Name<>A[J].Name, 'unique names');
      M := A[I]; if M.Brand='' then Continue;
      Inc(Count);
      Check((M.SourceURL<>'') and (M.VerifiedOn='2026-10-15') and (M.Product<>''), 'source provenance');
      Check((M.Hotend>=M.HotendMin) and (M.Hotend<=M.HotendMax), 'hotend starting point within published range');
      Check((M.Bed>=M.BedMin) and (M.Bed<=M.BedMax), 'bed starting point within published range');
      Check((M.HotendFirst=M.Hotend) and (M.BedFirst=M.Bed), 'no invented first-layer manufacturer recommendation');
      O := MaterialToJSON(M);
      try Restored := MaterialFromJSON(O); finally O.Free; end;
      Check((Restored.Brand=M.Brand) and (Restored.Kind=M.Kind) and (Restored.SourceURL=M.SourceURL) and
        (Restored.HotendMin=M.HotendMin) and (Restored.BedMax=M.BedMax) and (Restored.Hotend=M.Hotend), 'JSON metadata and temperatures');
    end;
    Check(Count=12, '12 commercial profiles');
    B := FilterMaterials(A, ' pla '); Check(Length(B)=8, 'PLA custom plus seven commercial profiles');
    for M in B do Check(M.Kind='PLA', 'PLA filter excludes ABS');
    Check(Pos('Customizado',MaterialCaption(B[0]))=1, 'custom option first');
    B := FilterMaterials(A, 'ABS'); Check(Length(B)=6, 'ABS custom plus five commercial profiles');
    for M in B do Check(M.Kind='ABS', 'ABS filter excludes PLA');
    Check(Length(FilterMaterials(A,'PETG'))=1, 'other generic materials retained');
    Check(Length(FilterMaterials(A,'missing'))=0, 'unknown kind has no accidental matches');
    M := A[FindMaterial(A,'eSUN PLA+')]; Check((M.Hotend=220) and (M.Bed=60), 'eSUN PLA+ values');
    M := A[FindMaterial(A,'3D Lab ABS Premium')]; Check((M.Hotend=235) and (M.Bed=110), '3D Lab published test values');
    O := TJSONObject.Create;
    try
      O.Add('name','Old PLA'); O.Add('kind','PLA'); O.Add('hotend',212);
      M := MaterialFromJSON(O);
    finally O.Free; end;
    Check((M.Brand='') and (M.Hotend=212) and (M.Kind='PLA'), 'legacy JSON without commercial fields');
    Dir := IncludeTrailingPathDelimiter(GetTempDir)+'commercial_filaments_'+IntToStr(GetProcessID);
    SlicerDataDirOverride := Dir;
    try
      M := A[FindMaterial(A,'eSUN ABS+')]; M.Name := 'Meu ABS calibrado'; M.Hotend := 248;
      SaveMaterial(M); B := LoadMaterials; I := FindMaterial(B,M.Name);
      Check((I>=0) and (B[I].Kind='ABS') and (B[I].Hotend=248) and (B[I].Brand='eSUN'), 'saved custom commercial profile');
      Check(FindMaterial(FilterMaterials(B,'PLA'),M.Name)<0, 'saved ABS never appears under PLA');
      Check(DeleteMaterial(M.Name), 'saved profile deleted');
    finally RemoveDir(Dir+PathDelim+'materials'); RemoveDir(Dir); end;
    Writeln('PASS: 12 commercial filaments, PLA/ABS filtering, defaults, provenance, ranges, custom and legacy persistence');
  except on E: Exception do begin Writeln('FAIL: ',E.Message); Halt(1); end; end;
end.
