unit multicad_fontoutlines;

{ Extrai as curvas da fonte do sistema, nunca rasteriza o texto.
  Windows: GDI GGO_NATIVE | GGO_UNHINTED; Unix: caminhos Cairo.
  Beziers sao discretizadas com erro de corda <= min(0.01 mm, altura/2000). }
{$mode objfpc}{$H+}{$codepage utf8}
{$pointermath on}
interface
uses SysUtils, Math, multicad_types, multicad_sketchtext;
function CadFontOutlines(const P: TCadTextSettings;
  out Paths: TCadTextContours; out Error: string): Boolean;
implementation
{$IFDEF MSWINDOWS}
uses Windows;
function GetGlyphIndicesW(DC:HDC;Text:PWideChar;Count:Integer;Indices:PWord;Flags:DWORD):DWORD;
  stdcall;external 'gdi32' name 'GetGlyphIndicesW';
{$ENDIF}
type
  TOutlineBuilder = class
    Paths: TCadTextContours;
    Current: TCadTextContour;
    Tol: Double;
    Count: Integer;
    procedure Point(const P: TCadVec2);
    procedure Close;
    procedure Quad(const A,B,C: TCadVec2; Depth: Integer = 0);
    procedure Cubic(const A,B,C,D: TCadVec2; Depth: Integer = 0);
  end;
function Mid(const A,B: TCadVec2): TCadVec2;
begin Result:=V2((A.X+B.X)/2,(A.Y+B.Y)/2);end;
function ChordDistance(const P,A,B: TCadVec2): Double;
var T,D: Double;
begin
  D:=Sqr(B.X-A.X)+Sqr(B.Y-A.Y);T:=0;
  if D>1E-20 then T:=EnsureRange(((P.X-A.X)*(B.X-A.X)+(P.Y-A.Y)*(B.Y-A.Y))/D,0.0,1.0);
  Result:=Hypot(P.X-A.X-T*(B.X-A.X),P.Y-A.Y-T*(B.Y-A.Y));
end;
procedure TOutlineBuilder.Point(const P: TCadVec2);
var N: Integer;
begin
  N:=Length(Current);
  if (N>0) and (Hypot(P.X-Current[N-1].X,P.Y-Current[N-1].Y)<1E-8) then Exit;
  Inc(Count);if Count>20000 then raise Exception.Create('Texto muito complexo. Insira trechos menores.');
  SetLength(Current,N+1);Current[N]:=P;
end;
procedure TOutlineBuilder.Close;
var N: Integer;
begin
  N:=Length(Current);
  if (N>1) and (Hypot(Current[0].X-Current[N-1].X,Current[0].Y-Current[N-1].Y)<1E-8) then
    SetLength(Current,N-1);
  if Length(Current)>=3 then begin
    N:=Length(Paths);SetLength(Paths,N+1);Paths[N]:=Current;
  end;
  Current:=nil;
end;
procedure TOutlineBuilder.Quad(const A,B,C: TCadVec2; Depth: Integer);
var AB,BC,M: TCadVec2;
begin
  if (Depth>=20) or (ChordDistance(B,A,C)<=Tol) then begin Point(C);Exit;end;
  AB:=Mid(A,B);BC:=Mid(B,C);M:=Mid(AB,BC);
  Quad(A,AB,M,Depth+1);Quad(M,BC,C,Depth+1);
end;
procedure TOutlineBuilder.Cubic(const A,B,C,D: TCadVec2; Depth: Integer);
var AB,BC,CD,ABC,BCD,M: TCadVec2;
begin
  if (Depth>=20) or (Math.Max(ChordDistance(B,A,D),ChordDistance(C,A,D))<=Tol) then begin Point(D);Exit;end;
  AB:=Mid(A,B);BC:=Mid(B,C);CD:=Mid(C,D);ABC:=Mid(AB,BC);BCD:=Mid(BC,CD);M:=Mid(ABC,BCD);
  Cubic(A,AB,ABC,M,Depth+1);Cubic(M,BCD,CD,D,Depth+1);
end;

{$IFDEF MSWINDOWS}
type
  TFixedPoint = packed record X,Y: LongInt;end;
  TNativeHeader = packed record Bytes,Kind: DWORD;Start: TFixedPoint;end;
  TNativeCurve = packed record Kind,Count: Word;end;
