program tinlinegenericcomparer1;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  SysUtils,
  Generics.Defaults,
  Generics.Collections;

type
  TEntry<T> = record
    value: T;
  end;

  TEntries<T> = class
  private
    fvalues: array of TEntry<T>;
  public
    procedure sort;
  end;

procedure TEntries<T>.sort;
begin
  TArray.Sort<TEntry<T>>(fvalues,
    TComparer<TEntry<T>>.Construct(
      function(const left,right: TEntry<T>): longint
      begin
        result:=TComparer<T>.Default.Compare(left.value,right.value);
      end));
end;

var
  entries: TEntries<longint>;

begin
  entries:=TEntries<longint>.create;
  try
    entries.sort;
  finally
    entries.free;
  end;
end.
