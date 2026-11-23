unit WeakInterfaceTypes;
{$mode delphiunicode}
interface

type
  TRow = record
    [Weak] Link: IInterface;
  end;

procedure Replace(out Row: TRow; const Value: IInterface);
procedure AssignStrong(var Value: IInterface);
procedure ResetStrong(out Value: IInterface);

implementation

procedure Replace(out Row: TRow; const Value: IInterface);
begin
  Row.Link := Value;
end;

procedure AssignStrong(var Value: IInterface);
begin
  Value := nil;
end;

procedure ResetStrong(out Value: IInterface);
begin
  Value := nil;
end;

end.
