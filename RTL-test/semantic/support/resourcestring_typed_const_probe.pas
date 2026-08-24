unit resourcestring_typed_const_probe;

interface

type
  TRemoteState = (remoteStateFirst, remoteStateSecond);

resourcestring
  RemoteFirst = 'remote first %s';
  RemoteSecond = 'remote second';

const
  RemoteStates: array[TRemoteState] of string = (
    RemoteFirst,
    RemoteSecond);
  RemoteUnicode: UnicodeString = RemoteFirst;
  RemoteAnsi: AnsiString = RemoteSecond;
  RemoteWide: WideString = RemoteSecond;

implementation

end.
