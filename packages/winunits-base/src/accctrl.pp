{******************************************************************************}
{                                                                              }
{ Interface Unit for Object Pascal                                             }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2003 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ Portions created by Marcel van Brakel are Copyright (C) 2003                 }
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

// $Id: AccCtrl.pas,v 1.9 2007/09/05 11:58:48 dezipaitor Exp $
unit AccCtrl;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

uses Windows;

(* Dependencies
// winnt
PSID
//wintype
HLOCAL
DWORD
GUID
LPSTR
LPWSTR
ULONG
PVOID
HANDLE
BOOL
LONG
*)

// (rom) MACRO
function AccFree(hMem: HLOCAL): HLOCAL;

//
// Definition:
// This enumerated type defines the objects supported by the get/set API within
// this document.  See section 3.1, Object Types for a detailed definition of the
// supported object types, and their name formats.
//

type
  _SE_OBJECT_TYPE = (
    SE_UNKNOWN_OBJECT_TYPE,
    SE_FILE_OBJECT,
    SE_SERVICE,
    SE_PRINTER,
    SE_REGISTRY_KEY,
    SE_LMSHARE,
    SE_KERNEL_OBJECT,
    SE_WINDOW_OBJECT,
    SE_DS_OBJECT,
    SE_DS_OBJECT_ALL,
    SE_PROVIDER_DEFINED_OBJECT,
    SE_WMIGUID_OBJECT,
    SE_REGISTRY_WOW64_32KEY);
  SE_OBJECT_TYPE = _SE_OBJECT_TYPE;
  TSeObjectType = SE_OBJECT_TYPE;

//
// Definition: TRUSTEE_TYPE
// This enumerated type specifies the type of trustee account for the trustee
// returned by the API described in this document.
// TRUSTEE_IS_UNKNOWN - The trustee is an unknown, but not necessarily invalid
//                      type.  This field is not validated on input to the APIs
//                      that take Trustees.
// TRUSTEE_IS_USER      The trustee account is a user account.
// TRUSTEE_IS_GROUP     The trustee account is a group account.
//

  _TRUSTEE_TYPE = (
    TRUSTEE_IS_UNKNOWN,
    TRUSTEE_IS_USER,
    TRUSTEE_IS_GROUP,
    TRUSTEE_IS_DOMAIN,
    TRUSTEE_IS_ALIAS,
    TRUSTEE_IS_WELL_KNOWN_GROUP,
    TRUSTEE_IS_DELETED,
    TRUSTEE_IS_INVALID,
    TRUSTEE_IS_COMPUTER);
  TRUSTEE_TYPE = _TRUSTEE_TYPE;
  TTrusteeType = TRUSTEE_TYPE;

//
// Definition: TRUSTEE_FORM
// This enumerated type specifies the form the trustee identifier is in for a
// particular trustee.
// TRUSTEE_IS_SID       The trustee is identified with a SID rather than with a name.
// TRUSTEE_IS_NAME      The trustee is identified with a name.
//

  _TRUSTEE_FORM = (
    TRUSTEE_IS_SID,
    TRUSTEE_IS_NAME,
    TRUSTEE_BAD_FORM,
    TRUSTEE_IS_OBJECTS_AND_SID,
    TRUSTEE_IS_OBJECTS_AND_NAME);
  TRUSTEE_FORM = _TRUSTEE_FORM;
  TTrusteeForm = TRUSTEE_FORM;

//
// Definition: MULTIPLE_TRUSTEE_OPERATION
// If the trustee is a multiple trustee, this enumerated type specifies the type.
// TRUSTEE_IS_IMPERSONATE       The trustee is an impersonate trustee and the multiple
//                          trustee field in the trustee points to another trustee
//                          that is a trustee for the server that will be doing the
//                          impersonation.
//

  _MULTIPLE_TRUSTEE_OPERATION = (NO_MULTIPLE_TRUSTEE, TRUSTEE_IS_IMPERSONATE);
  MULTIPLE_TRUSTEE_OPERATION = _MULTIPLE_TRUSTEE_OPERATION;
  TMultipleTrusteeOperation = MULTIPLE_TRUSTEE_OPERATION;

  POBJECTS_AND_SID = ^OBJECTS_AND_SID;
  _OBJECTS_AND_SID = record
    ObjectsPresent: DWORD;
    ObjectTypeGuid: GUID;
    InheritedObjectTypeGuid: GUID;
    pSid: PSID;
  end;
  OBJECTS_AND_SID = _OBJECTS_AND_SID;
  TObjectsAndSid = OBJECTS_AND_SID;
  PObjectsAndSid = POBJECTS_AND_SID;

  POBJECTS_AND_NAME_A = ^OBJECTS_AND_NAME_A;
  _OBJECTS_AND_NAME_A = record
    ObjectsPresent: DWORD;
    ObjectType: SE_OBJECT_TYPE;
    ObjectTypeName: LPSTR;
    InheritedObjectTypeName: LPSTR;
    ptstrName: LPSTR;
  end;
  OBJECTS_AND_NAME_A = _OBJECTS_AND_NAME_A;
  TObjectsAndNameA = OBJECTS_AND_NAME_A;
  PObjectsAndNameA = POBJECTS_AND_NAME_A;

  POBJECTS_AND_NAME_W = ^OBJECTS_AND_NAME_W;
  _OBJECTS_AND_NAME_W = record
    ObjectsPresent: DWORD;
    ObjectType: SE_OBJECT_TYPE;
    ObjectTypeName: LPWSTR;
    InheritedObjectTypeName: LPWSTR;
    ptstrName: LPWSTR;
  end;
  OBJECTS_AND_NAME_W = _OBJECTS_AND_NAME_W;
  TObjectsAndNameW = OBJECTS_AND_NAME_W;
  PObjectsAndNameW = POBJECTS_AND_NAME_W;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  OBJECTS_AND_NAME = OBJECTS_AND_NAME_W;
  POBJECTS_AND_NAME = POBJECTS_AND_NAME_W;
  TObjectsAndName = TObjectsAndNameW;
  PObjectsAndName = PObjectsAndNameW;
{$else}
  OBJECTS_AND_NAME = OBJECTS_AND_NAME_A;
  POBJECTS_AND_NAME = POBJECTS_AND_NAME_A;
  TObjectsAndName = TObjectsAndNameA;
  PObjectsAndName = PObjectsAndNameA;
{$endif}

