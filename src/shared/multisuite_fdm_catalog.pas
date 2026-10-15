unit multisuite_fdm_catalog;
{$mode objfpc}{$H+}
interface
{ Manufacturer specifications, checked 2026-10-15. FDM/FFF only.
  Catalog presence is not a tested firmware or transport implementation.
  MaxSpeed=0 means not recorded, never zero feed. See docs/CATALOGO_IMPRESSORAS_FDM.md. }
type
  TFDMModel = record
    Brand, Model: string;
    X,Y,Z,Nozzle,Filament: Double;
    MaxHotend,MaxBed,MaxSpeed: Integer;
    Workflow,SourceURL,Notes: string;
  end;
const
  FDM_RESEARCH_DATE = '2026-10-15';
  FDM_MODEL_COUNT = 11;
  FDM_MODELS: array[0..FDM_MODEL_COUNT-1] of TFDMModel = (
    (Brand:'Creality';Model:'K2';X:260;Y:260;Z:260;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:100;MaxSpeed:600;Workflow:'Creality Print';
     SourceURL:'https://www.creality.com/es/support/k2-series-3d-printer';
     Notes:'Wi-Fi / USB; CFS opcional.'),
    (Brand:'Creality';Model:'K2 Pro';X:300;Y:300;Z:300;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:110;MaxSpeed:600;Workflow:'Creality Print';
     SourceURL:'https://www.creality.com/support/k2-series';
     Notes:'Camara aquecida ate 60 C; Wi-Fi / LAN / USB.'),
    (Brand:'Creality';Model:'K2 Plus';X:350;Y:350;Z:350;Nozzle:0.4;Filament:1.75;
     MaxHotend:350;MaxBed:120;MaxSpeed:600;Workflow:'Creality Print';
     SourceURL:'https://www.creality.com/products/creality-k2-plus-cfs-combo';
     Notes:'Camara aquecida ate 60 C; CFS opcional. Limite publicado de 350 C nao altera o teto do controlador.'),
    (Brand:'Creality';Model:'K1C';X:220;Y:220;Z:250;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:100;MaxSpeed:600;Workflow:'Creality Print';
     SourceURL:'https://www.creality.com/products/k1c-carbon-3d-printer';
     Notes:'CoreXY; bico resistente a abrasao; USB / LAN / Creality Cloud.'),
    (Brand:'Bambu Lab';Model:'A1 mini';X:180;Y:180;Z:180;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:80;MaxSpeed:500;Workflow:'Bambu Studio';
     SourceURL:'https://us.store.bambulab.com/products/a1-mini?id=543566369394393101';
     Notes:'AMS lite opcional; mesa ate 80 C.'),
    (Brand:'Bambu Lab';Model:'A1';X:256;Y:256;Z:256;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:100;MaxSpeed:500;Workflow:'Bambu Studio';
     SourceURL:'https://us.store.bambulab.com/products/a1?variant=41583355232392';
     Notes:'AMS lite opcional; Wi-Fi / microSD.'),
    (Brand:'Bambu Lab';Model:'P1S';X:256;Y:256;Z:256;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:100;MaxSpeed:500;Workflow:'Bambu Studio';
     SourceURL:'https://us.store.bambulab.com/products/p1s?id=583855874739507213';
     Notes:'CoreXY fechada; AMS opcional; considerar area de exclusao do cortador no perfil oficial.'),
    (Brand:'Bambu Lab';Model:'X1 Carbon';X:256;Y:256;Z:256;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:110;MaxSpeed:500;Workflow:'Bambu Studio';
     SourceURL:'https://public-cdn.bambulab.com/store/bambulab-X1-carbon-tech-specs.pdf?v=20250715085516';
     Notes:'Mesa: 110 C em 220 V, 120 C em 110 V; catalogo usa 110 C. Area de exclusao deve vir do perfil oficial.'),
    (Brand:'Prusa Research';Model:'Original Prusa MK4S';X:250;Y:210;Z:220;Nozzle:0.4;Filament:1.75;
     MaxHotend:290;MaxBed:120;MaxSpeed:0;Workflow:'PrusaSlicer';
     SourceURL:'https://www.prusa3d.com/product/original-prusa-mk4s-3d-printer-7/?gQT=2';
     Notes:'Nextruder; bico CHT de alto fluxo; velocidade maxima nao cadastrada sem valor de referencia comparavel.'),
    (Brand:'Elegoo';Model:'Neptune 4 Pro';X:225;Y:225;Z:265;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:110;MaxSpeed:500;Workflow:'Elegoo Cura / perfil Klipper oficial';
     SourceURL:'https://www.elegoo.com/en-gb/products/elegoo-neptune-4-pro-fdm-3d-printer';
     Notes:'Klipper; area util 225 x 225, nao confundir com placa PEI de 235 x 235 mm.'),
    (Brand:'Anycubic';Model:'Kobra 3 V2';X:255;Y:255;Z:260;Nozzle:0.4;Filament:1.75;
     MaxHotend:300;MaxBed:110;MaxSpeed:600;Workflow:'Anycubic Slicer Next';
     SourceURL:'https://www.anycubic.com/en/kobra-3-v2-combo';
     Notes:'Kobra OS; LeviQ 3.0; ACE Pro opcional. Nao confundir com a Kobra 3 original.')
  );
implementation
end.
