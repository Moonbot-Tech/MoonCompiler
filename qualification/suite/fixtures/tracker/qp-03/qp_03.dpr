program tracker_qp_03;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}
uses SysUtils;
type
  TCallback<T> = reference to procedure(const Value: T);
  IFoo = interface
    ['{0CCB8AFD-9D05-4B25-B8E1-1B5FF41CB1DB}']
    procedure Ping;
  end;
  TGate = class
    class procedure Test<T: IInterface>(const X: IInterface; const Callback: TCallback<T>); static;
  end;
class procedure TGate.Test<T>(const X: IInterface; const Callback: TCallback<T>);
begin
  Callback(X);
end;
var X: IInterface;
begin
  TGate.Test<IFoo>(X,
    procedure(const Value: IFoo)
    begin
    end);
end.
