{******************************************************************************}
{                                                                              }
{ Access Control API interface Unit for Object Pascal                          }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: aclapi.h, released June 2000. The original Pascal      }
{ code is: AclApi.pas, released December 2000. The initial developer of the    }
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

// $Id: AclAPI.pas,v 1.11 2007/09/05 11:58:48 dezipaitor Exp $
unit AclAPI;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

uses Winapi.Support, AccCtrl, Windows;

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
  FN_PROGRESS = AccCtrl.FN_PROGRESS;
  TFnProgress = FN_PROGRESS;

function SetEntriesInAclA(cCountOfExplicitEntries: ULONG;
  pListOfExplicitEntries: PEXPLICIT_ACCESS_A; OldAcl: PACL;
  var NewAcl: PACL): DWORD; stdcall;
function SetEntriesInAclW(cCountOfExplicitEntries: ULONG;
  pListOfExplicitEntries: PEXPLICIT_ACCESS_W; OldAcl: PACL;
  var NewAcl: PACL): DWORD; stdcall;
function SetEntriesInAcl(cCountOfExplicitEntries: ULONG;
  pListOfExplicitEntries: PEXPLICIT_ACCESS; OldAcl: PACL;
  var NewAcl: PACL): DWORD; stdcall;

function GetExplicitEntriesFromAclA(pacl: PACL; var pcCountOfExplicitEntries: ULONG;
  var pListOfExplicitEntries: PEXPLICIT_ACCESS_A): DWORD; stdcall;
function GetExplicitEntriesFromAclW(pacl: PACL; var pcCountOfExplicitEntries: ULONG;
  var pListOfExplicitEntries: PEXPLICIT_ACCESS_W): DWORD; stdcall;
function GetExplicitEntriesFromAcl(pacl: PACL; var pcCountOfExplicitEntries: ULONG;
  var pListOfExplicitEntries: PEXPLICIT_ACCESS): DWORD; stdcall;

function GetEffectiveRightsFromAclA(pacl: PACL; pTrustee: PTRUSTEE_A;
  var pAccessRights: ACCESS_MASK): DWORD; stdcall;
function GetEffectiveRightsFromAclW(pacl: PACL; pTrustee: PTRUSTEE_W;
  var pAccessRights: ACCESS_MASK): DWORD; stdcall;
function GetEffectiveRightsFromAcl(pacl: PACL; pTrustee: PTRUSTEE;
  var pAccessRights: ACCESS_MASK): DWORD; stdcall;

function GetAuditedPermissionsFromAclA(pacl: PACL; pTrustee: PTRUSTEE_A;
  var pSuccessfulAuditedRights, pFailedAuditRights: ACCESS_MASK): DWORD; stdcall;
function GetAuditedPermissionsFromAclW(pacl: PACL; pTrustee: PTRUSTEE_W;
  var pSuccessfulAuditedRights, pFailedAuditRights: ACCESS_MASK): DWORD; stdcall;
function GetAuditedPermissionsFromAcl(pacl: PACL; pTrustee: PTRUSTEE;
  var pSuccessfulAuditedRights, pFailedAuditRights: ACCESS_MASK): DWORD; stdcall;

function GetNamedSecurityInfoA(pObjectName: LPSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; ppsidOwner, ppsidGroup: PPSID; ppDacl,
  ppSacl: PPACL; var ppSecurityDescriptor: PSECURITY_DESCRIPTOR): DWORD; stdcall;
function GetNamedSecurityInfoW(pObjectName: LPWSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; ppsidOwner, ppsidGroup: PPSID; ppDacl,
  ppSacl: PPACL; var ppSecurityDescriptor: PSECURITY_DESCRIPTOR): DWORD; stdcall;
function GetNamedSecurityInfo(pObjectName: LPTSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; ppsidOwner, ppsidGroup: PPSID; ppDacl,
  ppSacl: PPACL; var ppSecurityDescriptor: PSECURITY_DESCRIPTOR): DWORD; stdcall;

function GetSecurityInfo(handle: HANDLE; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; ppsidOwner: PPSID; ppsidGroup: PPSID;
  ppDacl, ppSacl: PPACL; var ppSecurityDescriptor: PSECURITY_DESCRIPTOR): DWORD; stdcall;

