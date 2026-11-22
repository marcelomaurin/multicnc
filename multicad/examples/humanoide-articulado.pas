begin
  IniciarSimultaneo;
  MoverArticulacao('upperarm01.L', 'z', 65, 800);
  MoverArticulacao('upperarm01.R', 'z', -65, 800);
  FinalizarSimultaneo;
  Esperar(400);
  IniciarSimultaneo;
  MoverArticulacao('upperarm01.L', 'z', 0, 800);
  MoverArticulacao('upperarm01.R', 'z', 0, 800);
  FinalizarSimultaneo;
end.