//
// Definition: TRUSTEE
// This structure is used to pass account information into and out of the system
// using the API defined in this document.
// PMultipleTrustee     - if NON-NULL, points to another trustee structure, as
//                    defined by the multiple trustee operation field.
// MultipleTrusteeOperation - Defines the multiple trustee operation/type.
// TrusteeForm - defines if the trustee is defined by name or SID.
// TrusteeType - defines if the trustee type is unknown, a user or a group.
// PwcsName     - points to the trustee name or the trustee SID.
//

  PTRUSTEE_A = ^TRUSTEE_A;
  _TRUSTEE_A = record
    pMultipleTrustee: PTRUSTEE_A;
    MultipleTrusteeOperation: MULTIPLE_TRUSTEE_OPERATION;
    TrusteeForm: TRUSTEE_FORM;
    TrusteeType: TRUSTEE_TYPE;
    ptstrName: LPSTR;
  end;
  TRUSTEE_A = _TRUSTEE_A;
  TRUSTEEA = TRUSTEE_A;
  PPTRUSTEE_A = ^PTRUSTEE_A;
  {$NODEFINE PPTRUSTEE_A}
  TTrusteeA = TRUSTEE_A;
  PTrusteeA = PTRUSTEE_A;

  PTRUSTEE_W = ^TRUSTEE_W;
  _TRUSTEE_W = record
    pMultipleTrustee: PTRUSTEE_W;
    MultipleTrusteeOperation: MULTIPLE_TRUSTEE_OPERATION;
    TrusteeForm: TRUSTEE_FORM;
    TrusteeType: TRUSTEE_TYPE;
    ptstrName: LPWSTR;
  end;
  TRUSTEE_W = _TRUSTEE_W;
  TRUSTEEW = TRUSTEE_W;
  PPTRUSTEE_W = ^PTRUSTEE_W;
  {$NODEFINE PPTRUSTEE_W}
  TTrusteeW = TRUSTEE_W;
  PTrusteeW = PTRUSTEE_W;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  TRUSTEE_ = TRUSTEE_W;
  PTRUSTEE_ = PTRUSTEE_W;
  TRUSTEE = TRUSTEEW;
  PPTRUSTEE = ^PPTRUSTEE_W;
{$else}
  TRUSTEE_ = TRUSTEE_A;
  PTRUSTEE_ = PTRUSTEE_A;
  TRUSTEE = TRUSTEEA;
  PPTRUSTEE = ^PPTRUSTEE_A;
{$endif}
  {$NODEFINE PPTRUSTEE}
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  TTrustee = TTrusteeW;
  PTrustee = PTrusteeW;
{$else}
  TTrustee = TTrusteeA;
  PTrustee = PTrusteeA;
{$endif}

//
// Definition: ACCESS_MODE
// This enumerated type specifies how permissions are (requested)/to be applied
//  for the trustee by the access control entry.  On input this field can by any
//  of the values, although it is not meaningful to mix access control and audit
//  control entries.  On output this field will be either SET_ACCESS, DENY_ACCESS,
// SET_AUDIT_SUCCESS, SET_AUDIT_FAILURE.
// The following descriptions define how this type effects an explicit access
// request to apply access permissions to an object.
// GRANT_ACCESS - The trustee will have at least the requested permissions upon
//                successful completion of the command. (If the trustee has
//                additional permissions they will not be removed).
// SET_ACCESS - The trustee will have exactly the requested permissions upon
//              successful completion of the command.
// DENY_ACCESS - The trustee will be denied the specified permissions.
// REVOKE_ACCESS - Any explicit access rights the trustee has will be revoked.
// SET_AUDIT_SUCCESS - The trustee will be audited for successful opens of the
//                     object using the requested permissions.
// SET_AUDIT_FAILURE - The trustee will be audited for failed opens of the object
//                     using the requested permissions.
//

  _ACCESS_MODE = (
    NOT_USED_ACCESS,
    GRANT_ACCESS,
    SET_ACCESS,
    DENY_ACCESS,
    REVOKE_ACCESS,
    SET_AUDIT_SUCCESS,
    SET_AUDIT_FAILURE);
  ACCESS_MODE = _ACCESS_MODE;
  TAccessMode = _ACCESS_MODE;

