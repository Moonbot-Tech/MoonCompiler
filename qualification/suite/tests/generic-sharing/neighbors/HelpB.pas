unit HelpB; interface uses Base;
type THelp=class helper for TScope class function Tag:Integer; static; end;
implementation class function THelp.Tag:Integer; begin Result:=33; end;
end.
