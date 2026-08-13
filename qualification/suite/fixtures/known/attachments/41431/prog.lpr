program prog;

// fpc.exe -O1 -vn- -vw- -Sa -uni -gw3 prog.lpr


{$mode objfpc}{$H+}
{$WARN 3124 off : Inlining disabled}

{$DEFINE TEST_WITH_SLOW} // If defined, disable heaptrc
  {$Optimization noREGVAR}
  {$Optimization noPEEPHOLE}
  {$inline off}


uses
  Classes, SysUtils, math, LazListClasses;

type

  { TTestRunnerListAnsiString }

  generic TTestRunnerListAnsiString<TListTypeX> = class
  protected
    // MUST be "var param" to avoid ref-count changes due to the call itself
    procedure AssertStringIsUnique(var s: ansistring); {$IF FPC_FULLVERSION > 030300} noinline; {$ENDIF}
    procedure AssertStringIsNotUnique(var s: ansistring); {$IF FPC_FULLVERSION > 030300} noinline; {$ENDIF}
    procedure GetNewString(var s: ansistring); {$IF FPC_FULLVERSION > 030300} noinline; {$ENDIF}

    procedure DoTestInsert;
    procedure TestInsert;
  end;



  TTestRoundBufferAnsiString = specialize TGenLazRoundListFixedType<
    AnsiString, specialize TLazListClassesMemInitManagedRefCnt<AnsiString>,
    TLazListClassesCapacityExp0x8000>;

  TTestListRoundMemAnsiString = specialize TTestRunnerListAnsiString<TTestRoundBufferAnsiString>;


{ TTestRunnerListAnsiString }
{$INLINE OFF}  {$Optimization NOAUTOINLINE}

procedure TTestRunnerListAnsiString.AssertStringIsUnique(var s: ansistring); {$IF FPC_FULLVERSION > 030300} noinline; {$ENDIF}
var
  p: PChar;
begin
  p := pchar(s);
  UniqueString(s);
end;

procedure TTestRunnerListAnsiString.AssertStringIsNotUnique(var s: ansistring); {$IF FPC_FULLVERSION > 030300} noinline; {$ENDIF}
var
  p: PChar;
begin
  p := pchar(s);
  UniqueString(s);
end;

procedure TTestRunnerListAnsiString.GetNewString(var s: ansistring); {$IF FPC_FULLVERSION > 030300} noinline; {$ENDIF}
begin
  s := IntToStr(Random(99)); // a unique string with refcount=1
end;

procedure TTestRunnerListAnsiString.DoTestInsert;
var
  TstLst: TListTypeX;

  procedure GetItem(idx: integer; var s: ansistring); {$IF FPC_FULLVERSION > 030300} noinline; {$ENDIF}
  begin
    s := TstLst.Items[idx]; // creates a temp string var for the "result" of the getter proc
  end;

(* There MUST NOT be any temporary string vars for "s"
   Therefore
   - do all modification/calls/assignments in none-inlined helper procs
   - always pass the string var as "var param", as that takes a pointer to the declared var
*)
var
  s: array of AnsiString;
  InsCnt, i, InsCnt1, InsCnt2, InsCnt3, j: Integer;
begin

  InsCnt := 5;
    TstLst.Create;

    SetLength(s, InsCnt);
        for i := 0 to InsCnt - 1 do begin
          TstLst.InsertRows(i,1);
          GetNewString(s[i]);
          TstLst.Items[i] := s[i];
        end;

    for i := 0 to InsCnt - 1 do begin
      AssertStringIsNotUnique(s[i]);
      GetItem(i, s[i]); // restore orig var, as stored in list
      AssertStringIsNotUnique(s[i]);
      GetItem(i, s[i]); // restore orig var, as stored in list
    end;

    for i := 0 to InsCnt - 1 do begin
      TstLst.DeleteRows(0,1);
      AssertStringIsUnique(s[i]);
    end;

    TstLst.Destroy;
    s := nil;
end;

procedure TTestRunnerListAnsiString.TestInsert;
var
  mem: PtrUInt;
begin
  DoTestInsert;
end;

var a:TTestListRoundMemAnsiString;
begin

  a := TTestListRoundMemAnsiString.Create;
  a.TestInsert;

end.

