{******************************************************************************}
{                                                                              }
{ WBEM Client interface Unit for Object Pascal                                 }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: wbemcli.idl, released Nov 2002. The original Pascal    }
{ code is: WbemCli.pas, released April 2002. The initial developer of the      }
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

// $Id: WbemCli.pas,v 1.8 2007/09/05 11:58:53 dezipaitor Exp $

unit WbemCli;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

uses ActiveX, Windows;

type
  tag_WBEM_GENUS_TYPE = DWORD;
  WBEM_GENUS_TYPE = tag_WBEM_GENUS_TYPE;
  TWbemGenusType = WBEM_GENUS_TYPE;

const
  WBEM_GENUS_CLASS      = 1;
  WBEM_GENUS_INSTANCE   = 2;

type
  tag_WBEM_CHANGE_FLAG_TYPE = DWORD;
  WBEM_CHANGE_FLAG_TYPE = tag_WBEM_CHANGE_FLAG_TYPE;
  TWbemChangeFlagType = WBEM_CHANGE_FLAG_TYPE;

const
  WBEM_FLAG_CREATE_OR_UPDATE  = $0;
  WBEM_FLAG_UPDATE_ONLY       = $1;
  WBEM_FLAG_CREATE_ONLY       = $2;
  WBEM_FLAG_UPDATE_COMPATIBLE = $0;
  WBEM_FLAG_UPDATE_SAFE_MODE  = $20;
  WBEM_FLAG_UPDATE_FORCE_MODE = $40;
  WBEM_MASK_UPDATE_MODE       = $60;
  WBEM_FLAG_ADVISORY          = $10000;

type
  tag_WBEM_GENERIC_FLAG_TYPE = DWORD;
  WBEM_GENERIC_FLAG_TYPE = tag_WBEM_GENERIC_FLAG_TYPE;
  TWbemGenericFlagType = WBEM_GENERIC_FLAG_TYPE;

const
  WBEM_FLAG_RETURN_IMMEDIATELY     = $10;
  WBEM_FLAG_RETURN_WBEM_COMPLETE   = $0;
  WBEM_FLAG_BIDIRECTIONAL          = $0;
  WBEM_FLAG_FORWARD_ONLY           = $20;
  WBEM_FLAG_NO_ERROR_OBJECT        = $40;
  WBEM_FLAG_RETURN_ERROR_OBJECT    = $0;
  WBEM_FLAG_SEND_STATUS            = $80;
  WBEM_FLAG_DONT_SEND_STATUS       = $0;
  WBEM_FLAG_ENSURE_LOCATABLE       = $100;
  WBEM_FLAG_DIRECT_READ            = $200;
  WBEM_FLAG_SEND_ONLY_SELECTED     = $0;
  WBEM_RETURN_WHEN_COMPLETE        = $0;
  WBEM_RETURN_IMMEDIATELY          = $10;
  WBEM_MASK_RESERVED_FLAGS         = $1f000;
  WBEM_FLAG_USE_AMENDED_QUALIFIERS = $20000;
  WBEM_FLAG_STRONG_VALIDATION      = $100000;

type
  tag_WBEM_STATUS_TYPE = DWORD;
  WBEM_STATUS_TYPE = tag_WBEM_STATUS_TYPE;
  TWbemStatusType = WBEM_STATUS_TYPE;

const
  WBEM_STATUS_COMPLETE     = 0;
  WBEM_STATUS_REQUIREMENTS = 1;
  WBEM_STATUS_PROGRESS     = 2;

type
  tag_WBEM_TIMEOUT_TYPE = DWORD;
  WBEM_TIMEOUT_TYPE = tag_WBEM_TIMEOUT_TYPE;
  TWbemTimeoutType = WBEM_TIMEOUT_TYPE;

const
  WBEM_NO_WAIT  = 0;
  WBEM_INFINITE = DWORD($ffffffff);

type
  tag_WBEM_CONDITION_FLAG_TYPE = DWORD;
  WBEM_CONDITION_FLAG_TYPE = tag_WBEM_CONDITION_FLAG_TYPE;
  TWbemConditionFlagType = WBEM_CONDITION_FLAG_TYPE;

const
  WBEM_FLAG_ALWAYS                    = $0;
  WBEM_FLAG_ONLY_IF_TRUE              = $1;
  WBEM_FLAG_ONLY_IF_FALSE             = $2;
  WBEM_FLAG_ONLY_IF_IDENTICAL         = $3;
  WBEM_MASK_PRIMARY_CONDITION         = $3;
  WBEM_FLAG_KEYS_ONLY                 = $4;
  WBEM_FLAG_REFS_ONLY                 = $8;
  WBEM_FLAG_LOCAL_ONLY                = $10;
  WBEM_FLAG_PROPAGATED_ONLY           = $20;
  WBEM_FLAG_SYSTEM_ONLY               = $30;
  WBEM_FLAG_NONSYSTEM_ONLY            = $40;
  WBEM_MASK_CONDITION_ORIGIN          = $70;
  WBEM_FLAG_CLASS_OVERRIDES_ONLY      = $100;
  WBEM_FLAG_CLASS_LOCAL_AND_OVERRIDES = $200;
  WBEM_MASK_CLASS_CONDITION           = $300;

type
  tag_WBEM_FLAVOR_TYPE = DWORD;
  WBEM_FLAVOR_TYPE = tag_WBEM_FLAVOR_TYPE;
  TWbemFlavorType = WBEM_FLAVOR_TYPE;

const
  WBEM_FLAVOR_DONT_PROPAGATE    = $0;
  WBEM_FLAVOR_FLAG_PROPAGATE_TO_INSTANCE      = $1;
  WBEM_FLAVOR_FLAG_PROPAGATE_TO_DERIVED_CLASS = $2;
  WBEM_FLAVOR_MASK_PROPAGATION  = $f;
  WBEM_FLAVOR_OVERRIDABLE       = $0;
  WBEM_FLAVOR_NOT_OVERRIDABLE   = $10;
  WBEM_FLAVOR_MASK_PERMISSIONS  = $10;
  WBEM_FLAVOR_ORIGIN_LOCAL      = $0;
  WBEM_FLAVOR_ORIGIN_PROPAGATED = $20;
  WBEM_FLAVOR_ORIGIN_SYSTEM     = $40;
  WBEM_FLAVOR_MASK_ORIGIN       = $60;
  WBEM_FLAVOR_NOT_AMENDED       = $0;
  WBEM_FLAVOR_AMENDED           = $80;
  WBEM_FLAVOR_MASK_AMENDED      = $80;

type
  tag_WBEM_QUERY_FLAG_TYPE = DWORD;
  WBEM_QUERY_FLAG_TYPE = tag_WBEM_QUERY_FLAG_TYPE;
  TWbemQueryFlagType = WBEM_QUERY_FLAG_TYPE;