//
// Definition: Inheritance flags
// These bit masks are provided to allow simple application of inheritance in
// explicit access requests on containers.
// NO_INHERITANCE       The specific access permissions will only be applied to
//                  the container, and will not be inherited by objects created
//                  within the container.
// SUB_CONTAINERS_ONLY_INHERIT  The specific access permissions will be inherited
//                              and applied to sub containers created within the
//                              container, and will be applied to the container
//                              itself.
// SUB_OBJECTS_ONLY_INHERIT     The specific access permissions will only be inherited
//                              by objects created within the specific container.
//                              The access permissions will not be applied to the
//                              container itself.
// SUB_CONTAINERS_AND_OBJECTS_INHERIT   The specific access permissions will be
//                                      inherited by containers created within the
//                                      specific container, will be applied to
//                                      objects created within the container, but
//                                      will not be applied to the container itself.
//

const
  NO_INHERITANCE                     = $0;
  SUB_OBJECTS_ONLY_INHERIT           = $1;
  SUB_CONTAINERS_ONLY_INHERIT        = $2;
  SUB_CONTAINERS_AND_OBJECTS_INHERIT = $3;
  INHERIT_NO_PROPAGATE               = $4;
  INHERIT_ONLY                       = $8;

//
// Informational bit that is returned
//

  INHERITED_ACCESS_ENTRY = $10;

//
// Informational bit that tells where a node was inherited from.  Valid only
// for NT 5 APIs
//

  INHERITED_PARENT      = $10000000;
  INHERITED_GRANDPARENT = $20000000;

//
// Definition: EXPLICIT_ACCESS
// This structure is used to pass access control entry information into and out
// of the system using the API defined in this document.
// grfAccessPermissions - This contains the access permissions to assign for the
//                     trustee.  It is in the form of an NT access mask.
// grfAccessMode - This field defines how the permissions are to be applied for
//                 the trustee.
// grfInheritance - For containers, this field defines how the access control
//                  entry is/(is requested) to be inherited on
//                  objects/sub-containers created within the container.
// Trustee - This field contains the definition of the trustee account the
//           explicit access applies to.
//

type
  PEXPLICIT_ACCESS_A = ^EXPLICIT_ACCESS_A;
  _EXPLICIT_ACCESS_A = record
    grfAccessPermissions: DWORD;
    grfAccessMode: ACCESS_MODE;
    grfInheritance: DWORD;
    Trustee: TRUSTEE_A;
  end;
  EXPLICIT_ACCESS_A = _EXPLICIT_ACCESS_A;
  EXPLICIT_ACCESSA = EXPLICIT_ACCESS_A;
  PEXPLICIT_ACCESSA = PEXPLICIT_ACCESS_A;
  TExplicitAccessA = EXPLICIT_ACCESS_A;
  PExplicitAccessA = PEXPLICIT_ACCESS_A;

  PEXPLICIT_ACCESS_W = ^EXPLICIT_ACCESS_W;
  _EXPLICIT_ACCESS_W = record
    grfAccessPermissions: DWORD;
    grfAccessMode: ACCESS_MODE;
    grfInheritance: DWORD;
    Trustee: TRUSTEE_W;
  end;
  EXPLICIT_ACCESS_W = _EXPLICIT_ACCESS_W;
  EXPLICIT_ACCESSW = EXPLICIT_ACCESS_W;
  PEXPLICIT_ACCESSW = PEXPLICIT_ACCESS_W;
  TExplicitAccessW = EXPLICIT_ACCESS_W;
  PExplicitAccessW = PEXPLICIT_ACCESS_W;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  EXPLICIT_ACCESS_ = EXPLICIT_ACCESS_W;
  PEXPLICIT_ACCESS_ = PEXPLICIT_ACCESS_W;
  EXPLICIT_ACCESS = EXPLICIT_ACCESSW;
  PEXPLICIT_ACCESS = PEXPLICIT_ACCESSW;
  TExplicitAccess = TExplicitAccessW;
  PExplicitAccess = PExplicitAccessW;
{$else}
  EXPLICIT_ACCESS_ = EXPLICIT_ACCESS_A;
  PEXPLICIT_ACCESS_ = PEXPLICIT_ACCESS_A;
  EXPLICIT_ACCESS = EXPLICIT_ACCESSA;
  PEXPLICIT_ACCESS = PEXPLICIT_ACCESSA;
  TExplicitAccess = TExplicitAccessA;
  PExplicitAccess = PExplicitAccessA;
{$endif}

//------------------------------------------------------------------------------
//                              NT5 APIs
//------------------------------------------------------------------------------

//
// Default provider
//

const
  ACCCTRL_DEFAULT_PROVIDERA = 'Windows NT Access Provider';
  ACCCTRL_DEFAULT_PROVIDERW = 'Windows NT Access Provider';

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ACCCTRL_DEFAULT_PROVIDER = ACCCTRL_DEFAULT_PROVIDERW;
{$else}
  ACCCTRL_DEFAULT_PROVIDER = ACCCTRL_DEFAULT_PROVIDERA;
{$endif}

