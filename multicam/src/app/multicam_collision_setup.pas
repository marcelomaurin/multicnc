unit multicam_collision_setup;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,Forms,Controls,StdCtrls,Dialogs,multisuite_numfmt,
 multicam_types,multicam_setup,multicam_collision;
function EditCollisionSetup(var Config:TCollisionConfig; var Tool:TTool; Setup:TMechanicalSetup):Boolean;
implementation
function EditCollisionSetup(var Config:TCollisionConfig; var Tool:TTool; Setup:TMechanicalSetup):Boolean;
const Names:array[0..10]of string=('Diametro da fresa','Comprimento de corte','Diametro da haste',
 'Comprimento exposto','Diametro do porta-ferramenta','Comprimento do porta-ferramenta',
 'X inicial','Y inicial','Z inicial','Plano protegido da mesa Z','Margem de seguranca');
var D:TForm; Ed:array[0..10]of TEdit;V:array[0..10]of Double;L:TLabel;B:TButton;
 Memo:TMemo;I,N:Integer;Parts:TStringList;Temp:TMechanicalSetup;F:TFixture;Valid:Boolean;
 procedure AddButton(const Caption:string;Left,Modal:Integer);
 begin B:=TButton.Create(D);B.Parent:=D;B.Caption:=Caption;B.SetBounds(Left,530,120,32);B.ModalResult:=Modal;end;
begin
 Result:=False;D:=TForm.CreateNew(nil);Parts:=TStringList.Create;Temp:=TMechanicalSetup.Create;
 try
 D.Caption:='Montagem para colisao (mm, coordenadas de trabalho)';D.SetBounds(80,80,720,610);D.Position:=poScreenCenter;
 V[0]:=Tool.Diameter;V[1]:=Tool.FluteLength;V[2]:=Config.ShankDiameter;
 V[3]:=Config.ExposedLength;V[4]:=Config.HolderDiameter;V[5]:=Config.HolderLength;
 V[6]:=Config.InitialPosition.X;V[7]:=Config.InitialPosition.Y;V[8]:=Config.InitialPosition.Z;
 V[9]:=Config.TableZ;V[10]:=Config.Margin;
 for I:=0 to 10 do begin
 L:=TLabel.Create(D);L.Parent:=D;L.Caption:=Names[I];L.SetBounds(12,12+I*28,310,24);
 Ed[I]:=TEdit.Create(D);Ed[I].Parent:=D;Ed[I].SetBounds(325,10+I*28,150,25);Ed[I].Text:=FloatToStr(V[I],InvariantFS);
 end;
 L:=TLabel.Create(D);L.Parent:=D;L.Caption:='Fixacoes: nome;X;Y;largura;altura;baseZ;topoZ (uma por linha, ponto decimal)';L.SetBounds(12,326,690,24);
 Memo:=TMemo.Create(D);Memo.Parent:=D;Memo.SetBounds(12,352,680,140);Memo.ScrollBars:=ssAutoBoth;
 for I:=0 to Setup.FixtureCount-1 do begin F:=Setup.Fixture(I);
 Memo.Lines.Add(Format('%s;%.3f;%.3f;%.3f;%.3f;%.3f;%.3f',[F.Name,F.X,F.Y,F.W,F.H,F.BottomZ,F.TopZ],InvariantFS));end;
 L:=TLabel.Create(D);L.Parent:=D;L.Caption:='Volumes conservadores; confirmar dimensoes reais. Salvar reinicia a simulacao.';L.SetBounds(12,500,690,24);
 AddButton('Salvar',440,mrOK);AddButton('Cancelar',572,mrCancel);
 Parts.Delimiter:=';';Parts.StrictDelimiter:=True;
 while D.ShowModal=mrOK do begin
 Valid:=True;for I:=0 to 10 do if not TryStrToFloat(Ed[I].Text,V[I],InvariantFS)or IsNan(V[I])or IsInfinite(V[I])then Valid:=False;
 if not Valid then begin ShowMessage('Preencha todos os campos com numeros finitos usando ponto decimal.');Continue;end;
 if(V[0]<=0)or(V[1]<=0)or(V[2]<=0)or(V[3]<V[1])or(V[4]<=0)or(V[5]<=0)or(V[10]<0)then begin ShowMessage('Dimensoes devem ser positivas; comprimento exposto >= corte; margem >= 0.');Continue;end;
 Temp.ClearFixtures;Temp.Stock:=Setup.Stock;
 try
 for I:=0 to Memo.Lines.Count-1 do if Trim(Memo.Lines[I])<>'' then begin
 Parts.DelimitedText:=Memo.Lines[I];if Parts.Count<>7 then raise Exception.Create('Fixacao deve ter 7 campos');
 F.Name:=Trim(Parts[0]);if F.Name=''then raise Exception.Create('Informe o nome da fixacao');
 for N:=1 to 6 do if not TryStrToFloat(Parts[N],F.X,InvariantFS)or IsNan(F.X)or IsInfinite(F.X) then raise Exception.Create('Numero de fixacao invalido');
 Temp.AddFixtureVolume(F.Name,StrToFloat(Parts[1],InvariantFS),StrToFloat(Parts[2],InvariantFS),StrToFloat(Parts[3],InvariantFS),StrToFloat(Parts[4],InvariantFS),StrToFloat(Parts[5],InvariantFS),StrToFloat(Parts[6],InvariantFS));
 end;
 except on E:Exception do begin ShowMessage(E.Message);Continue;end;end;
 Tool.Diameter:=V[0];Tool.FluteLength:=V[1];Config.ShankDiameter:=V[2];Config.ExposedLength:=V[3];
 Config.HolderDiameter:=V[4];Config.HolderLength:=V[5];Config.InitialPosition.X:=V[6];Config.InitialPosition.Y:=V[7];Config.InitialPosition.Z:=V[8];Config.TableZ:=V[9];Config.Margin:=V[10];
 Setup.ClearFixtures;for I:=0 to Temp.FixtureCount-1 do begin F:=Temp.Fixture(I);Setup.AddFixtureVolume(F.Name,F.X,F.Y,F.W,F.H,F.BottomZ,F.TopZ);end;
 Result:=True;Break;
 end;
 finally Temp.Free;Parts.Free;D.Free;end;
end;
end.
