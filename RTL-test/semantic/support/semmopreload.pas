unit semmopreload;
{$mode delphi}{$modeswitch advancedrecords}
interface
uses semtrack;
type
  TManaged = record
    Value: Integer;
    Token: IToken;
    class operator Initialize(var Dest: TManaged);
    class operator Finalize(var Dest: TManaged);
  end;
procedure Store(var Dest: TManaged); inline;
implementation
class operator TManaged.Initialize(var Dest: TManaged);
begin
  Dest.Value := 0;
end;
class operator TManaged.Finalize(var Dest: TManaged);
begin
end;
function MakeValue: TManaged; noinline;
begin
  Result.Value := 42;
  Result.Token := TToken.Create;
end;
procedure Store(var Dest: TManaged); inline;
begin
  Dest := MakeValue;
end;
end.
