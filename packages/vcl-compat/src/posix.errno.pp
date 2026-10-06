{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Errno;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, BaseUnix;
const
  EPERM = BaseUnix.ESysEPERM;
  ENOENT = BaseUnix.ESysENOENT;
  EINTR = BaseUnix.ESysEINTR;
  EIO = BaseUnix.ESysEIO;
  EBADF = BaseUnix.ESysEBADF;
  EAGAIN = BaseUnix.ESysEAGAIN;
  ENOMEM = BaseUnix.ESysENOMEM;
  EACCES = BaseUnix.ESysEACCES;
  EEXIST = BaseUnix.ESysEEXIST;
  ENOTDIR = BaseUnix.ESysENOTDIR;
  EISDIR = BaseUnix.ESysEISDIR;
  EINVAL = BaseUnix.ESysEINVAL;
  EMFILE = BaseUnix.ESysEMFILE;
  ENOSPC = BaseUnix.ESysENOSPC;
  EPIPE = BaseUnix.ESysEPIPE;
  ERANGE = BaseUnix.ESysERANGE;
  ENOSYS = BaseUnix.ESysENOSYS;
  ETIMEDOUT = BaseUnix.ESysETIMEDOUT;
  ECONNREFUSED = BaseUnix.ESysECONNREFUSED;
  EINPROGRESS = BaseUnix.ESysEINPROGRESS;
  EWOULDBLOCK = EAGAIN;
function __errno_location: Pcint; cdecl; external 'c';
function errno: cint; inline;

implementation
function errno: cint;
begin
  Result := __errno_location^;
end;
end.
