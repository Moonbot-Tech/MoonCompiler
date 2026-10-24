unit HelpA; interface uses Base;
type THelp=class helper for TScope class function Tag:Integer; static; end;
implementation class function THelp.Tag:Integer; begin Result:=22; end;
end.
