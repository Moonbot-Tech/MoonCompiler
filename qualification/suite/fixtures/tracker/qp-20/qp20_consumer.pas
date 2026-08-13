unit qp20_consumer;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
procedure RunMap;
implementation
uses SysUtils, qp20_map;
procedure RunMap;
var Map: TMap<Integer,string>; Entry: TMap<Integer,string>.TEntry; Seen: Integer;
begin
  Map := TMap<Integer,string>.Create(7, 'seven');
  try
    Seen := 0;
    for Entry in Map do
    begin
      if (Entry.Key <> 7) or (Entry.Value <> 'seven') then
        raise Exception.Create('payload');
      Inc(Seen);
    end;
    if Seen <> 1 then raise Exception.Create('count');
  finally Map.Free; end;
end;
end.