const
  WBEM_FLAG_DEEP      = 0;
  WBEM_FLAG_SHALLOW   = 1;
  WBEM_FLAG_PROTOTYPE = 2;

type
  tag_WBEM_SECURITY_FLAGS = DWORD;
  WBEM_SECURITY_FLAGS = tag_WBEM_SECURITY_FLAGS;
  TWbemSecurityFlags = WBEM_SECURITY_FLAGS;

const
  WBEM_ENABLE            = $1;
  WBEM_METHOD_EXECUTE    = $2;
  WBEM_FULL_WRITE_REP    = $4;
  WBEM_PARTIAL_WRITE_REP = $8;
  WBEM_WRITE_PROVIDER    = $10;
  WBEM_REMOTE_ACCESS     = $20;
  WBEM_RIGHT_SUBSCRIBE   = $40;
  WBEM_RIGHT_PUBLISH     = $80;

type
  tag_WBEM_LIMITATION_FLAG_TYPE = DWORD;
  WBEM_LIMITATION_FLAG_TYPE = tag_WBEM_LIMITATION_FLAG_TYPE;
  TWbemLimitationFlagType = WBEM_LIMITATION_FLAG_TYPE;

const
  WBEM_FLAG_EXCLUDE_OBJECT_QUALIFIERS   = $10;
  WBEM_FLAG_EXCLUDE_PROPERTY_QUALIFIERS = $20;

type
  tag_WBEM_TEXT_FLAG_TYPE = DWORD;
  WBEM_TEXT_FLAG_TYPE = tag_WBEM_TEXT_FLAG_TYPE;
  TWbemTextFlagType = WBEM_TEXT_FLAG_TYPE;

const
  WBEM_FLAG_NO_FLAVORS = $1;

type
  tag_WBEM_COMPARISON_FLAG = DWORD;
  WBEM_COMPARISON_FLAG = tag_WBEM_COMPARISON_FLAG;
  TWbemComparisonFlag = WBEM_COMPARISON_FLAG;

const
  WBEM_COMPARISON_INCLUDE_ALL     = $0;
  WBEM_FLAG_IGNORE_QUALIFIERS     = $1;
  WBEM_FLAG_IGNORE_OBJECT_SOURCE  = $2;
  WBEM_FLAG_IGNORE_DEFAULT_VALUES = $4;
  WBEM_FLAG_IGNORE_CLASS          = $8;
  WBEM_FLAG_IGNORE_CASE           = $10;
  WBEM_FLAG_IGNORE_FLAVOR         = $20;

type
  tag_WBEM_LOCKING = DWORD;
  WBEM_LOCKING_FLAG_TYPE = tag_WBEM_LOCKING;
  TWbemLockingFlagType = WBEM_LOCKING_FLAG_TYPE;

const
  WBEM_FLAG_ALLOW_READ = $1;

type
  tag_CIMTYPE_ENUMERATION = DWORD;
  CIMTYPE_ENUMERATION = tag_CIMTYPE_ENUMERATION;
  TCimTypeEnumeration = CIMTYPE_ENUMERATION;

const
  CIM_ILLEGAL    = $fff;
  CIM_EMPTY      = 0;
  CIM_SINT8      = 16;
  CIM_UINT8      = 17;
  CIM_SINT16     = 2;
  CIM_UINT16     = 18;
  CIM_SINT32     = 3;
  CIM_UINT32     = 19;
  CIM_SINT64     = 20;
  CIM_UINT64     = 21;
  CIM_REAL32     = 4;
  CIM_REAL64     = 5;
  CIM_BOOLEAN    = 11;
  CIM_STRING     = 8;
  CIM_DATETIME   = 101;
  CIM_REFERENCE  = 102;
  CIM_CHAR16     = 103;
  CIM_OBJECT     = 13;
  CIM_FLAG_ARRAY = $2000;

type
  tag_WBEM_BACKUP_RESTORE_FLAGS = DWORD;
  WBEM_BACKUP_RESTORE_FLAGS = tag_WBEM_BACKUP_RESTORE_FLAGS;
  TWbemBackupRestoreFlags = WBEM_BACKUP_RESTORE_FLAGS;

const
  WBEM_FLAG_BACKUP_RESTORE_DEFAULT        = 0;
  WBEM_FLAG_BACKUP_RESTORE_FORCE_SHUTDOWN = 1;

type
  tag_WBEM_REFRESHER_FLAGS = DWORD;
  WBEM_REFRESHER_FLAGS = tag_WBEM_REFRESHER_FLAGS;
  TWbemRefresherFlags = WBEM_REFRESHER_FLAGS;

const
  WBEM_FLAG_REFRESH_AUTO_RECONNECT    = 0;
  WBEM_FLAG_REFRESH_NO_AUTO_RECONNECT = 1;

type
  tag_WBEM_SHUTDOWN_FLAGS = DWORD;
  WBEM_SHUTDOWN_FLAGS = tag_WBEM_SHUTDOWN_FLAGS;
  TWbemShutdownFlags = WBEM_SHUTDOWN_FLAGS;

const
  WBEM_SHUTDOWN_UNLOAD_COMPONENT = 1;
  WBEM_SHUTDOWN_WMI              = 2;
  WBEM_SHUTDOWN_OS               = 3;

type
  CIMTYPE = LONG;

type
  tag_WBEMSTATUS_FORMAT = DWORD;
  WBEMSTATUS_FORMAT = tag_WBEMSTATUS_FORMAT;
  TWbemStatusFormat = WBEMSTATUS_FORMAT;

const
  WBEMSTATUS_FORMAT_NEWLINE    = 0;
  WBEMSTATUS_FORMAT_NO_NEWLINE = 1;

type
  tag_WBEM_LIMITS = DWORD;
  WBEM_LIMITS = tag_WBEM_LIMITS;
  TWbemLimits = WBEM_LIMITS;

const
  WBEM_MAX_IDENTIFIER      = $1000;
  WBEM_MAX_QUERY           = $4000;
  WBEM_MAX_PATH            = $2000;
  WBEM_MAX_OBJECT_NESTING  = 64;
  WBEM_MAX_USER_PROPERTIES = 1024;

type
  tag_WBEMSTATUS = DWORD;
  WBEMSTATUS = tag_WBEMSTATUS;
  TWbemStatus = WBEMSTATUS;