//
// Access rights
//

type
  ACCESS_RIGHTS = ULONG;
  PACCESS_RIGHTS = ^ACCESS_RIGHTS;

//
// Inheritance flags
//

  INHERIT_FLAGS = ULONG;
  PINHERIT_FLAGS = ^INHERIT_FLAGS;

//
// Access / Audit structures
//

  PACTRL_ACCESS_ENTRYA = ^ACTRL_ACCESS_ENTRYA;
  _ACTRL_ACCESS_ENTRYA = record
    Trustee: TRUSTEE_A;
    fAccessFlags: ULONG;
    Access: ACCESS_RIGHTS;
    ProvSpecificAccess: ACCESS_RIGHTS;
    Inheritance: INHERIT_FLAGS;
    lpInheritProperty: LPSTR;
  end;
  ACTRL_ACCESS_ENTRYA = _ACTRL_ACCESS_ENTRYA;
  TActrlAccessEntryA = ACTRL_ACCESS_ENTRYA;
  PActrlAccessEntryA = PACTRL_ACCESS_ENTRYA;

//
// Access / Audit structures
//

  PACTRL_ACCESS_ENTRYW = ^ACTRL_ACCESS_ENTRYW;
  _ACTRL_ACCESS_ENTRYW = record
    Trustee: TRUSTEE_W;
    fAccessFlags: ULONG;
    Access: ACCESS_RIGHTS;
    ProvSpecificAccess: ACCESS_RIGHTS;
    Inheritance: INHERIT_FLAGS;
    lpInheritProperty: LPWSTR;
  end;
  ACTRL_ACCESS_ENTRYW = _ACTRL_ACCESS_ENTRYW;
  TActrlAccessEntryW = ACTRL_ACCESS_ENTRYW;
  PActrlAccessEntryW = PACTRL_ACCESS_ENTRYW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ACTRL_ACCESS_ENTRY = ACTRL_ACCESS_ENTRYW;
  PACTRL_ACCESS_ENTRY = PACTRL_ACCESS_ENTRYW;
  TActrlAccessEntry = TActrlAccessEntryW;
  PActrlAccessEntry = PActrlAccessEntryW;
{$else}
  ACTRL_ACCESS_ENTRY = ACTRL_ACCESS_ENTRYA;
  PACTRL_ACCESS_ENTRY = PACTRL_ACCESS_ENTRYA;
  TActrlAccessEntry = TActrlAccessEntryA;
  PActrlAccessEntry = PActrlAccessEntryA;
{$endif}

  PACTRL_ACCESS_ENTRY_LISTA = ^ACTRL_ACCESS_ENTRY_LISTA;
  _ACTRL_ACCESS_ENTRY_LISTA = record
    cEntries: ULONG;
    pAccessList: PACTRL_ACCESS_ENTRYA;
  end;
  ACTRL_ACCESS_ENTRY_LISTA = _ACTRL_ACCESS_ENTRY_LISTA;
  TActrlAccessEntryListA = ACTRL_ACCESS_ENTRY_LISTA;
  PActrlAccessEntryListA = PACTRL_ACCESS_ENTRY_LISTA;

  PACTRL_ACCESS_ENTRY_LISTW = ^ACTRL_ACCESS_ENTRY_LISTW;
  _ACTRL_ACCESS_ENTRY_LISTW = record
    cEntries: ULONG;
    pAccessList: PACTRL_ACCESS_ENTRYW;
  end;
  ACTRL_ACCESS_ENTRY_LISTW = _ACTRL_ACCESS_ENTRY_LISTW;
  TActrlAccessEntryListW = ACTRL_ACCESS_ENTRY_LISTW;
  PActrlAccessEntryListW = PACTRL_ACCESS_ENTRY_LISTW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ACTRL_ACCESS_ENTRY_LIST = ACTRL_ACCESS_ENTRY_LISTW;
  PACTRL_ACCESS_ENTRY_LIST = PACTRL_ACCESS_ENTRY_LISTW;
  TActrlAccessEntryList = TActrlAccessEntryListW;
  PActrlAccessEntryList = PActrlAccessEntryListW;
{$else}
  ACTRL_ACCESS_ENTRY_LIST = ACTRL_ACCESS_ENTRY_LISTA;
  PACTRL_ACCESS_ENTRY_LIST = PACTRL_ACCESS_ENTRY_LISTA;
  TActrlAccessEntryList = TActrlAccessEntryListA;
  PActrlAccessEntryList = PActrlAccessEntryListA;
{$endif}

  PACTRL_PROPERTY_ENTRYA = ^ACTRL_PROPERTY_ENTRYA;
  _ACTRL_PROPERTY_ENTRYA = record
    lpProperty: LPSTR;
    pAccessEntryList: PACTRL_ACCESS_ENTRY_LISTA;
    fListFlags: ULONG;
  end;
  ACTRL_PROPERTY_ENTRYA = _ACTRL_PROPERTY_ENTRYA;
  TActrlPropertyEntryA = ACTRL_PROPERTY_ENTRYA;
  PActrlPropertyEntryA = PACTRL_PROPERTY_ENTRYA;

  PACTRL_PROPERTY_ENTRYW = ^ACTRL_PROPERTY_ENTRYW;
  _ACTRL_PROPERTY_ENTRYW = record
    lpProperty: LPWSTR;
    pAccessEntryList: PACTRL_ACCESS_ENTRY_LISTW;
    fListFlags: ULONG;
  end;
  ACTRL_PROPERTY_ENTRYW = _ACTRL_PROPERTY_ENTRYW;
  TActrlPropertyEntryW = ACTRL_PROPERTY_ENTRYW;
  PActrlPropertyEntryW = PACTRL_PROPERTY_ENTRYW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ACTRL_PROPERTY_ENTRY = ACTRL_PROPERTY_ENTRYW;
  PACTRL_PROPERTY_ENTRY = PACTRL_PROPERTY_ENTRYW;
  TActrlPropertyEntry = TActrlPropertyEntryW;
  PActrlPropertyEntry = PActrlPropertyEntryW;
{$else}
  ACTRL_PROPERTY_ENTRY = ACTRL_PROPERTY_ENTRYA;
  PACTRL_PROPERTY_ENTRY = PACTRL_PROPERTY_ENTRYA;
  TActrlPropertyEntry = TActrlPropertyEntryA;
  PActrlPropertyEntry = PActrlPropertyEntryA;
{$endif}

  PActrlAlistA = ^TActrlAlistA;
  _ACTRL_ALISTA = record
    cEntries: ULONG;
    pPropertyAccessList: PACTRL_PROPERTY_ENTRYA;
  end;
  ACTRL_ACCESSA = _ACTRL_ALISTA;
  PACTRL_ACCESSA = ^_ACTRL_ALISTA;
  ACTRL_AUDITA = ACTRL_ACCESSA;
  PACTRL_AUDITA = ^ACTRL_AUDITA;
  TActrlAlistA = _ACTRL_ALISTA;

  PActrlAlistW = ^TActrlAlistW;
  _ACTRL_ALISTW = record
    cEntries: ULONG;
    pPropertyAccessList: PACTRL_PROPERTY_ENTRYW;
  end;
  ACTRL_ACCESSW = _ACTRL_ALISTW;
  PACTRL_ACCESSW = ^_ACTRL_ALISTW;
  ACTRL_AUDITW = ACTRL_ACCESSW;
  PACTRL_AUDITW = ^ACTRL_AUDITW;
  TActrlAlistW = _ACTRL_ALISTW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ACTRL_ACCESS = ACTRL_ACCESSW;
  PACTRL_ACCESS = PACTRL_ACCESSW;
  ACTRL_AUDIT = ACTRL_AUDITW;
  PACTRL_AUDIT = PACTRL_AUDITW;
  TActrlAlist = TActrlAlistW;
  PActrlAlist = PActrlAlistW;
{$else}
  ACTRL_ACCESS = ACTRL_ACCESSA;
  PACTRL_ACCESS = PACTRL_ACCESSA;
  ACTRL_AUDIT = ACTRL_AUDITA;
  PACTRL_AUDIT = PACTRL_AUDITA;
  TActrlAlist = TActrlAlistA;
  PActrlAlist = PActrlAlistA;
{$endif}

