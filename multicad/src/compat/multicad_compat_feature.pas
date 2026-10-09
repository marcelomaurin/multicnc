unit multicad_compat_feature;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multicad_compat_types;
type
 TCadFeature=class
 public
  ID,Name:string;Kind:TCadFeatureKind;Enabled:Boolean;ParentID:string;
  constructor Create(AKind:TCadFeatureKind;const AName:string);virtual;
 end;
implementation
constructor TCadFeature.Create(AKind:TCadFeatureKind;const AName:string);
begin inherited Create;Kind:=AKind;Name:=AName;Enabled:=True;ID:=IntToHex(PtrUInt(Self),8);end;
end.
