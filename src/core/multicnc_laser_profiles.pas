unit multicnc_laser_profiles;
{$mode objfpc}{$H+}
{$codepage utf8}
interface
uses Classes, SysUtils, multicnc_laser_config, multisuite_numfmt;
type
  TLaserProfile = record
    Brand, Model: string;
    WorkX, WorkY, OpticalPowerW: Double;
    BaudRate, WavelengthNM: Integer;
    HasHoming: Boolean;
    SuggestedPower, SuggestedEngraveFeed, SuggestedCutFeed, SuggestedTravelFeed: Integer;
    SourceURL, Notes: string;
  end;
const
  LASER_PROFILE_COUNT = 34;
procedure GetLaserBrands(AList: TStrings);
procedure GetLaserModels(const ABrand: string; AList: TStrings);
function FindLaserProfile(const ABrand, AModel: string; out AProfile: TLaserProfile): Boolean;
function LaserProfileSummary(const P: TLaserProfile): string;
function LaserSettingsForProfile(const P: TLaserProfile): TLaserSettings;
implementation
{ Dados de origem e hipóteses em docs/LASER_PROFILES.md.
  Baud, comprimento de onda e parâmetros de trabalho são sugestões compatíveis.
  Este catálogo nunca envia configurações ($30/$32) ou altera o firmware. }
