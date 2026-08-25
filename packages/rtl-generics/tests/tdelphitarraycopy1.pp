program tdelphitarraycopy1;

{$mode delphi}

uses
  SysUtils,
  Generics.Collections;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Source,
  Destination,
  SameArray : TArray<Integer>;
  ManagedSource,
  ManagedDestination : TArray<string>;
  Raised : Boolean;

begin
  Source:=TArray<Integer>.Create(1,3,5,7);
  SetLength(Destination,Length(Source));
  TArray.Copy<Integer>(Source,Destination,Length(Source));
  Check((Destination[0]=1) and (Destination[3]=7),1);

  ManagedSource:=TArray<string>.Create('zero','one','two');
  SetLength(ManagedDestination,4);
  ManagedDestination[0]:='keep';
  ManagedDestination[2]:='replace-two';
  ManagedDestination[3]:='replace-three';
  TArray.Copy<string>(ManagedSource,ManagedDestination,1,2,2);
  Check((ManagedDestination[0]='keep') and (ManagedDestination[1]='') and
    (ManagedDestination[2]='one') and (ManagedDestination[3]='two'),2);

  Raised:=False;
  try
    TArray.Copy<Integer>(Source,Destination,0,0,Length(Source)+1);
  except
    on EArgumentOutOfRangeException do
      Raised:=True;
  end;
  Check(Raised,3);

  SameArray:=Source;
  Raised:=False;
  try
    TArray.Copy<Integer>(SameArray,SameArray,0);
  except
    on EArgumentException do
      Raised:=True;
  end;
  Check(Raised,4);
end.
