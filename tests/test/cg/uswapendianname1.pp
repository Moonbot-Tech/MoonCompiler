unit uswapendianname1;

{$mode delphiunicode}

interface

function SwapEndian(value: qword): qword; noinline;

implementation

function SwapEndian(value: qword): qword;
  begin
    result:=value xor $55aa55aa55aa55aa;
  end;

end.
