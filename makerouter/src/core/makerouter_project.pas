unit makerouter_project;

{ Projeto do MakeRouter: material, ferramentas, formas (vetores) e percursos.

  - As formas sao parametricas (retangulo, circulo, elipse, poligono, estrela,
    polilinha, texto) e sao a fonte da verdade: cada percurso guarda os Ids
    das formas e fica "desatualizado" (Dirty) quando uma delas muda.
  - Arquivo .mrouter: JSON versionado ("format": "makerouter", "version": 1).
  - Zero virtual: DatumPoint / ToOutput convertem do espaco do projeto (origem
    no canto inferior esquerdo, Z = 0 no topo) para o espaco do G-code. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, laserpcb_geom, makerouter_types;

type
  TMRShapeKind = (skRect, skCircle, skEllipse, skPolygon, skStar, skPolyline, skText);

  TMRShape = class
  public
    Id: Integer;
    Kind: TMRShapeKind;
    Name: string;
    X, Y: Double;          { centro (texto: base esquerda) }
    W, H: Double;          { retangulo e elipse }
    Radius: Double;        { circulo, poligono e estrela (externo) }
    Corner: Double;        { raio dos cantos do retangulo }
    Sides: Integer;        { poligono e pontas da estrela }
    Inner: Double;         { estrela: raio interno / externo }
    Rotation: Double;      { graus, anti-horario, em torno de (X, Y) }
    Text: string;
    TextHeight: Double;
    Points: TLPPath;       { polilinha (coordenadas absolutas) }
    Closed: Boolean;       { polilinha fechada }
    constructor Create(AKind: TMRShapeKind);
    procedure Assign(S: TMRShape);
    function KindName: string;
    function Caption: string;
    { geometria em mm; fechadas repetem o primeiro ponto }
    function Paths(Tol: Double = 0.01): TLPPaths;
    function IsClosed: Boolean;
    function Bounds: TLPRect;
    procedure MoveBy(DX, DY: Double);
  end;

  TMRMove = record
    X, Y, Z: Double;
    Rapid: Boolean;
    F: Double;             { avanco do G1 (mm/min) }
  end;
  TMRMoves = array of TMRMove;

  TMRToolpath = class
  public
    Id: Integer;
    Name: string;
    Kind: TMRToolpathKind;
    Enabled: Boolean;
    Tool: Integer;              { indice em Project.Tools }
    ShapeIds: array of Integer;
    Depth: Double;              { profundidade final (mm, positiva) }
    StartDepth: Double;         { comeca abaixo do topo (mm) }
    Side: TMRProfileSide;
    Direction: TMRCutDirection;
    Tabs: Integer;              { pontes por contorno (perfil por fora/dentro) }
    TabWidth, TabHeight: Double;
    Ramp: Boolean;              { entrada em rampa ao longo do caminho }
    Allowance: Double;          { sobremetal (mm) }
    PeckDepth: Double;          { furacao: bicada (0 = direto) }
    Moves: TMRMoves;            { calculado (espaco do projeto) }
    Dirty: Boolean;
    Warnings: string;
    constructor Create(AKind: TMRToolpathKind);
    function UsesShape(AId: Integer): Boolean;
    procedure RemoveShape(AId: Integer);
    function Caption: string;
  end;

  TMRProject = class
  private
    FShapes, FToolpaths: TList;
    FNextId: Integer;
    function GetShape(I: Integer): TMRShape;
    function GetToolpath(I: Integer): TMRToolpath;
  public
    Name: string;
    FileName: string;
    Material: TMRMaterial;
    Tools: TMRTools;
    Modified: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function NewId: Integer;
    { formas }
    function ShapeCount: Integer;
    property Shapes[I: Integer]: TMRShape read GetShape;
    function AddShape(S: TMRShape): TMRShape;
    function ShapeById(AId: Integer): TMRShape;
    function ShapeIndex(AId: Integer): Integer;
    procedure DeleteShape(AId: Integer);
    procedure ShapeChanged(AId: Integer);
    { percursos }
    function ToolpathCount: Integer;
    property Toolpaths[I: Integer]: TMRToolpath read GetToolpath;
    function AddToolpath(T: TMRToolpath): TMRToolpath;
    procedure DeleteToolpath(I: Integer);
    procedure MoveToolpath(I, Delta: Integer);
    procedure MarkAllDirty;
    { ferramentas }
    function ToolIndexByName(const N: string): Integer;
    { zero virtual }
    function DatumPoint: TLPPoint;       { ponto de zero XY no espaco do projeto }
    function DatumZOffset: Double;       { Z do zero no espaco do projeto }
    function ToOutput(const M: TMRMove): TMRMove;
    { arquivo }
    function ToJSON: string;
    procedure FromJSON(const S: string);
    procedure SaveToFile(const FN: string);
    procedure LoadFromFile(const FN: string);
  end;

{ projeto de exemplo: placa 300 x 200 x 18 com texto gravado, bolsao
  arredondado, 4 furos e o contorno com pontes }
procedure MRLoadExample(P: TMRProject);

implementation

uses makepcb_model, makepcb_font;

var
  InvFS: TFormatSettings;

{ ---------------- TMRShape ---------------- }

constructor TMRShape.Create(AKind: TMRShapeKind);
begin
  inherited Create;
  Kind := AKind;
  W := 50; H := 30; Radius := 20; Sides := 6; Inner := 0.5;
  TextHeight := 20; Text := 'MakeRouter'; Closed := True;
end;

procedure TMRShape.Assign(S: TMRShape);
begin
  Kind := S.Kind; Name := S.Name; X := S.X; Y := S.Y; W := S.W; H := S.H;
  Radius := S.Radius; Corner := S.Corner; Sides := S.Sides; Inner := S.Inner;
  Rotation := S.Rotation; Text := S.Text; TextHeight := S.TextHeight;
  Points := Copy(S.Points); Closed := S.Closed;
end;

function TMRShape.KindName: string;
const N: array[TMRShapeKind] of string = ('Retangulo', 'Circulo', 'Elipse', 'Poligono',
  'Estrela', 'Polilinha', 'Texto');
begin
  Result := N[Kind];
end;

function TMRShape.Caption: string;
begin
  if Name <> '' then Result := Name
  else if Kind = skText then Result := 'Texto "' + Text + '"'
  else Result := KindName + ' ' + IntToStr(Id);
end;

function TMRShape.IsClosed: Boolean;
begin
  case Kind of
    skText: Result := False;
    skPolyline: Result := Closed and (Length(Points) >= 3);
  else
    Result := True;
  end;
end;

function TMRShape.Paths(Tol: Double): TLPPaths;
var P: TLPPath; I, N, K: Integer; A, R, CR, HW, HH, CA, SA: Double;
  St: TMPStrokes;
  procedure Arc(CX, CY, Rad, A0, A1: Double);
  var J, M: Integer; T: Double;
  begin
    M := Max(2, LPArcSegments(Rad, Abs(A1 - A0), Tol));
    for J := 0 to M do
    begin
      T := A0 + (A1 - A0) * J / M;
      LPAddPoint(P, CX + Rad * Cos(T), CY + Rad * Sin(T));
    end;
  end;
  procedure Rot(var Q: TLPPath);
  var J: Integer; DX, DY: Double;
  begin
    if Abs(Rotation) < 1e-9 then Exit;
    CA := Cos(DegToRad(Rotation)); SA := Sin(DegToRad(Rotation));
    for J := 0 to High(Q) do
    begin
      DX := Q[J].X - X; DY := Q[J].Y - Y;
      Q[J].X := X + DX * CA - DY * SA;
      Q[J].Y := Y + DX * SA + DY * CA;
    end;
  end;
begin
  Result := nil;
  P := nil;
  if Tol <= 0 then Tol := 0.01;
  case Kind of
    skRect:
      begin
        HW := Abs(W) / 2; HH := Abs(H) / 2;
        CR := Max(0, Min(Corner, Min(HW, HH)));
        if CR < 1e-6 then
        begin
          LPAddPoint(P, X - HW, Y - HH); LPAddPoint(P, X + HW, Y - HH);
          LPAddPoint(P, X + HW, Y + HH); LPAddPoint(P, X - HW, Y + HH);
        end
        else
        begin
          Arc(X + HW - CR, Y - HH + CR, CR, -Pi / 2, 0);
          Arc(X + HW - CR, Y + HH - CR, CR, 0, Pi / 2);
          Arc(X - HW + CR, Y + HH - CR, CR, Pi / 2, Pi);
          Arc(X - HW + CR, Y - HH + CR, CR, Pi, 3 * Pi / 2);
        end;
      end;
    skCircle:
      P := Copy(LPCircle(X, Y, Max(0.01, Abs(Radius)), Tol));
    skEllipse:
      begin
        HW := Max(0.01, Abs(W) / 2); HH := Max(0.01, Abs(H) / 2);
        N := Max(16, LPArcSegments(Max(HW, HH), 2 * Pi, Tol));
        for I := 0 to N - 1 do
        begin
          A := 2 * Pi * I / N;
          LPAddPoint(P, X + HW * Cos(A), Y + HH * Sin(A));
        end;
      end;
    skPolygon:
      begin
        N := Max(3, Sides); R := Max(0.01, Abs(Radius));
        for I := 0 to N - 1 do
        begin
          A := Pi / 2 + 2 * Pi * I / N;
          LPAddPoint(P, X + R * Cos(A), Y + R * Sin(A));
        end;
      end;
    skStar:
      begin
        N := Max(3, Sides); R := Max(0.01, Abs(Radius));
        for I := 0 to 2 * N - 1 do
        begin
          A := Pi / 2 + Pi * I / N;
          if Odd(I) then CR := R * EnsureRange(Inner, 0.05, 0.95) else CR := R;
          LPAddPoint(P, X + CR * Cos(A), Y + CR * Sin(A));
        end;
      end;
    skPolyline:
      begin
        P := Copy(Points);
        if Length(P) < 2 then Exit;
        if IsClosed and (LPDist(P[0], P[High(P)]) > 1e-9) then LPAddPoint(P, P[0].X, P[0].Y);
        if not IsClosed then begin LPAddPath(Result, P); Exit; end;
        LPAddPath(Result, P);
        Exit;
      end;
    skText:
      begin
        St := MPTextStrokes(Text, X, Y, Max(0.5, TextHeight));
        for I := 0 to High(St) do
        begin
          P := nil;
          for K := 0 to High(St[I]) do LPAddPoint(P, St[I][K].X, St[I][K].Y);
          Rot(P);
          if Length(P) >= 2 then LPAddPath(Result, P);
        end;
        Exit;
      end;
  end;
  if Length(P) < 2 then Exit;
  LPAddPoint(P, P[0].X, P[0].Y);
  Rot(P);
  LPAddPath(Result, P);
end;

function TMRShape.Bounds: TLPRect;
begin
  Result := LPPathsBounds(Paths(0.05));
end;

procedure TMRShape.MoveBy(DX, DY: Double);
var I: Integer;
begin
  X := X + DX; Y := Y + DY;
  for I := 0 to High(Points) do
  begin
    Points[I].X := Points[I].X + DX;
    Points[I].Y := Points[I].Y + DY;
  end;
end;

{ ---------------- TMRToolpath ---------------- }

constructor TMRToolpath.Create(AKind: TMRToolpathKind);
begin
  inherited Create;
  Kind := AKind;
  Enabled := True;
  Depth := 3;
  Side := psOutside;
  Direction := cdClimb;
  TabWidth := 6; TabHeight := 2;
  Ramp := True;
  Dirty := True;
  Name := MR_TOOLPATH_NAMES[AKind];
end;

function TMRToolpath.UsesShape(AId: Integer): Boolean;
var I: Integer;
begin
  for I := 0 to High(ShapeIds) do if ShapeIds[I] = AId then Exit(True);
  Result := False;
end;

procedure TMRToolpath.RemoveShape(AId: Integer);
var I, K: Integer;
begin
  K := 0;
  for I := 0 to High(ShapeIds) do
    if ShapeIds[I] <> AId then begin ShapeIds[K] := ShapeIds[I]; Inc(K); end;
  if K <> Length(ShapeIds) then Dirty := True;
  SetLength(ShapeIds, K);
end;

function TMRToolpath.Caption: string;
begin
  Result := Name;
  if Dirty then Result := Result + ' (recalcular)';
end;

{ ---------------- TMRProject ---------------- }

constructor TMRProject.Create;
begin
  inherited Create;
  FShapes := TList.Create;
  FToolpaths := TList.Create;
  Clear;
end;

destructor TMRProject.Destroy;
begin
  Clear;
  FShapes.Free;
  FToolpaths.Free;
  inherited Destroy;
end;

procedure TMRProject.Clear;
var I: Integer;
begin
  for I := 0 to FShapes.Count - 1 do TObject(FShapes[I]).Free;
  for I := 0 to FToolpaths.Count - 1 do TObject(FToolpaths[I]).Free;
  FShapes.Clear; FToolpaths.Clear;
  FNextId := 1;
  Name := 'Novo projeto';
  FileName := '';
  Material := MRDefaultMaterial;
  Tools := MRDefaultTools;
  Modified := False;
end;

function TMRProject.NewId: Integer;
begin
  Result := FNextId;
  Inc(FNextId);
end;

function TMRProject.GetShape(I: Integer): TMRShape;
begin
  Result := TMRShape(FShapes[I]);
end;

function TMRProject.GetToolpath(I: Integer): TMRToolpath;
begin
  Result := TMRToolpath(FToolpaths[I]);
end;

function TMRProject.ShapeCount: Integer;
begin
  Result := FShapes.Count;
end;

function TMRProject.AddShape(S: TMRShape): TMRShape;
begin
  if S.Id <= 0 then S.Id := NewId else FNextId := Max(FNextId, S.Id + 1);
  FShapes.Add(S);
  Modified := True;
  Result := S;
end;

function TMRProject.ShapeIndex(AId: Integer): Integer;
var I: Integer;
begin
  for I := 0 to FShapes.Count - 1 do if Shapes[I].Id = AId then Exit(I);
  Result := -1;
end;

function TMRProject.ShapeById(AId: Integer): TMRShape;
var I: Integer;
begin
  I := ShapeIndex(AId);
  if I < 0 then Result := nil else Result := Shapes[I];
end;

procedure TMRProject.DeleteShape(AId: Integer);
var I: Integer;
begin
  I := ShapeIndex(AId);
  if I < 0 then Exit;
  Shapes[I].Free;
  FShapes.Delete(I);
  for I := 0 to ToolpathCount - 1 do Toolpaths[I].RemoveShape(AId);
  Modified := True;
end;

procedure TMRProject.ShapeChanged(AId: Integer);
var I: Integer;
begin
  for I := 0 to ToolpathCount - 1 do
    if Toolpaths[I].UsesShape(AId) then Toolpaths[I].Dirty := True;
  Modified := True;
end;

function TMRProject.ToolpathCount: Integer;
begin
  Result := FToolpaths.Count;
end;

function TMRProject.AddToolpath(T: TMRToolpath): TMRToolpath;
begin
  if T.Id <= 0 then T.Id := NewId else FNextId := Max(FNextId, T.Id + 1);
  FToolpaths.Add(T);
  Modified := True;
  Result := T;
end;

procedure TMRProject.DeleteToolpath(I: Integer);
begin
  if (I < 0) or (I >= ToolpathCount) then Exit;
  Toolpaths[I].Free;
  FToolpaths.Delete(I);
  Modified := True;
end;

procedure TMRProject.MoveToolpath(I, Delta: Integer);
var J: Integer;
begin
  J := I + Delta;
  if (I < 0) or (I >= ToolpathCount) or (J < 0) or (J >= ToolpathCount) then Exit;
  FToolpaths.Exchange(I, J);
  Modified := True;
end;

procedure TMRProject.MarkAllDirty;
var I: Integer;
begin
  for I := 0 to ToolpathCount - 1 do Toolpaths[I].Dirty := True;
end;

function TMRProject.ToolIndexByName(const N: string): Integer;
var I: Integer;
begin
  for I := 0 to High(Tools) do if SameText(Tools[I].Name, N) then Exit(I);
  Result := -1;
end;

function TMRProject.DatumPoint: TLPPoint;
var C, R: Integer;
begin
  C := Ord(Material.DatumXY) mod 3;   { 0 esquerda, 1 centro, 2 direita }
  R := Ord(Material.DatumXY) div 3;   { 0 baixo, 1 meio, 2 cima }
  Result := LPPoint(Material.Width * C / 2, Material.Height * R / 2);
end;

function TMRProject.DatumZOffset: Double;
begin
  if Material.DatumZ = dzTable then Result := -Material.Thickness else Result := 0;
end;

function TMRProject.ToOutput(const M: TMRMove): TMRMove;
var D: TLPPoint;
begin
  D := DatumPoint;
  Result := M;
  Result.X := M.X - D.X;
  Result.Y := M.Y - D.Y;
  Result.Z := M.Z - DatumZOffset;
end;

{ ---------------- JSON ---------------- }

function TMRProject.ToJSON: string;
var Root, O: TJSONObject; A, Pts, Ids: TJSONArray; I, J: Integer; S: TMRShape;
  T: TMRToolpath;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', 'makerouter');
    Root.Add('version', 1);
    Root.Add('name', Name);
    O := TJSONObject.Create;
    O.Add('width', Material.Width); O.Add('height', Material.Height);
    O.Add('thickness', Material.Thickness);
    O.Add('datumXY', MR_DATUM_CODES[Material.DatumXY]);
    O.Add('datumZ', MR_DATUMZ_CODES[Material.DatumZ]);
    O.Add('safeZ', Material.SafeZ); O.Add('travelZ', Material.TravelZ);
    O.Add('spinUp', Material.SpinUpSeconds); O.Add('visual', Material.Visual);
    Root.Add('material', O);
    A := TJSONArray.Create;
    for I := 0 to High(Tools) do
    begin
      O := TJSONObject.Create;
      O.Add('name', Tools[I].Name); O.Add('kind', Ord(Tools[I].Kind));
      O.Add('diameter', Tools[I].Diameter); O.Add('angle', Tools[I].Angle);
      O.Add('stepDown', Tools[I].StepDown); O.Add('stepOver', Tools[I].StepOver);
      O.Add('feed', Tools[I].Feed); O.Add('plunge', Tools[I].Plunge); O.Add('rpm', Tools[I].RPM);
      A.Add(O);
    end;
    Root.Add('tools', A);
    A := TJSONArray.Create;
    for I := 0 to ShapeCount - 1 do
    begin
      S := Shapes[I];
      O := TJSONObject.Create;
      O.Add('id', S.Id); O.Add('kind', Ord(S.Kind)); O.Add('name', S.Name);
      O.Add('x', S.X); O.Add('y', S.Y); O.Add('w', S.W); O.Add('h', S.H);
      O.Add('radius', S.Radius); O.Add('corner', S.Corner); O.Add('sides', S.Sides);
      O.Add('inner', S.Inner); O.Add('rotation', S.Rotation);
      O.Add('text', S.Text); O.Add('textHeight', S.TextHeight); O.Add('closed', S.Closed);
      if Length(S.Points) > 0 then
      begin
        Pts := TJSONArray.Create;
        for J := 0 to High(S.Points) do
        begin
          Pts.Add(S.Points[J].X); Pts.Add(S.Points[J].Y);
        end;
        O.Add('points', Pts);
      end;
      A.Add(O);
    end;
    Root.Add('shapes', A);
    A := TJSONArray.Create;
    for I := 0 to ToolpathCount - 1 do
    begin
      T := Toolpaths[I];
      O := TJSONObject.Create;
      O.Add('id', T.Id); O.Add('name', T.Name); O.Add('kind', Ord(T.Kind));
      O.Add('enabled', T.Enabled); O.Add('tool', T.Tool);
      Ids := TJSONArray.Create;
      for J := 0 to High(T.ShapeIds) do Ids.Add(T.ShapeIds[J]);
      O.Add('shapes', Ids);
      O.Add('depth', T.Depth); O.Add('startDepth', T.StartDepth);
      O.Add('side', Ord(T.Side)); O.Add('direction', Ord(T.Direction));
      O.Add('tabs', T.Tabs); O.Add('tabWidth', T.TabWidth); O.Add('tabHeight', T.TabHeight);
      O.Add('ramp', T.Ramp); O.Add('allowance', T.Allowance); O.Add('peck', T.PeckDepth);
      A.Add(O);
    end;
    Root.Add('toolpaths', A);
    Result := Root.FormatJSON;
  finally
    Root.Free;
  end;
end;

function Num(O: TJSONObject; const K: string; Def: Double): Double;
var D: TJSONData;
begin
  D := O.Find(K);
  if (D <> nil) and (D.JSONType = jtNumber) then Result := D.AsFloat else Result := Def;
  if not MRFinite(Result) then Result := Def;
end;

function Int(O: TJSONObject; const K: string; Def, Lo, Hi: Integer): Integer;
var D: TJSONData;
begin
  D := O.Find(K);
  if (D <> nil) and (D.JSONType = jtNumber) then Result := D.AsInteger else Result := Def;
  Result := EnsureRange(Result, Lo, Hi);
end;

function Str(O: TJSONObject; const K, Def: string): string;
var D: TJSONData;
begin
  D := O.Find(K);
  if (D <> nil) and (D.JSONType = jtString) then Result := D.AsString else Result := Def;
end;

function Bool(O: TJSONObject; const K: string; Def: Boolean): Boolean;
var D: TJSONData;
begin
  D := O.Find(K);
  if (D <> nil) and (D.JSONType = jtBoolean) then Result := D.AsBoolean else Result := Def;
end;

procedure TMRProject.FromJSON(const S: string);
var Data: TJSONData; Root, O: TJSONObject; A, Pts, Ids: TJSONArray; I, J: Integer;
  Sh: TMRShape; T: TMRToolpath; Code: string; D: TMRDatumXY;
begin
  Data := GetJSON(S);
  try
    if not (Data is TJSONObject) then raise Exception.Create('Arquivo .mrouter invalido');
    Root := TJSONObject(Data);
    if Str(Root, 'format', '') <> 'makerouter' then raise Exception.Create('Nao e um projeto do MakeRouter');
    if Int(Root, 'version', 1, 0, MaxInt) > 1 then raise Exception.Create('Projeto de versao mais nova do MakeRouter');
    Clear;
    Name := Str(Root, 'name', 'Projeto');
    O := Root.Find('material') as TJSONObject;
    if O <> nil then
    begin
      Material.Width := Num(O, 'width', Material.Width);
      Material.Height := Num(O, 'height', Material.Height);
      Material.Thickness := Num(O, 'thickness', Material.Thickness);
      Code := Str(O, 'datumXY', 'BL');
      for D := Low(TMRDatumXY) to High(TMRDatumXY) do
        if MR_DATUM_CODES[D] = Code then Material.DatumXY := D;
      if Str(O, 'datumZ', 'TOP') = 'TABLE' then Material.DatumZ := dzTable else Material.DatumZ := dzTop;
      Material.SafeZ := Num(O, 'safeZ', Material.SafeZ);
      Material.TravelZ := Num(O, 'travelZ', Material.TravelZ);
      Material.SpinUpSeconds := Num(O, 'spinUp', Material.SpinUpSeconds);
      Material.Visual := Int(O, 'visual', 0, 0, High(MR_WOODS));
    end;
    A := Root.Find('tools') as TJSONArray;
    if (A <> nil) and (A.Count > 0) then
    begin
      SetLength(Tools, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        Tools[I] := MRDefaultTool(TMRToolKind(Int(O, 'kind', 0, 0, Ord(High(TMRToolKind)))));
        Tools[I].Name := Str(O, 'name', Tools[I].Name);
        Tools[I].Diameter := Num(O, 'diameter', Tools[I].Diameter);
        Tools[I].Angle := Num(O, 'angle', Tools[I].Angle);
        Tools[I].StepDown := Num(O, 'stepDown', Tools[I].StepDown);
        Tools[I].StepOver := Num(O, 'stepOver', Tools[I].StepOver);
        Tools[I].Feed := Num(O, 'feed', Tools[I].Feed);
        Tools[I].Plunge := Num(O, 'plunge', Tools[I].Plunge);
        Tools[I].RPM := Num(O, 'rpm', Tools[I].RPM);
      end;
    end;
    A := Root.Find('shapes') as TJSONArray;
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        Sh := TMRShape.Create(TMRShapeKind(Int(O, 'kind', 0, 0, Ord(High(TMRShapeKind)))));
        Sh.Id := Int(O, 'id', 0, 0, MaxInt);
        Sh.Name := Str(O, 'name', '');
        Sh.X := Num(O, 'x', 0); Sh.Y := Num(O, 'y', 0);
        Sh.W := Num(O, 'w', Sh.W); Sh.H := Num(O, 'h', Sh.H);
        Sh.Radius := Num(O, 'radius', Sh.Radius); Sh.Corner := Num(O, 'corner', 0);
        Sh.Sides := Int(O, 'sides', 6, 3, 200); Sh.Inner := Num(O, 'inner', 0.5);
        Sh.Rotation := Num(O, 'rotation', 0);
        Sh.Text := Str(O, 'text', ''); Sh.TextHeight := Num(O, 'textHeight', 20);
        Sh.Closed := Bool(O, 'closed', True);
        Pts := O.Find('points') as TJSONArray;
        if Pts <> nil then
          for J := 0 to Pts.Count div 2 - 1 do
            LPAddPoint(Sh.Points, Pts.Items[2 * J].AsFloat, Pts.Items[2 * J + 1].AsFloat);
        AddShape(Sh);
      end;
    A := Root.Find('toolpaths') as TJSONArray;
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        T := TMRToolpath.Create(TMRToolpathKind(Int(O, 'kind', 0, 0, Ord(High(TMRToolpathKind)))));
        T.Id := Int(O, 'id', 0, 0, MaxInt);
        T.Name := Str(O, 'name', T.Name);
        T.Enabled := Bool(O, 'enabled', True);
        T.Tool := Int(O, 'tool', 0, 0, Max(0, High(Tools)));
        Ids := O.Find('shapes') as TJSONArray;
        if Ids <> nil then
        begin
          SetLength(T.ShapeIds, Ids.Count);
          for J := 0 to Ids.Count - 1 do T.ShapeIds[J] := Ids.Items[J].AsInteger;
        end;
        T.Depth := Num(O, 'depth', T.Depth); T.StartDepth := Num(O, 'startDepth', 0);
        T.Side := TMRProfileSide(Int(O, 'side', 0, 0, Ord(High(TMRProfileSide))));
        T.Direction := TMRCutDirection(Int(O, 'direction', 0, 0, Ord(High(TMRCutDirection))));
        T.Tabs := Int(O, 'tabs', 0, 0, 100);
        T.TabWidth := Num(O, 'tabWidth', T.TabWidth); T.TabHeight := Num(O, 'tabHeight', T.TabHeight);
        T.Ramp := Bool(O, 'ramp', True); T.Allowance := Num(O, 'allowance', 0);
        T.PeckDepth := Num(O, 'peck', 0);
        AddToolpath(T);
      end;
    Modified := False;
  finally
    Data.Free;
  end;
end;

procedure TMRProject.SaveToFile(const FN: string);
var L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := ToJSON;
    L.SaveToFile(FN);
    FileName := FN;
    Modified := False;
  finally
    L.Free;
  end;
end;

procedure TMRProject.LoadFromFile(const FN: string);
var L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FN);
    FromJSON(L.Text);
    FileName := FN;
  finally
    L.Free;
  end;
end;

{ ---------------- exemplo ---------------- }

procedure MRLoadExample(P: TMRProject);
var S: TMRShape; T: TMRToolpath; Border, Pocket, Txt: Integer; I: Integer;
  Holes: array[0..3] of Integer;
const HX: array[0..3] of Double = (25, 275, 275, 25);
  HY: array[0..3] of Double = (25, 25, 175, 175);
begin
  P.Clear;
  P.Name := 'Placa exemplo';
  P.Material.Width := 320; P.Material.Height := 220; P.Material.Thickness := 18;
  { contorno da placa, com folga de 10 mm na chapa }
  S := TMRShape.Create(skRect);
  S.Name := 'Contorno'; S.X := 160; S.Y := 110; S.W := 300; S.H := 200; S.Corner := 15;
  Border := P.AddShape(S).Id;
  S := TMRShape.Create(skRect);
  S.Name := 'Bolsao'; S.X := 160; S.Y := 70; S.W := 180; S.H := 50; S.Corner := 12;
  Pocket := P.AddShape(S).Id;
  S := TMRShape.Create(skText);
  S.Name := 'Texto'; S.Text := 'MULTISUITE'; S.TextHeight := 22;
  S.X := 160 - MPTextWidth(S.Text, S.TextHeight) / 2; S.Y := 140;
  Txt := P.AddShape(S).Id;
  for I := 0 to 3 do
  begin
    S := TMRShape.Create(skCircle);
    S.Name := 'Furo ' + IntToStr(I + 1); S.X := HX[I] + 10; S.Y := HY[I] + 10; S.Radius := 2.5;
    Holes[I] := P.AddShape(S).Id;
  end;
  T := TMRToolpath.Create(tpEngrave);
  T.Name := 'Gravar texto'; T.Tool := 5; T.Depth := 1.5;
  SetLength(T.ShapeIds, 1); T.ShapeIds[0] := Txt;
  P.AddToolpath(T);
  T := TMRToolpath.Create(tpPocket);
  T.Name := 'Bolsao 6 mm'; T.Tool := 0; T.Depth := 6;
  SetLength(T.ShapeIds, 1); T.ShapeIds[0] := Pocket;
  P.AddToolpath(T);
  T := TMRToolpath.Create(tpDrill);
  T.Name := 'Furos 5 mm'; T.Tool := 4; T.Depth := 19; T.PeckDepth := 6;
  SetLength(T.ShapeIds, 4);
  for I := 0 to 3 do T.ShapeIds[I] := Holes[I];
  P.AddToolpath(T);
  T := TMRToolpath.Create(tpProfile);
  T.Name := 'Recorte com pontes'; T.Tool := 0; T.Depth := 18.5; T.Side := psOutside;
  T.Tabs := 4; T.TabWidth := 8; T.TabHeight := 3;
  SetLength(T.ShapeIds, 1); T.ShapeIds[0] := Border;
  P.AddToolpath(T);
  P.Modified := False;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
