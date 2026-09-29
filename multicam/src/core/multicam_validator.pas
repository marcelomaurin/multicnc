unit multicam_validator;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multicam_job;
type TCamValidator=class public class function Validate(J:TCamJob;Errors:TStrings):Boolean;end;
implementation
class function TCamValidator.Validate(J:TCamJob;Errors:TStrings):Boolean;
begin Errors.Clear;if J.Tool.Diameter<=0 then Errors.Add('Diametro da ferramenta invalido');if J.Tool.Feed<=0 then Errors.Add('Feed deve ser configurado');if J.Tool.Plunge<=0 then Errors.Add('Plunge deve ser configurado');if J.Tool.SpindleRPM<=0 then Errors.Add('RPM do spindle deve ser configurado');if J.Settings.StepDown<=0 then Errors.Add('Step-down invalido');if J.Settings.SafeZ<=0 then Errors.Add('Safe Z invalido');if J.Count=0 then Errors.Add('Toolpath vazio');Result:=Errors.Count=0;end;
end.
