unit HelpDef; interface uses Base;
type THelp=class helper for TScope class function Tag:Integer; static; end;
implementation class function THelp.Tag:Integer; begin Result:=11; end;
end.