procedure WindowsOutlines(const P: TCadTextSettings; B: TOutlineBuilder);
var DC:HDC;Font,OldFont:HFONT;M:TMAT2;GM:TGlyphMetrics;U:UnicodeString;
  Face:UnicodeString; Buffer:array of Byte; Indices:array of Word;
  Size,Posn,EndPos,CurvePos:SizeInt; H:TNativeHeader;C:TNativeCurve;
  I,J,K,LineStart,LineEnd,FirstPath:Integer;Scale,X,Y,Advance,Shift:Double;
  A,Q,R,Z:TCadVec2;Kerns:array of TKerningPair;NK:DWORD;Code:Word;
  function Outline(CharCode:Word; WantBuffer:Boolean):DWORD;
  begin
    Result:=GetGlyphOutlineW(DC,CharCode,GGO_NATIVE or $100,@GM,0,nil,@M);
    if Result=GDI_ERROR then raise Exception.Create('Esta fonte não fornece contornos vetoriais. Escolha uma fonte TrueType ou OpenType.');
    if WantBuffer then begin
      SetLength(Buffer,Result);
      if (Result>0) and (GetGlyphOutlineW(DC,CharCode,GGO_NATIVE or $100,@GM,Result,@Buffer[0],@M)=GDI_ERROR) then
        raise Exception.Create('Não foi possível ler os contornos da fonte.');
    end;
  end;
  function Pt(Index:Integer):TCadVec2;
  var F:TFixedPoint;Offset:SizeInt;
  begin
    Offset:=CurvePos+SizeOf(C)+Index*SizeOf(F);
    if Offset+SizeOf(F)>EndPos then raise Exception.Create('Contorno de fonte inválido.');
    Move(Buffer[Offset],F,SizeOf(F));Result:=V2(X+F.X/65536*Scale,Y+F.Y/65536*Scale);
  end;
  function Kerning(Left,Right:Word):Double;
  var N:Integer;
  begin
    Result:=0;for N:=0 to High(Kerns) do
      if (Kerns[N].wFirst=Left) and (Kerns[N].wSecond=Right) then Exit(Kerns[N].iKernAmount*Scale);
  end;
