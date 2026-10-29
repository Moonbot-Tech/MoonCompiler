"""Separate translation units preserve private-static eligibility and its barriers."""

header = """program check_entry;
{$mode delphiunicode}{$H+}
uses SysUtils, Math;
var X,Y: Double; S: Single; I,N: Integer; P: ^Double; Bits: UInt64 absolute X;
    Callback: procedure;
procedure SetCaptured; noinline; begin X:=19; end;
procedure ReadCaptured; noinline; begin Writeln('captured=', X:0:3); end;
procedure ViaVar(var V: Double); noinline; begin V:=V+7; end;
procedure RaiseIt; noinline; begin raise Exception.Create('test'); end;
procedure Nested;
var LocalValue: Double;
  procedure Observe; begin Writeln('nested=',LocalValue:0:3); end;
begin
  LocalValue:=13;
  try Observe; finally Writeln('nested-final=',LocalValue:0:3); end;
end;
"""

header += "var Z,W: Double; K: Int64;\nbegin\n  N:=StrToInt(ParamStr(1));\n"

footer = "\nend.\n"

cases = {
    "sibling_before": "try Writeln('before'); finally Writeln('done'); end; Z:=5; Writeln(Z:0:3);",
    "sibling_after": "Z:=5; Writeln(Z:0:3); try Writeln('after'); finally Writeln('done'); end;",
    "initial_read": "try Writeln('before'); finally Writeln('done'); end; Writeln(Z:0:3); Z:=5; Writeln(Z:0:3);",
    "read_modify_write": "try Writeln('before'); finally Writeln('done'); end; Z:=Z+3; Writeln(Z:0:3);",
    "partial_branch": "try Writeln('before'); finally Writeln('done'); end; If N=0 then Z:=7; Writeln(Z:0:3);",
    "both_branches": "try Writeln('before'); finally Writeln('done'); end; If N=0 then Z:=7 else Z:=11; Writeln(Z:0:3);",
    "zero_for_liveout": "try Writeln('before'); finally Writeln('done'); end; for I:=1 to N do Z:=I/8; Writeln(Z:0:3);",
    "scratch_loop": "try Writeln('before'); finally Writeln('done'); end; W:=0; for I:=1 to N do begin Z:=I/8; W:=W+Z; end; Writeln(W:0:3);",
    "while_liveout": "try Writeln('before'); finally Writeln('done'); end; I:=0; while I<N do begin Z:=I/8; Inc(I); end; Writeln(Z:0:3);",
    "repeat_liveout": "try Writeln('before'); finally Writeln('done'); end; I:=0; repeat Z:=I/8; Inc(I); until I>=N; Writeln(Z:0:3);",
    "handler_before_write": "try If N=0 then RaiseIt; Z:=7; except Writeln('caught=',Z:0:3); end; Writeln('end=',Z:0:3);",
    "handler_after_write": "try Z:=7; If N=0 then RaiseIt; except Writeln('caught=',Z:0:3); end; Writeln('end=',Z:0:3);",
    "finally_before_write": "try If N=0 then Exit; Z:=7; finally Writeln('finally=',Z:0:3); end; Writeln('end=',Z:0:3);",
    "finally_inside_loop": "for I:=1 to N do begin try Z:=I/8; finally Writeln(Z:0:3); end; end; Writeln('end=',Z:0:3);",
    "finally_around_loop": "try for I:=1 to N do Z:=I/8; finally Writeln(Z:0:3); end;",
    "nested_rethrow": "try try If N=0 then RaiseIt; Z:=7; except Writeln('inner=',Z:0:3); raise; end; except Writeln('outer=',Z:0:3); end;",
    "break_finally": "try for I:=1 to N do begin If I=2 then Break; Z:=I/8; end; finally Writeln(Z:0:3); end;",
    "continue_finally": "try for I:=1 to N do begin If I=2 then Continue; Z:=I/8; end; finally Writeln(Z:0:3); end;",
    "global_callback": "Callback:=@SetCaptured; try Callback; finally ReadCaptured; end; Writeln(X:0:3);",
    "var_alias": "try ViaVar(Z); finally Writeln(Z:0:3); end;",
    "pointer_alias": "P:=@Z; try P^:=P^+9; finally Writeln(Z:0:3); end;",
    "absolute_alias": "try Writeln('before'); finally Writeln('done'); end; Bits:=$8000000000000000; Writeln(X:0:3);",
    "nested_capture": "try Nested; finally Writeln('done'); end;",
    "fp_width": "try Writeln('before'); finally Writeln('done'); end; S:=N/3; Z:=S; S:=Z+0.25; Writeln(S:0:6);",
    "fp_signed_zero": "try Writeln('before'); finally Writeln('done'); end; Z:=-0.0; Move(Z,K,8); Writeln(K);",
    "fp_nan": "try Writeln('before'); finally Writeln('done'); end; Z:=NaN; Writeln(IsNan(Z));",
}
