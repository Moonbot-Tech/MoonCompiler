{%target=linux}
{%cpu=x86_64}

program tdelphiunicodeexternalname1;

{$mode delphiunicode}

const
  LibcSuffix = '@GLIBC_2.2.5';

function getpid: LongInt; cdecl;
  external 'c' name 'getpid' + LibcSuffix;

begin
  if getpid <= 0 then
    Halt(1);
end.