const
  PROFILES: array[0..LASER_PROFILE_COUNT-1] of TLaserProfile = (
    (Brand: 'Generic'; Model: 'Generic GRBL Laser';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 0; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: '';
     Notes: 'Área e potência dependem da máquina; ajuste o perfil antes de usar.'),
    (Brand: 'CUSTOM'; Model: 'CUSTOM Laser';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 0; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 10; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: '';
     Notes: 'Informe os dados reais da máquina e salve pelo nome do equipamento. Valores iniciais são editáveis.'),
    (Brand: 'GLYPHO'; Model: 'S1 5W';
     WorkX: 130.0; WorkY: 130.0; OpticalPowerW: 5; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: True;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: '';
     Notes: '5 W interpretados de 5000 mW; área informada pelo operador. Comunicação e ajustes sugeridos para GRBL.'),
    (Brand: 'GLYPHO'; Model: 'S1 10W modificado';
     WorkX: 130.0; WorkY: 130.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: True;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: '';
     Notes: 'Upgrade informado pelo operador, não versão de fábrica. Foco e potência real dependem do módulo instalado.'),
    (Brand: 'ACMER'; Model: 'S1 2.5W';
     WorkX: 130.0; WorkY: 130.0; OpticalPowerW: 2.5; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://acmerlaser.com/products/portable-laser-engraver-mini-machine';
     Notes: 'Área e potência do fabricante; confirme sensores de homing na sua revisão.'),
    (Brand: 'ACMER'; Model: 'S1 3.5W';
     WorkX: 130.0; WorkY: 130.0; OpticalPowerW: 3.5; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://acmerlaser.com/products/portable-laser-engraver-mini-machine';
     Notes: 'Área e potência do fabricante; confirme sensores de homing na sua revisão.'),
    (Brand: 'ACMER'; Model: 'S1 6W';
     WorkX: 130.0; WorkY: 130.0; OpticalPowerW: 6; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 30; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://acmerlaser.com/products/portable-laser-engraver-mini-machine';
     Notes: 'Área e potência do fabricante; confirme sensores de homing na sua revisão.'),
    (Brand: 'ACMER'; Model: 'P2 20W';
     WorkX: 420.0; WorkY: 400.0; OpticalPowerW: 20; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 10; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://acmerlaser.com/products/acmer-p2-laser-engraver-cutter-machine';
     Notes: 'Área padrão; sem kit de extensão.'),
    (Brand: 'ACMER'; Model: 'P2 33W';
     WorkX: 420.0; WorkY: 400.0; OpticalPowerW: 33; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 6; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://acmerlaser.com/blogs/news/how-to-use-acmer-laser-cutter-to-cut-acrylic-sheets';
     Notes: 'Área padrão publicada para o P2 33W; sem extensão.'),
    (Brand: 'SCULPFUN'; Model: 'S9 5.5W';
     WorkX: 410.0; WorkY: 415.0; OpticalPowerW: 5.5; BaudRate: 115200;
     WavelengthNM: 450; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.sculpfun.com/products/sculpfun-s9-laser-engraver';
     Notes: 'Área do catálogo global atual; outras revisões anunciam 410x420 mm. Confira sua máquina.'),
    (Brand: 'SCULPFUN'; Model: 'S10 10W';
     WorkX: 410.0; WorkY: 400.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 455; HasHoming: False;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://eu.sculpfun.com/en-eu/products/sculpfun-s10-laser-engraver-machine';
     Notes: 'Área padrão, sem extensão Y.'),
    (Brand: 'SCULPFUN'; Model: 'S30 5W';
     WorkX: 410.0; WorkY: 400.0; OpticalPowerW: 5; BaudRate: 115200;
     WavelengthNM: 455; HasHoming: True;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.sculpfun.com/blogs/blog/sculpfun-s30-series';
     Notes: 'Área padrão, sem kit XY.'),
    (Brand: 'SCULPFUN'; Model: 'S30 Pro 10W';
     WorkX: 410.0; WorkY: 400.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 455; HasHoming: True;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.sculpfun.com/blogs/blog/sculpfun-s30-series';
     Notes: 'Área padrão, sem kit XY.'),
    (Brand: 'SCULPFUN'; Model: 'S30 Ultra 11W';
     WorkX: 600.0; WorkY: 600.0; OpticalPowerW: 11; BaudRate: 115200;
     WavelengthNM: 455; HasHoming: True;
     SuggestedPower: 18; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.sculpfun.com/products/sculpfun-s30-ultra-11w-laser-engraving-machine';
     Notes: 'Revisão do catálogo global: 600x600 mm; confira a revisão regional.'),
    (Brand: 'SCULPFUN'; Model: 'S30 Ultra 22W';
     WorkX: 590.0; WorkY: 595.0; OpticalPowerW: 22; BaudRate: 115200;
     WavelengthNM: 455; HasHoming: True;
     SuggestedPower: 9; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.sculpfun.com/products/sculpfun-s30-ultra-22w-laser-engraving-machine';
     Notes: 'Área útil padrão atual do catálogo global: 590x595 mm; sem extensão.'),
    (Brand: 'SCULPFUN'; Model: 'S30 Ultra 33W';
     WorkX: 590.0; WorkY: 595.0; OpticalPowerW: 33; BaudRate: 115200;
     WavelengthNM: 455; HasHoming: True;
     SuggestedPower: 6; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.sculpfun.com/products/sculpfun-s30-ultra-33w-laser-engraving-machine';
     Notes: 'Área útil padrão atual do catálogo global: 590x595 mm; sem extensão.'),
    (Brand: 'TwoTrees'; Model: 'TTS-55 Pro 5.5W';
     WorkX: 300.0; WorkY: 300.0; OpticalPowerW: 5.5; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://twotrees3d.com/products/tts-55-pro-tts-10-pro-diode-laser-engraver-twotrees';
     Notes: 'Área e potência do fabricante. Confira sensores e versão do firmware da sua placa.'),
    (Brand: 'TwoTrees'; Model: 'TTS-10 Pro 10W';
     WorkX: 300.0; WorkY: 300.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://twotrees3d.com/products/tts-55-pro-tts-10-pro-diode-laser-engraver-twotrees';
     Notes: 'Área e potência do fabricante. Confira sensores e versão do firmware da sua placa.'),
    (Brand: 'TwoTrees'; Model: 'TTS-20 Pro 20W';
     WorkX: 418.0; WorkY: 418.0; OpticalPowerW: 20; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 10; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://twotrees3d.com/products/tts-55-pro-tts-10-pro-diode-laser-engraver-twotrees';
     Notes: 'Área e potência do fabricante. Confira sensores e versão do firmware da sua placa.'),
    (Brand: 'Ortur'; Model: 'Laser Master 2 Pro S2 5.5W';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 5.5; BaudRate: 115200;
     WavelengthNM: 445; HasHoming: True;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://ortur.net/pages/support-olm2-pro-s2';
     Notes: 'Área e potência nominal do fabricante; não confundir com versão de 10 W.'),
    (Brand: 'Ortur'; Model: 'Laser Master 2 Pro S2 1.6W';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 1.6; BaudRate: 115200;
     WavelengthNM: 445; HasHoming: True;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://ortur.net/pages/support-olm2-pro-s2';
     Notes: 'Módulo LU2-2; área padrão publicada pelo fabricante.'),
    (Brand: 'Ortur'; Model: 'Laser Master 2 Pro S2 10W';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 445; HasHoming: True;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://ortur.net/pages/support-olm2-pro-s2';
     Notes: 'Módulo LU2-10A; área padrão publicada pelo fabricante.'),
    (Brand: 'Ortur'; Model: 'Laser Master 3 10W';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 445; HasHoming: True;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://ortur.net/pages/support-olm3';
     Notes: 'Módulo LU2-10A; potência óptica nominal 10 W.'),
    (Brand: 'Ortur'; Model: 'Laser Master 3 20W';
     WorkX: 400.0; WorkY: 380.0; OpticalPowerW: 20; BaudRate: 115200;
     WavelengthNM: 445; HasHoming: True;
     SuggestedPower: 10; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://ortur.net/pages/support-olm3';
     Notes: 'Módulo LU3-20A; área Y reduzida para 380 mm nesta variante.'),
    (Brand: 'Ortur'; Model: 'Laser Master 3 40W';
     WorkX: 400.0; WorkY: 380.0; OpticalPowerW: 40; BaudRate: 115200;
     WavelengthNM: 445; HasHoming: True;
     SuggestedPower: 5; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://ortur.net/pages/support-olm3';
     Notes: 'Módulo LU3-40A; área Y reduzida para 380 mm nesta variante.'),
    (Brand: 'AtomStack'; Model: 'A5 Pro 5W';
     WorkX: 410.0; WorkY: 400.0; OpticalPowerW: 5; BaudRate: 115200;
     WavelengthNM: 445; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://atomstack.net/products/atomstack-a5-pro-laser-engraving-machine';
     Notes: 'A5 Pro original; A5 Pro V2 tem dimensões diferentes. Potência óptica, não consumo elétrico.'),
    (Brand: 'AtomStack'; Model: 'A20 Pro V2 20W';
     WorkX: 400.0; WorkY: 365.0; OpticalPowerW: 20; BaudRate: 115200;
     WavelengthNM: 455; HasHoming: False;
     SuggestedPower: 10; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://jp.atomstack.com/products/atomstack-a20-pro-v2';
     Notes: 'Área da ficha oficial japonesa: 400x365 mm; confirme a revisão regional.'),
    (Brand: 'LONGER'; Model: 'RAY5 5W';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 5; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.longer3d.com/de/pages/longer-laser-engraver-ray5';
     Notes: 'Potência óptica nominal 5 W; área padrão, sem extensão.'),
    (Brand: 'LONGER'; Model: 'RAY5 10W';
     WorkX: 400.0; WorkY: 400.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.longer3d.com/products/longer-ray5-10w-laser-engraver';
     Notes: 'Potência nominal 10 W; área padrão da variante 10 W.'),
    (Brand: 'LONGER'; Model: 'RAY5 20W';
     WorkX: 400.0; WorkY: 365.0; OpticalPowerW: 20; BaudRate: 115200;
     WavelengthNM: 450; HasHoming: False;
     SuggestedPower: 10; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.longer3d.com/products/longer-ray5-10w-laser-engraver';
     Notes: 'Área padrão da variante 20 W: 400x365 mm; sem extensão.'),
    (Brand: 'Creality'; Model: 'CR-Laser Falcon 5W';
     WorkX: 400.0; WorkY: 415.0; OpticalPowerW: 5; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 40; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.crealityfalcon.com/collections/laser-engravers';
     Notes: 'Série CR original; não confundir com Falcon A1 ou Falcon2.'),
    (Brand: 'Creality'; Model: 'CR-Laser Falcon 10W';
     WorkX: 400.0; WorkY: 415.0; OpticalPowerW: 10; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 20; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.crealityfalcon.com/collections/laser-engravers';
     Notes: 'Série CR original; não confundir com Falcon A1 ou Falcon2.'),
    (Brand: 'Creality'; Model: 'Falcon2 22W';
     WorkX: 400.0; WorkY: 415.0; OpticalPowerW: 22; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 9; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.crealityfalcon.com/collections/laser-engravers';
     Notes: 'Falcon2 aberto; não é Falcon2 Pro.'),
    (Brand: 'Creality'; Model: 'Falcon2 40W';
     WorkX: 400.0; WorkY: 415.0; OpticalPowerW: 40; BaudRate: 115200;
     WavelengthNM: 0; HasHoming: False;
     SuggestedPower: 5; SuggestedEngraveFeed: 3000;
     SuggestedCutFeed: 600; SuggestedTravelFeed: 5000;
     SourceURL: 'https://www.crealityfalcon.com/collections/laser-engravers';
     Notes: 'Falcon2 aberto; não é Falcon2 Pro.')
  );
