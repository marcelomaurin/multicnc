unit multicam_gcode;
{$mode objfpc}{$H+}
{ Pos-processadores MultiCAM -> MultiCNC.

  ExportJob      - saida simples original (uma linha por movimento).
  BuildProgram / ExportJobEx - pos-processador moderno:
    * saida modal (so escreve eixos e F que mudaram) - arquivos menores;
    * arc fitting: sequencias de segmentos no mesmo Z viram G2/G3
      (tolerancia configuravel), reduzindo drasticamente o numero de linhas
      enviadas ao controlador;
    * cabecalho com ferramenta, limites e contagem de movimentos;
    * pausa opcional para o spindle atingir a rotacao (G4);
    * ponto decimal invariante (independente do idioma do sistema). }
interface
uses multisuite_numfmt,Classes,SysUtils,Math,multicam_types,multicam_job,multisuite_geometry,multisuite_arcfit;

type
  TCamPostOptions=record
    ArcFitting:Boolean;
    ArcTolerance:Double;   // mm
    Decimals:Integer;
    SpindleDwellSeconds:Double;
    EndAtSafeZ:Boolean;
  end;

  TCamGCode=class
  public
    class procedure ExportJob(J:TCamJob;const FN:string);
    class function DefaultPostOptions:TCamPostOptions;
    class procedure BuildProgram(J:TCamJob;const Opt:TCamPostOptions;Output:TStrings);
    class procedure ExportJobEx(J:TCamJob;const FN:string;const Opt:TCamPostOptions);
  end;

implementation

class procedure TCamGCode.ExportJob(J:TCamJob;const FN:string);
var S:TStringList;I:Integer;M:TPathMove;
begin S:=TStringList.Create;try S.Add('; MultiCAM -> MultiCNC');S.Add('G21');S.Add('G90');S.Add('M5');if(J.Tool.SpindleRPM>0)then S.Add(Format('M3 S%d',[J.Tool.SpindleRPM]));for I:=0 to J.Count-1 do begin M:=J.Move(I);if M.Rapid then S.Add(Format('G0 X%.3f Y%.3f Z%.3f',[M.P.X,M.P.Y,M.P.Z],InvariantFS)) else if I>0 then begin if M.P.Z<J.Move(I-1).P.Z then S.Add(Format('G1 X%.3f Y%.3f Z%.3f F%.0f',[M.P.X,M.P.Y,M.P.Z,J.Tool.Plunge],InvariantFS))else S.Add(Format('G1 X%.3f Y%.3f Z%.3f F%.0f',[M.P.X,M.P.Y,M.P.Z,J.Tool.Feed],InvariantFS));end;end;S.Add('M5');S.Add(Format('G0 Z%.3f',[J.Settings.SafeZ],InvariantFS));S.SaveToFile(FN);finally S.Free;end;end;

class function TCamGCode.DefaultPostOptions:TCamPostOptions;
begin
  Result.ArcFitting:=True;
  Result.ArcTolerance:=0.005;
  Result.Decimals:=3;
  Result.SpindleDwellSeconds:=2;
  Result.EndAtSafeZ:=True;
end;

type
  TModalWriter=class
    Out:TStrings;
    FS:TFormatSettings;
    Fmt:string;
    X,Y,Z,F:Double;
    Known:Boolean;
    LastG:Integer;
    constructor Create(AOut:TStrings;Decimals:Integer);
    function N(V:Double):string;
    procedure Move(G:Integer;NX,NY,NZ,NF:Double);
    procedure Arc(G:Integer;NX,NY,I,J,NF:Double);
  end;

constructor TModalWriter.Create(AOut:TStrings;Decimals:Integer);
begin
  Out:=AOut;
  FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';
  Fmt:='%.'+IntToStr(Max(0,Min(6,Decimals)))+'f';
  LastG:=-1;
end;

function TModalWriter.N(V:Double):string;
begin
  Result:=Format(Fmt,[V],FS);
  if(Pos('.',Result)>0)then begin
    while Result[Length(Result)]='0' do Delete(Result,Length(Result),1);
    if Result[Length(Result)]='.' then Delete(Result,Length(Result),1);
  end;
  if(Result='-0')then Result:='0';
end;

procedure TModalWriter.Move(G:Integer;NX,NY,NZ,NF:Double);
var L:string;
begin
  L:='';
  if(not Known)or(N(NX)<>N(X))then L:=L+' X'+N(NX);
  if(not Known)or(N(NY)<>N(Y))then L:=L+' Y'+N(NY);
  if(not Known)or(N(NZ)<>N(Z))then L:=L+' Z'+N(NZ);
  if L='' then Exit;
  if(G<>0)and(N(NF)<>N(F))then begin L:=L+' F'+IntToStr(Round(NF));F:=NF;end;
  if G<>LastG then L:='G'+IntToStr(G)+L else L:=Trim(L);
  LastG:=G;
  Out.Add(L);
  X:=NX;Y:=NY;Z:=NZ;Known:=True;
end;

procedure TModalWriter.Arc(G:Integer;NX,NY,I,J,NF:Double);
var L:string;
begin
  L:='G'+IntToStr(G)+' X'+N(NX)+' Y'+N(NY)+' I'+N(I)+' J'+N(J);
  if N(NF)<>N(F) then begin L:=L+' F'+IntToStr(Round(NF));F:=NF;end;
  LastG:=G;
  Out.Add(L);
  X:=NX;Y:=NY;
end;

class procedure TCamGCode.BuildProgram(J:TCamJob;const Opt:TCamPostOptions;Output:TStrings);
var
  W:TModalWriter;
  I,K,RunEnd:Integer;
  M,Prev:TPathMove;
  Feed,Plunge,MinX,MinY,MinZ,MaxX,MaxY,MaxZ:Double;
  Run:TPolygon2D;
  Fit:TFitMoves;
  AF:TArcFitOptions;
  Body:TStringList;
  Arcs,Lines:Integer;
