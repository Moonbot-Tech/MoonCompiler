unit uinlinecopy1;

{$mode delphi}

interface

type
  TInlineClass = class;
  TInlineClassRef = class of TInlineClass;
  TInlineClass = class
    class function Step(Tag: LongInt): TInlineClassRef; inline;
    class function ReadValue: LongInt; inline;
  end;

function Nested(Value: LongInt): LongInt; inline;

implementation

var
  State: LongInt;

class function TInlineClass.Step(Tag: LongInt): TInlineClassRef;
begin
  State := State * 10 + Tag;
  Result := TInlineClass;
end;

class function TInlineClass.ReadValue: LongInt;
begin
  Result := State;
end;

function Nested(Value: LongInt): LongInt;
begin
  Result := Value + 2;
end;

end.
