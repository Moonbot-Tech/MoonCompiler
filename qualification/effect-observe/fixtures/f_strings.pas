unit f_strings;

{ String COW (Pascal-check hole 1): S[i] := uniquifies through an RTL helper
  that takes S by var - the DESCRIPTOR itself is written and the payload may
  move.  The dangerous form must carry string_cow; the read form must not. }

interface

function StrElemRead(S: AnsiString): AnsiChar;
procedure StrElemWrite;
procedure UniElemWrite;
procedure StrShare;
procedure ConcatForm;

implementation

// the result is AnsiChar on purpose: with the Unicode product RTL a plain
// Char result would pull the ansichar->widechar conversion helper and turn
// the read into an opaque call - the fixture asserts the pure read
// EXPECT: proc=StrElemRead r=LH ie=t reason=may_trap
// EXPECT-NOT: proc=StrElemRead reason=string_cow
function StrElemRead(S: AnsiString): AnsiChar;
begin
  Result := S[1];
end;

// at the observe point the string stores are already lowered to compilerproc
// calls (fpc_ansistr_assign / fpc_ansistr_unique taking S by var): the
// ansistring descriptor symbol escapes (addr_taken) and the element store is
// managed-opaque with the COW reason
// EXPECT: proc=StrElemWrite r=EHGTP w=EHGTP ie=smt reason=string_cow
procedure StrElemWrite;
var
  S: AnsiString;
begin
  S := 'ab';
  S[1] := 'x';
end;

// the unicodestring uniquify helper has a typed var formal (proven
// non-capturing): S keeps its exact identity and the descriptor write is an
// exact local write - the COW hole closed with symbol precision
// EXPECT: proc=UniElemWrite r=LEHGTP w=LEHGTP ie=smt reason=string_cow
procedure UniElemWrite;
var
  S: UnicodeString;
begin
  S := 'ab';
  S[1] := 'x';
end;

// concatenation lowers to the multi-concat helper over a managed
// array-of-string constructor: the managed operation stays visible in the
// aggregate even after canonicalization
// EXPECT: proc=ConcatForm ie=smt reason=managed_operation reason=opaque_call
procedure ConcatForm;
var
  S, T: AnsiString;
begin
  S := 'a';
  T := 'b';
  S := S + '-' + T;
end;

// two descriptors over one payload: every mutation goes through opaque
// helpers, the write side stays wide (class H is invalidated class-wise)
// EXPECT: proc=StrShare ie=smt reason=opaque_call reason=string_cow
procedure StrShare;
var
  S1, S2: AnsiString;
begin
  S1 := 'ab';
  S2 := S1;
  S1[1] := 'x';
end;

end.