begin
  Feed:=J.Tool.Feed;if Feed<=0 then Feed:=600;
  Plunge:=J.Tool.Plunge;if Plunge<=0 then Plunge:=Feed*0.3;
  AF:=DefaultArcFitOptions;
  AF.Tolerance:=Max(Opt.ArcTolerance,1e-4);
  Body:=TStringList.Create;
  W:=TModalWriter.Create(Body,Opt.Decimals);
  Arcs:=0;Lines:=0;
  MinX:=0;MinY:=0;MinZ:=0;MaxX:=0;MaxY:=0;MaxZ:=0;
  try
    I:=0;
    while I<J.Count do begin
      M:=J.Move(I);
      if I=0 then begin MinX:=M.P.X;MaxX:=M.P.X;MinY:=M.P.Y;MaxY:=M.P.Y;MinZ:=M.P.Z;MaxZ:=M.P.Z;end;
      MinX:=Min(MinX,M.P.X);MaxX:=Max(MaxX,M.P.X);MinY:=Min(MinY,M.P.Y);MaxY:=Max(MaxY,M.P.Y);
      MinZ:=Min(MinZ,M.P.Z);MaxZ:=Max(MaxZ,M.P.Z);
      if M.Rapid or(I=0)then begin
        if M.Rapid then W.Move(0,M.P.X,M.P.Y,M.P.Z,0) else W.Move(1,M.P.X,M.P.Y,M.P.Z,Feed);
        Inc(Lines);Inc(I);Continue;
      end;
      Prev:=J.Move(I-1);
      if Abs(M.P.Z-Prev.P.Z)>1e-6 then begin
        // movimento com Z variavel (mergulho/rampa/helice): linear
        if M.P.Z<Prev.P.Z then W.Move(1,M.P.X,M.P.Y,M.P.Z,Plunge) else W.Move(1,M.P.X,M.P.Y,M.P.Z,Feed);
        Inc(Lines);Inc(I);Continue;
      end;
      // trecho no mesmo Z: candidato a arc fitting
      RunEnd:=I;
      while(RunEnd+1<J.Count)and(not J.Move(RunEnd+1).Rapid)and(Abs(J.Move(RunEnd+1).P.Z-M.P.Z)<=1e-6)do Inc(RunEnd);
      if Opt.ArcFitting and(RunEnd-I+1>=3)then begin
        SetLength(Run,RunEnd-I+2);
        Run[0]:=Pt(Prev.P.X,Prev.P.Y);
        for K:=I to RunEnd do Run[K-I+1]:=Pt(J.Move(K).P.X,J.Move(K).P.Y);
        Fit:=FitArcs(Run,AF);
        for K:=0 to High(Fit)do
          case Fit[K].Kind of
            fmLine:begin W.Move(1,Fit[K].X,Fit[K].Y,M.P.Z,Feed);Inc(Lines);end;
            fmArcCW:begin W.Arc(2,Fit[K].X,Fit[K].Y,Fit[K].I,Fit[K].J,Feed);Inc(Arcs);end;
            fmArcCCW:begin W.Arc(3,Fit[K].X,Fit[K].Y,Fit[K].I,Fit[K].J,Feed);Inc(Arcs);end;
          end;
        for K:=I to RunEnd do begin
          MinX:=Min(MinX,J.Move(K).P.X);MaxX:=Max(MaxX,J.Move(K).P.X);
          MinY:=Min(MinY,J.Move(K).P.Y);MaxY:=Max(MaxY,J.Move(K).P.Y);
        end;
        I:=RunEnd+1;
      end else begin
        W.Move(1,M.P.X,M.P.Y,M.P.Z,Feed);Inc(Lines);Inc(I);
      end;
    end;
    Output.Clear;
    Output.Add('; MultiCAM -> MultiCNC');
    Output.Add('; job: '+J.Name);
    Output.Add(Format('; ferramenta: %s D=%s mm, %d rpm, F%d, mergulho F%d',
      [J.Tool.Name,W.N(J.Tool.Diameter),J.Tool.SpindleRPM,Round(Feed),Round(Plunge)]));
    Output.Add(Format('; limites: X %s..%s Y %s..%s Z %s..%s',[W.N(MinX),W.N(MaxX),W.N(MinY),W.N(MaxY),W.N(MinZ),W.N(MaxZ)]));
    Output.Add(Format('; movimentos: %d originais -> %d lineares + %d arcos',[J.Count,Lines,Arcs]));
    Output.Add('G21 G90 G17 G94 G91.1');
    Output.Add('M5');
    Output.Add('G0 Z'+W.N(J.Settings.SafeZ));
    if J.Tool.SpindleRPM>0 then begin
      Output.Add(Format('M3 S%d',[J.Tool.SpindleRPM]));
      if Opt.SpindleDwellSeconds>0 then Output.Add('G4 P'+W.N(Opt.SpindleDwellSeconds));
    end;
    Output.AddStrings(Body);
    if Opt.EndAtSafeZ then Output.Add('G0 Z'+W.N(J.Settings.SafeZ));
    Output.Add('M5');
    Output.Add('M30');
  finally
    W.Free;
    Body.Free;
  end;
end;

class procedure TCamGCode.ExportJobEx(J:TCamJob;const FN:string;const Opt:TCamPostOptions);
var S:TStringList;
begin
  S:=TStringList.Create;
  try
    BuildProgram(J,Opt,S);
    S.SaveToFile(FN);
  finally
    S.Free;
  end;
end;

end.
