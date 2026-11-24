{ Native C varargs of pointers use the caller-provided widths on partial conversion. }

{$ifdef MSWINDOWS}
function BreadthCScan(Text, Pattern: PAnsiChar): Integer; cdecl; varargs; external 'msvcrt.dll' name 'sscanf';
{$else}
function BreadthCScan(Text, Pattern: PAnsiChar): Integer; cdecl; varargs; external 'c' name 'sscanf';
{$endif}

procedure RunBreadthCScan;
const
  Pattern: AnsiString = '%lld|%lf|%u|%hu';
var
  Line: AnsiString;
  Fields: record
    LeftGuard: UInt64;
    Ticket: Int64;
    Factor: Double;
    Flags: Cardinal;
    Level, RightGuard: Word;
  end;
  ReadCount: Integer;
begin
  FillChar(Fields, SizeOf(Fields), 0);
  Fields.LeftGuard := UInt64($AE1255669034D17C);
  Fields.RightGuard := $CD14;
  Fields.Level := $EB61;
  Line := AnsiString('-73014444049|-205|3300000042|invalid');
  ReadCount := BreadthCScan(PAnsiChar(Line), PAnsiChar(Pattern), @Fields.Ticket, @Fields.Factor, @Fields.Flags, @Fields.Level);
  Check((ReadCount = 3) and (Fields.Level = $EB61), 'breadth-c-scan-failed-field-keeps-destination');
  Check((Fields.Ticket = -73014444049) and (Fields.Factor = -205.0) and (Fields.Flags = 3300000042),
    'breadth-c-scan-commits-first-three-conversions-before-failure');
  Line := AnsiString('77000000031|987|4180000033|60125');
  ReadCount := BreadthCScan(PAnsiChar(Line), PAnsiChar(Pattern), @Fields.Ticket, @Fields.Factor, @Fields.Flags, @Fields.Level);
  Check((ReadCount = 4) and (Fields.Ticket = 77000000031) and (Fields.Factor = 987.0)
    and (Fields.Flags = 4180000033) and (Fields.Level = 60125), 'breadth-c-scan-converts-four-pointer-arguments');
  Check((Fields.LeftGuard = UInt64($AE1255669034D17C)) and (Fields.RightGuard = $CD14),
    'breadth-c-scan-pointer-widths-preserve-adjacent-guards');
  Mix(UInt64(Fields.Ticket) xor (UInt64(Fields.Level) shl 32));
end;
