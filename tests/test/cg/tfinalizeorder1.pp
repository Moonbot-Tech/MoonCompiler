{ %OPT=-O3 }
program tfinalizeorder1;

{$mode delphi}

type
  TTrace = class(TInterfacedObject)
  private
    FTag: AnsiChar;
  public
    constructor Create(ATag: AnsiChar);
    destructor Destroy; override;
  end;

  THolderRecord = record
    A, B, C: IInterface;
  end;

  THolderObject = class
  public
    A, B, C: IInterface;
  end;

  TIntfArray = array of IInterface;

var
  Trail: AnsiString;

constructor TTrace.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
end;

destructor TTrace.Destroy;
begin
  Trail := Trail + FTag;
  inherited Destroy;
end;

procedure RecordFields;
var
  Holder: THolderRecord;
begin
  Holder.A := TTrace.Create('d');
  Holder.B := TTrace.Create('e');
  Holder.C := TTrace.Create('f');
end;

procedure ObjectFields;
var
  Holder: THolderObject;
begin
  Holder := THolderObject.Create;
  Holder.A := TTrace.Create('A');
  Holder.B := TTrace.Create('B');
  Holder.C := TTrace.Create('C');
  Holder.Free;
end;

procedure ArrayElements;
var
  Values: TIntfArray;
begin
  SetLength(Values, 3);
  Values[0] := TTrace.Create('0');
  Values[1] := TTrace.Create('1');
  Values[2] := TTrace.Create('2');
  Values := nil;
end;

begin
  Trail := '';
  RecordFields;
  If Trail <> 'fed' then Halt(1);

  Trail := '';
  ObjectFields;
  If Trail <> 'CBA' then Halt(2);

  Trail := '';
  ArrayElements;
  If Trail <> '012' then Halt(3);
end.
