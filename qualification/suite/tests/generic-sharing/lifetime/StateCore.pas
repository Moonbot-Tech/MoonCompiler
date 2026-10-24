unit StateCore;
interface
uses System.SysUtils, Ledger;
type
  IToken = interface ['{96AA450D-DC8A-482A-B829-ED04BD2C521A}'] end;
  TToken = class(TInterfacedObject, IToken)
    constructor Create;
    destructor Destroy; override;
  end;
  TTracked = record
    Value: Integer;
    class operator Initialize(out Dest: TTracked);
    class operator Finalize(var Dest: TTracked);
  end;
  TState<T> = class
  public
    class var Text: UnicodeString;
    class var Token: IToken;
    class var Cell: TTracked;
    class constructor Init;
    class destructor Finish;
  end;
implementation
constructor TToken.Create;
begin inherited; Inc(RefCreates); Mark('R'); end;
destructor TToken.Destroy;
begin Inc(RefFrees); Mark('r'); inherited; end;
class operator TTracked.Initialize(out Dest: TTracked);
begin Inc(RecordInits); Dest.Value := 17; Mark('I'); end;
class operator TTracked.Finalize(var Dest: TTracked);
begin
  Inc(RecordFinals);
  if Dest.Value = 17 then Mark('F') else Mark('!');
  Dest.Value := 0;
end;
class constructor TState<T>.Init;
begin Inc(Ctors); Mark('C'); Text := 'start'; Token := TToken.Create; end;
class destructor TState<T>.Finish;
begin Inc(Dtors); Mark('D'); if Cell.Value <> 17 then Mark('?'); Token := nil; end;
end.
