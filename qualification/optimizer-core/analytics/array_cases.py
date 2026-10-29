"""Separate translation units preserve private-static eligibility and its barriers."""

header = """program array_test;
{$mode delphiunicode}{$H+}
uses SysUtils;
type TVals=array of Int64;
var B: TVals; I,N: Integer; Total:Int64;
"""

setup = """N:=StrToInt(ParamStr(1)); SetLength(A,5); SetLength(B,5);
for I:=0 to 4 do begin A[I]:=I+1; B[I]:=10+I; end;
Total:=0;
"""

loop = "for I:=0 to N-1 do begin %s Total:=Total+A[I]+A[4-I]; end;"

cases = {
    "named_descriptor_alias": (
        "var A:TVals cvar; Alias:Pointer external name 'A'; Saved:Pointer;",
        "Saved:=Pointer(A);",
        (loop % "If I=1 then Alias:=Pointer(B);") + " Alias:=Saved;",
    ),
    "generated_symbol_alias": (
        "var A:TVals; Alias:Pointer external name 'U_$P$ARRAY_TEST_$$_A'; Saved:Pointer;",
        "Saved:=Pointer(A);",
        (loop % "If I=1 then Alias:=Pointer(B);") + " Alias:=Saved;",
    ),
    "generated_symbol_field_alias": (
        "type TAlias=record Value:Pointer; end; "
        "var A:TVals; Alias:TAlias external name 'U_$P$ARRAY_TEST_$$_A'; Saved:Pointer;",
        "Saved:=Pointer(A);",
        (loop % "If I=1 then Alias.Value:=Pointer(B);") + " Alias.Value:=Saved;",
    ),
    "private_read": ("var A:TVals;", "", loop % ""),
    "sibling_eh": (
        "var A:TVals;",
        "",
        "try Total:=0; finally Total:=0; end; " + loop % "",
    ),
    "around_eh": (
        "var A:TVals;",
        "",
        "try " + loop % "" + " finally Writeln('final=',Total); end;",
    ),
    "inner_eh": (
        "var A:TVals;",
        "",
        loop % "try Total:=Total; finally Total:=Total; end;",
    ),
    "descriptor_assignment": ("var A:TVals;", "", loop % "If I=1 then A:=B;"),
    "descriptor_clear": (
        "var A:TVals;",
        "",
        "for I:=0 to N-1 do begin Total:=Total+A[I]+A[4-I]; If I=1 then begin A:=nil; Break; end; end;",
    ),
    "setlength": (
        "var A:TVals;",
        "",
        loop % "If I=1 then begin SetLength(A,6); A[1]:=37; end;",
    ),
    "element_write": ("var A:TVals;", "", loop % "A[I]:=A[I]+3;"),
    "aliased_elements": ("var A:TVals;", "B:=A;", loop % "B[I]:=B[I]+3;"),
    "absolute_descriptor": (
        "var A:TVals; Alias:TVals absolute A;",
        "",
        loop % "If I=1 then Alias:=B;",
    ),
    "pointer_descriptor": (
        "var A:TVals; Ptr:^TVals;",
        "Ptr:=@A;",
        loop % "If I=1 then Ptr^:=B;",
    ),
    "var_call": (
        "var A:TVals; procedure Change(var V:TVals); noinline; begin V:=B; end;",
        "",
        loop % "If I=1 then Change(A);",
    ),
    "global_call": (
        "var A:TVals; procedure Change; noinline; begin A:=B; end;",
        "",
        loop % "If I=1 then Change;",
    ),
    "indirect_call": (
        "var A:TVals; Callback:procedure; procedure Change; noinline; begin A:=B; end;",
        "Callback:=@Change;",
        loop % "If I=1 then Callback;",
    ),
    "inline_mutation": (
        "var A:TVals; procedure Change; inline; begin A:=B; end;",
        "",
        loop % "If I=1 then Change;",
    ),
    "public": ("var A:TVals public name 'published_array';", "", loop % ""),
    "threadvar": ("threadvar A:TVals;", "", loop % ""),
    "external": (
        "var Actual:TVals public name 'external_array'; A:TVals external name 'external_array';",
        "",
        loop % "",
    ),
    "volatile": (
        "var A:TVals;",
        "",
        "for I:=0 to N-1 do Total:=Total+volatile(A)[I]+volatile(A)[4-I];",
    ),
    "break": ("var A:TVals;", "", loop % "If I=2 then Break;"),
    "continue": ("var A:TVals;", "", loop % "If I=2 then Continue;"),
    "zero_nil": ("var A:TVals;", "A:=nil;", "for I:=1 to 0 do Total:=Total+A[I]+A[0];"),
}
