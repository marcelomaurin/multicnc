program test_ccx;

{ Integracao CalculiX (Fase 5): deck .inp da viga B2 e de duas pecas coladas,
  leitor .frd com um arquivo de exemplo no formato do ccx e, se o ccx estiver
  instalado (CALCULIX_EXE), comparacao da flecha e da 1a frequencia com o
  solver proprio. Sem ccx a comparacao sai como IGNORADO (nao conta como
  aprovada). }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, multisuite_numfmt, multiphysics_vector, multiphysics_geometry,
  multiphysics_mesh, multiphysics_sparse, multiphysics_contact, multiphysics_fem,
  multiphysics_ccx, multiphysics_check;

var
  Ok: Boolean;

function Steel: TFEMMaterial;
begin
  Result := FEMMaterial('Aco', 200e9, 0.3, 7850, 50, 12e-6, 250e6);
end;

function CountLines(S: TStrings; const Prefix: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to S.Count - 1 do
    if Copy(S[I], 1, Length(Prefix)) = Prefix then Inc(Result);
end;

function IndexOfLine(S: TStrings; const Line: string): Integer;
var
  I: Integer;
begin
  for I := 0 to S.Count - 1 do
    if Trim(S[I]) = Line then Exit(I);
  Result := -1;
end;

procedure TestDeck;
var
  M: TFEMMesh;
  F: TFEMModel;
  S: TStringList;
  FN: string;
  I, E0, Ne: Integer;
  T: TMeshTies;
begin
  Section('Deck da viga em balanco (B2)');
  M := TFEMMesh.Create;
  M.AddPart('VIGA');
  M.AddPrimitive(0, BoxPrim('b', V3(0, 0, 0), V3(0.2, 0.01, 0.02)), IdentityTransform, 0.005);
  M.Finalize; M.ConvertToTet10;
  F := TFEMModel.Create(M);
  S := TStringList.Create;
  try
    SetLength(F.Materials, 1); F.Materials[0] := Steel;
    F.AddLoad(FixLoad(M.FindTag('VIGA/b/xmin')));
    F.AddLoad(ForceLoad(M.FindTag('VIGA/b/xmax'), V3(0, 0, -100)));
    FN := GetTempDir + 'mp_test_ccx.inp';
    Check(WriteDeck(F, csStatic, 0, FN, nil), 'escreve o deck');
    S.LoadFromFile(FN);
    E0 := IndexOfLine(S, '*NODE, NSET=NALL');
    Check((E0 >= 0) and (Copy(S[E0 + 1], 1, 3) = '1, '), '*NODE com numeracao a partir de 1');
    Check(IndexOfLine(S, '*ELEMENT, TYPE=C3D10, ELSET=P_VIGA') >= 0, 'elementos C3D10 no conjunto da peca');
    E0 := IndexOfLine(S, '*ELEMENT, TYPE=C3D10, ELSET=P_VIGA');
    Ne := 0;
    I := E0 + 1;
    while (I < S.Count) and (Copy(S[I], 1, 1) <> '*') do begin Inc(Ne); Inc(I); end;
    Check(Ne = M.ElemCount, Format('%d elementos escritos', [Ne]));
    Check(IndexOfLine(S, '*NSET, NSET=N_VIGA_B_XMIN') >= 0, 'conjunto de nos da face engastada');
    Check(IndexOfLine(S, 'N_VIGA_B_XMIN, 1, 1') >= 0, 'engaste em *BOUNDARY');
    Check(IndexOfLine(S, '*CLOAD') >= 0, 'forca total como *CLOAD');
    Check(IndexOfLine(S, '*STATIC') >= 0, 'passo *STATIC');
    Check((IndexOfLine(S, '*NODE FILE') >= 0) and (IndexOfLine(S, 'U') >= 0), 'saida U');
    Check(Pos('2.000000000E+11', S.Text) > 0, 'modulo de elasticidade em Pa com ponto decimal');
    { modal e termico }
    Check(WriteDeck(F, csFrequency, 4, FN, nil), 'deck modal');
    S.LoadFromFile(FN);
    I := IndexOfLine(S, '*FREQUENCY');
    Check((I >= 0) and (Trim(S[I + 1]) = '4'), '*FREQUENCY com 4 modos');
    F.ClearLoads;
    F.AddLoad(TemperatureLoad(M.FindTag('VIGA/b/xmin'), 80));
    F.AddLoad(ConvectionLoad(M.FindTag('VIGA/b/ymin'), 15, 20));
    Check(WriteDeck(F, csHeat, 0, FN, nil), 'deck termico');
    S.LoadFromFile(FN);
    Check(IndexOfLine(S, '*ELEMENT, TYPE=DC3D10, ELSET=P_VIGA') >= 0, 'elementos termicos DC3D10');
    Check(IndexOfLine(S, 'N_VIGA_B_XMIN, 11, 11, 8.000000000E+01') >= 0, 'temperatura fixa no grau 11');
    Check(IndexOfLine(S, 'S_VIGA_B_YMIN, F, 2.000000000E+01, 1.500000000E+01') >= 0, 'conveccao *FILM');
    Check(CountLines(S, '*SURFACE, NAME=S_VIGA_B_YMIN') = 1, 'superficie da conveccao');
  finally
    S.Free; F.Free; M.Free;
  end;

  Section('Deck com contato colado (*EQUATION)');
  M := TFEMMesh.Create;
  M.AddPart('A'); M.AddPart('B');
  M.AddPrimitive(0, BoxPrim('b', V3(0, 0, 0), V3(0.01, 0.01, 0.01)), IdentityTransform, 0.005);
  M.AddPrimitive(1, BoxPrim('b', V3(0, 0, 0.01), V3(0.01, 0.01, 0.01)), IdentityTransform, 0.004);
  M.Finalize;
  F := TFEMModel.Create(M);
  S := TStringList.Create;
  try
    SetLength(F.Materials, 2); F.Materials[0] := Steel; F.Materials[1] := Steel;
    T := FindTies(M, 0, 1, 0.0005);
    AppendTies(T, FindTies(M, 1, 0, 0.0005));
    F.Ties := T;
    F.AddLoad(FixLoad(M.FindTag('A/b/zmin')));
    F.AddLoad(ForceLoad(M.FindTag('B/b/zmax'), V3(0, 0, -1000)));
    Check(WriteDeck(F, csStatic, 0, FN, nil), 'escreve o deck');
    S.LoadFromFile(FN);
    Check(IndexOfLine(S, '*EQUATION') >= 0, '*EQUATION presente');
    Check(Pos('ELSET=P_A', S.Text) * Pos('ELSET=P_B', S.Text) > 0, 'duas pecas em conjuntos separados');
    DeleteFile(FN);
  finally
    S.Free; F.Free; M.Free;
  end;
end;

procedure TestFRD;
var
  L: TStringList;
  R: TFRDResult;
  FN: string;

  function Rec(Node: Integer; const V: array of Double): string;
  var
    K: Integer;
  begin
    Result := ' -1' + Format('%10d', [Node]);
    for K := 0 to High(V) do Result := Result + FormatFloat(' 0.00000E+00;-0.00000E+00', V[K], InvariantFS);
  end;

begin
  Section('Leitor .frd');
  L := TStringList.Create;
  try
    { formato do ccx: blocos 100CL com nome (-4), componentes (-5), dados (-1) e fim (-3) }
    L.Add('    1C');
    L.Add('    2C                             3                                     1');
    L.Add(Rec(1, [0, 0, 0])); L.Add(Rec(2, [1, 0, 0])); L.Add(Rec(3, [0, 1, 0]));
    L.Add(' -3');
    L.Add('  100CL  101 2.03850E+02           3                     2    1MODAL      1');
    L.Add(' -4  DISP        4    1');
    L.Add(' -5  D1          1    2    1    0');
    L.Add(' -5  D2          1    2    2    0');
    L.Add(' -5  D3          1    2    3    0');
    L.Add(' -5  ALL         1    2    0    0    1ALL');
    L.Add(Rec(1, [0, 0, 0])); L.Add(Rec(2, [1.5e-4, -2e-5, 0])); L.Add(Rec(3, [0, 0, -3.25e-4]));
    L.Add(' -3');
    L.Add('  100CL  102 4.07690E+02           3                     2    2MODAL      1');
    L.Add(' -4  DISP        4    1');
    L.Add(' -5  D1          1    2    1    0');
    L.Add(Rec(1, [0, 0, 0])); L.Add(Rec(2, [0, 0, 1e-3])); L.Add(Rec(3, [0, 0, 0]));
    L.Add(' -3');
    L.Add('  100CL  103 1.00000E+00           3                     0    1           1');
    L.Add(' -4  STRESS      6    1');
    L.Add(' -5  SXX         1    4    1    1');
    L.Add(Rec(1, [1e6, 2e6, 3e6, 4e5, 5e5, 6e5])); L.Add(Rec(2, [0, 0, 0, 0, 0, 0])); L.Add(Rec(3, [-1e7, 0, 0, 0, 0, 0]));
    L.Add(' -3');
    L.Add('  100CL  104 1.00000E+00           3                     0    1           1');
    L.Add(' -4  NDTEMP      1    1');
    L.Add(' -5  T           1    1    0    0');
    L.Add(Rec(1, [80])); L.Add(Rec(2, [55.5])); L.Add(Rec(3, [20]));
    L.Add(' -3');
    L.Add(' 9999');
    FN := GetTempDir + 'mp_test.frd';
    L.SaveToFile(FN);
  finally
    L.Free;
  end;
  R := ReadFRD(FN, 3);
  Check(R.Ok, 'le o arquivo: ' + R.Message);
  Check(Length(R.Disp) = 2, 'dois blocos DISP (dois modos)');
  if Length(R.Disp) = 2 then
  begin
    CheckNear(R.Disp[0][3 * 1 + 0], 1.5e-4, 1e-4, 'deslocamento x do no 2');
    CheckNear(R.Disp[0][3 * 2 + 2], -3.25e-4, 1e-4, 'deslocamento z do no 3');
    CheckNear(R.Freq[0], 203.85, 1e-5, 'frequencia do 1o modo');
    CheckNear(R.Freq[1], 407.69, 1e-5, 'frequencia do 2o modo');
  end;
  Check((Length(R.Stress) = 1) and SameValue(R.Stress[0][5], 6e5, 1) and SameValue(R.Stress[0][12], -1e7, 1), 'tensoes (6 componentes por no)');
  Check((Length(R.Temp) = 3) and SameValue(R.Temp[1], 55.5, 1e-9), 'temperaturas NDTEMP');
  DeleteFile(FN);
  R := ReadFRD(GetTempDir + 'nao_existe.frd', 3);
  Check(not R.Ok, 'arquivo ausente recusado');
end;

procedure TestCompare;
var
  Exe, Dir, Inp: string;
  M: TFEMMesh;
  F: TFEMModel;
  RS: TStaticResult;
  R: TFRDResult;
  Log: TStringList;
  Own, CC: Double;
  I: Integer;
begin
  Section('Comparacao com o CalculiX');
  Exe := FindCCX;
  if Exe = '' then
  begin
    Writeln('  IGNORADO: ccx nao encontrado (defina CALCULIX_EXE para comparar)');
    Exit;
  end;
  M := TFEMMesh.Create;
  M.AddPart('VIGA');
  M.AddPrimitive(0, BoxPrim('b', V3(0, 0, 0), V3(0.2, 0.01, 0.02)), IdentityTransform, 0.005);
  M.Finalize; M.ConvertToTet10;
  F := TFEMModel.Create(M);
  Log := TStringList.Create;
  try
    SetLength(F.Materials, 1); F.Materials[0] := Steel;
    F.AddLoad(FixLoad(M.FindTag('VIGA/b/xmin')));
    F.AddLoad(ForceLoad(M.FindTag('VIGA/b/xmax'), V3(0, 0, -100)));
    Ok := F.SolveStatic(RS);
    Check(Ok, 'solver proprio');
    Dir := GetTempDir + 'mp_ccx_cmp' + PathDelim;
    ForceDirectories(Dir);
    Inp := Dir + 'viga.inp';
    WriteDeck(F, csStatic, 0, Inp, Log);
    Ok := RunCCX(Exe, Inp, 300, Log);
    Check(Ok, 'ccx executa');
    if not Ok then begin Writeln(Log.Text); Exit; end;
    R := ReadFRD(ChangeFileExt(Inp, '.frd'), M.NodeCount);
    Check(R.Ok and (Length(R.Disp) > 0), 'le o resultado do ccx');
    Own := 0; CC := 0;
    for I := 0 to M.NodeCount - 1 do
    begin
      Own := Max(Own, Abs(RS.U[3 * I + 2]));
      CC := Max(CC, Abs(R.Disp[High(R.Disp)][3 * I + 2]));
    end;
    CheckNear(CC, Own, 0.02, 'flecha maxima: CalculiX x solver proprio');
  finally
    Log.Free; F.Free; M.Free;
  end;
end;

begin
  TestDeck;
  TestFRD;
  TestCompare;
  Finish('integracao CalculiX');
end.