function SetNamedSecurityInfoA(pObjectName: LPSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; psidOwner, psidGroup: PSID;
  pDacl, pSacl: PACL): DWORD; stdcall;
function SetNamedSecurityInfoW(pObjectName: LPWSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; psidOwner, psidGroup: PSID;
  pDacl, pSacl: PACL): DWORD; stdcall;
function SetNamedSecurityInfo(pObjectName: LPTSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; psidOwner, psidGroup: PSID;
  pDacl, pSacl: PACL): DWORD; stdcall;

function SetSecurityInfo(handle: HANDLE; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; psidOwner, psidGroup: PSID;
  pDacl, pSacl: PACL): DWORD; stdcall;

function GetInheritanceSourceA(pObjectName: LPSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; Container: BOOL; pObjectClassGuids: LPGUID;
  GuidCount: DWORD; pAcl: PACL; pfnArray: PFN_OBJECT_MGR_FUNCTS;
  pGenericMapping: PGENERIC_MAPPING; pInheritArray: PINHERITED_FROMA): DWORD; stdcall;
function GetInheritanceSourceW(pObjectName: LPWSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; Container: BOOL; pObjectClassGuids: LPGUID;
  GuidCount: DWORD; pAcl: PACL; pfnArray: PFN_OBJECT_MGR_FUNCTS;
  pGenericMapping: PGENERIC_MAPPING; pInheritArray: PINHERITED_FROMW): DWORD; stdcall;
function GetInheritanceSource(pObjectName: LPTSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; Container: BOOL; pObjectClassGuids: LPGUID;
  GuidCount: DWORD; pAcl: PACL; pfnArray: PFN_OBJECT_MGR_FUNCTS;
  pGenericMapping: PGENERIC_MAPPING; pInheritArray: PINHERITED_FROM): DWORD; stdcall;

function FreeInheritedFromArray(pInheritArray: PINHERITED_FROMW; AceCnt: USHORT;
  pfnArray: PFN_OBJECT_MGR_FUNCTS): DWORD; stdcall;

function TreeResetNamedSecurityInfoA(pObjectName: LPSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; pOwner, pGroup: PSID; pDacl, pSacl: PACL;
  KeepExplicit: BOOL; fnProgress: FN_PROGRESS; ProgressInvokeSetting: PROG_INVOKE_SETTING;
  Args: PVOID): DWORD; stdcall;
function TreeResetNamedSecurityInfoW(pObjectName: LPWSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; pOwner, pGroup: PSID; pDacl, pSacl: PACL;
  KeepExplicit: BOOL; fnProgress: FN_PROGRESS; ProgressInvokeSetting: PROG_INVOKE_SETTING;
  Args: PVOID): DWORD; stdcall;
function TreeResetNamedSecurityInfo(pObjectName: LPTSTR; ObjectType: SE_OBJECT_TYPE;
  SecurityInfo: SECURITY_INFORMATION; pOwner, pGroup: PSID; pDacl, pSacl: PACL;
  KeepExplicit: BOOL; fnProgress: FN_PROGRESS; ProgressInvokeSetting: PROG_INVOKE_SETTING;
  Args: PVOID): DWORD; stdcall;

//----------------------------------------------------------------------------
// The following API are provided for trusted servers to use to
// implement access control on their own objects.
//----------------------------------------------------------------------------

function BuildSecurityDescriptorA(pOwner: PTRUSTEE_A; pGroup: PTRUSTEE_A;
  cCountOfAccessEntries: ULONG; pListOfAccessEntries: PEXPLICIT_ACCESS_A;
  cCountOfAuditEntries: ULONG; pListOfAuditEntries: PEXPLICIT_ACCESS_A;
  pOldSD: PSECURITY_DESCRIPTOR; var pSizeNewSD: ULONG;
  var pNewSD: PSECURITY_DESCRIPTOR): DWORD; stdcall;