//
// TRUSTEE_ACCESS flags
//

const
  TRUSTEE_ACCESS_ALLOWED    = $00000001;
  TRUSTEE_ACCESS_READ       = $00000002;
  TRUSTEE_ACCESS_WRITE      = $00000004;

  TRUSTEE_ACCESS_EXPLICIT   = $00000001;
  TRUSTEE_ACCESS_READ_WRITE = TRUSTEE_ACCESS_READ or TRUSTEE_ACCESS_WRITE;

  TRUSTEE_ACCESS_ALL = DWORD($FFFFFFFF);

type
  PTRUSTEE_ACCESSA = ^TRUSTEE_ACCESSA;
  _TRUSTEE_ACCESSA = record
    lpProperty: LPSTR;
    Access: ACCESS_RIGHTS;
    fAccessFlags: ULONG;
    fReturnedAccess: ULONG;
  end;
  TRUSTEE_ACCESSA = _TRUSTEE_ACCESSA;
  TTrusteeAccessA = TRUSTEE_ACCESSA;
  PTrusteeAccessA = PTRUSTEE_ACCESSA;

  PTRUSTEE_ACCESSW = ^TRUSTEE_ACCESSW;
  _TRUSTEE_ACCESSW = record
    lpProperty: LPWSTR;
    Access: ACCESS_RIGHTS;
    fAccessFlags: ULONG;
    fReturnedAccess: ULONG;
  end;
  TRUSTEE_ACCESSW = _TRUSTEE_ACCESSW;
  TTrusteeAccessW = TRUSTEE_ACCESSW;
  PTrusteeAccessW = PTRUSTEE_ACCESSW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  TRUSTEE_ACCESS = TRUSTEE_ACCESSW;
  PTRUSTEE_ACCESS = PTRUSTEE_ACCESSW;
  TTrusteeAccess = TTrusteeAccessW;
  PTrusteeAccess = PTrusteeAccessW;
{$else}
  TRUSTEE_ACCESS = TRUSTEE_ACCESSA;
  PTRUSTEE_ACCESS = PTRUSTEE_ACCESSA;
  TTrusteeAccess = TTrusteeAccessA;
  PTrusteeAccess = PTrusteeAccessA;
{$endif}

