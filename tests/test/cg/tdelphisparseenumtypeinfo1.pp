program tdelphisparseenumtypeinfo1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}TypInfo{$else}System.TypInfo{$endif};

type
  TSparseEnum = (seZero, seOne, seThree = 3, seSeven = 7);
  TProbe<T> = class
    class function Info: PTypeInfo; static;
  end;

class function TProbe<T>.Info: PTypeInfo;
begin
  Result:=System.TypeInfo(T);
end;

begin
  If TProbe<TSparseEnum>.Info<>nil then
    Halt(1);
end.
