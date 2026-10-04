program aggregate_exception_enumerator_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Threading;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('AGGREGATE_ENUMERATOR_FAIL: '+AMessage);
end;

procedure CheckEmpty;
var
  Aggregate: EAggregateException;
  Enumerator: EAggregateException.TExceptionEnumerator;
  Item: Exception;
  Count: Integer;
begin
  Aggregate:=EAggregateException.Create([]);
  try
    Count:=0;
    for Item in Aggregate do
      Inc(Count);
    Check(Count=0,'empty aggregate');
    Enumerator:=Aggregate.GetEnumerator;
    try
      Check(not Enumerator.MoveNext,'empty first MoveNext');
      Check(not Enumerator.MoveNext,'empty repeated MoveNext');
    finally
      Enumerator.Free;
    end;
  finally
    Aggregate.Free;
  end;
end;

procedure CheckItems;
var
  Aggregate: EAggregateException;
  Enumerator: EAggregateException.TExceptionEnumerator;
  Item: Exception;
  Count: Integer;
begin
  Aggregate:=EAggregateException.Create([
    Exception.Create('first'),Exception.Create('second'),Exception.Create('third')]);
  try
    Count:=0;
    for Item in Aggregate do
      begin
      Check(Assigned(Item),'nil spare entry');
      case Count of
        0: Check(Item.Message='first','first item');
        1: Check(Item.Message='second','second item');
        2: Check(Item.Message='third','third item');
      else
        Check(False,'enumerated past logical end');
      end;
      Inc(Count);
      end;
    Check(Count=3,'logical count');
    Enumerator:=Aggregate.GetEnumerator;
    try
      while Enumerator.MoveNext do
        ;
      Check(not Enumerator.MoveNext,'populated repeated MoveNext');
    finally
      Enumerator.Free;
    end;
  finally
    Aggregate.Free;
  end;
end;

begin
  CheckEmpty;
  CheckItems;
  WriteLn('AGGREGATE_EXCEPTION_ENUMERATOR_SEMANTIC_PASS');
end.
