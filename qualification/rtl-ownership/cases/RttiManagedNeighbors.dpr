program RttiManagedNeighbors;
uses mormot.core.fpcx64mm, System.SysUtils, System.Rtti, System.Variants;

{$RTTI EXPLICIT FIELDS([vcPublic])}
type
  ITracked = interface ['{6408134B-9D58-4970-8A0C-93D10335A22A}'] end;
  TTracked = class(TInterfacedObject, ITracked)
    destructor Destroy; override;
  end;
  TStrings = array of string;
  TData = record Text: string; end;
  TRow = class
  public
    Ref: ITracked;
    Items: TStrings;
    Data: TData;
    V: Variant;
  end;
var Destroyed: Integer;

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

procedure Run;
var Context: TRttiContext; Field: TRttiField; Row: TRow;
  I: Integer; Mode: string; Ref: ITracked; Items: TStrings; Data: TData; V: Variant;
begin
  Context := TRttiContext.Create;
  try
    Mode := ParamStr(1);
    Field := Context.GetType(TRow).GetField(Mode);
    If Field = nil then raise Exception.Create('Missing field');
    for I := 1 to 32 do begin
      Row := TRow.Create;
      try
        If Mode = 'Ref' then begin
          Row.Ref := TTracked.Create;
          Ref := TTracked.Create;
          Field.SetValue(Row,TValue.From<ITracked>(Ref));
          If Row.Ref <> Ref then Halt(2);
          Ref := nil;
        end else If Mode = 'Items' then begin
          SetLength(Row.Items,1);
          Row.Items[0] := StringOfChar('A',100+I);
          SetLength(Items,1);
          Items[0] := StringOfChar('B',200+I);
          Field.SetValue(Row,TValue.From<TStrings>(Items));
          If Row.Items[0] <> Items[0] then Halt(3);
          Items := nil;
        end else If Mode = 'Data' then begin
          Row.Data.Text := StringOfChar('A',100+I);
          Data.Text := StringOfChar('B',200+I);
          Field.SetValue(Row,TValue.From<TData>(Data));
          If Row.Data.Text <> Data.Text then Halt(4);
          Data.Text := '';
        end else If Mode = 'V' then begin
          Row.V := StringOfChar('A',100+I);
          V := StringOfChar('B',200+I);
          Field.SetValue(Row,TValue.From<Variant>(V));
          If Row.V <> V then Halt(5);
          VarClear(V);
        end;
      finally
        Row.Free;
      end;
    end;
  finally
    Context.Free;
  end;
end;

begin
  Run;
  Writeln('VALUES_PASS mode=',ParamStr(1),' destroyed=',Destroyed);
end.
