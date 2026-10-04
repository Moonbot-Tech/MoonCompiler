program generics_reorder_contracts;

{$mode delphiunicode}

uses
  SysUtils,
  Generics.Collections;

type
  TTracked = record
    Value: Integer;
    class operator Initialize(out Dest: TTracked);
    class operator Assign(var Dest: TTracked; const [ref] Source: TTracked);
    class operator Finalize(var Dest: TTracked);
  end;

var
  Assigns,Finalizes,Initializes: Integer;
  RaiseOnAssign: Boolean;

class operator TTracked.Initialize(out Dest: TTracked);
begin
  Inc(Initializes);
  Dest.Value:=0;
end;

class operator TTracked.Assign(var Dest: TTracked; const [ref] Source: TTracked);
begin
  Inc(Assigns);
  if RaiseOnAssign then
    raise Exception.Create('reorder invoked Assign');
  Dest.Value:=Source.Value;
end;

class operator TTracked.Finalize(var Dest: TTracked);
begin
  Inc(Finalizes);
end;

procedure Fail(const Name: string);
begin
  WriteLn('FAIL ',Name);
  Halt(1);
end;

procedure ExpectDeleteRangeError(List: TList<Integer>; Index,Count: SizeInt;
  const Name: string);
begin
  try
    List.DeleteRange(Index,Count);
  except
    on EArgumentOutOfRangeException do
      Exit;
  end;
  Fail(Name);
end;

procedure CheckDeleteRangeMatrix;
var
  Integers: TList<Integer>;
  Strings: TList<string>;
begin
  Integers:=TList<Integer>.Create;
  try
    ExpectDeleteRangeError(Integers,-1,0,'empty-negative-index');
    ExpectDeleteRangeError(Integers,1,0,'empty-index-past-end');
    Integers.DeleteRange(0,0);
    Integers.Add(11);
    ExpectDeleteRangeError(Integers,-1,0,'negative-index');
    ExpectDeleteRangeError(Integers,2,0,'index-past-end');
    ExpectDeleteRangeError(Integers,0,-1,'negative-count');
    ExpectDeleteRangeError(Integers,1,1,'range-past-end');
    Integers.DeleteRange(1,0);
    if (Integers.Count<>1) or (Integers[0]<>11) then
      Fail('valid-empty-range-mutated-list');
  finally
    Integers.Free;
  end;

  Strings:=TList<string>.Create;
  try
    Strings.Add('left');
    Strings.Add('middle');
    Strings.Add('right');
    Strings.DeleteRange(1,1);
    if (Strings.Count<>2) or (Strings[0]<>'left') or (Strings[1]<>'right') then
      Fail('managed-delete-range');
  finally
    Strings.Free;
  end;
end;

procedure CheckRawReorder;
var
  I: Integer;
  List: TList<TTracked>;
  Value: TTracked;
begin
  List:=TList<TTracked>.Create;
  try
    for I:=1 to 5 do
      begin
        Value.Value:=I;
        List.Add(Value);
      end;
    Assigns:=0;
    Initializes:=0;
    Finalizes:=0;
    RaiseOnAssign:=True;
    List.Reverse;
    List.Exchange(1,3);
    RaiseOnAssign:=False;
    if (Assigns<>0) or (Initializes<>0) or (Finalizes<>0) then
      Fail('reorder-ran-managed-hooks');
    if (List[0].Value<>5) or (List[1].Value<>2) or (List[2].Value<>3) or
       (List[3].Value<>4) or (List[4].Value<>1) then
      Fail('reorder-values');
  finally
    RaiseOnAssign:=False;
    List.Free;
  end;
end;

procedure CheckStringOwnership;
var
  List: TList<string>;
begin
  List:=TList<string>.Create;
  try
    List.Add('alpha');
    List.Add('beta');
    List.Add('gamma');
    List.Reverse;
    List.Exchange(0,2);
    if (List[0]<>'alpha') or (List[1]<>'beta') or (List[2]<>'gamma') then
      Fail('string-ownership');
  finally
    List.Free;
  end;
end;

begin
  CheckDeleteRangeMatrix;
  CheckRawReorder;
  CheckStringOwnership;
  WriteLn('GENERICS_REORDER_CONTRACTS_OK');
end.
