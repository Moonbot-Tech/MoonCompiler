{ %fail }

program tinlinecopyfail1;

{$mode delphi}

type
  TInlineClass = class;
  TInlineClassRef = class of TInlineClass;
  TInlineClass = class
    class function Step: TInlineClassRef; inline;
  end;

class function TInlineClass.Step: TInlineClassRef;
begin
  Result := TInlineClass;
end;

begin
  TInlineClass.Step.MissingMember;
end.