const
  WBEM_NO_ERROR = 0;
  WBEM_S_NO_ERROR = 0;
  WBEM_S_SAME = 0;
  WBEM_S_FALSE = 1;
  WBEM_S_ALREADY_EXISTS = DWORD($40001);
  WBEM_S_RESET_TO_DEFAULT = DWORD($40002);
  WBEM_S_DIFFERENT = DWORD($40003);
  WBEM_S_TIMEDOUT = DWORD($40004);
  WBEM_S_NO_MORE_DATA = DWORD($40005);
  WBEM_S_OPERATION_CANCELLED = DWORD($40006);
  WBEM_S_PENDING = DWORD($40007);
  WBEM_S_DUPLICATE_OBJECTS = DWORD($40008);
  WBEM_S_ACCESS_DENIED = DWORD($40009);
  WBEM_S_PARTIAL_RESULTS = DWORD($40010);
  WBEM_S_SOURCE_NOT_AVAILABLE = DWORD($40017);
  WBEM_E_FAILED = DWORD($80041001);
  WBEM_E_NOT_FOUND = DWORD($80041002);
  WBEM_E_ACCESS_DENIED = DWORD($80041003);
  WBEM_E_PROVIDER_FAILURE = DWORD($80041004);
  WBEM_E_TYPE_MISMATCH = DWORD($80041005);
  WBEM_E_OUT_OF_MEMORY = DWORD($80041006);
  WBEM_E_INVALID_CONTEXT = DWORD($80041007);
  WBEM_E_INVALID_PARAMETER = DWORD($80041008);
  WBEM_E_NOT_AVAILABLE = DWORD($80041009);
  WBEM_E_CRITICAL_ERROR = DWORD($8004100a);
  WBEM_E_INVALID_STREAM = DWORD($8004100b);
  WBEM_E_NOT_SUPPORTED = DWORD($8004100c);
  WBEM_E_INVALID_SUPERCLASS = DWORD($8004100d);
  WBEM_E_INVALID_NAMESPACE = DWORD($8004100e);
  WBEM_E_INVALID_OBJECT = DWORD($8004100f);
  WBEM_E_INVALID_CLASS = DWORD($80041010);
  WBEM_E_PROVIDER_NOT_FOUND = DWORD($80041011);
  WBEM_E_INVALID_PROVIDER_REGISTRATION = DWORD($80041012);
  WBEM_E_PROVIDER_LOAD_FAILURE = DWORD($80041013);
  WBEM_E_INITIALIZATION_FAILURE = DWORD($80041014);
  WBEM_E_TRANSPORT_FAILURE = DWORD($80041015);
  WBEM_E_INVALID_OPERATION = DWORD($80041016);
  WBEM_E_INVALID_QUERY = DWORD($80041017);
  WBEM_E_INVALID_QUERY_TYPE = DWORD($80041018);
  WBEM_E_ALREADY_EXISTS = DWORD($80041019);
  WBEM_E_OVERRIDE_NOT_ALLOWED = DWORD($8004101a);
  WBEM_E_PROPAGATED_QUALIFIER = DWORD($8004101b);
  WBEM_E_PROPAGATED_PROPERTY = DWORD($8004101c);
  WBEM_E_UNEXPECTED = DWORD($8004101d);
  WBEM_E_ILLEGAL_OPERATION = DWORD($8004101e);
  WBEM_E_CANNOT_BE_KEY = DWORD($8004101f);
  WBEM_E_INCOMPLETE_CLASS = DWORD($80041020);
  WBEM_E_INVALID_SYNTAX = DWORD($80041021);
  WBEM_E_NONDECORATED_OBJECT = DWORD($80041022);
  WBEM_E_READ_ONLY = DWORD($80041023);
  WBEM_E_PROVIDER_NOT_CAPABLE = DWORD($80041024);
  WBEM_E_CLASS_HAS_CHILDREN = DWORD($80041025);
  WBEM_E_CLASS_HAS_INSTANCES = DWORD($80041026);
  WBEM_E_QUERY_NOT_IMPLEMENTED = DWORD($80041027);
  WBEM_E_ILLEGAL_NULL = DWORD($80041028);
  WBEM_E_INVALID_QUALIFIER_TYPE = DWORD($80041029);
  WBEM_E_INVALID_PROPERTY_TYPE = DWORD($8004102a);
  WBEM_E_VALUE_OUT_OF_RANGE = DWORD($8004102b);
  WBEM_E_CANNOT_BE_SINGLETON = DWORD($8004102c);
  WBEM_E_INVALID_CIM_TYPE = DWORD($8004102d);
  WBEM_E_INVALID_METHOD = DWORD($8004102e);
  WBEM_E_INVALID_METHOD_PARAMETERS = DWORD($8004102f);
  WBEM_E_SYSTEM_PROPERTY = DWORD($80041030);
  WBEM_E_INVALID_PROPERTY = DWORD($80041031);
  WBEM_E_CALL_CANCELLED = DWORD($80041032);
  WBEM_E_SHUTTING_DOWN = DWORD($80041033);
  WBEM_E_PROPAGATED_METHOD = DWORD($80041034);
  WBEM_E_UNSUPPORTED_PARAMETER = DWORD($80041035);
  WBEM_E_MISSING_PARAMETER_ID = DWORD($80041036);
  WBEM_E_INVALID_PARAMETER_ID = DWORD($80041037);
  WBEM_E_NONCONSECUTIVE_PARAMETER_IDS = DWORD($80041038);
  WBEM_E_PARAMETER_ID_ON_RETVAL = DWORD($80041039);
  WBEM_E_INVALID_OBJECT_PATH = DWORD($8004103a);
  WBEM_E_OUT_OF_DISK_SPACE = DWORD($8004103b);
  WBEM_E_BUFFER_TOO_SMALL = DWORD($8004103c);
  WBEM_E_UNSUPPORTED_PUT_EXTENSION = DWORD($8004103d);
  WBEM_E_UNKNOWN_OBJECT_TYPE = DWORD($8004103e);
  WBEM_E_UNKNOWN_PACKET_TYPE = DWORD($8004103f);
  WBEM_E_MARSHAL_VERSION_MISMATCH = DWORD($80041040);
  WBEM_E_MARSHAL_INVALID_SIGNATURE = DWORD($80041041);
  WBEM_E_INVALID_QUALIFIER = DWORD($80041042);
  WBEM_E_INVALID_DUPLICATE_PARAMETER = DWORD($80041043);
  WBEM_E_TOO_MUCH_DATA = DWORD($80041044);
  WBEM_E_SERVER_TOO_BUSY = DWORD($80041045);
  WBEM_E_INVALID_FLAVOR = DWORD($80041046);
  WBEM_E_CIRCULAR_REFERENCE = DWORD($80041047);
  WBEM_E_UNSUPPORTED_CLASS_UPDATE = DWORD($80041048);
  WBEM_E_CANNOT_CHANGE_KEY_INHERITANCE = DWORD($80041049);
  WBEM_E_CANNOT_CHANGE_INDEX_INHERITANCE = DWORD($80041050);
  WBEM_E_TOO_MANY_PROPERTIES = DWORD($80041051);
  WBEM_E_UPDATE_TYPE_MISMATCH = DWORD($80041052);
  WBEM_E_UPDATE_OVERRIDE_NOT_ALLOWED = DWORD($80041053);
  WBEM_E_UPDATE_PROPAGATED_METHOD = DWORD($80041054);
  WBEM_E_METHOD_NOT_IMPLEMENTED = DWORD($80041055);
  WBEM_E_METHOD_DISABLED = DWORD($80041056);
  WBEM_E_REFRESHER_BUSY = DWORD($80041057);
  WBEM_E_UNPARSABLE_QUERY = DWORD($80041058);
  WBEM_E_NOT_EVENT_CLASS = DWORD($80041059);
  WBEM_E_MISSING_GROUP_WITHIN = DWORD($8004105a);
  WBEM_E_MISSING_AGGREGATION_LIST = DWORD($8004105b);
  WBEM_E_PROPERTY_NOT_AN_OBJECT = DWORD($8004105c);
  WBEM_E_AGGREGATING_BY_OBJECT = DWORD($8004105d);
  WBEM_E_UNINTERPRETABLE_PROVIDER_QUERY = DWORD($8004105f);
  WBEM_E_BACKUP_RESTORE_WINMGMT_RUNNING = DWORD($80041060);
  WBEM_E_QUEUE_OVERFLOW = DWORD($80041061);
  WBEM_E_PRIVILEGE_NOT_HELD = DWORD($80041062);
  WBEM_E_INVALID_OPERATOR = DWORD($80041063);
  WBEM_E_LOCAL_CREDENTIALS = DWORD($80041064);
  WBEM_E_CANNOT_BE_ABSTRACT = DWORD($80041065);
  WBEM_E_AMENDED_OBJECT = DWORD($80041066);
  WBEM_E_CLIENT_TOO_SLOW = DWORD($80041067);
  WBEM_E_NULL_SECURITY_DESCRIPTOR = DWORD($80041068);
  WBEM_E_TIMED_OUT = DWORD($80041069);
  WBEM_E_INVALID_ASSOCIATION = DWORD($8004106a);
  WBEM_E_AMBIGUOUS_OPERATION = DWORD($8004106b);
  WBEM_E_QUOTA_VIOLATION = DWORD($8004106c);
  WBEM_E_RESERVED_001 = DWORD($8004106d);
  WBEM_E_RESERVED_002 = DWORD($8004106e);
  WBEM_E_UNSUPPORTED_LOCALE = DWORD($8004106f);
  WBEM_E_HANDLE_OUT_OF_DATE = DWORD($80041070);
  WBEM_E_CONNECTION_FAILED = DWORD($80041071);
  WBEM_E_INVALID_HANDLE_REQUEST = DWORD($80041072);
  WBEM_E_PROPERTY_NAME_TOO_WIDE = DWORD($80041073);
  WBEM_E_CLASS_NAME_TOO_WIDE = DWORD($80041074);
  WBEM_E_METHOD_NAME_TOO_WIDE = DWORD($80041075);
  WBEM_E_QUALIFIER_NAME_TOO_WIDE = DWORD($80041076);
  WBEM_E_RERUN_COMMAND = DWORD($80041077);
  WBEM_E_DATABASE_VER_MISMATCH = DWORD($80041078);
  WBEM_E_VETO_DELETE = DWORD($80041079);
  WBEM_E_VETO_PUT = DWORD($8004107a);
  WBEM_E_INVALID_LOCALE = DWORD($80041080);
  WBEM_E_PROVIDER_SUSPENDED = DWORD($80041081);
  WBEM_E_SYNCHRONIZATION_REQUIRED = DWORD($80041082);
  WBEM_E_NO_SCHEMA = DWORD($80041083);
  WBEM_E_PROVIDER_ALREADY_REGISTERED = DWORD($80041084);
  WBEM_E_PROVIDER_NOT_REGISTERED = DWORD($80041085);
  WBEM_E_FATAL_TRANSPORT_ERROR = DWORD($80041086);
  WBEM_E_ENCRYPTED_CONNECTION_REQUIRED = DWORD($80041087);
  WBEM_E_PROVIDER_TIMED_OUT = DWORD($80041088);
  WBEM_E_NO_KEY = DWORD($80041089);
  WBEM_E_PROVIDER_DISABLED = DWORD($8004108a);
  WBEMESS_E_REGISTRATION_TOO_BROAD = DWORD($80042001);
  WBEMESS_E_REGISTRATION_TOO_PRECISE = DWORD($80042002);
  WBEMMOF_E_EXPECTED_QUALIFIER_NAME = DWORD($80044001);
  WBEMMOF_E_EXPECTED_SEMI = DWORD($80044002);
  WBEMMOF_E_EXPECTED_OPEN_BRACE = DWORD($80044003);
  WBEMMOF_E_EXPECTED_CLOSE_BRACE = DWORD($80044004);
  WBEMMOF_E_EXPECTED_CLOSE_BRACKET = DWORD($80044005);
  WBEMMOF_E_EXPECTED_CLOSE_PAREN = DWORD($80044006);
  WBEMMOF_E_ILLEGAL_CONSTANT_VALUE = DWORD($80044007);
  WBEMMOF_E_EXPECTED_TYPE_IDENTIFIER = DWORD($80044008);
  WBEMMOF_E_EXPECTED_OPEN_PAREN = DWORD($80044009);
  WBEMMOF_E_UNRECOGNIZED_TOKEN = DWORD($8004400a);
  WBEMMOF_E_UNRECOGNIZED_TYPE = DWORD($8004400b);
  WBEMMOF_E_EXPECTED_PROPERTY_NAME = DWORD($8004400c);
  WBEMMOF_E_TYPEDEF_NOT_SUPPORTED = DWORD($8004400d);
  WBEMMOF_E_UNEXPECTED_ALIAS = DWORD($8004400e);
  WBEMMOF_E_UNEXPECTED_ARRAY_INIT = DWORD($8004400f);
  WBEMMOF_E_INVALID_AMENDMENT_SYNTAX = DWORD($80044010);
  WBEMMOF_E_INVALID_DUPLICATE_AMENDMENT = DWORD($80044011);
  WBEMMOF_E_INVALID_PRAGMA = DWORD($80044012);
  WBEMMOF_E_INVALID_NAMESPACE_SYNTAX = DWORD($80044013);
  WBEMMOF_E_EXPECTED_CLASS_NAME = DWORD($80044014);
  WBEMMOF_E_TYPE_MISMATCH = DWORD($80044015);
  WBEMMOF_E_EXPECTED_ALIAS_NAME = DWORD($80044016);
  WBEMMOF_E_INVALID_CLASS_DECLARATION = DWORD($80044017);
  WBEMMOF_E_INVALID_INSTANCE_DECLARATION = DWORD($80044018);
  WBEMMOF_E_EXPECTED_DOLLAR = DWORD($80044019);
  WBEMMOF_E_CIMTYPE_QUALIFIER = DWORD($8004401a);
  WBEMMOF_E_DUPLICATE_PROPERTY = DWORD($8004401b);
  WBEMMOF_E_INVALID_NAMESPACE_SPECIFICATION = DWORD($8004401c);
  WBEMMOF_E_OUT_OF_RANGE = DWORD($8004401d);
  WBEMMOF_E_INVALID_FILE = DWORD($8004401e);
  WBEMMOF_E_ALIASES_IN_EMBEDDED = DWORD($8004401f);
  WBEMMOF_E_NULL_ARRAY_ELEM = DWORD($80044020);
  WBEMMOF_E_DUPLICATE_QUALIFIER = DWORD($80044021);
  WBEMMOF_E_EXPECTED_FLAVOR_TYPE = DWORD($80044022);
  WBEMMOF_E_INCOMPATIBLE_FLAVOR_TYPES = DWORD($80044023);
  WBEMMOF_E_MULTIPLE_ALIASES = DWORD($80044024);
  WBEMMOF_E_INCOMPATIBLE_FLAVOR_TYPES2 = DWORD($80044025);
  WBEMMOF_E_NO_ARRAYS_RETURNED = DWORD($80044026);
  WBEMMOF_E_MUST_BE_IN_OR_OUT = DWORD($80044027);
  WBEMMOF_E_INVALID_FLAGS_SYNTAX = DWORD($80044028);
  WBEMMOF_E_EXPECTED_BRACE_OR_BAD_TYPE = DWORD($80044029);
  WBEMMOF_E_UNSUPPORTED_CIMV22_QUAL_VALUE = DWORD($8004402a);
  WBEMMOF_E_UNSUPPORTED_CIMV22_DATA_TYPE = DWORD($8004402b);
  WBEMMOF_E_INVALID_DELETEINSTANCE_SYNTAX = DWORD($8004402c);
  WBEMMOF_E_INVALID_QUALIFIER_SYNTAX = DWORD($8004402d);
  WBEMMOF_E_QUALIFIER_USED_OUTSIDE_SCOPE = DWORD($8004402e);
  WBEMMOF_E_ERROR_CREATING_TEMP_FILE = DWORD($8004402f);
  WBEMMOF_E_ERROR_INVALID_INCLUDE_FILE = DWORD($80044030);
  WBEMMOF_E_INVALID_DELETECLASS_SYNTAX = DWORD($80044031);

