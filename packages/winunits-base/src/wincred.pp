{******************************************************************************}
{                                                                              }
{ Credentials Manager API interface Unit for Object Pascal                     }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: wincred.h, released November 2001. The original Pascal }
{ code is: WinCred.pas, released March 2002. The initial developer of the      }
{ Pascal code is Marcel van Brakel (brakelm att chello dott nl).               }
{                                                                              }
{ Portions created by Marcel van Brakel are Copyright (C) 1999-2001            }
{ Marcel van Brakel. All Rights Reserved.                                      }
{                                                                              }
{ Obtained through: Joint Endeavour of Delphi Innovators (Project JEDI)        }
{                                                                              }
{ You may retrieve the latest version of this file at the Project JEDI         }
{ APILIB home page, located at http://jedi-apilib.sourceforge.net              }
{                                                                              }
{ The contents of this file are used with permission, subject to the Mozilla   }
{ Public License Version 1.1 (the "License"); you may not use this file except }
{ in compliance with the License. You may obtain a copy of the License at      }
{ http://www.mozilla.org/MPL/MPL-1.1.html                                      }
{                                                                              }
{ Software distributed under the License is distributed on an "AS IS" basis,   }
{ WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for }
{ the specific language governing rights and limitations under the License.    }
{                                                                              }
{ Alternatively, the contents of this file may be used under the terms of the  }
{ GNU Lesser General Public License (the  "LGPL License"), in which case the   }
{ provisions of the LGPL License are applicable instead of those above.        }
{ If you wish to allow use of your version of this file only under the terms   }
{ of the LGPL License and not to allow others to use your version of this file }
{ under the MPL, indicate your decision by deleting  the provisions above and  }
{ replace  them with the notice and other provisions required by the LGPL      }
{ License.  If you do not delete the provisions above, a recipient may use     }
{ your version of this file under either the MPL or the LGPL License.          }
{                                                                              }
{ For more information about the LGPL: http://www.gnu.org/copyleft/lesser.html }
{                                                                              }
{******************************************************************************}

// $Id: WinCred.pas,v 1.15 2007/09/14 06:48:48 marquardt Exp $

unit WinCred;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

 //used for D5 compiling

interface

uses Winapi.Support, Windows;

type
  PCtxtHandle = PSecHandle;

//-----------------------------------------------------------------------------
// Macros
//-----------------------------------------------------------------------------

//
// Macro to determine whether CredUIPromptForCredentials should be called upon a failed
//      authentication attempt.
//
// Implemented as a macro so that the caller can delay load credui.dll only if this
//      macro returns TRUE.
//
// Include only status codes that imply the username/password are wrong or that the
//      password is expired.  In the former case, asking for a another username or password
//      is appropriate.  In the later case, we put up a different dialog asking the
//      user to change the password on the server.
//
// Don't include status codes such as ERROR_ACCOUNT_DISABLED, ERROR_ACCOUNT_RESTRICTION,
//      ERROR_ACCOUNT_LOCKED_OUT, ERROR_ACCOUNT_EXPIRED, ERROR_LOGON_TYPE_NOT_GRANTED.
//      For those, the user isn't going to have another account so prompting him
//      won't help.
//
// STATUS_DOWNGRADE_DETECTED is included to handle the case where a corporate laptop
//      is brought to another LAN.  A downgrade attack will indeed be detected,
//      but we want to popup UI to allow the user to connect to resources in the
//      other LAN.
//
// Don't use the CREDUIP_* macros directly.  Their definition is private to credui.dll.
//

// Don't require ntstatus.h

const
  STATUS_LOGON_FAILURE          = NTSTATUS($C000006D); // ntsubauth
  STATUS_WRONG_PASSWORD         = NTSTATUS($C000006A); // ntsubauth
  STATUS_PASSWORD_EXPIRED       = NTSTATUS($C0000071); // ntsubauth
  STATUS_PASSWORD_MUST_CHANGE   = NTSTATUS($C0000224); // ntsubauth
  STATUS_ACCESS_DENIED          = NTSTATUS($C0000022);
  STATUS_DOWNGRADE_DETECTED     = NTSTATUS($C0000388);
  STATUS_AUTHENTICATION_FIREWALL_FAILED = NTSTATUS($C0000413);
  STATUS_ACCOUNT_DISABLED       = NTSTATUS($C0000072);   // ntsubauth
  STATUS_ACCOUNT_RESTRICTION    = NTSTATUS($C000006E);   // ntsubauth
  STATUS_ACCOUNT_LOCKED_OUT     = NTSTATUS($C0000234);   // ntsubauth
  STATUS_ACCOUNT_EXPIRED        = NTSTATUS($C0000193);   // ntsubauth
  STATUS_LOGON_TYPE_NOT_GRANTED = NTSTATUS($C000015B);

// Don't require lmerr.h

  NERR_BASE            = 2100;
  NERR_PasswordExpired = NERR_BASE + 142; // The password of this user has expired.

function CREDUIP_IS_USER_PASSWORD_ERROR(_Status: NTSTATUS): BOOL;

function CREDUIP_IS_DOWNGRADE_ERROR(_Status: NTSTATUS): BOOL;

function CREDUIP_IS_EXPIRED_ERROR(_Status: NTSTATUS): BOOL;

function CREDUI_IS_AUTHENTICATION_ERROR(_Status: NTSTATUS): BOOL;

function CREDUI_NO_PROMPT_AUTHENTICATION_ERROR(_Status: NTSTATUS): BOOL;

//-----------------------------------------------------------------------------
// Structures
//-----------------------------------------------------------------------------

//
// Credential Attribute
//

const

// Maximum length of the various credential string fields (in characters)

  CRED_MAX_STRING_LENGTH = 256;

// Maximum length of the UserName field.  The worst case is <User>@<DnsDomain>

  CRED_MAX_USERNAME_LENGTH = 256 + 1 + 256;

// Maximum length of the TargetName field for CRED_TYPE_GENERIC (in characters)

  CRED_MAX_GENERIC_TARGET_NAME_LENGTH = 32767;

// Maximum length of the TargetName field for CRED_TYPE_DOMAIN_* (in characters)
//      Largest one is <DfsRoot>\<DfsShare>

  CRED_MAX_DOMAIN_TARGET_NAME_LENGTH = 256 + 1 + 80;

// Maximum size of the Credential Attribute Value field (in bytes)

  CRED_MAX_VALUE_SIZE = 256;

// Maximum number of attributes per credential

  CRED_MAX_ATTRIBUTES = 64;

type
  PCREDENTIAL_ATTRIBUTEA = ^CREDENTIAL_ATTRIBUTEA;
  _CREDENTIAL_ATTRIBUTEA = record
    Keyword: LPSTR;
    Flags: DWORD;
    ValueSize: DWORD;
    Value: LPBYTE;
  end;
  CREDENTIAL_ATTRIBUTEA = _CREDENTIAL_ATTRIBUTEA;
  TCredentialAttributeA = CREDENTIAL_ATTRIBUTEA;
  PCredentialAttributeA = PCREDENTIAL_ATTRIBUTEA;

  PCREDENTIAL_ATTRIBUTEW = ^CREDENTIAL_ATTRIBUTEW;
  _CREDENTIAL_ATTRIBUTEW = record
    Keyword: LPWSTR;
    Flags: DWORD;
    ValueSize: DWORD;
    Value: LPBYTE;
  end;
  CREDENTIAL_ATTRIBUTEW = _CREDENTIAL_ATTRIBUTEW;
  TCredentialAttributeW = CREDENTIAL_ATTRIBUTEW;
  PCredentialAttributeW = PCREDENTIAL_ATTRIBUTEW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  CREDENTIAL_ATTRIBUTE = CREDENTIAL_ATTRIBUTEW;
  PCREDENTIAL_ATTRIBUTE = PCREDENTIAL_ATTRIBUTEW;
  TCredentialAttribute = TCredentialAttributeW;
  PCredentialAttribute = PCredentialAttributeW;
{$else}
  CREDENTIAL_ATTRIBUTE = CREDENTIAL_ATTRIBUTEA;
  PCREDENTIAL_ATTRIBUTE = PCREDENTIAL_ATTRIBUTEA;
  TCredentialAttribute = TCredentialAttributeA;
  PCredentialAttribute = PCredentialAttributeA;
{$endif}

//
// Special values of the TargetName field
//

const
  CRED_SESSION_WILDCARD_NAME_W      = WideString('*Session');
  CRED_SESSION_WILDCARD_NAME_A      = '*Session';
  CRED_SESSION_WILDCARD_NAME_LENGTH = SizeOf(CRED_SESSION_WILDCARD_NAME_A) - 1;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  CRED_SESSION_WILDCARD_NAME = CRED_SESSION_WILDCARD_NAME_W;
{$else}
  CRED_SESSION_WILDCARD_NAME = CRED_SESSION_WILDCARD_NAME_A;
{$endif}

//
// Values of the Credential Flags field.
//

const
  CRED_FLAGS_PASSWORD_FOR_CERT  = $0001;
  CRED_FLAGS_PROMPT_NOW         = $0002;
  CRED_FLAGS_USERNAME_TARGET    = $0004;
  CRED_FLAGS_OWF_CRED_BLOB      = $0008;
  CRED_FLAGS_VALID_FLAGS        = $000F;  // Mask of all valid flags

//
// Values of the Credential Type field.
//

  CRED_TYPE_GENERIC                 = 1;
  CRED_TYPE_DOMAIN_PASSWORD         = 2;
  CRED_TYPE_DOMAIN_CERTIFICATE      = 3;
  CRED_TYPE_DOMAIN_VISIBLE_PASSWORD = 4;
  CRED_TYPE_MAXIMUM                 = 5; // Maximum supported cred type
  CRED_TYPE_MAXIMUM_EX              = CRED_TYPE_MAXIMUM + 1000;  // Allow new applications to run on old OSes

//
// Maximum size of the CredBlob field (in bytes)
//

  CRED_MAX_CREDENTIAL_BLOB_SIZE = 512;

//
// Values of the Credential Persist field
//

  CRED_PERSIST_NONE          = 0;
  CRED_PERSIST_SESSION       = 1;
  CRED_PERSIST_LOCAL_MACHINE = 2;
  CRED_PERSIST_ENTERPRISE    = 3;

//
// A credential
//

type
  PCREDENTIALA = ^CREDENTIALA;
  _CREDENTIALA = record
    Flags: DWORD;
    Type_: DWORD;
    TargetName: LPSTR;
    Comment: LPSTR;
    LastWritten: FILETIME;
    CredentialBlobSize: DWORD;
    CredentialBlob: LPBYTE;
    Persist: DWORD;
    AttributeCount: DWORD;
    Attributes: PCREDENTIAL_ATTRIBUTEA;
    TargetAlias: LPSTR;
    UserName: LPSTR;
  end;
  CREDENTIALA = _CREDENTIALA;
  TCredentialA = CREDENTIALA;

  PCREDENTIALW = ^CREDENTIALW;
  _CREDENTIALW = record
    Flags: DWORD;
    Type_: DWORD;
    TargetName: LPWSTR;
    Comment: LPWSTR;
    LastWritten: FILETIME;
    CredentialBlobSize: DWORD;
    CredentialBlob: LPBYTE;
    Persist: DWORD;
    AttributeCount: DWORD;
    Attributes: PCREDENTIAL_ATTRIBUTEW;
    TargetAlias: LPWSTR;
    UserName: LPWSTR;
  end;
  CREDENTIALW = _CREDENTIALW;
  TCredentialW = CREDENTIALW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  CREDENTIAL = CREDENTIALW;
  PCREDENTIAL = PCREDENTIALW;
  TCredential = TCredentialW;
{$else}
  CREDENTIAL = CREDENTIALA;
  PCREDENTIAL = PCREDENTIALA;
  TCredential = TCredentialA;
{$endif}

//
// Value of the Flags field in CREDENTIAL_TARGET_INFORMATION
//

const
  CRED_TI_SERVER_FORMAT_UNKNOWN  = $0001; // Don't know if server name is DNS or netbios format
  CRED_TI_DOMAIN_FORMAT_UNKNOWN  = $0002; // Don't know if domain name is DNS or netbios format
  CRED_TI_ONLY_PASSWORD_REQUIRED = $0004; // Server only requires a password and not a username
  CRED_TI_USERNAME_TARGET        = $0008; // TargetName is username
  CRED_TI_CREATE_EXPLICIT_CRED   = $0010; // When creating a cred, create one named TargetInfo->TargetName
  CRED_TI_WORKGROUP_MEMBER       = $0020; // Indicates the machine is a member of a workgroup
  CRED_TI_VALID_FLAGS            = $003F;

//
// A credential target
//

type
  PCREDENTIAL_TARGET_INFORMATIONA = ^CREDENTIAL_TARGET_INFORMATIONA;
  _CREDENTIAL_TARGET_INFORMATIONA = record
    TargetName: LPSTR;
    NetbiosServerName: LPSTR;
    DnsServerName: LPSTR;
    NetbiosDomainName: LPSTR;
    DnsDomainName: LPSTR;
    DnsTreeName: LPSTR;
    PackageName: LPSTR;
    Flags: ULONG;
    CredTypeCount: DWORD;
    CredTypes: LPDWORD;
  end;
  CREDENTIAL_TARGET_INFORMATIONA = _CREDENTIAL_TARGET_INFORMATIONA;
  TCredentialTargetInformationA = CREDENTIAL_TARGET_INFORMATIONA;
  PCredentialTargetInformationA = PCREDENTIAL_TARGET_INFORMATIONA;

  PCREDENTIAL_TARGET_INFORMATIONW = ^CREDENTIAL_TARGET_INFORMATIONW;
  _CREDENTIAL_TARGET_INFORMATIONW = record
    TargetName: LPWSTR;
    NetbiosServerName: LPWSTR;
    DnsServerName: LPWSTR;
    NetbiosDomainName: LPWSTR;
    DnsDomainName: LPWSTR;
    DnsTreeName: LPWSTR;
    PackageName: LPWSTR;
    Flags: ULONG;
    CredTypeCount: DWORD;
    CredTypes: LPDWORD;
  end;
  CREDENTIAL_TARGET_INFORMATIONW = _CREDENTIAL_TARGET_INFORMATIONW;
  TCredentialTargetInformationW = CREDENTIAL_TARGET_INFORMATIONW;
  PCredentialTargetInformationW = PCREDENTIAL_TARGET_INFORMATIONW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  CREDENTIAL_TARGET_INFORMATION = CREDENTIAL_TARGET_INFORMATIONW;
  PCREDENTIAL_TARGET_INFORMATION = PCREDENTIAL_TARGET_INFORMATIONW;
  TCredentialTargetInformation = TCredentialTargetInformationW;
  PCredentialTargetInformation = PCredentialTargetInformationW;
{$else}
  CREDENTIAL_TARGET_INFORMATION = CREDENTIAL_TARGET_INFORMATIONA;
  PCREDENTIAL_TARGET_INFORMATION = PCREDENTIAL_TARGET_INFORMATIONA;
  TCredentialTargetInformation = TCredentialTargetInformationA;
  PCredentialTargetInformation = PCredentialTargetInformationA;
{$endif}

//
// Certificate credential information
//
// The cbSize should be the size of the structure, sizeof(CERT_CREDENTIAL_INFO),
// rgbHashofCert is the hash of the cert which is to be used as the credential.
//

const
  CERT_HASH_LENGTH = 20; // SHA1 hashes are used for cert hashes

type
  PCERT_CREDENTIAL_INFO = ^CERT_CREDENTIAL_INFO;
  _CERT_CREDENTIAL_INFO = record
    cbSize: ULONG;
    rgbHashOfCert: array [0..CERT_HASH_LENGTH - 1] of UCHAR;
  end;
  CERT_CREDENTIAL_INFO = _CERT_CREDENTIAL_INFO;
  TCertCredentialInfo = CERT_CREDENTIAL_INFO;
  PCertCredentialInfo = PCERT_CREDENTIAL_INFO;

//
// Username Target credential information
//
// This credential can be pass to LsaLogonUser to ask it to find a credential with a
// TargetName of UserName.
//

  PUSERNAME_TARGET_CREDENTIAL_INFO = ^USERNAME_TARGET_CREDENTIAL_INFO;
  _USERNAME_TARGET_CREDENTIAL_INFO = record
    UserName: LPWSTR;
  end;
  USERNAME_TARGET_CREDENTIAL_INFO = _USERNAME_TARGET_CREDENTIAL_INFO;
  TUsernameTargetCredentialInfo = USERNAME_TARGET_CREDENTIAL_INFO;
  PUsernameTargetCredentialInfo = PUSERNAME_TARGET_CREDENTIAL_INFO;

//
// Credential type for credential marshaling routines
//

  _CRED_MARSHAL_TYPE = DWORD;
  CRED_MARSHAL_TYPE = _CRED_MARSHAL_TYPE;
  PCRED_MARSHAL_TYPE = ^CRED_MARSHAL_TYPE;
  TCredMarshalType = CRED_MARSHAL_TYPE;
  PCredMarshalType = PCRED_MARSHAL_TYPE;

const
  CertCredential = 1;
  UsernameTargetCredential = 2;

//
// Credential UI info
//

type
  PCREDUI_INFOA = ^CREDUI_INFOA;
  _CREDUI_INFOA = record
    cbSize: DWORD;
    hwndParent: HWND;
    pszMessageText: PCSTR;
    pszCaptionText: PCSTR;
    hbmBanner: HBITMAP;
  end;
  CREDUI_INFOA = _CREDUI_INFOA;
  TCredUIInfoA = CREDUI_INFOA;
  PCredUIInfoA = PCREDUI_INFOA;

  PCREDUI_INFOW = ^CREDUI_INFOW;
  _CREDUI_INFOW = record
    cbSize: DWORD;
    hwndParent: HWND;
    pszMessageText: LPCWSTR;
    pszCaptionText: LPCWSTR;
    hbmBanner: HBITMAP;
  end;
  CREDUI_INFOW = _CREDUI_INFOW;
  TCredUIInfoW = CREDUI_INFOW;
  PCredUIInfoW = PCREDUI_INFOW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  CREDUI_INFO = CREDUI_INFOW;
  PCREDUI_INFO = PCREDUI_INFOW;
  TCredUIInfo = TCredUIInfoW;
  PCredUIInfo = PCredUIInfoW;
{$else}
  CREDUI_INFO = CREDUI_INFOA;
  PCREDUI_INFO = PCREDUI_INFOA;
  TCredUIInfo = TCredUIInfoA;
  PCredUIInfo = PCredUIInfoA;
{$endif}

//-----------------------------------------------------------------------------
// Values
//-----------------------------------------------------------------------------

// String length limits:

const
  CREDUI_MAX_MESSAGE_LENGTH        = 32767;
  CREDUI_MAX_CAPTION_LENGTH        = 128;
  CREDUI_MAX_GENERIC_TARGET_LENGTH = CRED_MAX_GENERIC_TARGET_NAME_LENGTH;
  CREDUI_MAX_DOMAIN_TARGET_LENGTH  = CRED_MAX_DOMAIN_TARGET_NAME_LENGTH;
  CREDUI_MAX_USERNAME_LENGTH       = CRED_MAX_USERNAME_LENGTH;
  CREDUI_MAX_PASSWORD_LENGTH       = CRED_MAX_CREDENTIAL_BLOB_SIZE div 2;

//
// Flags for CredUIPromptForCredentials and/or CredUICmdLinePromptForCredentials
//

  CREDUI_FLAGS_INCORRECT_PASSWORD          = $00001; // indicates the username is valid, but password is not
  CREDUI_FLAGS_DO_NOT_PERSIST              = $00002; // Do not show "Save" checkbox, and do not persist credentials
  CREDUI_FLAGS_REQUEST_ADMINISTRATOR       = $00004; // Populate list box with admin accounts
  CREDUI_FLAGS_EXCLUDE_CERTIFICATES        = $00008; // do not include certificates in the drop list
  CREDUI_FLAGS_REQUIRE_CERTIFICATE         = $00010;
  CREDUI_FLAGS_SHOW_SAVE_CHECK_BOX         = $00040;
  CREDUI_FLAGS_ALWAYS_SHOW_UI              = $00080;
  CREDUI_FLAGS_REQUIRE_SMARTCARD           = $00100;
  CREDUI_FLAGS_PASSWORD_ONLY_OK            = $00200;
  CREDUI_FLAGS_VALIDATE_USERNAME           = $00400;
  CREDUI_FLAGS_COMPLETE_USERNAME           = $00800;
  CREDUI_FLAGS_PERSIST                     = $01000; // Do not show "Save" checkbox, but persist credentials anyway
  CREDUI_FLAGS_SERVER_CREDENTIAL           = $04000;
  CREDUI_FLAGS_EXPECT_CONFIRMATION         = $20000; // do not persist unless caller later confirms credential via CredUIConfirmCredential() api
  CREDUI_FLAGS_GENERIC_CREDENTIALS         = $40000; // Credential is a generic credential
  CREDUI_FLAGS_USERNAME_TARGET_CREDENTIALS = $80000; // Credential has a username as the target
  CREDUI_FLAGS_KEEP_USERNAME               = $100000; // don't allow the user to change the supplied username

//
// Mask of flags valid for CredUIPromptForCredentials
//

  CREDUI_FLAGS_PROMPT_VALID =
    CREDUI_FLAGS_INCORRECT_PASSWORD or
    CREDUI_FLAGS_DO_NOT_PERSIST or
    CREDUI_FLAGS_REQUEST_ADMINISTRATOR or
    CREDUI_FLAGS_EXCLUDE_CERTIFICATES or
    CREDUI_FLAGS_REQUIRE_CERTIFICATE or
    CREDUI_FLAGS_SHOW_SAVE_CHECK_BOX or
    CREDUI_FLAGS_ALWAYS_SHOW_UI or
    CREDUI_FLAGS_REQUIRE_SMARTCARD or
    CREDUI_FLAGS_PASSWORD_ONLY_OK or
    CREDUI_FLAGS_VALIDATE_USERNAME or
    CREDUI_FLAGS_COMPLETE_USERNAME or
    CREDUI_FLAGS_PERSIST or
    CREDUI_FLAGS_SERVER_CREDENTIAL or
    CREDUI_FLAGS_EXPECT_CONFIRMATION or
    CREDUI_FLAGS_GENERIC_CREDENTIALS or
    CREDUI_FLAGS_USERNAME_TARGET_CREDENTIALS or
    CREDUI_FLAGS_KEEP_USERNAME;

//-----------------------------------------------------------------------------
// Functions
//-----------------------------------------------------------------------------

//
// Values of flags to CredWrite and CredWriteDomainCredentials
//

const
  CRED_PRESERVE_CREDENTIAL_BLOB = $1;

type
  PPCREDENTIALA = ^PCREDENTIALA;
  PPCREDENTIALW = ^PCREDENTIALW;
  PPCREDENTIAL = ^PCREDENTIAL;

function CredWriteA(Credential: PCREDENTIALA; Flags: DWORD): BOOL; stdcall;
function CredWriteW(Credential: PCREDENTIALW; Flags: DWORD): BOOL; stdcall;
function CredWrite(Credential: PCREDENTIAL; Flags: DWORD): BOOL; stdcall;

function CredReadA(TargetName: LPCSTR; Type_: DWORD; Flags: DWORD; var Credential: PCREDENTIALA): BOOL; stdcall;
function CredReadW(TargetName: LPCWSTR; Type_: DWORD; Flags: DWORD; var Credential: PCREDENTIALW): BOOL; stdcall;
function CredRead(TargetName: LPCTSTR; Type_: DWORD; Flags: DWORD; var Credential: PCREDENTIAL): BOOL; stdcall;

function CredEnumerateA(Filter: LPCSTR; Flags: DWORD; var Count: DWORD; var Credential: PPCREDENTIALA): BOOL; stdcall;
function CredEnumerateW(Filter: LPCWSTR; Flags: DWORD; var Count: DWORD; var Credential: PPCREDENTIALW): BOOL; stdcall;
function CredEnumerate(Filter: LPCTSTR; Flags: DWORD; var Count: DWORD; var Credential: PPCREDENTIAL): BOOL; stdcall;

function CredWriteDomainCredentialsA(TargetInfo: PCREDENTIAL_TARGET_INFORMATIONA; Credential: PCREDENTIALA; Flags: DWORD): BOOL; stdcall;
function CredWriteDomainCredentialsW(TargetInfo: PCREDENTIAL_TARGET_INFORMATIONW; Credential: PCREDENTIALW; Flags: DWORD): BOOL; stdcall;
function CredWriteDomainCredentials(TargetInfo: PCREDENTIAL_TARGET_INFORMATION; Credential: PCREDENTIAL; Flags: DWORD): BOOL; stdcall;

//
// Values of flags to CredReadDomainCredentials
//

const
  CRED_CACHE_TARGET_INFORMATION = $1;

function CredReadDomainCredentialsA(TargetInfo: PCREDENTIAL_TARGET_INFORMATIONA; Flags: DWORD; var Count: DWORD; var Credential: PPCREDENTIALA): BOOL; stdcall;
function CredReadDomainCredentialsW(TargetInfo: PCREDENTIAL_TARGET_INFORMATIONW; Flags: DWORD; var Count: DWORD; var Credential: PPCREDENTIALW): BOOL; stdcall;
function CredReadDomainCredentials(TargetInfo: PCREDENTIAL_TARGET_INFORMATION; Flags: DWORD; var Count: DWORD; var Credential: PPCREDENTIAL): BOOL; stdcall;

function CredDeleteA(TargetName: LPCSTR; Type_: DWORD; Flags: DWORD): BOOL; stdcall;
function CredDeleteW(TargetName: LPCWSTR; Type_: DWORD; Flags: DWORD): BOOL; stdcall;
function CredDelete(TargetName: LPCTSTR; Type_: DWORD; Flags: DWORD): BOOL; stdcall;

function CredRenameA(OldTargetName: LPCSTR; NewTargetName: LPCSTR; Type_: DWORD; Flags: DWORD): BOOL; stdcall;
function CredRenameW(OldTargetName: LPCWSTR; NewTargetName: LPCWSTR; Type_: DWORD; Flags: DWORD): BOOL; stdcall;
function CredRename(OldTargetName: LPCTSTR; NewTargetName: LPCTSTR; Type_: DWORD; Flags: DWORD): BOOL; stdcall;

//
// Values of flags to CredGetTargetInfo
//

const
  CRED_ALLOW_NAME_RESOLUTION = $1;

function CredGetTargetInfoA(TargetName: LPCSTR; Flags: DWORD; var TargetInfo: PCREDENTIAL_TARGET_INFORMATIONA): BOOL; stdcall;
function CredGetTargetInfoW(TargetName: LPCWSTR; Flags: DWORD; var TargetInfo: PCREDENTIAL_TARGET_INFORMATIONW): BOOL; stdcall;
function CredGetTargetInfo(TargetName: LPCTSTR; Flags: DWORD; var TargetInfo: PCREDENTIAL_TARGET_INFORMATION): BOOL; stdcall;

function CredMarshalCredentialA(CredType: CRED_MARSHAL_TYPE; Credential: PVOID; var MarshaledCredential: LPSTR): BOOL; stdcall;
function CredMarshalCredentialW(CredType: CRED_MARSHAL_TYPE; Credential: PVOID; var MarshaledCredential: LPWSTR): BOOL; stdcall;
function CredMarshalCredential(CredType: CRED_MARSHAL_TYPE; Credential: PVOID; var MarshaledCredential: LPTSTR): BOOL; stdcall;

function CredUnmarshalCredentialA(MarshaledCredential: LPCSTR; CredType: PCRED_MARSHAL_TYPE; var Credential: PVOID): BOOL; stdcall;
function CredUnmarshalCredentialW(MarshaledCredential: LPCWSTR; CredType: PCRED_MARSHAL_TYPE; var Credential: PVOID): BOOL; stdcall;
function CredUnmarshalCredential(MarshaledCredential: LPCTSTR; CredType: PCRED_MARSHAL_TYPE; var Credential: PVOID): BOOL; stdcall;

function CredIsMarshaledCredentialA(MarshaledCredential: LPCSTR): BOOL; stdcall;
function CredIsMarshaledCredentialW(MarshaledCredential: LPCWSTR): BOOL; stdcall;
function CredIsMarshaledCredential(MarshaledCredential: LPCTSTR): BOOL; stdcall;

function CredGetSessionTypes(MaximumPersistCount: DWORD; MaximumPersist: LPDWORD): BOOL; stdcall;

procedure CredFree(Buffer: PVOID); stdcall;

function CredUIPromptForCredentialsA(pUiInfo: PCREDUI_INFOA; pszTargetName: PCSTR; pContext: PCtxtHandle; dwAuthError: DWORD; pszUserName: PSTR; ulUserNameBufferSize: ULONG; pszPassword: PSTR; ulPasswordBufferSize: ULONG; var save: BOOL; dwFlags: DWORD): DWORD; stdcall;
function CredUIPromptForCredentialsW(pUiInfo: PCREDUI_INFOW; pszTargetName: LPCWSTR; pContext: PCtxtHandle; dwAuthError: DWORD; pszUserName: PWSTR; ulUserNameBufferSize: ULONG; pszPassword: PWSTR; ulPasswordBufferSize: ULONG; var save: BOOL; dwFlags: DWORD): DWORD; stdcall;
function CredUIPromptForCredentials(pUiInfo: PCREDUI_INFO; pszTargetName: LPCTSTR; pContext: PCtxtHandle; dwAuthError: DWORD; pszUserName: PTSTR; ulUserNameBufferSize: ULONG; pszPassword: PTSTR; ulPasswordBufferSize: ULONG; var save: BOOL; dwFlags: DWORD): DWORD; stdcall;

function CredUIParseUserNameA(pszUserName: PCSTR; pszUser: PSTR; ulUserBufferSize: ULONG; pszDomain: PSTR; ulDomainBufferSize: ULONG): DWORD; stdcall;
function CredUIParseUserNameW(pszUserName: LPCWSTR; pszUser: PWSTR; ulUserBufferSize: ULONG; pszDomain: PWSTR; ulDomainBufferSize: ULONG): DWORD; stdcall;
function CredUIParseUserName(pszUserName: LPCTSTR; pszUser: PTSTR; ulUserBufferSize: ULONG; pszDomain: PTSTR; ulDomainBufferSize: ULONG): DWORD; stdcall;

function CredUICmdLinePromptForCredentialsA(pszTargetName: PCSTR; pContext: PCtxtHandle; dwAuthError: DWORD; UserName: PSTR; ulUserBufferSize: ULONG; pszPassword: PSTR; ulPasswordBufferSize: ULONG; pfSave: PBOOL; dwFlags: DWORD): DWORD; stdcall;
function CredUICmdLinePromptForCredentialsW(pszTargetName: LPCWSTR; pContext: PCtxtHandle; dwAuthError: DWORD; UserName: PWSTR; ulUserBufferSize: ULONG; pszPassword: PWSTR; ulPasswordBufferSize: ULONG; pfSave: PBOOL; dwFlags: DWORD): DWORD; stdcall;
function CredUICmdLinePromptForCredentials(pszTargetName: LPCTSTR; pContext: PCtxtHandle; dwAuthError: DWORD; UserName: PTSTR; ulUserBufferSize: ULONG; pszPassword: PTSTR; ulPasswordBufferSize: ULONG; pfSave: PBOOL; dwFlags: DWORD): DWORD; stdcall;

//
// Call this API with bConfirm set to TRUE to confirm that the credential (previously created
// via CredUIGetCredentials or CredUIPromptForCredentials worked, or with bConfirm set to FALSE
// to indicate it didn't

function CredUIConfirmCredentialsA(pszTargetName: PCSTR; bConfirm: BOOL): DWORD; stdcall;
function CredUIConfirmCredentialsW(pszTargetName: LPCWSTR; bConfirm: BOOL): DWORD; stdcall;
function CredUIConfirmCredentials(pszTargetName: LPCTSTR; bConfirm: BOOL): DWORD; stdcall;

function CredUIStoreSSOCredW(pszRealm, pszUsername, pszPassword: LPCWSTR; bPersist: BOOL): DWORD; stdcall;

function CredUIReadSSOCredW(pszRealm: LPCWSTR; out ppszUsername: PWSTR): DWORD; stdcall;

implementation
//uses ...

const
  credapi = 'advapi32.dll';
  credui = 'credui.dll';
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  AWSuffix = 'W';
{$else}
  AWSuffix = 'A';
{$endif}

function CREDUIP_IS_USER_PASSWORD_ERROR(_Status: NTSTATUS): BOOL;
begin
  Result :=
    (DWORD(_Status) = ERROR_LOGON_FAILURE) or
    (_Status = HRESULT_FROM_WIN32(ERROR_LOGON_FAILURE)) or
    (_Status = STATUS_LOGON_FAILURE) or
    (_Status = HRESULT_FROM_NT(STATUS_LOGON_FAILURE)) or
    (DWORD(_Status) = ERROR_ACCESS_DENIED) or
    (_Status = HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED)) or
    (_Status = STATUS_ACCESS_DENIED) or
    (_Status = HRESULT_FROM_NT(STATUS_ACCESS_DENIED)) or
    (DWORD(_Status) = ERROR_INVALID_PASSWORD) or
    (_Status = HRESULT_FROM_WIN32(ERROR_INVALID_PASSWORD)) or
    (_Status = STATUS_WRONG_PASSWORD) or
    (_Status = HRESULT_FROM_NT(STATUS_WRONG_PASSWORD)) or
    (_Status = SEC_E_NO_CREDENTIALS) or
    (_Status = SEC_E_LOGON_DENIED);
end;

function CREDUIP_IS_DOWNGRADE_ERROR(_Status: NTSTATUS): BOOL;
begin
  Result :=
    (DWORD(_Status) = ERROR_DOWNGRADE_DETECTED) or
    (_Status = HRESULT_FROM_WIN32(ERROR_DOWNGRADE_DETECTED)) or
    (_Status = STATUS_DOWNGRADE_DETECTED) or
    (_Status = HRESULT_FROM_NT(STATUS_DOWNGRADE_DETECTED))
end;

function CREDUIP_IS_EXPIRED_ERROR(_Status: NTSTATUS): BOOL;
begin
  Result :=
    (DWORD(_Status) = ERROR_PASSWORD_EXPIRED) or
    (_Status = HRESULT_FROM_WIN32( ERROR_PASSWORD_EXPIRED)) or
    (_Status = STATUS_PASSWORD_EXPIRED) or
    (_Status = HRESULT_FROM_NT( STATUS_PASSWORD_EXPIRED)) or
    (DWORD(_Status) = ERROR_PASSWORD_MUST_CHANGE) or
    (_Status = HRESULT_FROM_WIN32( ERROR_PASSWORD_MUST_CHANGE)) or
    (_Status = STATUS_PASSWORD_MUST_CHANGE) or
    (_Status = HRESULT_FROM_NT( STATUS_PASSWORD_MUST_CHANGE)) or
    (_Status = NERR_PasswordExpired) or
    (_Status = HRESULT_FROM_WIN32(NERR_PasswordExpired));
end;

function CREDUI_IS_AUTHENTICATION_ERROR(_Status: NTSTATUS): BOOL;
begin
  Result := CREDUIP_IS_USER_PASSWORD_ERROR(_Status) or CREDUIP_IS_DOWNGRADE_ERROR(_Status) or CREDUIP_IS_EXPIRED_ERROR(_Status);
end;

function CREDUI_NO_PROMPT_AUTHENTICATION_ERROR(_Status: NTSTATUS): BOOL;
begin
  Result :=
    (_Status = NTSTATUS(ERROR_AUTHENTICATION_FIREWALL_FAILED)) or
    (_Status = HRESULT_FROM_WIN32(ERROR_AUTHENTICATION_FIREWALL_FAILED)) or
    (_Status = STATUS_AUTHENTICATION_FIREWALL_FAILED) or
    (_Status = HRESULT_FROM_NT(STATUS_AUTHENTICATION_FIREWALL_FAILED)) or
    (DWORD(_Status) = ERROR_ACCOUNT_DISABLED) or
    (_Status = HRESULT_FROM_WIN32(ERROR_ACCOUNT_DISABLED)) or
    (_Status = STATUS_ACCOUNT_DISABLED) or
    (_Status = HRESULT_FROM_NT(STATUS_ACCOUNT_DISABLED)) or
    (DWORD(_Status) = ERROR_ACCOUNT_RESTRICTION) or
    (_Status = HRESULT_FROM_WIN32(ERROR_ACCOUNT_RESTRICTION)) or
    (_Status = STATUS_ACCOUNT_RESTRICTION) or
    (_Status = HRESULT_FROM_NT(STATUS_ACCOUNT_RESTRICTION)) or
    (DWORD(_Status) = ERROR_ACCOUNT_LOCKED_OUT) or
    (_Status = HRESULT_FROM_WIN32(ERROR_ACCOUNT_LOCKED_OUT)) or
    (_Status = STATUS_ACCOUNT_LOCKED_OUT) or
    (_Status = HRESULT_FROM_NT(STATUS_ACCOUNT_LOCKED_OUT)) or
    (DWORD(_Status) = ERROR_ACCOUNT_EXPIRED) or
    (_Status = HRESULT_FROM_WIN32(ERROR_ACCOUNT_EXPIRED)) or
    (_Status = STATUS_ACCOUNT_EXPIRED) or
    (_Status = HRESULT_FROM_NT(STATUS_ACCOUNT_EXPIRED)) or
    (DWORD(_Status) = ERROR_LOGON_TYPE_NOT_GRANTED) or
    (_Status = HRESULT_FROM_WIN32(ERROR_LOGON_TYPE_NOT_GRANTED)) or
    (_Status = STATUS_LOGON_TYPE_NOT_GRANTED) or
    (_Status = HRESULT_FROM_NT(STATUS_LOGON_TYPE_NOT_GRANTED));
end;

function CredWriteW; external credapi name 'CredWriteW';
function CredWriteA; external credapi name 'CredWriteA';
function CredWrite; external credapi name 'CredWrite' + AWSuffix;
function CredReadW; external credapi name 'CredReadW';
function CredReadA; external credapi name 'CredReadA';
function CredRead; external credapi name 'CredRead' + AWSuffix;
function CredEnumerateW; external credapi name 'CredEnumerateW';
function CredEnumerateA; external credapi name 'CredEnumerateA';
function CredEnumerate; external credapi name 'CredEnumerate' + AWSuffix;
function CredWriteDomainCredentialsW; external credapi name 'CredWriteDomainCredentialsW';
function CredWriteDomainCredentialsA; external credapi name 'CredWriteDomainCredentialsA';
function CredWriteDomainCredentials; external credapi name 'CredWriteDomainCredentials' + AWSuffix;
function CredReadDomainCredentialsW; external credapi name 'CredReadDomainCredentialsW';
function CredReadDomainCredentialsA; external credapi name 'CredReadDomainCredentialsA';
function CredReadDomainCredentials; external credapi name 'CredReadDomainCredentials' + AWSuffix;
function CredDeleteW; external credapi name 'CredDeleteW';
function CredDeleteA; external credapi name 'CredDeleteA';
function CredDelete; external credapi name 'CredDelete' + AWSuffix;
function CredRenameW; external credapi name 'CredRenameW';
function CredRenameA; external credapi name 'CredRenameA';
function CredRename; external credapi name 'CredRename' + AWSuffix;
function CredGetTargetInfoW; external credapi name 'CredGetTargetInfoW';
function CredGetTargetInfoA; external credapi name 'CredGetTargetInfoA';
function CredGetTargetInfo; external credapi name 'CredGetTargetInfo' + AWSuffix;
function CredMarshalCredentialW; external credapi name 'CredMarshalCredentialW';
function CredMarshalCredentialA; external credapi name 'CredMarshalCredentialA';
function CredMarshalCredential; external credapi name 'CredMarshalCredential' + AWSuffix;
function CredUnmarshalCredentialW; external credapi name 'CredUnmarshalCredentialW';
function CredUnmarshalCredentialA; external credapi name 'CredUnmarshalCredentialA';
function CredUnmarshalCredential; external credapi name 'CredUnmarshalCredential' + AWSuffix;
function CredIsMarshaledCredentialW; external credapi name 'CredIsMarshaledCredentialW';
function CredIsMarshaledCredentialA; external credapi name 'CredIsMarshaledCredentialA';
function CredIsMarshaledCredential; external credapi name 'CredIsMarshaledCredential' + AWSuffix;
function CredGetSessionTypes; external credapi name 'CredGetSessionTypes';
procedure CredFree; external credapi name 'CredFree';
function CredUIPromptForCredentialsW; external credui name 'CredUIPromptForCredentialsW';
function CredUIPromptForCredentialsA; external credui name 'CredUIPromptForCredentialsA';
function CredUIPromptForCredentials; external credui name 'CredUIPromptForCredentials' + AWSuffix;
function CredUIParseUserNameW; external credui name 'CredUIParseUserNameW';
function CredUIParseUserNameA; external credui name 'CredUIParseUserNameA';
function CredUIParseUserName; external credui name 'CredUIParseUserName' + AWSuffix;
function CredUICmdLinePromptForCredentialsW; external credui name 'CredUICmdLinePromptForCredentialsW';
function CredUICmdLinePromptForCredentialsA; external credui name 'CredUICmdLinePromptForCredentialsA';
function CredUICmdLinePromptForCredentials; external credui name 'CredUICmdLinePromptForCredentials' + AWSuffix;
function CredUIConfirmCredentialsW; external credui name 'CredUIConfirmCredentialsW';
function CredUIConfirmCredentialsA; external credui name 'CredUIConfirmCredentialsA';
function CredUIConfirmCredentials; external credui name 'CredUIConfirmCredentials' + AWSuffix;
function CredUIStoreSSOCredW; external credui name 'CredUIStoreSSOCredW';
function CredUIReadSSOCredW; external credui name 'CredUIReadSSOCredW';

end.