//
// Generic permission values
//

const
  ACTRL_RESERVED = $00000000;
  ACTRL_PERM_1   = $00000001;
  ACTRL_PERM_2   = $00000002;
  ACTRL_PERM_3   = $00000004;
  ACTRL_PERM_4   = $00000008;
  ACTRL_PERM_5   = $00000010;
  ACTRL_PERM_6   = $00000020;
  ACTRL_PERM_7   = $00000040;
  ACTRL_PERM_8   = $00000080;
  ACTRL_PERM_9   = $00000100;
  ACTRL_PERM_10  = $00000200;
  ACTRL_PERM_11  = $00000400;
  ACTRL_PERM_12  = $00000800;
  ACTRL_PERM_13  = $00001000;
  ACTRL_PERM_14  = $00002000;
  ACTRL_PERM_15  = $00004000;
  ACTRL_PERM_16  = $00008000;
  ACTRL_PERM_17  = $00010000;
  ACTRL_PERM_18  = $00020000;
  ACTRL_PERM_19  = $00040000;
  ACTRL_PERM_20  = $00080000;

//
// Access permissions
//

  ACTRL_ACCESS_ALLOWED = $00000001;
  ACTRL_ACCESS_DENIED  = $00000002;
  ACTRL_AUDIT_SUCCESS  = $00000004;
  ACTRL_AUDIT_FAILURE  = $00000008;

//
// Property list flags
//

  ACTRL_ACCESS_PROTECTED = $00000001;

//
// Standard and object rights
//

  ACTRL_SYSTEM_ACCESS      = $04000000;
  ACTRL_DELETE             = $08000000;
  ACTRL_READ_CONTROL       = $10000000;
  ACTRL_CHANGE_ACCESS      = $20000000;
  ACTRL_CHANGE_OWNER       = $40000000;
  ACTRL_SYNCHRONIZE        = DWORD($80000000);
  ACTRL_STD_RIGHTS_ALL     = DWORD($f8000000);
  ACTRL_STD_RIGHT_REQUIRED = DWORD(ACTRL_STD_RIGHTS_ALL and not ACTRL_SYNCHRONIZE);

  ACTRL_DS_OPEN           = ACTRL_RESERVED;
  ACTRL_DS_CREATE_CHILD   = ACTRL_PERM_1;
  ACTRL_DS_DELETE_CHILD   = ACTRL_PERM_2;
  ACTRL_DS_LIST           = ACTRL_PERM_3;
  ACTRL_DS_SELF           = ACTRL_PERM_4;
  ACTRL_DS_READ_PROP      = ACTRL_PERM_5;
  ACTRL_DS_WRITE_PROP     = ACTRL_PERM_6;
  ACTRL_DS_DELETE_TREE    = ACTRL_PERM_7;
  ACTRL_DS_LIST_OBJECT    = ACTRL_PERM_8;
  ACTRL_DS_CONTROL_ACCESS = ACTRL_PERM_9;

  ACTRL_FILE_READ           = ACTRL_PERM_1;
  ACTRL_FILE_WRITE          = ACTRL_PERM_2;
  ACTRL_FILE_APPEND         = ACTRL_PERM_3;
  ACTRL_FILE_READ_PROP      = ACTRL_PERM_4;
  ACTRL_FILE_WRITE_PROP     = ACTRL_PERM_5;
  ACTRL_FILE_EXECUTE        = ACTRL_PERM_6;
  ACTRL_FILE_READ_ATTRIB    = ACTRL_PERM_8;
  ACTRL_FILE_WRITE_ATTRIB   = ACTRL_PERM_9;
  ACTRL_FILE_CREATE_PIPE    = ACTRL_PERM_10;
  ACTRL_DIR_LIST            = ACTRL_PERM_1;
  ACTRL_DIR_CREATE_OBJECT   = ACTRL_PERM_2;
  ACTRL_DIR_CREATE_CHILD    = ACTRL_PERM_3;
  ACTRL_DIR_DELETE_CHILD    = ACTRL_PERM_7;
  ACTRL_DIR_TRAVERSE        = ACTRL_PERM_6;
  ACTRL_KERNEL_TERMINATE    = ACTRL_PERM_1;
  ACTRL_KERNEL_THREAD       = ACTRL_PERM_2;
  ACTRL_KERNEL_VM           = ACTRL_PERM_3;
  ACTRL_KERNEL_VM_READ      = ACTRL_PERM_4;
  ACTRL_KERNEL_VM_WRITE     = ACTRL_PERM_5;
  ACTRL_KERNEL_DUP_HANDLE   = ACTRL_PERM_6;
  ACTRL_KERNEL_PROCESS      = ACTRL_PERM_7;
  ACTRL_KERNEL_SET_INFO     = ACTRL_PERM_8;
  ACTRL_KERNEL_GET_INFO     = ACTRL_PERM_9;
  ACTRL_KERNEL_CONTROL      = ACTRL_PERM_10;
  ACTRL_KERNEL_ALERT        = ACTRL_PERM_11;
  ACTRL_KERNEL_GET_CONTEXT  = ACTRL_PERM_12;
  ACTRL_KERNEL_SET_CONTEXT  = ACTRL_PERM_13;
  ACTRL_KERNEL_TOKEN        = ACTRL_PERM_14;
  ACTRL_KERNEL_IMPERSONATE  = ACTRL_PERM_15;
  ACTRL_KERNEL_DIMPERSONATE = ACTRL_PERM_16;
  ACTRL_PRINT_SADMIN        = ACTRL_PERM_1;
  ACTRL_PRINT_SLIST         = ACTRL_PERM_2;
  ACTRL_PRINT_PADMIN        = ACTRL_PERM_3;
  ACTRL_PRINT_PUSE          = ACTRL_PERM_4;
  ACTRL_PRINT_JADMIN        = ACTRL_PERM_5;
  ACTRL_SVC_GET_INFO        = ACTRL_PERM_1;
  ACTRL_SVC_SET_INFO        = ACTRL_PERM_2;
  ACTRL_SVC_STATUS          = ACTRL_PERM_3;
  ACTRL_SVC_LIST            = ACTRL_PERM_4;
  ACTRL_SVC_START           = ACTRL_PERM_5;
  ACTRL_SVC_STOP            = ACTRL_PERM_6;
  ACTRL_SVC_PAUSE           = ACTRL_PERM_7;
  ACTRL_SVC_INTERROGATE     = ACTRL_PERM_8;
  ACTRL_SVC_UCONTROL        = ACTRL_PERM_9;
  ACTRL_REG_QUERY           = ACTRL_PERM_1;
  ACTRL_REG_SET             = ACTRL_PERM_2;
  ACTRL_REG_CREATE_CHILD    = ACTRL_PERM_3;
  ACTRL_REG_LIST            = ACTRL_PERM_4;
  ACTRL_REG_NOTIFY          = ACTRL_PERM_5;
  ACTRL_REG_LINK            = ACTRL_PERM_6;
  ACTRL_WIN_CLIPBRD         = ACTRL_PERM_1;
  ACTRL_WIN_GLOBAL_ATOMS    = ACTRL_PERM_2;
  ACTRL_WIN_CREATE          = ACTRL_PERM_3;
  ACTRL_WIN_LIST_DESK       = ACTRL_PERM_4;
  ACTRL_WIN_LIST            = ACTRL_PERM_5;
  ACTRL_WIN_READ_ATTRIBS    = ACTRL_PERM_6;
  ACTRL_WIN_WRITE_ATTRIBS   = ACTRL_PERM_7;
  ACTRL_WIN_SCREEN          = ACTRL_PERM_8;
  ACTRL_WIN_EXIT            = ACTRL_PERM_9;

