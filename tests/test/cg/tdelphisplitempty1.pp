program tdelphisplitempty1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  SysUtils;

var
  Source: string;
  CharSeparators: array[0..0] of Char;
  StringSeparators: array[0..0] of string;
  EmptyCharSeparators: array of Char;
  EmptyStringSeparators: array of string;

procedure RequireEmpty(const Parts: TArray<string>; ErrorCode: Byte);
begin
  if Length(Parts)<>0 then
    Halt(ErrorCode);
end;

begin
  Source:='';
  CharSeparators[0]:=',';
  StringSeparators[0]:=',';
  EmptyCharSeparators:=nil;
  EmptyStringSeparators:=nil;

  RequireEmpty(Source.Split(CharSeparators),1);
  RequireEmpty(Source.Split(CharSeparators,TStringSplitOptions.None),2);
  RequireEmpty(Source.Split(CharSeparators,TStringSplitOptions.ExcludeEmpty),3);
  RequireEmpty(Source.Split(CharSeparators,TStringSplitOptions.ExcludeLastEmpty),4);
  RequireEmpty(Source.Split(CharSeparators,1,TStringSplitOptions.None),5);
  RequireEmpty(Source.Split(CharSeparators,'"','"',TStringSplitOptions.None),6);

  RequireEmpty(Source.Split(StringSeparators),10);
  RequireEmpty(Source.Split(StringSeparators,TStringSplitOptions.None),11);
  RequireEmpty(Source.Split(StringSeparators,TStringSplitOptions.ExcludeEmpty),12);
  RequireEmpty(Source.Split(StringSeparators,TStringSplitOptions.ExcludeLastEmpty),13);
  RequireEmpty(Source.Split(StringSeparators,1,TStringSplitOptions.None),14);
  RequireEmpty(Source.Split(StringSeparators,'"','"',TStringSplitOptions.None),15);

  RequireEmpty(Source.Split(EmptyCharSeparators),20);
  RequireEmpty(Source.Split(EmptyStringSeparators),21);

  Source:=',';
  if Length(Source.Split(CharSeparators))<>2 then
    Halt(30);
  Source:='a';
  if Length(Source.Split(CharSeparators))<>1 then
    Halt(31);
  Source:='a,,b';
  if Length(Source.Split(CharSeparators))<>3 then
    Halt(32);
  Source:=',';
  if Length(Source.Split(StringSeparators))<>2 then
    Halt(33);
  Source:='a';
  if Length(Source.Split(StringSeparators))<>1 then
    Halt(34);
  Source:='a,,b';
  if Length(Source.Split(StringSeparators))<>3 then
    Halt(35);
end.
