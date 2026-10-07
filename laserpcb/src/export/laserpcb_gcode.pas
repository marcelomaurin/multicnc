unit laserpcb_gcode;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, multisuite_numfmt, laserpcb_job, laserpcb_types;
type TLaserGCodeExporter = class
  public
    class procedure ValidateJob(J: TLaserPCBJob);
    class procedure ExportJob(J: TLaserPCBJob; const FN: string);
end;
implementation
class procedure TLaserGCodeExporter.ValidateJob(J: TLaserPCBJob);
var I, Cuts: Integer; P: TPathPoint; Power, Feed: Double;
begin
  if J = nil then raise Exception.Create('Trabalho inexistente');
  if J.Count = 0 then raise Exception.Create('O trabalho nao possui trajetorias');
  if (J.Profile.Passes < 1) or (J.Profile.Passes > 1000) then
    raise Exception.Create('Informe 1 a 1000 passadas');
  if IsNan(J.Profile.SMax) or IsInfinite(J.Profile.SMax) or (J.Profile.SMax < 1) then
    raise Exception.Create('S-max deve ser positivo e finito');
  Cuts := 0;
  for I := 0 to J.Count - 1 do
  begin
    P := J.Point(I);
    if IsNan(P.X) or IsInfinite(P.X) or IsNan(P.Y) or IsInfinite(P.Y) then
      raise Exception.Create('Coordenada invalida no ponto ' + IntToStr(I));
    if not P.LaserOn then Continue;
    if I = 0 then raise Exception.Create('A trajetoria deve iniciar com laser desligado');
    Inc(Cuts);
    Power := P.Power; if Power = 0 then Power := J.Profile.Power;
    Feed := P.Feed; if Feed = 0 then Feed := J.Profile.Feed;
    if IsNan(Power) or IsInfinite(Power) or (Power <= 0) or (Power > 1e9) then
      raise Exception.Create('Potencia invalida no ponto ' + IntToStr(I));
    if Round(Power) < 1 then raise Exception.Create('A potencia seria arredondada para S0');
    if (J.Profile.SMax > 0) and (Power > J.Profile.SMax) then
      raise Exception.Create('Potencia maior que o S-max configurado');
    if IsNan(Feed) or IsInfinite(Feed) or (Feed < 0.001) then
      raise Exception.Create('Velocidade invalida no ponto ' + IntToStr(I));
  end;
  if Cuts = 0 then raise Exception.Create('O trabalho nao possui movimentos de processamento');
end;

class procedure TLaserGCodeExporter.ExportJob(J: TLaserPCBJob; const FN: string);
var S: TStringList; I, K: Integer; P: TPathPoint; Power, Feed: Double;
  LaserActive: Boolean; LastPower: Int64;
begin
  ValidateJob(J);
  S := TStringList.Create;
  try
    S.Add('; LaserPCB -> MultiCNC');
    S.Add('; GRBL laser: conferir $32=1 e $30 (S-max) no MultiCNC');
    S.Add('G21'); S.Add('G90'); S.Add('G94'); S.Add('M5');
    for K := 1 to J.Profile.Passes do
    begin
      S.Add(Format('; PASS %d/%d', [K, J.Profile.Passes]));
      LaserActive := False; LastPower := -1;
      for I := 0 to J.Count - 1 do
      begin
        P := J.Point(I);
        if P.LaserOn then
        begin
          Power := P.Power; if Power = 0 then Power := J.Profile.Power;
          Feed := P.Feed; if Feed = 0 then Feed := J.Profile.Feed;
          if not LaserActive then S.Add('M4 S' + IntToStr(Round(Power)))
          else if LastPower <> Round(Power) then S.Add('S' + IntToStr(Round(Power)));
          LaserActive := True; LastPower := Round(Power);
          S.Add(Format('G1 X%.3f Y%.3f F%.3f', [P.X, P.Y, Feed], InvariantFS));
        end
        else
        begin
          S.Add('M5'); LaserActive := False;
          S.Add(Format('G0 X%.3f Y%.3f', [P.X, P.Y], InvariantFS));
        end;
      end;
      S.Add('M5');
    end;
    S.Add('M5');
    { Verificacao completa antes de tocar no arquivo. }
    S.SaveToFile(FN);
  finally S.Free; end;
end;
end.
