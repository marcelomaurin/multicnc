program test_hsm;
{$mode objfpc}{$H+}
{ MultiCAM moderno: trocoidal, pocket por offset, perfil compensado com
  rampa e tabs, feeds & speeds com afinamento de cavaco e pos-processador
  com arc fitting validado pelo preflight do MultiCNC. }
uses Classes, SysUtils, Math, multicam_types, multicam_job, multicam_profile,
  multicam_hsm, multicam_feeds, multicam_gcode, multisuite_geometry,
  multicnc_gcode_analyzer;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

function Square(X, Y, S: Double): TPolygon2D;
begin
  SetLength(Result, 4);
  Result[0] := Pt(X, Y); Result[1] := Pt(X + S, Y);
  Result[2] := Pt(X + S, Y + S); Result[3] := Pt(X, Y + S);
end;

var
  J: TCamJob;
  Req: TCutRequest;
  Cut: TCutResult;
  I, Rings, Plunges, AtTab, G2: Integer;
  M, P: TPathMove;
  D, MinZ, R: Double;
  Tabs: TTabSettings;
  Prog, Warn: TStringList;
  Opt: TCamPostOptions;
  Rep: TGCodeReport;
  Env: TMachineEnvelope;
  Sq: TPolygon2D;
begin
  { Feeds & speeds }
  Check(Abs(ChipThinningFactor(10, 1) - 1 / 0.6) < 1e-9, 'RCTF ae=0.1D');
  Check(ChipThinningFactor(10, 6) = 1, 'sem afinamento acima de D/2');
  Req := DefaultCutRequest(cmAluminum6061, 6, 2);
  Req.RadialEngagement := 0.6; // 10% - estrategia HSM
  Req.AxialDepth := 12;
  Cut := ComputeFeedsAndSpeeds(Req);
  Check(Abs(Cut.RPM - 250 * 1000 / (Pi * 6)) < 1e-6, 'rpm por Vc');
  Check(Abs(Cut.Feed - Cut.RPM * 2 * 0.048 * (1 / 0.6)) < 1e-6, 'avanco com RCTF');
  Check(Cut.MRR > 0, 'MRR');
  Req.SpindlePowerW := 100;
  Cut := ComputeFeedsAndSpeeds(Req);
  Check(Cut.PowerLimited and (Abs(Cut.PowerW - 100) < 1e-9), 'limite de potencia');
  Req := DefaultCutRequest(cmMDF, 3.175, 2);
  Cut := ComputeFeedsAndSpeeds(Req);
  Check(Abs(Cut.RPM - 24000) < 1e-9, 'rpm limitada ao spindle');

  J := TCamJob.Create;
  Prog := TStringList.Create;
  Warn := TStringList.Create;
  try
    J.Tool := DefaultRouterTool;
    J.Tool.Diameter := 6;
    J.Tool.FluteLength := 20;
    J.Settings := DefaultCamSettings;
    J.Settings.StepDown := 2;
    J.Settings.StepOver := 0.4;
    ApplyToTool(J.Tool, ComputeFeedsAndSpeeds(DefaultCutRequest(cmAluminum6061, 6, 2)));

    { Trocoidal: ferramenta sempre dentro do rasgo de 10 mm }
    THSMCAM.TrochoidalSlot(J, 10, 10, 60, 10, 10, -8, 0.1);
    Check(J.Count > 500, 'trocoidal gera lacos');
    R := (10 - 6) / 2;
    for I := 0 to J.Count - 1 do begin
      M := J.Move(I);
      if M.Rapid then Continue;
      if M.P.X < 10 then D := Hypot(M.P.X - 10, M.P.Y - 10)
      else if M.P.X > 60 then D := Hypot(M.P.X - 60, M.P.Y - 10)
      else D := Abs(M.P.Y - 10);
      Check(D <= R + 1e-6, Format('trocoidal fora do rasgo no movimento %d', [I]));
    end;
    Check(Abs(J.Move(J.Count - 2).P.Z + 8) < 1e-9, 'trocoidal em profundidade total');

    { Pocket por offsets }
    Sq := Square(0, 0, 30);
    Rings := THSMCAM.OffsetPocket(J, Sq, -4, True);
    Check(Rings >= 3, Format('pocket com aneis (%d)', [Rings]));
    MinZ := 0;
    for I := 0 to J.Count - 1 do begin
      M := J.Move(I);
      MinZ := Min(MinZ, M.P.Z);
      if M.Rapid then Continue;
      Check(DistanceToPolygon(Pt(M.P.X, M.P.Y), Sq) >= 3 - 1e-6, 'pocket respeita raio da ferramenta');
      Check(PointInPolygon(Pt(M.P.X, M.P.Y), Sq), 'pocket dentro da regiao');
    end;
    Check(Abs(MinZ + 4) < 1e-9, 'pocket ate o fundo');
    Check(THSMCAM.OffsetPocket(J, Square(0, 0, 5), -1) = 0, 'regiao menor que a fresa');

    { Perfil externo compensado com rampa e tabs }
    Tabs.Count := 4; Tabs.Width := 4; Tabs.Height := 1.5;
    THSMCAM.CompensatedProfile(J, Sq, csOutside, -6, 0.3, True, Tabs, True);
    Plunges := 0; AtTab := 0; MinZ := 0;
    for I := 1 to J.Count - 1 do begin
      M := J.Move(I); P := J.Move(I - 1);
      MinZ := Min(MinZ, M.P.Z);
      if M.Rapid or P.Rapid then Continue;
      if (Hypot(M.P.X - P.P.X, M.P.Y - P.P.Y) < 1e-9) and (M.P.Z < P.P.Z - 1e-9) and (P.P.Z < 0.4) and (M.P.Z < -0.6) then
        if Abs(M.P.Z + 6) > 1e-6 then Inc(Plunges); // so descidas de tab sao verticais
      if Abs(M.P.Z - (-6 + 1.5)) < 1e-9 then Inc(AtTab);
      D := DistanceToPolygon(Pt(M.P.X, M.P.Y), Sq);
      Check((Abs(D - 3.3) < 0.01) or (Abs(D - 3) < 0.01), Format('compensacao de raio (d=%.4f)', [D]));
    end;
    Check(Abs(MinZ + 6) < 1e-9, 'perfil na profundidade final');
    Check(AtTab > 0, 'tabs presentes');
    Check(Plunges = 0, Format('entrada em rampa sem mergulho vertical (%d)', [Plunges]));

    { Pos-processador com arc fitting, validado pelo preflight do MultiCNC }
    Opt := TCamGCode.DefaultPostOptions;
    TCamGCode.BuildProgram(J, Opt, Prog);
    G2 := 0;
    for I := 0 to Prog.Count - 1 do if Copy(Prog[I], 1, 2) = 'G2' then Inc(G2);
    Check(G2 >= 4, Format('cantos arredondados viram G2 (%d)', [G2]));
    Check(Prog.Count < J.Count, Format('programa menor que movimentos (%d < %d)', [Prog.Count, J.Count]));
    Check(Pos('G91.1', Prog.Text) > 0, 'IJ incremental declarado');
    Env := DefaultEnvelope(200, 200, 50);
    Env.MinX := -20; Env.MinY := -20;
    Rep := TGCodeAnalyzer.Analyze(Prog, Env, Warn);
    Check(Rep.Errors = 0, 'preflight do programa CAM: ' + Warn.Text);
    Check(Abs(Rep.MinZ + 6) < 1e-6, 'preflight ve profundidade final');
    Opt.ArcFitting := False;
    TCamGCode.BuildProgram(J, Opt, Warn);
    Check(Warn.Count > Prog.Count, 'arc fitting reduz linhas');
    WriteLn(Format('MultiCAM HSM: OK (pocket %d aneis, perfil %d linhas com arcos vs %d sem)',
      [Rings, Prog.Count, Warn.Count]));
  finally
    Warn.Free;
    Prog.Free;
    J.Free;
  end;
end.