function BuildSecurityDescriptorW(pOwner: PTRUSTEE_W; pGroup: PTRUSTEE_W;
  cCountOfAccessEntries: ULONG; pListOfAccessEntries: PEXPLICIT_ACCESS_W;
  cCountOfAuditEntries: ULONG; pListOfAuditEntries: PEXPLICIT_ACCESS_W;
  pOldSD: PSECURITY_DESCRIPTOR; var pSizeNewSD: ULONG;
  var pNewSD: PSECURITY_DESCRIPTOR): DWORD; stdcall;
function BuildSecurityDescriptor(pOwner: PTRUSTEE; pGroup: PTRUSTEE;
  cCountOfAccessEntries: ULONG; pListOfAccessEntries: PEXPLICIT_ACCESS;
  cCountOfAuditEntries: ULONG; pListOfAuditEntries: PEXPLICIT_ACCESS;
  pOldSD: PSECURITY_DESCRIPTOR; var pSizeNewSD: ULONG;
  var pNewSD: PSECURITY_DESCRIPTOR): DWORD; stdcall;

function LookupSecurityDescriptorPartsA(pOwner, pGroup: PPTRUSTEE_A;
  cCountOfAccessEntries: PULONG; var pListOfAccessEntries: PEXPLICIT_ACCESS_A;
  cCountOfAuditEntries: PULONG; var pListOfAuditEntries: PEXPLICIT_ACCESS_A;
  var pSD: SECURITY_DESCRIPTOR): DWORD; stdcall;
function LookupSecurityDescriptorPartsW(pOwner, pGroup: PPTRUSTEE_W;
  cCountOfAccessEntries: PULONG; var pListOfAccessEntries: PEXPLICIT_ACCESS_W;
  cCountOfAuditEntries: PULONG; var pListOfAuditEntries: PEXPLICIT_ACCESS_W;
  var pSD: SECURITY_DESCRIPTOR): DWORD; stdcall;
function LookupSecurityDescriptorParts(pOwner, pGroup: PPTRUSTEE;
  cCountOfAccessEntries: PULONG; var pListOfAccessEntries: PEXPLICIT_ACCESS;
  cCountOfAuditEntries: PULONG; var pListOfAuditEntries: PEXPLICIT_ACCESS;
  var pSD: SECURITY_DESCRIPTOR): DWORD; stdcall;

//----------------------------------------------------------------------------
// The following helper API are provided for building
// access control structures.
//----------------------------------------------------------------------------

procedure BuildExplicitAccessWithNameA(pExplicitAccess: PEXPLICIT_ACCESS_A;
  pTrusteeName: LPSTR; AccessPermissions: DWORD; AccessMode: ACCESS_MODE;
  Inheritance: DWORD); stdcall;
procedure BuildExplicitAccessWithNameW(pExplicitAccess: PEXPLICIT_ACCESS_W;
  pTrusteeName: LPWSTR; AccessPermissions: DWORD; AccessMode: ACCESS_MODE;
  Inheritance: DWORD); stdcall;
procedure BuildExplicitAccessWithName(pExplicitAccess: PEXPLICIT_ACCESS;
  pTrusteeName: LPTSTR; AccessPermissions: DWORD; AccessMode: ACCESS_MODE;
  Inheritance: DWORD); stdcall;

procedure BuildImpersonateExplicitAccessWithNameA(pExplicitAccess: PEXPLICIT_ACCESS_A;
  pTrusteeName: LPSTR; pTrustee: PTRUSTEE_A; AccessPermissions: DWORD;
  AccessMode: ACCESS_MODE; Inheritance: DWORD); stdcall;
procedure BuildImpersonateExplicitAccessWithNameW(pExplicitAccess: PEXPLICIT_ACCESS_W;
  pTrusteeName: LPWSTR; pTrustee: PTRUSTEE_W; AccessPermissions: DWORD;
  AccessMode: ACCESS_MODE; Inheritance: DWORD); stdcall;
procedure BuildImpersonateExplicitAccessWithName(pExplicitAccess: PEXPLICIT_ACCESS;
  pTrusteeName: LPTSTR; pTrustee: PTRUSTEE; AccessPermissions: DWORD;
  AccessMode: ACCESS_MODE; Inheritance: DWORD); stdcall;

