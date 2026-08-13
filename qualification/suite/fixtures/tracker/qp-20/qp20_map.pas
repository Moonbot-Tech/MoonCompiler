unit qp20_map;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
uses Generics.Collections;
type
  TPairEnumerator<K,V> = class(TEnumerator<TPair<K,V>>)
  private
    FDone: Boolean;
    FCurrent: TPair<K,V>;
  protected
    function DoGetCurrent: TPair<K,V>; override;
    function DoMoveNext: Boolean; override;
  public
    constructor Create(const AKey: K; const AValue: V);
  end;
  TMap<K,V> = class(TEnumerable<TPair<K,V>>)
  public type
    TEntry = TPair<K,V>;
  private
    FKey: K;
    FValue: V;
  protected
    function DoGetEnumerator: TEnumerator<TPair<K,V>>; override;
  public
    constructor Create(const AKey: K; const AValue: V);
  end;
implementation
constructor TPairEnumerator<K,V>.Create(const AKey: K; const AValue: V);
begin inherited Create; FCurrent := TPair<K,V>.Create(AKey, AValue); end;
function TPairEnumerator<K,V>.DoGetCurrent: TPair<K,V>;
begin Result := FCurrent; end;
function TPairEnumerator<K,V>.DoMoveNext: Boolean;
begin Result := not FDone; FDone := True; end;
constructor TMap<K,V>.Create(const AKey: K; const AValue: V);
begin inherited Create; FKey := AKey; FValue := AValue; end;
function TMap<K,V>.DoGetEnumerator: TEnumerator<TPair<K,V>>;
begin Result := TPairEnumerator<K,V>.Create(FKey, FValue); end;
end.
