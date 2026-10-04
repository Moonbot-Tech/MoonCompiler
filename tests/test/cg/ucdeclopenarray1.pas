unit ucdeclopenarray1;

{$mode unleashed}

interface

type
  TVarRecDynArray = array of TVarRec;
  TCdeclConstPair = function(const Left,Right: array of const; Tail: NativeInt): Int64; cdecl;
  TCdeclConstReader = class
    function ReadPair(const Left,Right: array of const; Tail: NativeInt): Int64; cdecl;
  end;

function OpenHigh(const Values: array of Integer): NativeInt; cdecl;
function ConstHigh(const Values: array of const): NativeInt; cdecl;
function ConstFirstInteger(const Values: array of const): NativeInt; cdecl;
function ConstPair(const Left,Right: array of const; Tail: NativeInt): Int64; cdecl;
function ForwardConstPair(const Left,Right: array of const; Tail: NativeInt): Int64;
function ForwardTypedPair(const Left,Right: array of TVarRec; Tail: NativeInt): Int64;

implementation

function OpenHigh(const Values: array of Integer): NativeInt; cdecl;
begin
  Result:=High(Values);
end;

function ConstHigh(const Values: array of const): NativeInt; cdecl;
begin
  Result:=High(Values);
end;

function ConstFirstInteger(const Values: array of const): NativeInt; cdecl;
begin
  if (Length(Values)<>1) or (Values[0].VType<>vtInteger) then
    Result:=-1
  else
    Result:=Values[0].VInteger;
end;

function ConstPair(const Left,Right: array of const; Tail: NativeInt): Int64; cdecl;
var
  I: NativeInt;
begin
  Result:=Tail*1000000+Length(Left)*100000+Length(Right)*10000;
  for I:=0 to High(Left) do
    begin
      if Left[I].VType<>vtInteger then
        Halt(10);
      Inc(Result,Left[I].VInteger*(I+1));
    end;
  for I:=0 to High(Right) do
    begin
      if Right[I].VType<>vtInteger then
        Halt(11);
      Inc(Result,Right[I].VInteger*(I+1)*100);
    end;
end;

function ForwardConstPair(const Left,Right: array of const; Tail: NativeInt): Int64;
begin
  Result:=ConstPair(Left,Right,Tail);
end;

function ForwardTypedPair(const Left,Right: array of TVarRec; Tail: NativeInt): Int64;
begin
  Result:=ConstPair(Left,Right,Tail);
end;

function TCdeclConstReader.ReadPair(const Left,Right: array of const; Tail: NativeInt): Int64; cdecl;
begin
  Result:=ConstPair(Left,Right,Tail);
end;

end.