type
  PACTRL_OVERLAPPED = ^ACTRL_OVERLAPPED;
  _ACTRL_OVERLAPPED = record
    //union {
    Provider: PVOID;
    //    ULONG Reserved1;
    //};
    Reserved2: ULONG;
    hEvent: HANDLE;
  end;
  ACTRL_OVERLAPPED = _ACTRL_OVERLAPPED;
  TActrlOverlapped = ACTRL_OVERLAPPED;
  PActrlOverlapped = PACTRL_OVERLAPPED;

  PACTRL_ACCESS_INFOA = ^ACTRL_ACCESS_INFOA;
  _ACTRL_ACCESS_INFOA = record
    fAccessPermission: ULONG;
    lpAccessPermissionName: LPSTR;
  end;
  ACTRL_ACCESS_INFOA = _ACTRL_ACCESS_INFOA;
  TActrlAccessInfoA = ACTRL_ACCESS_INFOA;
  PActrlAccessInfoA = PACTRL_ACCESS_INFOA;

  PACTRL_ACCESS_INFOW = ^ACTRL_ACCESS_INFOW;
  _ACTRL_ACCESS_INFOW = record
    fAccessPermission: ULONG;
    lpAccessPermissionName: LPWSTR;
  end;
  ACTRL_ACCESS_INFOW = _ACTRL_ACCESS_INFOW;
  TActrlAccessInfoW = ACTRL_ACCESS_INFOW;
  PActrlAccessInfoW = PACTRL_ACCESS_INFOW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ACTRL_ACCESS_INFO = ACTRL_ACCESS_INFOW;
  PACTRL_ACCESS_INFO = PACTRL_ACCESS_INFOW;
  TActrlAccessInfo = TActrlAccessInfoW;
  PActrlAccessInfo = PActrlAccessInfoW;
{$else}
  ACTRL_ACCESS_INFO = ACTRL_ACCESS_INFOA;
  PACTRL_ACCESS_INFO = PACTRL_ACCESS_INFOA;
  TActrlAccessInfo = TActrlAccessInfoA;
  PActrlAccessInfo = PActrlAccessInfoA;
{$endif}

  PACTRL_CONTROL_INFOA = ^ACTRL_CONTROL_INFOA;
  _ACTRL_CONTROL_INFOA = record
    lpControlId: LPSTR;
    lpControlName: LPSTR;
  end;
  ACTRL_CONTROL_INFOA = _ACTRL_CONTROL_INFOA;
  TActrlControlInfoA = ACTRL_CONTROL_INFOA;
  PActrlControlInfoA = PACTRL_CONTROL_INFOA;

  PACTRL_CONTROL_INFOW = ^ACTRL_CONTROL_INFOW;
  _ACTRL_CONTROL_INFOW = record
    lpControlId: LPWSTR;
    lpControlName: LPWSTR;
  end;
  ACTRL_CONTROL_INFOW = _ACTRL_CONTROL_INFOW;
  TActrlControlInfoW = ACTRL_CONTROL_INFOW;
  PActrlControlInfoW = PACTRL_CONTROL_INFOW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ACTRL_CONTROL_INFO = ACTRL_CONTROL_INFOW;
  PACTRL_CONTROL_INFO = PACTRL_CONTROL_INFOW;
  TActrlControlInfo = TActrlControlInfoW;
  PActrlControlInfo = PActrlControlInfoW;
{$else}
  ACTRL_CONTROL_INFO = ACTRL_CONTROL_INFOA;
  PACTRL_CONTROL_INFO = PACTRL_CONTROL_INFOA;
  TActrlControlInfo = TActrlControlInfoA;
  PActrlControlInfo = PActrlControlInfoA;
{$endif}

