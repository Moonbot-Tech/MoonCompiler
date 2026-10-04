program array_of_const_dynamic;

{$mode delphiunicode}

type
  TVarRecDynArray = array of TVarRec;

var
  ExpectedCount: Integer;
  ExpectedText: AnsiString;

procedure Fail(const Name: AnsiString);
begin
  Writeln('FAIL ', Name);
  Halt(1);
end;

procedure CheckArgs(const Args: array of const; const Name: AnsiString);
begin
  If Length(Args) <> ExpectedCount then
    Fail(Name + '-count');
  If ExpectedCount = 0 then
    Exit;
  If (Args[0].VType <> vtInteger) or (Args[0].VInteger <> 17) then
    Fail(Name + '-integer');
  If (Args[1].VType <> vtAnsiString) or
      (AnsiString(Args[1].VAnsiString) <> ExpectedText) then
    Fail(Name + '-string');
end;

procedure CheckArgsCdecl(const Args: array of const); cdecl;
begin
  CheckArgs(Args, 'cdecl');
end;

function MakeArgs(const Text: AnsiString): TVarRecDynArray;
begin
  SetLength(Result, 2);
  Result[0].VType := vtInteger;
  Result[0].VInteger := 17;
  Result[1].VType := vtAnsiString;
  Result[1].VAnsiString := Pointer(Text);
end;

var
  Args: TVarRecDynArray;
  Text: AnsiString;
begin
  Text := 'moon';
  ExpectedText := Text;
  ExpectedCount := 2;

  Args := MakeArgs(Text);
  CheckArgs(Args, 'pascal');
  CheckArgsCdecl(Args);

  SetLength(Args, 0);
  ExpectedCount := 0;
  CheckArgs(Args, 'pascal-empty');
  CheckArgsCdecl(Args);

  Writeln('ARRAY_OF_CONST_DYNAMIC_OK');
end.
