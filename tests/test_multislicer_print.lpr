program test_multislicer_print;
{ Contract test using an immediate-ack transport stub. It does not simulate
  motion, thermal waits, mesh or arcs. See test_multicnc_tcp for actual simulation. }
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multicnc_types, multicnc_simulator, multicnc_session,
  multisuite_gcode_writer, multislicer_types, multislicer_mesh, multislicer_pipeline,
  multislicer_printers, multislicer_machines;
var
  S: TSimulationSession; T: TSimulatorTransport; G: TStringList; M: TMesh;
  Slicer: TModernSlicer; St: TSliceSettings; R: TSliceReport; P: TPrinterDef;
  H: TSuiteGCodeHeader; HB: TSuiteBounds; FN, Reason: string; I, K: Integer; T0: QWord;
procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then raise Exception.Create(Msg);
end;
begin
  try
    FN := GetTempFileName(GetTempDir, 'msl') + '.gcode';
    G := TStringList.Create; M := TMesh.Create; Slicer := TModernSlicer.Create;
    S := TSimulationSession.Create;
    try
      { peca de 20 x 20 x 3 mm no centro da mesa da Ender-3 S1 }
      AddBox(M, 100, 100, 0, 120, 120, 3);
      K := FindMachine('Creality', 'Ender-3 S1');
      Check(K >= 0, 'Ender-3 S1 no catalogo');
      P := MachinePrinterDef(MachineCatalog[K], 'Ender-3 S1 da oficina', 0, 0, 0);
      St := DefaultSliceSettings;
      St.Printer.Name := P.Name;
      St.Printer.BedX := P.BedX; St.Printer.BedY := P.BedY; St.Printer.MaxZ := P.BedZ;
      St.StartGCode := P.StartGCode; St.EndGCode := P.EndGCode;
      St.MaterialName := 'PLA';
      R := Slicer.Slice(M, St, G);
      Check(R.Layers = 15, 'camadas');
      G.SaveToFile(FN);
      if ParamCount > 0 then G.SaveToFile(ParamStr(1));
      Check(SuiteParseHeader(G, H, HB) and SameText(H.Machine, 'printer3d') and HB.Valid, 'contrato printer3d');
      Check(Pos('M420 S1', G.Text) > 0, 'G-code inicial da S1 com a malha de nivelamento');
      Check((Pos('G2 ', G.Text) > 0) or (Pos('G3 ', G.Text) > 0) or (Pos('M486', G.Text) > 0), 'arcos ou rotulos no G-code');

      S.LoadFile(FN);
      Check(S.Count > 100, 'programa carregado');
      T := TSimulatorTransport.Create;
      Check(S.ConnectTransport(mtPrinter3D, pkMarlin, T, T), 'conecta simulador Marlin');
      S.SetWorkEnvelope(P.BedX, P.BedY, P.BedZ);
      T0 := GetTickCount64;
      while not S.ControllerReady and (GetTickCount64 - T0 < 5000) do begin S.Tick; Sleep(5); end;
      Check(S.ValidateProgram(Reason), 'programa aceito no modo impressora: ' + Reason);
      Check(S.Start, 'inicia: ' + S.LastError);
      T0 := GetTickCount64;
      while (S.State in [ssRunning, ssPaused]) and (GetTickCount64 - T0 < 60000) do
      begin
        S.Tick;
        Sleep(1);
      end;
      Check(S.State = ssDone, Format('termina (estado %d, %d de %d linhas, erro "%s")',
        [Ord(S.State), S.Completed, S.Count, S.LastError]));
      Check(S.Completed = S.Count, 'todas as linhas confirmadas');
      Writeln(Format('MultiSlicer -> MultiCNC: OK (%d linhas confirmadas pelo transporte falso Marlin em %d ms)',
        [S.Count, GetTickCount64 - T0]));
    finally
      S.Free; Slicer.Free; M.Free; G.Free;
      DeleteFile(FN);
    end;
  except
    on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end;
  end;
end.
