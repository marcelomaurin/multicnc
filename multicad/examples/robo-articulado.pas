var I: Integer;
begin
  for I := 1 to 2 do
  begin
    MoverSegmento('braco', 45, 600);
    MoverSegmento('antebraco', 60, 400);
    Esperar(300);
    MoverSegmento('antebraco', 0, 400);
    MoverSegmento('braco', 0, 600);
  end;
  MoverSegmento('base', 90, 1000);
  MoverSegmento('base', 0, 1000);
end.
