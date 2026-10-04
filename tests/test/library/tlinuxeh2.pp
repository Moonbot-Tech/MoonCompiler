{ %target=linux }
{ %needlibrary }

program tlinuxeh2;

function CatchLibraryException: LongInt; cdecl;
  external 'tlinuxeh1' name 'CatchLibraryException';

begin
  if CatchLibraryException<>42 then
    Halt(1);
end.
