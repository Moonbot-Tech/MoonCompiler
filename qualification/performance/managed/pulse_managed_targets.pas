unit pulse_managed_targets;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$modeswitch anonymousfunctions}
{$endif}

interface

uses
  SysUtils;

type
  TPulseManagedRecord = record
    Name: UnicodeString;
    Payload: TBytes;
    Value: UInt64;
  end;

function CopyUnicode(const Value: UnicodeString): UnicodeString;
function CopyBytes(const Value: TBytes): TBytes;
function MakeManagedRecord(Index: Integer): TPulseManagedRecord;

implementation

function CopyUnicode(const Value: UnicodeString): UnicodeString;
begin
  Result := Value;
end;

function CopyBytes(const Value: TBytes): TBytes;
begin
  Result := Copy(Value);
end;

function MakeManagedRecord(Index: Integer): TPulseManagedRecord;
begin
  Result.Name := UnicodeString('record-') + UnicodeString(IntToStr(Index));
  SetLength(Result.Payload, 16 + (Index and 15));
  If Length(Result.Payload) <> 0 then
    FillChar(Result.Payload[0], Length(Result.Payload), Index);
  Result.Value := UInt64(Index) * UInt64($9E3779B185EBCA87);
end;

end.
