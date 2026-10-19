unit multiphysics_ccx;

{ Integracao com o CalculiX (ccx), solver FEM externo e gratuito.

  - WriteDeck: deck .inp completo a partir do modelo do FEM proprio
    (mesma malha, cargas e amarracoes): *NODE, *ELEMENT C3D4/C3D10, conjuntos
    por peca e por face, *MATERIAL, *SOLID SECTION, *EQUATION (contatos
    colados), *BOUNDARY, *CLOAD, *DLOAD (pressao, gravidade), *DFLUX, *FILM,
    passo *STATIC / *HEAT TRANSFER / *FREQUENCY e saidas U, S, NT;
  - RunCCX: executa o ccx na pasta do deck, com tempo limite;
  - ReadFRD: le o .frd ASCII (DISP, STRESS, NDTEMP e frequencias).

  Unidades SI. Numeracao do ccx = indice do no + 1. O ccx nao vem no setup
  (GPL, tamanho): o caminho vem de CALCULIX_EXE ou da configuracao. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process, multisuite_numfmt, multiphysics_vector,
  multiphysics_mesh, multiphysics_sparse, multiphysics_contact, multiphysics_fem;

type
  TCCXStep = (csStatic, csHeat, csFrequency);

  TFRDResult = record
    Ok: Boolean;
    Message: string;
    Disp: array of TDoubleArray;     { um bloco DISP por passo/modo: 3 por no }
    Stress: array of TDoubleArray;   { 6 por no: SXX SYY SZZ SXY SYZ SZX }
    Temp: TDoubleArray;              { NDTEMP do ultimo bloco }
    Freq: TDoubleArray;              { Hz, um por bloco DISP no modal }
  end;

{ escreve o deck; Modes so no modal }
function WriteDeck(F: TFEMModel; Step: TCCXStep; Modes: Integer; const FN: string; Log: TStrings): Boolean;
function ReadFRD(const FN: string; NodeCount: Integer): TFRDResult;
function FindCCX: string;
{ executa ccx -i job na pasta do arquivo .inp; espera ate TimeoutSec }
function RunCCX(const Exe, InpFile: string; TimeoutSec: Integer; Log: TStrings): Boolean;
function SanitizeName(const S: string): string;

implementation

function SanitizeName(const S: string): string;
var
  I: Integer;
begin
  Result := UpperCase(S);
  for I := 1 to Length(Result) do
    if not (Result[I] in ['A'..'Z', '0'..'9', '_']) then Result[I] := '_';
  if Result = '' then Result := 'X';
  if Length(Result) > 70 then Result := Copy(Result, 1, 70);
end;

function FN9(V: Double): string;
begin
  Result := FormatFloat('0.000000000E+00', V, InvariantFS);
end;

function FindCCX: string;
var
  Candidates: array[0..5] of string;
  I: Integer;
begin
  Result := GetEnvironmentVariable('CALCULIX_EXE');
  if (Result <> '') and FileExists(Result) then Exit;
  Candidates[0] := ExtractFilePath(ParamStr(0)) + 'ccx.exe';
  Candidates[1] := 'C:\Program Files\CalculiX\ccx.exe';
  Candidates[2] := 'C:\CalculiX\ccx.exe';
  Candidates[3] := 'C:\Program Files\bConverged\CalculiX\ccx\ccx.exe';
  Candidates[4] := '/usr/bin/ccx';
  Candidates[5] := '/usr/local/bin/ccx';
  for I := 0 to High(Candidates) do
    if FileExists(Candidates[I]) then Exit(Candidates[I]);
  Result := ExeSearch('ccx' + {$IFDEF WINDOWS}'.exe'{$ELSE}''{$ENDIF}, GetEnvironmentVariable('PATH'));
end;

{ face local do C3D4/C3D10 (S1: 1-2-3, S2: 1-4-2, S3: 2-4-3, S4: 3-4-1) }
function ElementFaceIndex(M: TFEMMesh; Fc: Integer): Integer;
const
  FN: array[1..4, 0..2] of Integer = ((0, 1, 2), (0, 3, 1), (1, 3, 2), (2, 3, 0));
var
  E, K, J, Hit: Integer;
begin
  E := M.Faces[Fc].Elem;
  for K := 1 to 4 do
  begin
    Hit := 0;
    for J := 0 to 2 do
      if (M.Elems[E].N[FN[K, J]] = M.Faces[Fc].N[0]) or (M.Elems[E].N[FN[K, J]] = M.Faces[Fc].N[1]) or
         (M.Elems[E].N[FN[K, J]] = M.Faces[Fc].N[2]) then Inc(Hit);
    if Hit = 3 then Exit(K);
  end;
  Result := 1;
end;

function WriteDeck(F: TFEMModel; Step: TCCXStep; Modes: Integer; const FN: string; Log: TStrings): Boolean;
var
  S: TStringList;
  M: TFEMMesh;
  I, J, K, P, N, Fc, Cnt, NPE: Integer;
  Line, ElType: string;
  Ids: TIntArray;
  Fixed: array of Boolean;
  Dependent: array of Boolean;
  CL: TDoubleArray;
  L: TFEMLoad;
  Thermal: Boolean;
  NEq, Terms: Integer;
  Mat: TFEMMaterial;
  TagUsed: array of Boolean;

  procedure AddIdList(const Arr: TIntArray);
  var
    Q: Integer;
    Ln: string;
  begin
    Ln := '';
    for Q := 0 to High(Arr) do
    begin
      if Ln <> '' then Ln := Ln + ', ';
      Ln := Ln + IntToStr(Arr[Q] + 1);
      if (Q mod 16 = 15) or (Q = High(Arr)) then
      begin
        S.Add(Ln);
        Ln := '';
      end;
    end;
  end;

  function TagSurfName(Tag: Integer): string;
  begin
    Result := 'S_' + SanitizeName(M.FaceNames[Tag]);
  end;

  function TagSetName(Tag: Integer): string;
  begin
    Result := 'N_' + SanitizeName(M.FaceNames[Tag]);
  end;

begin
  Result := False;
  M := F.Mesh;
  NPE := M.NodesPerElement;
  if NPE = 10 then ElType := 'C3D10' else ElType := 'C3D4';
  Thermal := Step = csHeat;
  S := TStringList.Create;
  try
    S.Add('** MultiPhysics -> CalculiX (unidades SI: m, N, Pa, kg, s, W, C)');
    S.Add('*HEADING');
    S.Add('MultiPhysics');
    S.Add('*NODE, NSET=NALL');
    for I := 0 to M.NodeCount - 1 do
      S.Add(Format('%d, %s, %s, %s', [I + 1, FN9(M.Nodes[I].X), FN9(M.Nodes[I].Y), FN9(M.Nodes[I].Z)]));
    { elementos por peca }
    for P := 0 to M.PartNames.Count - 1 do
    begin
      Cnt := 0;
      for I := 0 to M.ElemCount - 1 do if M.Elems[I].Part = P then Inc(Cnt);
      if Cnt = 0 then Continue;
      if Thermal then S.Add('*ELEMENT, TYPE=D' + ElType + ', ELSET=P_' + SanitizeName(M.PartNames[P]))
      else S.Add('*ELEMENT, TYPE=' + ElType + ', ELSET=P_' + SanitizeName(M.PartNames[P]));
      for I := 0 to M.ElemCount - 1 do
        if M.Elems[I].Part = P then
        begin
          Line := IntToStr(I + 1);
          for K := 0 to NPE - 1 do Line := Line + ', ' + IntToStr(M.Elems[I].N[K] + 1);
          S.Add(Line);
        end;
    end;
    S.Add('*ELSET, ELSET=EALL');
    for P := 0 to M.PartNames.Count - 1 do
    begin
      Cnt := 0;
      for I := 0 to M.ElemCount - 1 do if M.Elems[I].Part = P then Inc(Cnt);
      if Cnt > 0 then S.Add('P_' + SanitizeName(M.PartNames[P]));
    end;
    { conjuntos das faces usadas pelas cargas }
    SetLength(TagUsed, M.FaceNames.Count);
    for J := 0 to High(F.Loads) do
      if (F.Loads[J].Tag >= 0) and (F.Loads[J].Tag < Length(TagUsed)) then TagUsed[F.Loads[J].Tag] := True;
    for I := 0 to M.FaceNames.Count - 1 do
    begin
      if not TagUsed[I] then Continue;
      Ids := M.NodesOfTag(I);
      if Length(Ids) = 0 then Continue;
      S.Add('*NSET, NSET=' + TagSetName(I));
      AddIdList(Ids);
      S.Add('*SURFACE, NAME=' + TagSurfName(I) + ', TYPE=ELEMENT');
      for Fc := 0 to M.FaceCount - 1 do
        if M.Faces[Fc].Tag = I then
          S.Add(Format('%d, S%d', [M.Faces[Fc].Elem + 1, ElementFaceIndex(M, Fc)]));
    end;
    { materiais }
    for P := 0 to M.PartNames.Count - 1 do
    begin
      if P <= High(F.Materials) then Mat := F.Materials[P]
      else if Length(F.Materials) > 0 then Mat := F.Materials[0]
      else Mat := FEMMaterial('Aco', 200e9, 0.3, 7850, 50, 12e-6, 250e6);
      S.Add('*MATERIAL, NAME=M_' + SanitizeName(M.PartNames[P]));
      S.Add('*ELASTIC');
      S.Add(FN9(Mat.E) + ', ' + FN9(Mat.Nu));
      S.Add('*DENSITY');
      S.Add(FN9(Mat.Rho));
      S.Add('*CONDUCTIVITY');
      S.Add(FN9(Mat.K));
      S.Add('*EXPANSION');
      S.Add(FN9(Mat.Alpha));
      S.Add('*SPECIFIC HEAT');
      S.Add(FN9(500));
      S.Add('*SOLID SECTION, ELSET=P_' + SanitizeName(M.PartNames[P]) + ', MATERIAL=M_' + SanitizeName(M.PartNames[P]));
    end;
    { contatos colados: *EQUATION, cada grau dependente uma vez so e nunca fixo }
    SetLength(Fixed, M.NodeCount);
    for J := 0 to High(F.Loads) do
      if (F.Loads[J].Kind in [flFix, flDisplacement, flTemperature]) and (F.Loads[J].Tag >= 0) then
      begin
        Ids := M.NodesOfTag(F.Loads[J].Tag);
        for I := 0 to High(Ids) do Fixed[Ids[I]] := True;
      end;
    SetLength(Dependent, M.NodeCount);
    NEq := 0;
    if Length(F.Ties) > 0 then
    begin
      S.Add('** contatos colados (amarracoes do MultiPhysics)');
      S.Add('*EQUATION');
      for I := 0 to High(F.Ties) do
      begin
        if Dependent[F.Ties[I].Slave] or Fixed[F.Ties[I].Slave] then Continue;
        { o no escravo nao pode aparecer entre os mestres da propria equacao }
        Terms := 1;
        for J := 0 to F.Ties[I].NM - 1 do
          if Abs(F.Ties[I].W[J]) > 1e-12 then Inc(Terms);
        Dependent[F.Ties[I].Slave] := True;
        for K := 1 to IfThen(Thermal, 1, 3) do
        begin
          S.Add(IntToStr(Terms));
          Line := Format('%d, %d, 1.0', [F.Ties[I].Slave + 1, IfThen(Thermal, 11, K)]);
          N := 1;
          for J := 0 to F.Ties[I].NM - 1 do
          begin
            if Abs(F.Ties[I].W[J]) <= 1e-12 then Continue;
            if N mod 4 = 0 then
            begin
              S.Add(Line);
              Line := '';
            end
            else
              Line := Line + ', ';
            Line := Line + Format('%d, %d, %s', [F.Ties[I].Masters[J] + 1, IfThen(Thermal, 11, K), FN9(-F.Ties[I].W[J])]);
            Inc(N);
          end;
          S.Add(Line);
          Inc(NEq);
        end;
      end;
    end;
    S.Add('*INITIAL CONDITIONS, TYPE=TEMPERATURE');
    S.Add('NALL, ' + FN9(F.RefTemperature));
    { condicoes fixas fora do passo (valem para todo o modelo) }
    for J := 0 to High(F.Loads) do
    begin
      L := F.Loads[J];
      if (L.Tag < 0) or not (L.Kind in [flFix, flDisplacement]) or Thermal then Continue;
      S.Add('*BOUNDARY');
      for K := 0 to 2 do
        if L.Mask[K] then
        begin
          if L.Kind = flFix then S.Add(Format('%s, %d, %d', [TagSetName(L.Tag), K + 1, K + 1]))
          else S.Add(Format('%s, %d, %d, %s', [TagSetName(L.Tag), K + 1, K + 1,
            FN9(IfThen(K = 0, L.Vec.X, IfThen(K = 1, L.Vec.Y, L.Vec.Z)))]));
        end;
    end;
    { passo }
    case Step of
      csStatic: begin S.Add('*STEP'); S.Add('*STATIC'); end;
      csHeat: begin S.Add('*STEP'); S.Add('*HEAT TRANSFER, STEADY STATE'); end;
      csFrequency: begin S.Add('*STEP'); S.Add('*FREQUENCY'); S.Add(IntToStr(Max(1, Modes))); end;
    end;
    if Step = csStatic then
    begin
      CL := F.ForceLoadVector;
      Cnt := 0;
      for I := 0 to High(CL) do if CL[I] <> 0 then Inc(Cnt);
      if Cnt > 0 then
      begin
        S.Add('*CLOAD');
        for I := 0 to M.NodeCount - 1 do
          for K := 0 to 2 do
            if CL[3 * I + K] <> 0 then S.Add(Format('%d, %d, %s', [I + 1, K + 1, FN9(CL[3 * I + K])]));
      end;
      for J := 0 to High(F.Loads) do
        if (F.Loads[J].Kind = flPressure) and (F.Loads[J].Tag >= 0) then
        begin
          S.Add('*DLOAD');
          S.Add(TagSurfName(F.Loads[J].Tag) + ', P, ' + FN9(F.Loads[J].Value));
        end;
      if VLength(F.Gravity) > 0 then
      begin
        S.Add('*DLOAD');
        S.Add('EALL, GRAV, ' + FN9(VLength(F.Gravity)) + ', ' + FN9(F.Gravity.X / VLength(F.Gravity)) + ', ' +
          FN9(F.Gravity.Y / VLength(F.Gravity)) + ', ' + FN9(F.Gravity.Z / VLength(F.Gravity)));
      end;
      if Length(F.Temperature) = M.NodeCount then
      begin
        S.Add('*TEMPERATURE');
        for I := 0 to M.NodeCount - 1 do S.Add(Format('%d, %s', [I + 1, FN9(F.Temperature[I])]));
      end;
    end;
    if Thermal then
      for J := 0 to High(F.Loads) do
      begin
        L := F.Loads[J];
        case L.Kind of
          flTemperature:
            begin
              S.Add('*BOUNDARY');
              S.Add(TagSetName(L.Tag) + ', 11, 11, ' + FN9(L.Value));
            end;
          flHeatFlux:
            begin
              S.Add('*DFLUX');
              S.Add(TagSurfName(L.Tag) + ', S, ' + FN9(L.Value));
            end;
          flConvection:
            begin
              S.Add('*FILM');
              S.Add(TagSurfName(L.Tag) + ', F, ' + FN9(L.Value2) + ', ' + FN9(L.Value));
            end;
          flHeatPower:
            if (L.Part >= 0) and (M.PartVolume(L.Part) > 0) then
            begin
              S.Add('*DFLUX');
              S.Add('P_' + SanitizeName(M.PartNames[L.Part]) + ', BF, ' + FN9(L.Value / M.PartVolume(L.Part)));
            end;
        end;
      end;
    case Step of
      csHeat:
        begin
          S.Add('*NODE FILE');
          S.Add('NT');
        end;
      else
      begin
        S.Add('*NODE FILE');
        S.Add('U');
        if Step = csStatic then
        begin
          S.Add('*EL FILE');
          S.Add('S');
        end;
      end;
    end;
    S.Add('*END STEP');
    S.SaveToFile(FN);
    if Log <> nil then
      Log.Add(Format('Deck CalculiX: %s (%d nos, %d elementos %s, %d equacoes de contato)',
        [FN, M.NodeCount, M.ElemCount, ElType, NEq]));
    Result := True;
  finally
    S.Free;
  end;
end;

function RunCCX(const Exe, InpFile: string; TimeoutSec: Integer; Log: TStrings): Boolean;
var
  Pr: TProcess;
  T0: QWord;
  Buf: array[0..4095] of Char;
  N: Integer;
  OutS: string;
begin
  Result := False;
  if (Exe = '') or not FileExists(Exe) then
  begin
    if Log <> nil then Log.Add('CalculiX (ccx) nao encontrado. Defina CALCULIX_EXE ou o caminho na etapa Resolver.');
    Exit;
  end;
  Pr := TProcess.Create(nil);
  try
    Pr.Executable := Exe;
    Pr.Parameters.Add('-i');
    Pr.Parameters.Add(ChangeFileExt(ExtractFileName(InpFile), ''));
    Pr.CurrentDirectory := ExtractFilePath(InpFile);
    Pr.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    Pr.Execute;
    T0 := GetTickCount64;
    OutS := '';
    while Pr.Running do
    begin
      while Pr.Output.NumBytesAvailable > 0 do
      begin
        N := Pr.Output.Read(Buf, SizeOf(Buf));
        if N > 0 then OutS := OutS + Copy(string(Buf), 1, N);
      end;
      if GetTickCount64 - T0 > QWord(TimeoutSec) * 1000 then
      begin
        Pr.Terminate(1);
        if Log <> nil then Log.Add('CalculiX passou do tempo limite e foi interrompido.');
        Exit;
      end;
      Sleep(20);
    end;
    while Pr.Output.NumBytesAvailable > 0 do
    begin
      N := Pr.Output.Read(Buf, SizeOf(Buf));
      if N > 0 then OutS := OutS + Copy(string(Buf), 1, N);
    end;
    if Log <> nil then
    begin
      if Length(OutS) > 3000 then OutS := '...' + Copy(OutS, Length(OutS) - 3000, 3000);
      Log.Add(OutS);
    end;
    Result := (Pr.ExitStatus = 0) and FileExists(ChangeFileExt(InpFile, '.frd'));
    if not Result and (Log <> nil) then Log.Add(Format('CalculiX terminou com codigo %d.', [Pr.ExitStatus]));
  finally
    Pr.Free;
  end;
end;

function ReadFRD(const FN: string; NodeCount: Integer): TFRDResult;
var
  L: TStringList;
  I, K, Node, NComp, Kind, NB: Integer;
  Line, Name: string;
  Block: TDoubleArray;
  BlockValue: Double;

  function FixedFloat(const S: string; Col: Integer): Double;
  var
    T: string;
  begin
    T := Trim(Copy(S, Col, 12));
    if not TryStrToFloat(T, Result, InvariantFS) then Result := 0;
  end;

begin
  Result.Ok := False;
  Result.Message := '';
  Result.Disp := nil; Result.Stress := nil; Result.Temp := nil; Result.Freq := nil;
  if not FileExists(FN) then
  begin
    Result.Message := 'Arquivo .frd nao encontrado: ' + FN;
    Exit;
  end;
  L := TStringList.Create;
  try
    L.LoadFromFile(FN);
    I := 0;
    BlockValue := 0;
    while I < L.Count do
    begin
      Line := L[I];
      if Copy(Line, 1, 7) = '  100CL' then
      begin
        { valor do bloco: tempo do passo ou frequencia do modo }
        BlockValue := FixedFloat(Line, 13);
        Inc(I);
        if I >= L.Count then Break;
        Line := L[I];
        Name := Trim(Copy(Line, 5, 8));
        if Name = 'DISP' then begin Kind := 1; NComp := 3; end
        else if Name = 'STRESS' then begin Kind := 2; NComp := 6; end
        else if Name = 'NDTEMP' then begin Kind := 3; NComp := 1; end
        else begin Kind := 0; NComp := 0; end;
        SetLength(Block, Max(1, NComp) * NodeCount);
        { pula as linhas -4/-5 e le os -1 ate o -3 }
        Inc(I);
        while (I < L.Count) and (Copy(L[I], 1, 3) <> ' -3') do
        begin
          Line := L[I];
          if (Copy(Line, 1, 3) = ' -1') and (Kind > 0) then
          begin
            Node := StrToIntDef(Trim(Copy(Line, 4, 10)), 0) - 1;
            if (Node >= 0) and (Node < NodeCount) then
              for K := 0 to NComp - 1 do Block[NComp * Node + K] := FixedFloat(Line, 14 + 12 * K);
          end;
          Inc(I);
        end;
        case Kind of
          1:
            begin
              NB := Length(Result.Disp);
              SetLength(Result.Disp, NB + 1);
              Result.Disp[NB] := Copy(Block);
              SetLength(Result.Freq, NB + 1);
              Result.Freq[NB] := BlockValue;
            end;
          2:
            begin
              NB := Length(Result.Stress);
              SetLength(Result.Stress, NB + 1);
              Result.Stress[NB] := Copy(Block);
            end;
          3: Result.Temp := Copy(Block);
        end;
      end;
      Inc(I);
    end;
    Result.Ok := (Length(Result.Disp) > 0) or (Length(Result.Temp) > 0);
    if not Result.Ok then Result.Message := 'Nenhum resultado (DISP/NDTEMP) no .frd';
  finally
    L.Free;
  end;
end;

end.
