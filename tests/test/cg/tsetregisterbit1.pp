program tsetregisterbit1;
{$mode delphi}{$Q-}{$R-}
uses {$ifdef unix} BaseUnix {$else} Windows {$endif};
type
  TByteSet=set of Byte;
{$packset 1}
  TOffset=96..175;
  TOffsetSet=set of TOffset;
  TTailSet=set of 64..128;
  PTailSet=^TTailSet;
{$packset default}
  THolder=record Value: TByteSet end;
var
  Sets: array[0..3] of THolder;
  Expected: array[0..255] of Boolean;
  Calls: Integer;

function Member(I: Integer; const S: TByteSet): Boolean; noinline;
begin
  Result:=I in S;
end;

function WideMember(I: Int64; const S: TByteSet): Boolean; noinline;
begin
  Result:=I in S;
end;

function OffsetMember(I: Integer; const S: TOffsetSet): Boolean; noinline;
begin
  Result:=I in S;
end;

function TailMember(I: Integer; const S: TTailSet): Boolean; noinline;
begin
  Result:=I in S;
end;

function FieldMember(I,K: Integer): Boolean; noinline;
begin
  Result:=I in Sets[K].Value;
end;

function MakeSet: TByteSet; noinline;
begin
  Inc(Calls);
  Result:=[0,3,17,31,32,63,64,95,127,128,159,191,223,254,255];
end;

function ConstantMember(I: Integer): Boolean; noinline;
begin
  Result:=I in [0,3,17,31,32,63,64,95,127,128,159,191,223,254,255];
end;

function BooleanMember(I: Integer; const S: TByteSet): Boolean; noinline;
begin
  Result:=not (I in S) and ((I+1 in S) or (I-1 in S));
end;

var I,K: Integer; S: TByteSet; OffsetSet: TOffsetSet; B: Boolean;
  Mem: Pointer; Tail: PTailSet;
{$ifndef unix}
  OldProtect: DWORD;
{$endif}
begin
  for K:=0 to 3 do
  begin
    S:=[];
    for I:=0 to 255 do
    begin
      Expected[I]:=((I*13+K*7) mod 19)<8;
      if Expected[I] then Include(S,I);
    end;
    Sets[K].Value:=S;
    for I:=-10 to 266 do
    begin
      B:=False;
      if (I>=0) and (I<=255) then B:=Expected[I];
      if Member(I,S)<>B then Halt(1);
      if WideMember(I,S)<>B then Halt(2);
      if FieldMember(I,K)<>B then Halt(3);
      if BooleanMember(I,S)<>((not B) and (Member(I-1,S) or Member(I+1,S))) then Halt(4);
    end;
  end;
  OffsetSet:=[96,98,111,127,128,139,159,174,175];
  for I:=0 to 255 do
  begin
    B:=(I=96) or (I=98) or (I=111) or (I=127) or (I=128) or (I=139) or (I=159) or (I=174) or (I=175);
    if OffsetMember(I,OffsetSet)<>B then Halt(5);
  end;
  Calls:=0;
  for I:=-1 to 256 do
  begin
    S:=MakeSet;
    if (I in MakeSet)<>ConstantMember(I) then Halt(6);
    if Member(I,S)<>ConstantMember(I) then Halt(7);
  end;
  if Calls<>516 then Halt(8);
  if SizeOf(TTailSet)<>9 then Halt(9);
{$ifdef unix}
  Mem:=fpMMap(nil,8192,PROT_READ or PROT_WRITE,MAP_PRIVATE or MAP_ANONYMOUS,-1,0);
  if PtrInt(Mem)=-1 then Halt(10);
  if fpMProtect(Pointer(PtrUInt(Mem)+4096),4096,PROT_NONE)<>0 then Halt(11);
{$else}
  Mem:=VirtualAlloc(nil,8192,MEM_COMMIT or MEM_RESERVE,PAGE_READWRITE);
  if Mem=nil then Halt(10);
  if not VirtualProtect(Pointer(PtrUInt(Mem)+4096),4096,PAGE_NOACCESS,OldProtect) then Halt(11);
{$endif}
  Tail:=Pointer(PtrUInt(Mem)+4096-SizeOf(TTailSet));
  Tail^:=[64,66,79,95,96,111,127,128];
  for I:=0 to 255 do
  begin
    B:=(I=64) or (I=66) or (I=79) or (I=95) or (I=96) or (I=111) or (I=127) or (I=128);
    if TailMember(I,Tail^)<>B then Halt(12);
  end;
{$ifdef unix}
  fpMUnmap(Mem,8192);
{$else}
  VirtualFree(Mem,0,MEM_RELEASE);
{$endif}
end.
