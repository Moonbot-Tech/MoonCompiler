program string_builder_growth_semantic;

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  SysUtils;

type
  TStringBuilderProbe = class(TStringBuilder)
  public
    procedure ForceState(ALength, AMaxCapacity: Integer);
    procedure AppendArray(const AValue: TArray<Char>);
  end;

procedure TStringBuilderProbe.ForceState(ALength, AMaxCapacity: Integer);
begin
  SetLength(FData, 1);
  FLength := ALength;
  FMaxCapacity := AMaxCapacity;
end;

procedure TStringBuilderProbe.AppendArray(const AValue: TArray<Char>);
begin
  DoAppend(AValue, 0, System.Length(AValue));
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    begin
      WriteLn('FAIL ', AMessage);
      Halt(1);
    end;
end;

var
  Builder: TStringBuilderProbe;
  Chars: TArray<Char>;
begin
  Builder := TStringBuilderProbe.Create(1, High(Integer));
  try
    Builder.Append('ab');
    Builder.Append('c');
    SetLength(Chars, 2);
    Chars[0] := 'd';
    Chars[1] := 'e';
    Builder.AppendArray(Chars);
    Check(Builder.ToString = 'abcde', 'ordinary append result');

    Builder.ForceState(High(Integer), High(Integer));
    try
      Builder.Append('x');
      Check(False, 'char accepted an overflowing length');
    except
      on E: ERangeError do
        ;
    end;

    Builder.ForceState(High(Integer) - 1, High(Integer));
    try
      Builder.Append('xy');
      Check(False, 'string accepted an overflowing length');
    except
      on E: ERangeError do
        ;
    end;

    Builder.ForceState(High(Integer) - 1, High(Integer));
    try
      Builder.AppendArray(Chars);
      Check(False, 'array accepted an overflowing length');
    except
      on E: ERangeError do
        ;
    end;
  finally
    Builder.Free;
  end;

  WriteLn('STRING_BUILDER_GROWTH_OK');
end.
