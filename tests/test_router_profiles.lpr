program test_router_profiles;

{ Confere a tabela de perfis de CNC Router: curso positivo, baud GRBL,
  marca/modelo unicos e presenca das maquinas genericas. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, multicnc_router_profiles;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then
  begin
    Inc(Failures);
    Writeln('FAIL: ', Msg);
  end;
end;

var
  Brands, Models, Seen: TStringList;
  I, J, Total: Integer;
  P: TRouterProfile;
  Key: string;
begin
  Brands := TStringList.Create;
  Models := TStringList.Create;
  Seen := TStringList.Create;
  try
    GetRouterBrands(Brands);
    Check(Brands.Count > 1, 'mais de uma marca cadastrada');
    Total := 0;
    for I := 0 to Brands.Count - 1 do
    begin
      GetRouterModels(Brands[I], Models);
      Check(Models.Count > 0, 'marca sem modelos: ' + Brands[I]);
      for J := 0 to Models.Count - 1 do
      begin
        Inc(Total);
        Key := LowerCase(Brands[I] + '|' + Models[J]);
        Check(Seen.IndexOf(Key) < 0, 'marca/modelo repetido: ' + Key);
        Seen.Add(Key);
        Check(FindRouterProfile(Brands[I], Models[J], P), 'perfil nao encontrado: ' + Key);
        Check((P.WorkX > 0) and (P.WorkY > 0) and (P.WorkZ > 0), 'curso invalido: ' + Key);
        Check(P.BaudRate = 115200, 'baud GRBL esperado em ' + Key);
        Check((P.SpindlePowerW >= 0) and (P.SpindleMaxRPM >= 0), 'spindle negativo: ' + Key);
        Check(Trim(P.Firmware) <> '', 'firmware vazio: ' + Key);
      end;
    end;
    Check(Total = ROUTER_PROFILE_COUNT, Format('total de perfis %d <> %d', [Total, ROUTER_PROFILE_COUNT]));

    Check(FindRouterProfile('Generic', 'Generic GRBL Router', P), 'router generico presente');
    Check(FindRouterProfile('Generic', 'Mini Fresadora CNC 3018 Router 3 Eixos', P) and
      (P.WorkX = 300) and (P.WorkY = 180) and (P.WorkZ = 45), 'mini fresadora 3018 com 300x180x45');
    Check(FindRouterProfile('TwoTrees', 'TTC3018', P) and
      (P.WorkX = 300) and (P.WorkY = 180) and (P.WorkZ = 40) and
      (P.BaudRate = 115200) and (P.Firmware = 'GRBL') and P.DisablePhysicalHoming, 'TwoTrees TTC3018 com perfil proprio');
    Check(not FindRouterProfile('Generic', 'Inexistente', P) and (P.WorkX = 0), 'perfil inexistente zerado');
    Check(Pos('not informed', SpindleText(P)) > 0, 'spindle nao informado descrito');
  finally
    Brands.Free; Models.Free; Seen.Free;
  end;
  if Failures > 0 then begin Writeln(Failures, ' falha(s)'); Halt(1); end;
  Writeln('PASS: perfis de CNC Router (', ROUTER_PROFILE_COUNT, ' modelos)');
end.
