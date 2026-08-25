program rtl_api_array_copy;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch arrayoperators}
{$endif}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif}
{$endif}
  System.SysUtils,
  System.Generics.Collections;

procedure Check(ACondition: Boolean; const AName: string);
begin
  If not ACondition then begin
    WriteLn('FAIL ', AName);
    Halt(1);
  end;
end;

procedure CheckFailures(const ASource: TArray<Integer>;
  var ADestination: TArray<Integer>);
var
  Raised: Boolean;
  SameArray: TArray<Integer>;
begin
  Raised := False;
  try
    TArray.Copy<Integer>(ASource, ADestination, 0, 0,
      Length(ASource) + 1);
  except
    on EArgumentOutOfRangeException do begin
      Raised := True;
    end;
  end;
  Check(Raised, 'count-out-of-range');

  SameArray := ASource;
  Raised := False;
  try
    TArray.Copy<Integer>(SameArray, SameArray, 0);
  except
    on EArgumentException do begin
      Raised := True;
    end;
  end;
  Check(Raised, 'same-array-even-zero-count');
end;

var
  Copied: TArray<Integer>;
  EmptyDestination: TArray<Integer>;
  EmptySource: TArray<Integer>;
  ManagedCopied: TArray<string>;
  ManagedSource: TArray<string>;
  Source: TArray<Integer>;

begin
  Source := TArray<Integer>.Create(1, 3, 5, 7);
  SetLength(Copied, Length(Source));
  TArray.Copy<Integer>(Source, Copied, Length(Source));
  Check((Length(Copied) = 4) and (Copied[0] = 1) and (Copied[3] = 7),
    'unmanaged-three-argument');
  ManagedSource := TArray<string>.Create('zero', 'one', 'two');
  SetLength(ManagedCopied, 4);
  ManagedCopied[0] := 'keep';
  ManagedCopied[2] := 'replace-two';
  ManagedCopied[3] := 'replace-three';
  TArray.Copy<string>(ManagedSource, ManagedCopied, 1, 2, 2);
  Check((ManagedCopied[0] = 'keep') and (ManagedCopied[1] = '') and
    (ManagedCopied[2] = 'one') and (ManagedCopied[3] = 'two'),
    'managed-five-argument');
  TArray.Copy<Integer>(EmptySource, EmptyDestination, 0);
  Check((Length(EmptySource) = 0) and (Length(EmptyDestination) = 0),
    'empty-zero-count');
  CheckFailures(Source, Copied);
  WriteLn('RTL_API_ARRAY_COPY_OK');
end.