procedure GetLaserBrands(AList: TStrings);
var I: Integer;
begin
  AList.Clear;
  for I := 0 to High(PROFILES) do
    if AList.IndexOf(PROFILES[I].Brand) < 0 then AList.Add(PROFILES[I].Brand);
end;
procedure GetLaserModels(const ABrand: string; AList: TStrings);
var I: Integer;
begin
  AList.Clear;
  for I := 0 to High(PROFILES) do
    if SameText(PROFILES[I].Brand, ABrand) then AList.Add(PROFILES[I].Model);
end;
function FindLaserProfile(const ABrand, AModel: string; out AProfile: TLaserProfile): Boolean;
var I: Integer;
begin
  for I := 0 to High(PROFILES) do
    if SameText(PROFILES[I].Brand, ABrand) and SameText(PROFILES[I].Model, AModel) then
    begin AProfile := PROFILES[I]; Exit(True); end;
  AProfile := Default(TLaserProfile);
  Result := False;
end;
function LaserProfileSummary(const P: TLaserProfile): string;
var PowerText, WaveText, SourceText: string;
begin
  if P.OpticalPowerW > 0 then PowerText := Format('%g W ópticos', [P.OpticalPowerW], InvariantFS)
  else PowerText := 'potência não informada';
  if P.WavelengthNM > 0 then WaveText := IntToStr(P.WavelengthNM) + ' nm'
  else WaveText := 'não informado';
  Result := Format('%s %s | %s | Área XY: %g x %g mm (Z manual)' + LineEnding +
    'Conexão sugerida: GRBL / USB %d baud, 8N1 | Comprimento de onda: %s' + LineEnding +
    'Materiais: madeira, acrílico opaco escuro, couro natural, cortiça, pedra, vidro preparado e papel.' + LineEnding +
    'Vidro/transparências precisam de preparação; resultados dependem do material e do módulo.' + LineEnding +
    'Ajustes do aplicativo (não receitas de fábrica): gravação %d mm/min a %d%%; corte %d; deslocamento %d mm/min.' + LineEnding +
    'S máximo sugerido 1000: confira $30; M4 requer GRBL 1.1 com $32=1. Faça teste no material.' + LineEnding +
    '%s',
    [P.Brand, P.Model, PowerText, P.WorkX, P.WorkY, P.BaudRate, WaveText,
     P.SuggestedEngraveFeed, P.SuggestedPower, P.SuggestedCutFeed, P.SuggestedTravelFeed, P.Notes], InvariantFS);
  if P.SourceURL <> '' then
    SourceText := 'Área e potência: ficha publicada pelo fabricante.'
  else if SameText(P.Brand, 'GLYPHO') then
    SourceText := 'Perfil personalizado informado pelo operador.'
  else SourceText := '';
  if SourceText <> '' then Result := Result + LineEnding + SourceText;
end;
function LaserSettingsForProfile(const P: TLaserProfile): TLaserSettings;
begin
  Result := DefaultLaserSettings;
  Result.WorkMode := lwmEngrave;
  Result.LaserPower := P.SuggestedPower;
  Result.EngraveFeed := P.SuggestedEngraveFeed;
  Result.CutFeed := P.SuggestedCutFeed;
  Result.RapidFeed := P.SuggestedTravelFeed;
  Result.PassFeed := P.SuggestedCutFeed;
  Result.PassPower := P.SuggestedPower;
  Result.PerforatePower := P.SuggestedPower;
  Result.PerforateFeed := P.SuggestedEngraveFeed;
  Result.AirAssist := False;
  Result.PassZStep := 0;
  Result.FramingLaser := False;
  Result.OverrideSpeeds := False;
end;
end.