procedure BuildTrusteeWithNameA(pTrustee: PTRUSTEE_A; pName: LPSTR); stdcall;
procedure BuildTrusteeWithNameW(pTrustee: PTRUSTEE_W; pName: LPWSTR); stdcall;
procedure BuildTrusteeWithName(pTrustee: PTRUSTEE; pName: LPTSTR); stdcall;

procedure BuildImpersonateTrusteeA(pTrustee: PTRUSTEE_A;
  pImpersonateTrustee: PTRUSTEE_A); stdcall;
procedure BuildImpersonateTrusteeW(pTrustee: PTRUSTEE_W;
  pImpersonateTrustee: PTRUSTEE_W); stdcall;
procedure BuildImpersonateTrustee(pTrustee: PTRUSTEE;
  pImpersonateTrustee: PTRUSTEE); stdcall;

procedure BuildTrusteeWithSidA(pTrustee: PTRUSTEE_A; pSid: PSID); stdcall;
procedure BuildTrusteeWithSidW(pTrustee: PTRUSTEE_W; pSid: PSID); stdcall;
procedure BuildTrusteeWithSid(pTrustee: PTRUSTEE; pSid: PSID); stdcall;

procedure BuildTrusteeWithObjectsAndSidA(pTrustee: PTRUSTEE_A;
  pObjSid: POBJECTS_AND_SID; pObjectGuid: PGUID; pInheritedObjectGuid: PGUID;
  pSid: PSID); stdcall;
procedure BuildTrusteeWithObjectsAndSidW(pTrustee: PTRUSTEE_W;
  pObjSid: POBJECTS_AND_SID; pObjectGuid: PGUID; pInheritedObjectGuid: PGUID;
  pSid: PSID); stdcall;
procedure BuildTrusteeWithObjectsAndSid(pTrustee: PTRUSTEE;
  pObjSid: POBJECTS_AND_SID; pObjectGuid: PGUID; pInheritedObjectGuid: PGUID;
  pSid: PSID); stdcall;

procedure BuildTrusteeWithObjectsAndNameA(pTrustee: PTRUSTEE_A;
  pObjName: POBJECTS_AND_NAME_A; ObjectType: SE_OBJECT_TYPE;
  ObjectTypeName, InheritedObjectTypeName, Name: LPSTR); stdcall;
procedure BuildTrusteeWithObjectsAndNameW(pTrustee: PTRUSTEE_W;
  pObjName: POBJECTS_AND_NAME_W; ObjectType: SE_OBJECT_TYPE;
  ObjectTypeName, InheritedObjectTypeName, Name: LPWSTR); stdcall;
procedure BuildTrusteeWithObjectsAndName(pTrustee: PTRUSTEE;
  pObjName: POBJECTS_AND_NAME; ObjectType: SE_OBJECT_TYPE;
  ObjectTypeName, InheritedObjectTypeName, Name: LPTSTR); stdcall;

function GetTrusteeNameA(pTrustee: PTRUSTEE_A): LPSTR; stdcall;
function GetTrusteeNameW(pTrustee: PTRUSTEE_W): LPWSTR; stdcall;
function GetTrusteeName(pTrustee: PTRUSTEE): LPTSTR; stdcall;

function GetTrusteeTypeA(pTrustee: PTRUSTEE_A): TRUSTEE_TYPE; stdcall;
function GetTrusteeTypeW(pTrustee: PTRUSTEE_W): TRUSTEE_TYPE; stdcall;
function GetTrusteeType(pTrustee: PTRUSTEE): TRUSTEE_TYPE; stdcall;

function GetTrusteeFormA(pTrustee: PTRUSTEE_A): TRUSTEE_FORM; stdcall;
function GetTrusteeFormW(pTrustee: PTRUSTEE_W): TRUSTEE_FORM; stdcall;
function GetTrusteeForm(pTrustee: PTRUSTEE): TRUSTEE_FORM; stdcall;