const
  ACTRL_ACCESS_NO_OPTIONS              = $00000000;
  ACTRL_ACCESS_SUPPORTS_OBJECT_ENTRIES = $00000001;

  ProgressInvokeNever = 1;        // Never invoke the progress function
  ProgressInvokeEveryObject = 2;  // Invoke for each object
  ProgressInvokeOnError = 3;      // Invoke only for each error case
  ProgressCancelOperation = 4;    // Stop propagation and return
  ProgressRetryOperation = 5;     // Retry operation on subtree

type
  PROG_INVOKE_SETTING = DWORD;
  PPROG_INVOKE_SETTING = ^PROG_INVOKE_SETTING;
  TProgInvokeSetting = PROG_INVOKE_SETTING;
  PProgInvokeSetting = PPROG_INVOKE_SETTING;

//
// Progress Function:
// Caller of tree operation implements this Progress function, then
// passes its function pointer to tree operation.
// Tree operation invokes Progress function to provide progress and error
// information to the caller during the potentially long execution
// of the tree operation.  Tree operation provides the name of the object
// last processed and the error status of the operation on that object.
// Tree operation also passes the current InvokeSetting value.
// Caller may change the InvokeSetting value, for example, from "Always"
// to "Only On Error."
//

type
  FN_PROGRESS = procedure(pObjectName: LPWSTR; Status: DWORD;
    var pInvokeSetting: PROG_INVOKE_SETTING; Args: PVOID; SecuritySet: BOOL); stdcall;
  TFnProgress = FN_PROGRESS;

//
// New Object Type function pointers.  TBD.
// To support additional object resource managers generically, the
// resource manager must provide it's own functions for operations
// like:
// GetAncestorAcl(IN ObjName, IN GenerationGap, IN DaclOrSacl?, ...)
// GetAncestorName(...)
// FreeNameStructure(...)
//

type
  _FN_OBJECT_MGR_FUNCTIONS = record
    Placeholder: ULONG;
  end;
  FN_OBJECT_MGR_FUNCTS = _FN_OBJECT_MGR_FUNCTIONS;
  PFN_OBJECT_MGR_FUNCTS = ^FN_OBJECT_MGR_FUNCTS;
  TFnObjectMgrFuncts = FN_OBJECT_MGR_FUNCTS;
  PFnObjectMgrFuncts = PFN_OBJECT_MGR_FUNCTS;

//
// Name of ancestor and number of generations between
// ancestor and inheriting object.
//
// GenerationGap:
//     Name of ancestor from which ACE was inherited.
//     NULL for explicit ACE.
//
// AncestorName:
//     Number of levels (or generations) between the object and the ancestor.
//     Parent, gap=1.
//     Grandparent, gap=2.
//     Set to 0 for explicit ACE on object.
//

type
  _INHERITED_FROMA = record
    GenerationGap: LONG;
    AncestorName: LPSTR;
  end;
  INHERITED_FROMA = _INHERITED_FROMA;
  PINHERITED_FROMA = ^INHERITED_FROMA;
  TInheritedFromA = INHERITED_FROMA;
  PInheritedFromA = PINHERITED_FROMA;

  _INHERITED_FROMW = record
    GenerationGap: LONG;
    AncestorName: LPWSTR;
  end;
  INHERITED_FROMW = _INHERITED_FROMW;
  PINHERITED_FROMW = ^INHERITED_FROMW;
  TInheritedFromW = INHERITED_FROMW;
  PInheritedFromW = PINHERITED_FROMW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  INHERITED_FROM = INHERITED_FROMW;
  PINHERITED_FROM = PINHERITED_FROMW;
  TInheritedFrom = TInheritedFromW;
  PInheritedFrom = PInheritedFromW;
{$else}
  INHERITED_FROM = INHERITED_FROMA;
  PINHERITED_FROM = PINHERITED_FROMA;
  TInheritedFrom = TInheritedFromA;
  PInheritedFrom = PInheritedFromA;
{$endif}

implementation

// (rom) MACRO implementation
function AccFree(hMem: HLOCAL): HLOCAL;
begin
  Result := LocalFree(hMem);
end;

end.
