unit multicad_document;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multicad_feature,multicad_sketch;
type TCadDocument=class
 private FFeatures:TList;
 public Name,FileName:string;Modified:Boolean;constructor Create;destructor Destroy;override;
  procedure Clear;function AddSketch(const AName:string):TCadSketch;procedure AddFeature(F:TCadFeature);function Count:Integer;function Feature(I:Integer):TCadFeature;
 end;
implementation
constructor TCadDocument.Create;begin inherited;FFeatures:=TList.Create;Name:='Novo projeto';end;
destructor TCadDocument.Destroy;begin Clear;FFeatures.Free;inherited;end;
procedure TCadDocument.Clear;var I:Integer;begin for I:=FFeatures.Count-1 downto 0 do TObject(FFeatures[I]).Free;FFeatures.Clear;Modified:=False;end;
procedure TCadDocument.AddFeature(F:TCadFeature);begin FFeatures.Add(F);Modified:=True;end;
function TCadDocument.AddSketch(const AName:string):TCadSketch;begin Result:=TCadSketch.Create(AName);AddFeature(Result);end;
function TCadDocument.Count:Integer;begin Result:=FFeatures.Count;end;
function TCadDocument.Feature(I:Integer):TCadFeature;begin Result:=TCadFeature(FFeatures[I]);end;
end.