function GetMultipleTrusteeOperationA(pTrustee: PTRUSTEE_A): MULTIPLE_TRUSTEE_OPERATION; stdcall;
function GetMultipleTrusteeOperationW(pTrustee: PTRUSTEE_W): MULTIPLE_TRUSTEE_OPERATION; stdcall;
function GetMultipleTrusteeOperation(pTrustee: PTRUSTEE): MULTIPLE_TRUSTEE_OPERATION; stdcall;

function GetMultipleTrusteeA(pTrustee: PTRUSTEE_A): PTRUSTEE_A; stdcall;
function GetMultipleTrusteeW(pTrustee: PTRUSTEE_W): PTRUSTEE_W; stdcall;
function GetMultipleTrustee(pTrustee: PTRUSTEE): PTRUSTEE; stdcall;

implementation
//uses ...

const
  aclapilib = 'advapi32.dll';
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  AWSuffix = 'W';
{$else}
  AWSuffix = 'A';
{$endif}

function SetEntriesInAclA; external aclapilib name 'SetEntriesInAclA';
function SetEntriesInAclW; external aclapilib name 'SetEntriesInAclW';
function SetEntriesInAcl; external aclapilib name 'SetEntriesInAcl' + AWSuffix;
function GetExplicitEntriesFromAclA; external aclapilib name 'GetExplicitEntriesFromAclA';
function GetExplicitEntriesFromAclW; external aclapilib name 'GetExplicitEntriesFromAclW';
function GetExplicitEntriesFromAcl; external aclapilib name 'GetExplicitEntriesFromAcl' + AWSuffix;
function GetEffectiveRightsFromAclA; external aclapilib name 'GetEffectiveRightsFromAclA';
function GetEffectiveRightsFromAclW; external aclapilib name 'GetEffectiveRightsFromAclW';
function GetEffectiveRightsFromAcl; external aclapilib name 'GetEffectiveRightsFromAcl' + AWSuffix;
function GetAuditedPermissionsFromAclA; external aclapilib name 'GetAuditedPermissionsFromAclA';
function GetAuditedPermissionsFromAclW; external aclapilib name 'GetAuditedPermissionsFromAclW';
function GetAuditedPermissionsFromAcl; external aclapilib name 'GetAuditedPermissionsFromAcl' + AWSuffix;
function GetNamedSecurityInfoA; external aclapilib name 'GetNamedSecurityInfoA';
function GetNamedSecurityInfoW; external aclapilib name 'GetNamedSecurityInfoW';
function GetNamedSecurityInfo; external aclapilib name 'GetNamedSecurityInfo' + AWSuffix;
function GetSecurityInfo; external aclapilib name 'GetSecurityInfo';
function SetNamedSecurityInfoA; external aclapilib name 'SetNamedSecurityInfoA';
function SetNamedSecurityInfoW; external aclapilib name 'SetNamedSecurityInfoW';
function SetNamedSecurityInfo; external aclapilib name 'SetNamedSecurityInfo' + AWSuffix;
function SetSecurityInfo; external aclapilib name 'SetSecurityInfo';
function GetInheritanceSourceA; external aclapilib name 'GetInheritanceSourceA';
function GetInheritanceSourceW; external aclapilib name 'GetInheritanceSourceW';
function GetInheritanceSource; external aclapilib name 'GetInheritanceSource' + AWSuffix;
function FreeInheritedFromArray; external aclapilib name 'FreeInheritedFromArray';
function TreeResetNamedSecurityInfoA; external aclapilib name 'TreeResetNamedSecurityInfoA';
function TreeResetNamedSecurityInfoW; external aclapilib name 'TreeResetNamedSecurityInfoW';
function TreeResetNamedSecurityInfo; external aclapilib name 'TreeResetNamedSecurityInfo' + AWSuffix;
function BuildSecurityDescriptorA; external aclapilib name 'BuildSecurityDescriptorA';
function BuildSecurityDescriptorW; external aclapilib name 'BuildSecurityDescriptorW';
function BuildSecurityDescriptor; external aclapilib name 'BuildSecurityDescriptor' + AWSuffix;
function LookupSecurityDescriptorPartsA; external aclapilib name 'LookupSecurityDescriptorPartsA';
function LookupSecurityDescriptorPartsW; external aclapilib name 'LookupSecurityDescriptorPartsW';
function LookupSecurityDescriptorParts; external aclapilib name 'LookupSecurityDescriptorParts' + AWSuffix;
procedure BuildExplicitAccessWithNameA; external aclapilib name 'BuildExplicitAccessWithNameA';
procedure BuildExplicitAccessWithNameW; external aclapilib name 'BuildExplicitAccessWithNameW';
procedure BuildExplicitAccessWithName; external aclapilib name 'BuildExplicitAccessWithName' + AWSuffix;
procedure BuildImpersonateExplicitAccessWithNameA; external aclapilib name 'BuildImpersonateExplicitAccessWithNameA';
procedure BuildImpersonateExplicitAccessWithNameW; external aclapilib name 'BuildImpersonateExplicitAccessWithNameW';
procedure BuildImpersonateExplicitAccessWithName; external aclapilib name 'BuildImpersonateExplicitAccessWithName' + AWSuffix;
procedure BuildTrusteeWithNameA; external aclapilib name 'BuildTrusteeWithNameA';
procedure BuildTrusteeWithNameW; external aclapilib name 'BuildTrusteeWithNameW';
procedure BuildTrusteeWithName; external aclapilib name 'BuildTrusteeWithName' + AWSuffix;
procedure BuildImpersonateTrusteeA; external aclapilib name 'BuildImpersonateTrusteeA';
procedure BuildImpersonateTrusteeW; external aclapilib name 'BuildImpersonateTrusteeW';
procedure BuildImpersonateTrustee; external aclapilib name 'BuildImpersonateTrustee' + AWSuffix;
procedure BuildTrusteeWithSidA; external aclapilib name 'BuildTrusteeWithSidA';
procedure BuildTrusteeWithSidW; external aclapilib name 'BuildTrusteeWithSidW';
procedure BuildTrusteeWithSid; external aclapilib name 'BuildTrusteeWithSid' + AWSuffix;
procedure BuildTrusteeWithObjectsAndSidA; external aclapilib name 'BuildTrusteeWithObjectsAndSidA';
procedure BuildTrusteeWithObjectsAndSidW; external aclapilib name 'BuildTrusteeWithObjectsAndSidW';
procedure BuildTrusteeWithObjectsAndSid; external aclapilib name 'BuildTrusteeWithObjectsAndSid' + AWSuffix;
procedure BuildTrusteeWithObjectsAndNameA; external aclapilib name 'BuildTrusteeWithObjectsAndNameA';
procedure BuildTrusteeWithObjectsAndNameW; external aclapilib name 'BuildTrusteeWithObjectsAndNameW';
procedure BuildTrusteeWithObjectsAndName; external aclapilib name 'BuildTrusteeWithObjectsAndName' + AWSuffix;
function GetTrusteeNameA; external aclapilib name 'GetTrusteeNameA';
function GetTrusteeNameW; external aclapilib name 'GetTrusteeNameW';
function GetTrusteeName; external aclapilib name 'GetTrusteeName' + AWSuffix;
function GetTrusteeTypeA; external aclapilib name 'GetTrusteeTypeA';
function GetTrusteeTypeW; external aclapilib name 'GetTrusteeTypeW';
function GetTrusteeType; external aclapilib name 'GetTrusteeType' + AWSuffix;
function GetTrusteeFormA; external aclapilib name 'GetTrusteeFormA';
function GetTrusteeFormW; external aclapilib name 'GetTrusteeFormW';
function GetTrusteeForm; external aclapilib name 'GetTrusteeForm' + AWSuffix;
function GetMultipleTrusteeOperationA; external aclapilib name 'GetMultipleTrusteeOperationA';
function GetMultipleTrusteeOperationW; external aclapilib name 'GetMultipleTrusteeOperationW';
function GetMultipleTrusteeOperation; external aclapilib name 'GetMultipleTrusteeOperation' + AWSuffix;
function GetMultipleTrusteeA; external aclapilib name 'GetMultipleTrusteeA';
function GetMultipleTrusteeW; external aclapilib name 'GetMultipleTrusteeW';
function GetMultipleTrustee; external aclapilib name 'GetMultipleTrustee' + AWSuffix;

end.