//const
//EXTERN_C const IID LIBID_WbemClient_v1;

const
  IID_IWbemClassObject: TGUID = '{dc12a681-737f-11cf-884d-00aa004b2e24}';
  IID_IWbemObjectAccess: TGUID = '{49353c9a-516b-11d1-aea6-00c04fb68820}';
  IID_IWbemQualifierSet: TGUID = '{dc12a680-737f-11cf-884d-00aa004b2e24}';
  IID_IWbemServices: TGUID = '{9556dc99-828c-11cf-a37e-00aa003240c7}';
  IID_IWbemLocator: TGUID = '{dc12a687-737f-11cf-884d-00aa004b2e24}';
  IID_IWbemObjectSink: TGUID = '{7c857801-7381-11cf-884d-00aa004b2e24}';
  IID_IEnumWbemClassObject: TGUID = '{027947e1-d731-11ce-a357-000000000001}';
  IID_IWbemCallResult: TGUID = '{44aca675-e8fc-11d0-a07c-00c04fb68820}';
  IID_IWbemContext: TGUID = '{44aca674-e8fc-11d0-a07c-00c04fb68820}';
  IID_IUnsecuredApartment: TGUID = '{1cfaba8c-1523-11d1-ad79-00c04fd8fdff}';
  IID_IWbemUnsecuredApartment: TGUID = '{31739d04-3471-4cf4-9a7c-57a44ae71956}';
  IID_IWbemStatusCodeText: TGUID = '{eb87e1bc-3233-11d2-aec9-00c04fb68820}';
  IID_IWbemBackupRestore: TGUID = '{C49E32C7-BC8B-11d2-85D4-00105A1F8304}';
  IID_IWbemBackupRestoreEx: TGUID = '{A359DEC5-E813-4834-8A2A-BA7F1D777D76}';
  IID_IWbemRefresher: TGUID = '{49353c99-516b-11d1-aea6-00c04fb68820}';
  IID_IWbemHiPerfEnum: TGUID = '{2705C288-79AE-11d2-B348-00105A1F8177}';
  IID_IWbemConfigureRefresher: TGUID = '{49353c92-516b-11d1-aea6-00c04fb68820}';