begin
  DC:=CreateCompatibleDC(0);if DC=0 then raise Exception.Create('Não foi possível abrir o serviço de fontes.');
  Font:=0;OldFont:=0;
  try
    Face:=UTF8Decode(P.FontName);
    I:=FW_NORMAL;if P.Bold then I:=FW_BOLD;
    Font:=CreateFontW(-4096,0,0,0,I,Ord(P.Italic),0,0,DEFAULT_CHARSET,
      OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,PWideChar(Face));
    if Font=0 then raise Exception.Create('Não foi possível abrir a fonte.');
    OldFont:=SelectObject(DC,Font);
    M:=Default(TMAT2);M.eM11.value:=1;M.eM22.value:=1;
    Outline(Ord('H'),False);if GM.gmBlackBoxY=0 then raise Exception.Create('Fonte sem altura de letras.');
    Scale:=P.Height/GM.gmBlackBoxY;
    NK:=GetKerningPairsW(DC,0,nil);SetLength(Kerns,NK);
    if NK>0 then begin NK:=GetKerningPairsW(DC,NK,@Kerns[0]);SetLength(Kerns,NK);end;
    U:=UTF8Decode(StringReplace(P.Text,#13,'',[rfReplaceAll]));
    SetLength(Indices,Length(U));
    if GetGlyphIndicesW(DC,PWideChar(U),Length(U),@Indices[0],1)=GDI_ERROR then
      raise Exception.Create('Não foi possível ler os caracteres da fonte.');
    for I:=1 to Length(U) do
      if (U[I]<>#10) and ((Indices[I-1]=$FFFF) or ((Ord(U[I])>=$D800) and (Ord(U[I])<=$DFFF))) then
        raise Exception.Create('A fonte não contém um dos caracteres informados. Escolha outra fonte.');
    LineStart:=1;Y:=0;
    while LineStart<=Length(U) do begin
      LineEnd:=LineStart;while (LineEnd<=Length(U)) and (U[LineEnd]<>#10) do Inc(LineEnd);
      X:=0;FirstPath:=Length(B.Paths);
      for I:=LineStart to LineEnd-1 do begin
        Code:=Ord(U[I]);
        if I>LineStart then X:=X+Kerning(Ord(U[I-1]),Code);
        Outline(Code,True);Advance:=GM.gmCellIncX*Scale;
        Posn:=0;Size:=Length(Buffer);
        while Posn<Size do begin
          if Posn+SizeOf(H)>Size then raise Exception.Create('Contorno de fonte truncado.');
          Move(Buffer[Posn],H,SizeOf(H));EndPos:=Posn+H.Bytes;
          if (H.Kind<>24) or (H.Bytes<SizeOf(H)) or (EndPos>Size) then raise Exception.Create('Contorno de fonte inválido.');
          A:=V2(X+H.Start.X/65536*Scale,Y+H.Start.Y/65536*Scale);B.Point(A);
          CurvePos:=Posn+SizeOf(H);
          while CurvePos<EndPos do begin
            if CurvePos+SizeOf(C)>EndPos then raise Exception.Create('Curva de fonte truncada.');
            Move(Buffer[CurvePos],C,SizeOf(C));
            if (C.Count=0) or (CurvePos+SizeOf(C)+C.Count*SizeOf(TFixedPoint)>EndPos) then
              raise Exception.Create('Curva de fonte inválida.');
            case C.Kind of
              1: for J:=0 to C.Count-1 do begin A:=Pt(J);B.Point(A);end;
              2: for J:=0 to C.Count-2 do begin
                Q:=Pt(J);R:=Pt(J+1);if J<C.Count-2 then R:=Mid(Q,R);
                B.Quad(A,Q,R);A:=R;
              end;
              3: begin
                if C.Count mod 3<>0 then raise Exception.Create('Curva cúbica inválida.');
                J:=0;while J<C.Count do begin Q:=Pt(J);R:=Pt(J+1);Z:=Pt(J+2);B.Cubic(A,Q,R,Z);A:=Z;Inc(J,3);end;
              end;
            else raise Exception.Create('Tipo de curva de fonte não suportado.');end;
            Inc(CurvePos,SizeOf(C)+C.Count*SizeOf(TFixedPoint));
          end;
          B.Close;Posn:=EndPos;
        end;
        X:=X+Advance;
      end;
      Shift:=0;if P.Alignment=taCenter then Shift:=-X/2 else if P.Alignment=taRight then Shift:=-X;
      for J:=FirstPath to High(B.Paths) do for K:=0 to High(B.Paths[J]) do B.Paths[J][K].X:=B.Paths[J][K].X+Shift;
      Y:=Y-P.Height*1.5;LineStart:=LineEnd+1;
    end;
  finally
    if OldFont<>0 then SelectObject(DC,OldFont);
    if Font<>0 then DeleteObject(Font);DeleteDC(DC);
  end;
end;
{$ELSE}
type
  TCairoExtents=record XB,YB,Width,Height,XAdvance,YAdvance:Double;end;
  TCairoPathData=record case Byte of
    0:(Kind,Len:LongInt);
    1:(X,Y:Double);
  end;
  PCairoPathData=^TCairoPathData;
  TCairoPath=record Status:LongInt;Data:PCairoPathData;Count:LongInt;end;
  PCairoPath=^TCairoPath;
function cairo_image_surface_create(Format,W,H:LongInt):Pointer;cdecl;external 'libcairo.so.2';
function cairo_create(Surface:Pointer):Pointer;cdecl;external 'libcairo.so.2';
procedure cairo_destroy(Cr:Pointer);cdecl;external 'libcairo.so.2';
procedure cairo_surface_destroy(Surface:Pointer);cdecl;external 'libcairo.so.2';
procedure cairo_select_font_face(Cr:Pointer;Family:PChar;Slant,Weight:LongInt);cdecl;external 'libcairo.so.2';
procedure cairo_set_font_size(Cr:Pointer;Size:Double);cdecl;external 'libcairo.so.2';
procedure cairo_set_tolerance(Cr:Pointer;Tol:Double);cdecl;external 'libcairo.so.2';
procedure cairo_text_extents(Cr:Pointer;Text:PChar;var Ext:TCairoExtents);cdecl;external 'libcairo.so.2';
procedure cairo_move_to(Cr:Pointer;X,Y:Double);cdecl;external 'libcairo.so.2';
procedure cairo_text_path(Cr:Pointer;Text:PChar);cdecl;external 'libcairo.so.2';
function cairo_copy_path_flat(Cr:Pointer):PCairoPath;cdecl;external 'libcairo.so.2';
procedure cairo_path_destroy(Path:PCairoPath);cdecl;external 'libcairo.so.2';
procedure cairo_new_path(Cr:Pointer);cdecl;external 'libcairo.so.2';
procedure UnixOutlines(const P:TCadTextSettings;B:TOutlineBuilder);
var Surface,Cr:Pointer;Path:PCairoPath;E:TCairoExtents;Scale,Y,X:Double;I,Start,Stop:Integer;Line,Text:string;
begin
  Surface:=cairo_image_surface_create(0,1,1);Cr:=cairo_create(Surface);
  try
    cairo_select_font_face(Cr,PChar(P.FontName),Ord(P.Italic),Ord(P.Bold));
    cairo_set_font_size(Cr,4096);cairo_text_extents(Cr,'H',E);
    if E.Height<=0 then raise Exception.Create('Fonte sem altura de letras.');
    Scale:=P.Height/E.Height;cairo_set_tolerance(Cr,B.Tol/Scale);
    Text:=StringReplace(P.Text,#13,'',[rfReplaceAll]);Start:=1;Y:=0;
    while Start<=Length(Text) do begin
      Stop:=Start;while (Stop<=Length(Text)) and (Text[Stop]<>#10) do Inc(Stop);
      Line:=Copy(Text,Start,Stop-Start);cairo_text_extents(Cr,PChar(Line),E);X:=0;
      if P.Alignment=taCenter then X:=-E.XAdvance/2 else if P.Alignment=taRight then X:=-E.XAdvance;
      cairo_new_path(Cr);cairo_move_to(Cr,X,Y);cairo_text_path(Cr,PChar(Line));Path:=cairo_copy_path_flat(Cr);
      if Path=nil then raise Exception.Create('Não foi possível ler os contornos da fonte.');
      try
        if Path^.Status<>0 then raise Exception.Create('Não foi possível ler os contornos da fonte.');
        I:=0;while I<Path^.Count do begin
          case Path^.Data[I].Kind of
            0: begin B.Close;B.Point(V2(Path^.Data[I+1].X*Scale,-Path^.Data[I+1].Y*Scale));end;
            1: B.Point(V2(Path^.Data[I+1].X*Scale,-Path^.Data[I+1].Y*Scale));
            3: B.Close;
          else raise Exception.Create('Curva de fonte inválida.');end;
          Inc(I,Path^.Data[I].Len);
        end;B.Close;
      finally cairo_path_destroy(Path);end;
      Y:=Y+P.Height*1.5/Scale;Start:=Stop+1;
    end;
  finally cairo_destroy(Cr);cairo_surface_destroy(Surface);end;
end;
{$ENDIF}
function CadFontOutlines(const P: TCadTextSettings;
  out Paths: TCadTextContours; out Error: string): Boolean;
var B:TOutlineBuilder;I,J:Integer;X,Y,C,S:Double;
begin
  Result:=False;Paths:=nil;Error:=ValidateSketchText(P);if Error<>'' then Exit;
  B:=TOutlineBuilder.Create;B.Tol:=Math.Min(0.01,P.Height/2000);
  try
    try
      {$IFDEF MSWINDOWS}WindowsOutlines(P,B);{$ELSE}UnixOutlines(P,B);{$ENDIF}
      B.Paths:=CadCleanTextContours(B.Paths);
      if Length(B.Paths)=0 then raise Exception.Create('O texto não contém contornos vetoriais.');
      C:=Cos(DegToRad(P.Angle));S:=Sin(DegToRad(P.Angle));
      for I:=0 to High(B.Paths) do for J:=0 to High(B.Paths[I]) do begin
        X:=B.Paths[I][J].X;Y:=B.Paths[I][J].Y;
        B.Paths[I][J]:=V2(P.Origin.X+X*C-Y*S,P.Origin.Y+X*S+Y*C);
      end;
      Paths:=B.Paths;Result:=True;
    except on E:Exception do Error:=E.Message;end;
  finally B.Free;end;
end;
end.