type
  // forward declarations

  IWbemQualifierSet = interface;
  IWbemContext = interface;
  IWbemCallResult = interface;
  IWbemObjectSink = interface;
  IEnumWbemClassObject = interface;

  IWbemClassObject = interface(IUnknown)
  ['{dc12a681-737f-11cf-884d-00aa004b2e24}']
    function GetQualifierSet(out ppQualSet: IWbemQualifierSet): HRESULT; stdcall;
    function Get(wszName: LPCWSTR; lFlags: Longint; var pVal: OleVariant; var pType: CIMTYPE; var plFlavor: Longint): HRESULT; stdcall;
    function Put(wszName: LPCWSTR; lFlags: Longint; pVal: POleVariant; Type_: CIMTYPE): HRESULT; stdcall;
    function Delete(wszName: LPCWSTR): HRESULT; stdcall;
    function GetNames(wszQualifierName: LPCWSTR; lFlags: Longint; pQualifierVal: POleVariant; out pNames: PSafeArray): HRESULT; stdcall;
    function BeginEnumeration(lEnumFlags: Longint): HRESULT; stdcall;
    function Next(lFlags: Longint; var strName: WideString; var pVal: OleVariant; var pType: CIMTYPE; var plFlavor: Longint): HRESULT; stdcall;
    function EndEnumeration: HRESULT; stdcall;
    function GetPropertyQualifierSet(wszProperty: LPCWSTR; out ppQualSet: IWbemQualifierSet): HRESULT; stdcall;
    function Clone(out ppCopy: IWbemClassObject): HRESULT; stdcall;
    function GetObjectText(lFlags: Longint; out pstrObjectText: WideString): HRESULT; stdcall;
    function SpawnDerivedClass(lFlags: Longint; out ppNewClass: IWbemClassObject): HRESULT; stdcall;
    function SpawnInstance(lFlags: Longint; out ppNewInstance: IWbemClassObject): HRESULT; stdcall;
    function CompareTo(lFlags: Longint; pCompareTo: IWbemClassObject): HRESULT; stdcall;
    function GetPropertyOrigin(wszName: LPCWSTR; out pstrClassName: WideString): HRESULT; stdcall;
    function InheritsFrom(strAncestor: LPCWSTR): HRESULT; stdcall;
    function GetMethod(wszName: LPCWSTR; lFlags: Longint; out ppInSignature, ppOutSignature: IWbemClassObject): HRESULT; stdcall;
    function PutMethod(wszName: LPCWSTR; lFlags: Longint; pInSignature, pOutSignature: IWbemClassObject): HRESULT; stdcall;
    function DeleteMethod(wszName: LPCWSTR): HRESULT; stdcall;
    function BeginMethodEnumeration(lEnumFlags: Longint): HRESULT; stdcall;
    function NextMethod(lFlags: Longint; var pstrName: WideString; var ppInSignature, ppOutSignature: IWbemClassObject): HRESULT; stdcall;
    function EndMethodEnumeration: HRESULT; stdcall;
    function GetMethodQualifierSet(wszMethod: LPCWSTR; out ppQualSet: IWbemQualifierSet): HRESULT; stdcall;
    function GetMethodOrigin(wszMethodName: LPCWSTR; out pstrClassName: WideString): HRESULT; stdcall;
  end;

  IWbemObjectAccess = interface(IWbemClassObject)
  ['{49353c9a-516b-11d1-aea6-00c04fb68820}']
    function GetPropertyHandle(wszPropertyName: LPCWSTR; out pType: CIMTYPE; out plHandle: Longint): HRESULT; stdcall;
    function WritePropertyValue(lHandle, lNumBytes: Longint; aData: LPBYTE): HRESULT; stdcall;
    function ReadPropertyValue(lHandle, lBufferSize: Longint; out plNumBytes: Longint; aData: LPBYTE): HRESULT; stdcall;
    function ReadDWORD(lHandle: Longint; out pdw: DWORD): HRESULT; stdcall;
    function WriteDWORD(lHandle: Longint; dw: DWORD): HRESULT; stdcall;
    function ReadQWORD(lHandle: Longint; out pqw: Int64): HRESULT; stdcall;
    function WriteQWORD(lHandle: Longint; pw: Int64): HRESULT; stdcall;
    function GetPropertyInfoByHandle(lHandle: Longint; out pstrName: WideString; out pType: CIMTYPE): HRESULT; stdcall;
    function Lock(lFlags: Longint): HRESULT; stdcall;
    function Unlock(lFlags: Longint): HRESULT; stdcall;
  end;

  IWbemQualifierSet = interface(IUnknown)
  ['{dc12a680-737f-11cf-884d-00aa004b2e24}']
    function Get(wszName: LPCWSTR; lFlags: Longint; var pVal: OleVariant; var plFlavor: Longint): HRESULT; stdcall;
    function Put(wszName: LPCWSTR; pVal: POleVariant; lFlavor: Longint): HRESULT; stdcall;
    function Delete(wszName: LPCWSTR): HRESULT; stdcall;
    function GetNames(lFlags: Longint; out pNames: PSafeArray): HRESULT; stdcall;
    function BeginEnumeration(lFlags: Longint): HRESULT; stdcall;
    function Next(lFlags: Longint; var pstrName: WideString; var pVal: OleVariant; var plFlavor: Longint): HRESULT; stdcall;
    function EndEnumeration: HRESULT; stdcall;
  end;

  IWbemServices = interface(IUnknown)
  ['{9556dc99-828c-11cf-a37e-00aa003240c7}']
    function OpenNamespace(strNamespace: WideString; lFlags: Longint; pCtx: IWbemContext; out ppWorkingNamespace: IWbemServices; out ppResult: IWbemCallResult): HRESULT; stdcall;
    function CancelAsyncCall(pSink: IWbemObjectSink): HRESULT; stdcall;
    function QueryObjectSink(lFlags: Longint; out ppResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function GetObject(strObjectPath: WideString; lFlags: Longint; pCtx: IWbemContext; out ppObject: IWbemClassObject; out ppCallResult: IWbemCallResult): HRESULT; stdcall;
    function GetObjectAsync(strObjectPath: WideString; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function PutClass(pObject: IWbemClassObject; lFlags: Longint; pCtx: IWbemContext; out ppCallResult: IWbemCallResult): HRESULT; stdcall;
    function PutClassAsync(pObject: IWbemClassObject; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function DeleteClass(strClass: WideString; lFlags: Longint; pCtx: IWbemContext; out ppCallResult: IWbemCallResult): HRESULT; stdcall;
    function DeleteClassAsync(strClass: WideString; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function CreateClassEnum(strSuperclass: WideString; lFlags: Longint; pCtx: IWbemContext; out ppEnum: IEnumWbemClassObject): HRESULT; stdcall;
    function CreateClassEnumAsync(strSuperclass: WideString; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function PutInstance(pInst: IWbemClassObject; lFlags: Longint; pCtx: IWbemContext; out ppCallResult: IWbemCallResult): HRESULT; stdcall;
    function PutInstanceAsync(pInst: IWbemClassObject; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function DeleteInstance(strObjectPath: WideString; lFlags: Longint; pCtx: IWbemContext; out ppCallResult: IWbemCallResult): HRESULT; stdcall;
    function DeleteInstanceAsync(strObjectPath: WideString; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function CreateInstanceEnum(strFilter: WideString; lFlags: Longint; pCtx: IWbemContext; out ppEnum: IEnumWbemClassObject): HRESULT; stdcall;
    function CreateInstanceEnumAsync(strFilter: WideString; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function ExecQuery(strQueryLanguage, strQuery: WideString; lFlags: Longint; pCtx: IWbemContext; out ppEnum: IEnumWbemClassObject): HRESULT; stdcall;
    function ExecQueryAsync(strQueryLanguage, strQuery: WideString; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function ExecNotificationQuery(strQueryLanguage, strQuery: WideString; lFlags: Longint; pCtx: IWbemContext; out ppEnum: IEnumWbemClassObject): HRESULT; stdcall;
    function ExecNotificationQueryAsync(strQueryLanguage, strQuery: WideString; lFlags: Longint; pCtx: IWbemContext; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
    function ExecMethod(strObjectPath, strMethodName: WideString; lFlags: Longint; pCtx: IWbemContext; pInParams: IWbemClassObject; out ppOutParams: IWbemClassObject; out ppCallResult: IWbemCallResult): HRESULT; stdcall;
    function ExecMethodAsync(strObjectPath, strMethodName: WideString; lFlags: Longint; pCtx: IWbemContext; pInParams: IWbemClassObject; pResponseHandler: IWbemObjectSink): HRESULT; stdcall;
  end;

  IWbemLocator = interface(IUnknown)
  ['{dc12a687-737f-11cf-884d-00aa004b2e24}']
    function ConnectServer(strNetworkResource, strUser, strPassword, strLocale: WideString; lSecurityFlags: Longint;
      strAuthority: WideString; pCtx: IWbemContext; out ppNamespace: IWbemServices): HRESULT; stdcall;
  end;

  IWbemObjectSink = interface(IUnknown)
  ['{7c857801-7381-11cf-884d-00aa004b2e24}']
    function Indicate(lObjectCount: Longint; var apObjArray: IWbemClassObject{todo}): HRESULT; stdcall;
    function SetStatus(lFlags: Longint; hResult: HRESULT; strParam: WideString; pObjParam: IWbemClassObject): HRESULT; stdcall;
  end;

  IEnumWbemClassObject = interface(IUnknown)
  ['{027947e1-d731-11ce-a357-000000000001}']
    function Reset: HRESULT; stdcall;
    function Next(lTimeout: Longint; uCount: ULONG; out apObjects: IWbemClassObject; out puReturned: ULONG): HRESULT; stdcall;
    function NextAsync(uCount: ULONG; pSink: IWbemObjectSink): HRESULT; stdcall;
    function Clone(out ppEnum: IEnumWbemClassObject): HRESULT; stdcall;
    function Skip(lTimeout: Longint; nCount: ULONG): HRESULT; stdcall;
  end;

  IWbemCallResult = interface(IUnknown)
  ['{44aca675-e8fc-11d0-a07c-00c04fb68820}']
    function GetResultObject(lTimeout: Longint; out ppResultObject: IWbemClassObject): HRESULT; stdcall;
    function GetResultString(lTimeout: Longint; out pstrResultString: WideString): HRESULT; stdcall;
    function GetResultServices(lTimeout: Longint; out ppServices: IWbemServices): HRESULT; stdcall;
    function GetCallStatus(lTimeout: Longint; out plStatus: Longint): HRESULT; stdcall;
  end;

  IWbemContext = interface(IUnknown)
  ['{44aca674-e8fc-11d0-a07c-00c04fb68820}']
    function Clone(out ppNewCopy: IWbemContext): HRESULT; stdcall;
    function GetNames(lFlags: Longint; out pNames: PSafeArray): HRESULT; stdcall;
    function BeginEnumeration(lFlags: Longint): HRESULT; stdcall;
    function Next(lFlags: Longint; out pstrName: WideString; out pValue: OleVariant): HRESULT; stdcall;
    function EndEnumeration: HRESULT; stdcall;
    function SetValue(wszName: LPCWSTR; lFlags: Longint; pValue: POleVariant): HRESULT; stdcall;
    function GetValue(wszName: LPCWSTR; lFlags: Longint; out pValue: OleVariant): HRESULT; stdcall;
    function DeleteValue(wszName: LPCWSTR; lFlags: Longint): HRESULT; stdcall;
    function DeleteAll: HRESULT; stdcall;
  end;

  IUnsecuredApartment = interface(IUnknown)
  ['{1cfaba8c-1523-11d1-ad79-00c04fd8fdff}']
    function CreateObjectStub(pObject: IUnknown; out ppStub: IUnknown): HRESULT; stdcall;
  end;

  IWbemUnsecuredApartment = interface(IUnsecuredApartment)
  ['{31739d04-3471-4cf4-9a7c-57a44ae71956}']
    function CreateSinkStub(pSink: IWbemObjectSink; dwFlags: DWORD; wszReserved: LPCWSTR; out ppStub: IWbemObjectSink): HRESULT; stdcall;
  end;

  IWbemStatusCodeText = interface(IUnknown)
  ['{eb87e1bc-3233-11d2-aec9-00c04fb68820}']
    function GetErrorCodeText(hRes: HRESULT; LocaleId: LCID; lFlags: Longint; out MessageText: WideString): HRESULT; stdcall;
    function GetFacilityCodeText(hRes: HRESULT; LocaleId: LCID; lFlags: Longint; out MessageText: WideString): HRESULT; stdcall;
  end;

  IWbemBackupRestore = interface(IUnknown)
  ['{C49E32C7-BC8B-11d2-85D4-00105A1F8304}']
    function Backup(strBackupToFile: LPCWSTR; lFlags: Longint): HRESULT; stdcall;
    function Restore(strRestoreFromFile: LPCWSTR; lFlags: Longint): HRESULT; stdcall;
  end;

  IWbemBackupRestoreEx = interface(IWbemBackupRestore)
  ['{A359DEC5-E813-4834-8A2A-BA7F1D777D76}']
    function Pause: HRESULT; stdcall;
    function Resume: HRESULT; stdcall;
  end;

  IWbemRefresher = interface(IUnknown)
  ['{49353c99-516b-11d1-aea6-00c04fb68820}']
    function Refresh(lFlags: Longint): HRESULT; stdcall;
  end;

  PIWbemObjectAccess = ^IWbemObjectAccess;

  PLongint = ^Longint; // TODO PLongint introduced in Delphi 6

  IWbemHiPerfEnum = interface(IUnknown)
  ['{2705C288-79AE-11d2-B348-00105A1F8177}']
    function AddObjects(lFlags: Longint; uNumObjects: ULONG; apIds: PLongint; apObj: PIWbemObjectAccess): HRESULT; stdcall;
    function RemoveObjects(lFlags: Longint; uNumObjects: ULONG; apIds: PLongint): HRESULT; stdcall;
    function GetObjects(lFlags: Longint; uNumObjects: ULONG; out apObj: IWbemObjectAccess; out puReturned: ULONG): HRESULT; stdcall;
    function RemoveAll(lFlags: Longint): HRESULT; stdcall;
  end;

  IWbemConfigureRefresher = interface(IUnknown)
  ['{49353c92-516b-11d1-aea6-00c04fb68820}']
    function AddObjectByPath(pNamespace: IWbemServices; wszPath: LPCWSTR; lFlags: Longint; pContext: IWbemContext; out ppRefreshable: IWbemClassObject; var plId: Longint): HRESULT; stdcall;
    function AddObjectByTemplate(pNamespace: IWbemServices; pTemplate: IWbemClassObject; lFlags: Longint; pContext: IWbemContext; out ppRefreshable: IWbemClassObject; var plId: Longint): HRESULT; stdcall;
    function AddRefresher(pRefresher: IWbemRefresher; lFlags: Longint; var plId: Longint): HRESULT; stdcall;
    function Remove(lId, lFlags: Longint): HRESULT; stdcall;
    function AddEnum(pNamespace: IWbemServices; wszClassName: LPCWSTR; lFlags: Longint; pContext: IWbemContext; out ppEnum: IWbemHiPerfEnum; var plId: Longint): HRESULT; stdcall;
  end;

const
  CLSID_WbemLocator: TGUID = '{4590f811-1d3a-11d0-891f-00aa004b2e24}';
  CLSID_WbemContext: TGUID = '{674B6698-EE92-11d0-AD71-00C04FD8FDFF}';
  CLSID_UnsecuredApartment: TGUID = '{49bd2028-1523-11d1-ad79-00c04fd8fdff}';
  CLSID_WbemClassObject: TGUID = '{9A653086-174F-11d2-B5F9-00104B703EFD}';
  CLSID_MofCompiler: TGUID = '{6daf9757-2e37-11d2-aec9-00c04fb68820}';
  CLSID_WbemStatusCodeText: TGUID = '{eb87e1bd-3233-11d2-aec9-00c04fb68820}';
  CLSID_WbemBackupRestore: TGUID = '{C49E32C6-BC8B-11d2-85D4-00105A1F8304}';
  CLSID_WbemRefresher: TGUID = '{c71566f2-561e-11d1-ad87-00c04fd8fdff}';
  CLSID_WbemObjectTextSrc: TGUID = '{8D1C559D-84F0-4bb3-A7D5-56A7435A9BA6}';

const
  IID_IWbemShutdown: TGUID = '{b7b31df9-d515-11d3-a11c-00105a1f515a}';

type
  IWbemShutdown = interface(IUnknown)
  ['{b7b31df9-d515-11d3-a11c-00105a1f515a}']
    function Shutdown(uReason: LONG; uMaxMilliseconds: ULONG; pCtx: IWbemContext): HRESULT; stdcall;
  end;

type
  tag_WMI_OBJ_TEXT = DWORD;
  WMI_OBJ_TEXT = tag_WMI_OBJ_TEXT;
  TWmiObjText = WMI_OBJ_TEXT;

const
  WMI_OBJ_TEXT_CIM_DTD_2_0 = 1;
  WMI_OBJ_TEXT_WMI_DTD_2_0 = 2;
  WMI_OBJ_TEXT_WMI_EXT1 = 3;
  WMI_OBJ_TEXT_WMI_EXT2 = 4;
  WMI_OBJ_TEXT_WMI_EXT3 = 5;
  WMI_OBJ_TEXT_WMI_EXT4 = 6;
  WMI_OBJ_TEXT_WMI_EXT5 = 7;
  WMI_OBJ_TEXT_WMI_EXT6 = 8;
  WMI_OBJ_TEXT_WMI_EXT7 = 9;
  WMI_OBJ_TEXT_WMI_EXT8 = 10;
  WMI_OBJ_TEXT_WMI_EXT9 = 11;
  WMI_OBJ_TEXT_WMI_EXT10 = 12;
  WMI_OBJ_TEXT_LAST = 13;

const
  IID_IWbemObjectTextSrc: TGUID = '{bfbf883a-cad7-11d3-a11b-00105a1f515a}';

type
  IWbemObjectTextSrc = interface(IUnknown)
  ['{bfbf883a-cad7-11d3-a11b-00105a1f515a}']
    function GetText(lFlags: Longint; pObj: IWbemClassObject; uObjTextFormat: ULONG; pCtx: IWbemContext; out strText: WideString): HRESULT; stdcall;
    function CreateFromText(lFlags: Longint; strText: WideString; uObjTextFormat: ULONG; pCtx: IWbemContext; out pNewObj:IWbemClassObject): HRESULT; stdcall;
  end;

const
  IID_IMofCompiler: TGUID = '{6daf974e-2e37-11d2-aec9-00c04fb68820}';

type
  tag_CompileStatusInfo = record
    lPhaseError: Longint;
    hRes: HRESULT;
    ObjectNum: Longint;
    FirstLine: Longint;
    LastLine: Longint;
    dwOutFlags: DWORD;
  end;
  WBEM_COMPILE_STATUS_INFO = tag_CompileStatusInfo;
  TWbemCompileStatusInfo = WBEM_COMPILE_STATUS_INFO;

type
  tag_WBEM_COMPILER_OPTIONS = DWORD;
  WBEM_COMPILER_OPTIONS = tag_WBEM_COMPILER_OPTIONS;
  TWbemCompilerOptions = WBEM_COMPILER_OPTIONS;

const
  WBEM_FLAG_CHECK_ONLY       = $1;
  WBEM_FLAG_AUTORECOVER      = $2;
  WBEM_FLAG_WMI_CHECK        = $4;
  WBEM_FLAG_CONSOLE_PRINT    = $8;
  WBEM_FLAG_DONT_ADD_TO_LIST = $10;
  WBEM_FLAG_SPLIT_FILES      = $20;
  WBEM_FLAG_STORE_FILE       = $100;

type
  tag_WBEM_CONNECT_OPTIONS = DWORD;
  WBEM_CONNECT_OPTIONS = tag_WBEM_CONNECT_OPTIONS;
  TWbemConnectOptions = WBEM_CONNECT_OPTIONS;

const
  WBEM_FLAG_CONNECT_REPOSITORY_ONLY = $40;
  WBEM_FLAG_CONNECT_USE_MAX_WAIT = $80;

type
  IMofCompiler = interface(IUnknown)
  ['{6daf974e-2e37-11d2-aec9-00c04fb68820}']
    function CompileFile(FileName, ServerAndNamespace, User, Authority, Password: LPWSTR;
      lOptionFlags, lClassFlags, lInstanceFlags: LONG; var pInfo: WBEM_COMPILE_STATUS_INFO): HRESULT; stdcall;
    function CompileBuffer(buffSize: Longint; pBuffer: LPBYTE; ServerAndNamespace, User, Authority, Password: LPWSTR;
      lOptionFlags, lClassFlags, lInstanceFlags: LONG; var pInfo: WBEM_COMPILE_STATUS_INFO): HRESULT; stdcall;
    function CreateBMOF(TextFileName, BMOFFileName, ServerAndNamespace: LPWSTR;
      lOptionFlags, lClassFlags, lInstanceFlags: LONG; var pInfo: WBEM_COMPILE_STATUS_INFO): HRESULT; stdcall;
  end;

type
  tag_WBEM_UNSECAPP_FLAG_TYPE = DWORD;
  WBEM_UNSECAPP_FLAG_TYPE = tag_WBEM_UNSECAPP_FLAG_TYPE;
  TWbemUnsecAppFlagType = WBEM_UNSECAPP_FLAG_TYPE;

const
  WBEM_FLAG_UNSECAPP_DEFAULT_CHECK_ACCESS = 0;
  WBEM_FLAG_UNSECAPP_CHECK_ACCESS         = 1;
  WBEM_FLAG_UNSECAPP_DONT_CHECK_ACCESS    = 2;

type
  tag_WBEM_INFORMATION_FLAG_TYPE = DWORD;
  WBEM_INFORMATION_FLAG_TYPE = tag_WBEM_INFORMATION_FLAG_TYPE;
  TWbemInformationFlagType = WBEM_INFORMATION_FLAG_TYPE;

const
  WBEM_FLAG_SHORT_NAME = $1;
  WBEM_FLAG_LONG_NAME  = $2;

// Additional Prototypes for ALL interfaces

//unsigned long             __RPC_USER  WideString_UserSize(     unsigned long *, unsigned long            , WideString * );
//unsigned AnsiChar * __RPC_USER  WideString_UserMarshal(  unsigned long *, unsigned AnsiChar *, WideString * );
//unsigned AnsiChar * __RPC_USER  WideString_UserUnmarshal(unsigned long *, unsigned AnsiChar *, WideString * );
//void                      __RPC_USER  WideString_UserFree(     unsigned long *, WideString * );

// end of Additional Prototypes

implementation
//uses ...

//your implementation here

end.
