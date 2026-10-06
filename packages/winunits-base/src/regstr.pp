{******************************************************************************}
{                                                                              }
{ Registry Key Definitions API interface Unit for Object Pascal                }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: regstr.h, released June 2000. The original Pascal      }
{ code is: RegStr.pas, released December 2000. The initial developer of the    }
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

// $Id: RegStr.pas,v 1.10 2007/09/05 11:58:52 dezipaitor Exp $

unit RegStr;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

{.$DEFINE NEC_98}

uses Windows;

const

// Public registry key names

  REGSTR_KEY_CLASS       = 'Class'; // under LOCAL_MACHINE
  REGSTR_KEY_CONFIG      = 'Config'; // under LOCAL_MACHINE
  REGSTR_KEY_ENUM        = 'Enum'; // under LOCAL_MACHINE
  REGSTR_KEY_ROOTENUM    = 'Root'; // child of ENUM
  REGSTR_KEY_BIOSENUM    = 'BIOS'; // child of ENUM
  REGSTR_KEY_ACPIENUM    = 'ACPI'; // child of ENUM
  REGSTR_KEY_PCMCIAENUM  = 'PCMCIA'; // child of ENUM
  REGSTR_KEY_PCIENUM     = 'PCI'; // child of ENUM
  REGSTR_KEY_VPOWERDENUM = 'VPOWERD'; // child of ENUM
  REGSTR_KEY_ISAENUM  = 'ISAPnP'; // child of ENUM
  REGSTR_KEY_EISAENUM = 'EISA'; // child of ENUM
  REGSTR_KEY_LOGCONFIG   = 'LogConfig'; // child of enum\<enumerator>\<deviceid>\<instanceid>
  REGSTR_KEY_SYSTEMBOARD = '*PNP0C01'; // child of enum\root
  REGSTR_KEY_APM         = '*PNP0C05'; // child of enum\root

  REGSTR_KEY_INIUPDATE = 'IniUpdate';
  REG_KEY_INSTDEV      = 'Installed'; // child of hklm\class\classname (Win98-only)

  REGSTR_KEY_DOSOPTCDROM = 'CD-ROM';
  REGSTR_KEY_DOSOPTMOUSE = 'MOUSE';

  REGSTR_KEY_KNOWNDOCKINGSTATES = 'Hardware Profiles';
  REGSTR_KEY_DEVICEPARAMETERS   = 'Device Parameters';

// Public registry paths

  REGSTR_DEFAULT_INSTANCE          = '0000';
  REGSTR_PATH_MOTHERBOARD          = REGSTR_KEY_SYSTEMBOARD + '\' + REGSTR_DEFAULT_INSTANCE;
  REGSTR_PATH_SETUP                = 'Software\Microsoft\Windows\CurrentVersion';
  REGSTR_PATH_DRIVERSIGN           = 'Software\Microsoft\Driver Signing';
  REGSTR_PATH_NONDRIVERSIGN        = 'Software\Microsoft\Non-Driver Signing';
  REGSTR_PATH_DRIVERSIGN_POLICY    = 'Software\Policies\Microsoft\Windows NT\Driver Signing';
  REGSTR_PATH_NONDRIVERSIGN_POLICY = 'Software\Policies\Microsoft\Windows NT\Non-Driver Signing';
  REGSTR_PATH_PIFCONVERT           = 'Software\Microsoft\Windows\CurrentVersion\PIFConvert';
  REGSTR_PATH_MSDOSOPTS            = 'Software\Microsoft\Windows\CurrentVersion\MS-DOSOptions';
  REGSTR_PATH_NOSUGGMSDOS          = 'Software\Microsoft\Windows\CurrentVersion\NoMSDOSWarn';
  REGSTR_PATH_NEWDOSBOX            = 'Software\Microsoft\Windows\CurrentVersion\MS-DOSSpecialConfig';
  REGSTR_PATH_RUNONCE              = 'Software\Microsoft\Windows\CurrentVersion\RunOnce';
  REGSTR_PATH_RUNONCEEX            = 'Software\Microsoft\Windows\CurrentVersion\RunOnceEx';
  REGSTR_PATH_RUN                  = 'Software\Microsoft\Windows\CurrentVersion\Run';
  REGSTR_PATH_RUNSERVICESONCE      = 'Software\Microsoft\Windows\CurrentVersion\RunServicesOnce';
  REGSTR_PATH_RUNSERVICES          = 'Software\Microsoft\Windows\CurrentVersion\RunServices';
  REGSTR_PATH_EXPLORER             = 'Software\Microsoft\Windows\CurrentVersion\Explorer';
  REGSTR_PATH_DETECT               = 'Software\Microsoft\Windows\CurrentVersion\Detect';
  REGSTR_PATH_APPPATHS             = 'Software\Microsoft\Windows\CurrentVersion\App Paths';
  REGSTR_PATH_UNINSTALL            = 'Software\Microsoft\Windows\CurrentVersion\Uninstall';
  REGSTR_PATH_REALMODENET          = 'Software\Microsoft\Windows\CurrentVersion\Network\Real Mode Net';
  REGSTR_PATH_NETEQUIV             = 'Software\Microsoft\Windows\CurrentVersion\Network\Equivalent';
  REGSTR_PATH_CVNETWORK            = 'Software\Microsoft\Windows\CurrentVersion\Network';
  REGSTR_PATH_WMI_SECURITY         = 'System\CurrentControlSet\Control\Wmi\Security';
  REGSTR_PATH_RELIABILITY          = 'Software\Microsoft\Windows\CurrentVersion\Reliability';
  REGSTR_PATH_RELIABILITY_POLICY   = 'Software\Policies\Microsoft\Windows NT\Reliability';
  REGSTR_PATH_RELIABILITY_POLICY_SHUTDOWNREASONUI = 'ShutdownReasonUI';
  REGSTR_PATH_RELIABILITY_POLICY_SNAPSHOT         = 'Snapshot';
  REGSTR_PATH_RELIABILITY_POLICY_REPORTSNAPSHOT   = 'ReportSnapshot';
  REGSTR_PATH_REINSTALL            = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Reinstall';
  REGSTR_PATH_NT_CURRENTVERSION    = 'Software\Microsoft\Windows NT\CurrentVersion';

  REGSTR_PATH_VOLUMECACHE = 'Software\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches';
  REGSTR_VAL_DISPLAY      = 'display';

  REGSTR_PATH_IDCONFIGDB             = 'System\CurrentControlSet\Control\IDConfigDB';
  REGSTR_PATH_CRITICALDEVICEDATABASE = 'System\CurrentControlSet\Control\CriticalDeviceDatabase';
  REGSTR_PATH_CLASS                  = 'System\CurrentControlSet\Services\Class';
  REGSTR_PATH_DISPLAYSETTINGS        = 'Display\Settings';
  REGSTR_PATH_FONTS                  = 'Display\Fonts';
  REGSTR_PATH_ENUM                   = 'Enum';
  REGSTR_PATH_ROOT                   = 'Enum\Root';

  REGSTR_PATH_CURRENTCONTROLSET = 'System\CurrentControlSet';
  REGSTR_PATH_SYSTEMENUM        = 'System\CurrentControlSet\Enum';
  REGSTR_PATH_HWPROFILES        = 'System\CurrentControlSet\Hardware Profiles';
  REGSTR_PATH_HWPROFILESCURRENT = 'System\CurrentControlSet\Hardware Profiles\Current';
  REGSTR_PATH_CLASS_NT          = 'System\CurrentControlSet\Control\Class';
  REGSTR_PATH_PER_HW_ID_STORAGE = 'Software\Microsoft\Windows NT\CurrentVersion\PerHwIdStorage';

  REGSTR_PATH_DEVICE_CLASSES = 'System\CurrentControlSet\Control\DeviceClasses';

  REGSTR_PATH_CODEVICEINSTALLERS = 'System\CurrentControlSet\Control\CoDeviceInstallers';
  REGSTR_PATH_BUSINFORMATION     = 'System\CurrentControlSet\Control\PnP\BusInformation';

  REGSTR_PATH_SERVICES  = 'System\CurrentControlSet\Services';
  REGSTR_PATH_VXD       = 'System\CurrentControlSet\Services\VxD';
  REGSTR_PATH_IOS       = 'System\CurrentControlSet\Services\VxD\IOS';
  REGSTR_PATH_VMM       = 'System\CurrentControlSet\Services\VxD\VMM';
  REGSTR_PATH_VPOWERD   = 'System\CurrentControlSet\Services\VxD\VPOWERD';
  REGSTR_PATH_VNETSUP   = 'System\CurrentControlSet\Services\VxD\VNETSUP';
  REGSTR_PATH_NWREDIR   = 'System\CurrentControlSet\Services\VxD\NWREDIR';
  REGSTR_PATH_NCPSERVER = 'System\CurrentControlSet\Services\NcpServer\Parameters';
  REGSTR_PATH_VCOMM     = 'System\CurrentControlSet\Services\VxD\VCOMM';

  REGSTR_PATH_IOARB   = 'System\CurrentControlSet\Services\Arbitrators\IOArb';
  REGSTR_PATH_ADDRARB = 'System\CurrentControlSet\Services\Arbitrators\AddrArb';
  REGSTR_PATH_DMAARB  = 'System\CurrentControlSet\Services\Arbitrators\DMAArb';
  REGSTR_PATH_IRQARB  = 'System\CurrentControlSet\Services\Arbitrators\IRQArb';

  REGSTR_PATH_CODEPAGE              = 'System\CurrentControlSet\Control\Nls\Codepage';
  REGSTR_PATH_FILESYSTEM            = 'System\CurrentControlSet\Control\FileSystem';
  REGSTR_PATH_FILESYSTEM_NOVOLTRACK = 'System\CurrentControlSet\Control\FileSystem\NoVolTrack';
  REGSTR_PATH_CDFS                  = 'System\CurrentControlSet\Control\FileSystem\CDFS';
  REGSTR_PATH_WINBOOT               = 'System\CurrentControlSet\Control\WinBoot';
  REGSTR_PATH_INSTALLEDFILES        = 'System\CurrentControlSet\Control\InstalledFiles';
  REGSTR_PATH_VMM32FILES            = 'System\CurrentControlSet\Control\VMM32Files';

//
// Reasonable Limit for Values Names
//

  REGSTR_MAX_VALUE_LENGTH = 256;

//
// Values used by user mode Pnp Manager
//

  REGSTR_KEY_DEVICE_PROPERTIES          = 'Properties';
  REGSTR_VAL_SLOTNUMBER                 = 'SlotNumber';
  REGSTR_VAL_ATTACHEDCOMPONENTS         = 'AttachedComponents';
  REGSTR_VAL_BASEDEVICEPATH             = 'BaseDevicePath';
  REGSTR_VAL_SYSTEMBUSNUMBER            = 'SystemBusNumber';
  REGSTR_VAL_BUSDATATYPE                = 'BusDataType';
  REGSTR_VAL_INTERFACETYPE              = 'InterfaceType';
  REGSTR_VAL_SERVICE                    = 'Service';
  REGSTR_VAL_DETECTSIGNATURE            = 'DetectSignature';
  REGSTR_VAL_CLASSGUID                  = 'ClassGUID';
  REGSTR_VAL_INSTANCEIDENTIFIER         = 'InstanceIdentifier';
  REGSTR_VAL_DUPLICATEOF                = 'DuplicateOf';
  REGSTR_VAL_STATUSFLAGS                = 'StatusFlags';
  REGSTR_VAL_DISABLECOUNT               = 'DisableCount';
  REGSTR_VAL_UNKNOWNPROBLEMS            = 'UnknownProblem';
  REGSTR_VAL_DOCKSTATE                  = 'DockState';
  REGSTR_VAL_PREFERENCEORDER            = 'PreferenceOrder';
  REGSTR_VAL_USERWAITINTERVAL           = 'UserWaitInterval';
  REGSTR_VAL_DEVICE_INSTANCE            = 'DeviceInstance';
  REGSTR_VAL_SYMBOLIC_LINK              = 'SymbolicLink';
  REGSTR_VAL_DEFAULT                    = 'Default';
  REGSTR_VAL_LOWERFILTERS               = 'LowerFilters';
  REGSTR_VAL_UPPERFILTERS               = 'UpperFilters';
  REGSTR_VAL_LOCATION_INFORMATION       = 'LocationInformation';
  REGSTR_VAL_UI_NUMBER                  = 'UINumber';
  REGSTR_VAL_UI_NUMBER_DESC_FORMAT      = 'UINumberDescFormat';
  REGSTR_VAL_CAPABILITIES               = 'Capabilities';
  REGSTR_VAL_DEVICE_TYPE                = 'DeviceType';
  REGSTR_VAL_DEVICE_CHARACTERISTICS     = 'DeviceCharacteristics';
  REGSTR_VAL_DEVICE_SECURITY_DESCRIPTOR = 'Security';
  REGSTR_VAL_DEVICE_EXCLUSIVE           = 'Exclusive';
  REGSTR_VAL_RESOURCE_PICKER_TAGS       = 'ResourcePickerTags';
  REGSTR_VAL_RESOURCE_PICKER_EXCEPTIONS = 'ResourcePickerExceptions';
  REGSTR_VAL_CUSTOM_PROPERTY_CACHE_DATE = 'CustomPropertyCacheDate';
  REGSTR_VAL_CUSTOM_PROPERTY_HW_ID_KEY  = 'CustomPropertyHwIdKey';
  REGSTR_VAL_LAST_UPDATE_TIME           = 'LastUpdateTime';

//
// Values used by kernel mode Pnp Manager
//

  REGSTR_VALUE_DEVICE_OBJECT_NAME   = 'DeviceObjectName';
  REGSTR_VALUE_DEVICE_SYMBOLIC_NAME = 'DeviceSymbolicName';
  REGSTR_VAL_EJECT_PRIORITY         = 'EjectPriority';

//
// Values used by both kernel-mode and user-mode PnP Managers
//

  REGSTR_KEY_CONTROL              = 'Control';
  REGSTR_VAL_ACTIVESERVICE        = 'ActiveService';
  REGSTR_VAL_LINKED               = 'Linked';
  REGSTR_VAL_PHYSICALDEVICEOBJECT = 'PhysicalDeviceObject';
  REGSTR_VAL_REMOVAL_POLICY       = 'RemovalPolicy';

//
// Values under REGSTR_PATH_NT_CURRENTVERSION
//

  REGSTR_VAL_CURRENT_VERSION    = 'CurrentVersion';
  REGSTR_VAL_CURRENT_BUILD      = 'CurrentBuildNumber';
  REGSTR_VAL_CURRENT_CSDVERSION = 'CSDVersion';
  REGSTR_VAL_CURRENT_TYPE       = 'CurrentType';

//
// Values under REGSTR_PATH_DISPLAYSETTINGS
//

  REGSTR_VAL_BITSPERPIXEL = 'BitsPerPixel';
  REGSTR_VAL_RESOLUTION   = 'Resolution';
  REGSTR_VAL_DPILOGICALX  = 'DPILogicalX';
  REGSTR_VAL_DPILOGICALY  = 'DPILogicalY';
  REGSTR_VAL_DPIPHYSICALX = 'DPIPhysicalX';
  REGSTR_VAL_DPIPHYSICALY = 'DPIPhysicalY';
  REGSTR_VAL_REFRESHRATE  = 'RefreshRate';
  REGSTR_VAL_DISPLAYFLAGS = 'DisplayFlags';

// under HKEY_CURRENT_USER

  REGSTR_PATH_CONTROLPANEL = 'Control Panel';

// under HKEY_LOCAL_MACHINE

  REGSTR_PATH_CONTROLSFOLDER = 'Software\Microsoft\Windows\CurrentVersion\Controls Folder';

//
// Entries under REGSTR_PATH_CODEPAGE
//

  REGSTR_VAL_DOSCP = 'OEMCP';
  REGSTR_VAL_WINCP = 'ACP';

  REGSTR_PATH_DYNA_ENUM = 'Config Manager\Enum';

//
// Entries under REGSTR_PATH_DYNA_ENUM
//

  REGSTR_VAL_HARDWARE_KEY = 'HardWareKey';
  REGSTR_VAL_ALLOCATION   = 'Allocation';
  REGSTR_VAL_PROBLEM      = 'Problem';
  REGSTR_VAL_STATUS       = 'Status';

//
//  Used by address arbitrator
//

  REGSTR_VAL_DONTUSEMEM = 'DontAllocLastMem';

//
//  Entries under REGSTR_PATH_SETUP
//

  REGSTR_VAL_SYSTEMROOT      = 'SystemRoot';
  REGSTR_VAL_BOOTCOUNT       = 'BootCount';
  REGSTR_VAL_REALNETSTART    = 'RealNetStart';
  REGSTR_VAL_MEDIA           = 'MediaPath';
  REGSTR_VAL_CONFIG          = 'ConfigPath';
  REGSTR_VAL_DEVICEPATH      = 'DevicePath'; // default search path for .INFs
  REGSTR_VAL_SRCPATH         = 'SourcePath'; // last source files path during setup.
  REGSTR_VAL_SVCPAKSRCPATH   = 'ServicePackSourcePath'; // last service pack source path
  REGSTR_VAL_DRIVERCACHEPATH = 'DriverCachePath'; // location of driver cache

  REGSTR_VAL_OLDWINDIR            = 'OldWinDir'; // old windows location
  REGSTR_VAL_SETUPFLAGS           = 'SetupFlags'; // flags that setup passes on after install.
  REGSTR_VAL_REGOWNER             = 'RegisteredOwner';
  REGSTR_VAL_REGORGANIZATION      = 'RegisteredOrganization';
  REGSTR_VAL_LICENSINGINFO        = 'LicensingInfo';
  REGSTR_VAL_OLDMSDOSVER          = 'OldMSDOSVer'; // will be DOS ver < 7 (when Setup run)
  REGSTR_VAL_FIRSTINSTALLDATETIME = 'FirstInstallDateTime'; // will Win 95 install date-time

  REGSTR_VAL_INSTALLTYPE = 'InstallType';

  //  Values for InstallType

  IT_COMPACT         = $0000;
  IT_TYPICAL         = $0001;
  IT_PORTABLE        = $0002;
  IT_CUSTOM          = $0003;

  REGSTR_VAL_WRAPPER = 'Wrapper';

  REGSTR_VAL_LASTALIVEINTERVAL = 'TimeStampInterval';
  REGSTR_VAL_LASTALIVESTAMP    = 'LastAliveStamp';
  REGSTR_VAL_LASTALIVEUPTIME   =  'LastAliveUptime';
  REGSTR_VAL_SHUTDOWNREASON    = 'ShutdownReason';
  REGSTR_VAL_SHUTDOWNREASON_CODE        = 'ShutdownReasonCode';
  REGSTR_VAL_SHUTDOWNREASON_COMMENT     = 'ShutdownReasonComment';
  REGSTR_VAL_SHUTDOWNREASON_PROCESS     = 'ShutdownReasonProcess';
  REGSTR_VAL_SHUTDOWNREASON_USERNAME    = 'ShutdownReasonUserName';
  REGSTR_VAL_SHOWREASONUI               = 'ShutdownReasonUI';
  REGSTR_VAL_SHUTDOWN_IGNORE_PREDEFINED = 'ShutdownIgnorePredefinedReasons';
  REGSTR_VAL_SHUTDOWN_STATE_SNAPSHOT = 'ShutdownStateSnapshot';

  REGSTR_KEY_SETUP      = '\Setup';
  REGSTR_VAL_BOOTDIR    = 'BootDir';
  REGSTR_VAL_WINBOOTDIR = 'WinbootDir';
  REGSTR_VAL_WINDIR     = 'WinDir';

  REGSTR_VAL_APPINSTPATH = 'AppInstallPath'; // Used by install wizard

// Values for international startup disk

  REGSTR_PATH_EBD = REGSTR_PATH_SETUP + REGSTR_KEY_SETUP + '\EBD';

// Keys under REGSTR_KEY_EBD

  REGSTR_KEY_EBDFILESLOCAL          = 'EBDFilesLocale';
  REGSTR_KEY_EBDFILESKEYBOARD       = 'EBDFilesKeyboard';
  REGSTR_KEY_EBDAUTOEXECBATLOCAL    = 'EBDAutoexecBatLocale';
  REGSTR_KEY_EBDAUTOEXECBATKEYBOARD = 'EBDAutoexecBatKeyboard';
  REGSTR_KEY_EBDCONFIGSYSLOCAL      = 'EBDConfigSysLocale';
  REGSTR_KEY_EBDCONFIGSYSKEYBOARD   = 'EBDConfigSysKeyboard';

// Values under REGSTR_PATH_DRIVERSIGN and REGSTR_PATH_NONDRIVERSIGN

  REGSTR_VAL_POLICY = 'Policy';

// Values under REGSTR_PATH_DRIVERSIGN_POLICY and REGSTR_PATH_NONDRIVERSIGN_POLICY

  REGSTR_VAL_BEHAVIOR_ON_FAILED_VERIFY = 'BehaviorOnFailedVerify';

// Types of driver signing policies (apply to both preference and policy values
// defined above)

  DRIVERSIGN_NONE     = $00000000;
  DRIVERSIGN_WARNING  = $00000001;
  DRIVERSIGN_BLOCKING = $00000002;

//
//  Entries under REGSTR_PATH_PIFCONVERT
//

  REGSTR_VAL_MSDOSMODE        = 'MSDOSMode';
  REGSTR_VAL_MSDOSMODEDISCARD = 'Discard';

//
//  Entries under REGSTR_PATH_MSDOSOPTS (global settings)
//

  REGSTR_VAL_DOSOPTGLOBALFLAGS = 'GlobalFlags';

//  Flags for GlobalFlags

  DOSOPTGF_DEFCLEAN = $00000001; // Default action is clean config

//
//  Entries under REGSTR_PATH_MSDOSOPTS \ OptionSubkey
//

  REGSTR_VAL_DOSOPTFLAGS  = 'Flags';
  REGSTR_VAL_OPTORDER     = 'Order';
  REGSTR_VAL_CONFIGSYS    = 'Config.Sys';
  REGSTR_VAL_AUTOEXEC     = 'Autoexec.Bat';
  REGSTR_VAL_STDDOSOPTION = 'StdOption';
  REGSTR_VAL_DOSOPTTIP    = 'TipText';

//  Flags for DOSOPTFLAGS

  DOSOPTF_DEFAULT     = $00000001; // Default enabled for clean config
  DOSOPTF_SUPPORTED   = $00000002; // Option actually supported
  DOSOPTF_ALWAYSUSE   = $00000004; // Always use this option
  DOSOPTF_USESPMODE   = $00000008; // Option puts machine in Prot Mode
  DOSOPTF_PROVIDESUMB = $00000010; // Can load drivers high
  DOSOPTF_NEEDSETUP   = $00000020; // Need to configure option
  DOSOPTF_INDOSSTART  = $00000040; // Supported by DOSSTART.BAT
  DOSOPTF_MULTIPLE    = $00000080; // Load multiple configuration lines

//
//  Flags returned by SUGetSetSetupFlags and in the registry
//

  SUF_FIRSTTIME  = $00000001; // First boot into Win95.
  SUF_EXPRESS    = $00000002; // User Setup via express mode (vs customize).
  SUF_BATCHINF   = $00000004; // Setup using batch file (MSBATCH.INF).
  SUF_CLEAN      = $00000008; // Setup was done to a clean directory.
  SUF_INSETUP    = $00000010; // You're in Setup.
  SUF_NETSETUP   = $00000020; // Doing a net (workstation) setup.
  SUF_NETHDBOOT  = $00000040; // Workstation boots from local harddrive
  SUF_NETRPLBOOT = $00000080; // Workstation boots via RPL (vs floppy)
  SUF_SBSCOPYOK  = $00000100; // Can copy to LDID_SHARED (SBS)

//
//  Entries under REGSTR_PATH_VMM
//

  REGSTR_VAL_DOSPAGER  = 'DOSPager';
  REGSTR_VAL_VXDGROUPS = 'VXDGroups';

//
//  Entries under REGSTR_PATH_VPOWERD
//

  REGSTR_VAL_VPOWERDFLAGS   = 'Flags';
  VPDF_DISABLEPWRMGMT       = $00000001; // Don't load device
  VPDF_FORCEAPM10MODE       = $00000002; // Always go into 1.0 mode
  VPDF_SKIPINTELSLCHECK     = $00000004; // Don't detect Intel SL chipset
  VPDF_DISABLEPWRSTATUSPOLL = $00000008; // Don't poll power status
  VPDF_DISABLERINGRESUME    = $00000010; // Don't let the modem wake the machine (APM 1.2 only)
  VPDF_SHOWMULTIBATT        = $00000020; // Show all batteries checkbox in power control panel

//
// Entries under REGSTR_PATH_BUSINFORMATION
//

  BIF_SHOWSIMILARDRIVERS     = $00000001;  // Show similar drivers instead of all class drivers in UI.
  BIF_RAWDEVICENEEDSDRIVER   = $00000002;  // RAW device needs a driver installed.

//
//  Entries under REGSTR_PATH_VNETSUP
//

  REGSTR_VAL_WORKGROUP    = 'Workgroup';
  REGSTR_VAL_DIRECTHOST   = 'DirectHost';
  REGSTR_VAL_FILESHARING  = 'FileSharing';
  REGSTR_VAL_PRINTSHARING = 'PrintSharing';

//
//  Entries under REGSTR_PATH_NWREDIR
//

  REGSTR_VAL_FIRSTNETDRIVE     = 'FirstNetworkDrive';
  REGSTR_VAL_MAXCONNECTIONS    = 'MaxConnections';
  REGSTR_VAL_APISUPPORT        = 'APISupport';
  REGSTR_VAL_MAXRETRY          = 'MaxRetry';
  REGSTR_VAL_MINRETRY          = 'MinRetry';
  REGSTR_VAL_SUPPORTLFN        = 'SupportLFN';
  REGSTR_VAL_SUPPORTBURST      = 'SupportBurst';
  REGSTR_VAL_SUPPORTTUNNELLING = 'SupportTunnelling';
  REGSTR_VAL_FULLTRACE         = 'FullTrace';
  REGSTR_VAL_READCACHING       = 'ReadCaching';
  REGSTR_VAL_SHOWDOTS          = 'ShowDots';
  REGSTR_VAL_GAPTIME           = 'GapTime';
  REGSTR_VAL_SEARCHMODE        = 'SearchMode';
  REGSTR_VAL_SHELLVERSION      = 'ShellVersion';
  REGSTR_VAL_MAXLIP            = 'MaxLIP';
  REGSTR_VAL_PRESERVECASE      = 'PreserveCase';
  REGSTR_VAL_OPTIMIZESFN       = 'OptimizeSFN';

//
//  Entries under REGSTR_PATH_NCPSERVER
//

  REGSTR_VAL_NCP_BROWSEMASTER    = 'BrowseMaster';
  REGSTR_VAL_NCP_USEPEERBROWSING = 'Use_PeerBrowsing';
  REGSTR_VAL_NCP_USESAP          = 'Use_Sap';

//
// Entries under REGSTR_PATH_VCOMM
//

  REGSTR_VAL_PCCARD_POWER = 'EnablePowerManagement';

//
//  Entries under REGSTR_PATH_FILESYSTEM
//

  REGSTR_VAL_WIN31FILESYSTEM      = 'Win31FileSystem';
  REGSTR_VAL_PRESERVELONGNAMES    = 'PreserveLongNames';
  REGSTR_VAL_DRIVEWRITEBEHIND     = 'DriveWriteBehind';
  REGSTR_VAL_ASYNCFILECOMMIT      = 'AsyncFileCommit';
  REGSTR_VAL_PATHCACHECOUNT       = 'PathCache';
  REGSTR_VAL_NAMECACHECOUNT       = 'NameCache';
  REGSTR_VAL_CONTIGFILEALLOC      = 'ContigFileAllocSize';
  REGSTR_VAL_FREESPACERATIO       = 'FreeSpaceRatio';
  REGSTR_VAL_VOLIDLETIMEOUT       = 'VolumeIdleTimeout';
  REGSTR_VAL_BUFFIDLETIMEOUT      = 'BufferIdleTimeout';
  REGSTR_VAL_BUFFAGETIMEOUT       = 'BufferAgeTimeout';
  REGSTR_VAL_NAMENUMERICTAIL      = 'NameNumericTail';
  REGSTR_VAL_READAHEADTHRESHOLD   = 'ReadAheadThreshold';
  REGSTR_VAL_DOUBLEBUFFER         = 'DoubleBuffer';
  REGSTR_VAL_SOFTCOMPATMODE       = 'SoftCompatMode';
  REGSTR_VAL_DRIVESPINDOWN        = 'DriveSpinDown';
  REGSTR_VAL_FORCEPMIO            = 'ForcePMIO';
  REGSTR_VAL_FORCERMIO            = 'ForceRMIO';
  REGSTR_VAL_LASTBOOTPMDRVS       = 'LastBootPMDrvs';
  REGSTR_VAL_ACSPINDOWNPREVIOUS   = 'ACSpinDownPrevious';
  REGSTR_VAL_BATSPINDOWNPREVIOUS  = 'BatSpinDownPrevious';
  REGSTR_VAL_VIRTUALHDIRQ         = 'VirtualHDIRQ';
  REGSTR_VAL_SRVNAMECACHECOUNT    = 'ServerNameCacheMax';
  REGSTR_VAL_SRVNAMECACHE         = 'ServerNameCache';
  REGSTR_VAL_SRVNAMECACHENETPROV  = 'ServerNameCacheNumNets';
  REGSTR_VAL_AUTOMOUNT            = 'AutoMountDrives';
  REGSTR_VAL_COMPRESSIONMETHOD    = 'CompressionAlgorithm';
  REGSTR_VAL_COMPRESSIONTHRESHOLD = 'CompressionThreshold';
  REGSTR_VAL_ACDRIVESPINDOWN      = 'ACDriveSpinDown';
  REGSTR_VAL_BATDRIVESPINDOWN     = 'BatDriveSpinDown';

//
//      Entries under REGSTR_PATH_FILESYSTEM_NOVOLTRACK
//
//      A sub-key under which a variable number of variable length structures are stored.
//
//      Each structure contains an offset followed by a number of pattern bytes.
//      The pattern in each structure is compared at the specified offset within
//      the boot record at the time a volume is mounted.  If any pattern in this
//      set of patterns matches a pattern already in the boot record, VFAT will not
//      write a volume tracking serial number in the OEM_SerialNum field of the
//      boot record on the volume being mounted.
//

//
//  Entries under REGSTR_PATH_CDFS
//

  REGSTR_VAL_CDCACHESIZE    = 'CacheSize'; // Number of 2K cache sectors
  REGSTR_VAL_CDPREFETCH     = 'Prefetch'; // Number of 2K cache sectors for prefetching
  REGSTR_VAL_CDPREFETCHTAIL = 'PrefetchTail'; // Number of LRU1 prefetch sectors
  REGSTR_VAL_CDRAWCACHE     = 'RawCache'; // Number of 2352-byte cache sectors
  REGSTR_VAL_CDEXTERRORS    = 'ExtendedErrors'; // Return extended error codes
  REGSTR_VAL_CDSVDSENSE     = 'SVDSense'; // 0=PVD, 1=Kanji, 2=Unicode
  REGSTR_VAL_CDSHOWVERSIONS = 'ShowVersions'; // Show file version numbers
  REGSTR_VAL_CDCOMPATNAMES  = 'MSCDEXCompatNames'; // Disable Numeric Tails on long file names
  REGSTR_VAL_CDNOREADAHEAD  = 'NoReadAhead'; // Disable Read Ahead if set to 1

//
//      define values for IOS devices
//

  REGSTR_VAL_SCSI = 'SCSI\';
  REGSTR_VAL_ESDI = 'ESDI\';
  REGSTR_VAL_FLOP = 'FLOP\';

//
// define defs for IOS device types and values for IOS devices
//

  REGSTR_VAL_DISK    = 'GenDisk';
  REGSTR_VAL_CDROM   = 'GenCD';
  REGSTR_VAL_TAPE    = 'TAPE';
  REGSTR_VAL_SCANNER = 'SCANNER';
  REGSTR_VAL_FLOPPY  = 'FLOPPY';

  REGSTR_VAL_SCSITID      = 'SCSITargetID';
  REGSTR_VAL_SCSILUN      = 'SCSILUN';
  REGSTR_VAL_REVLEVEL     = 'RevisionLevel';
  REGSTR_VAL_PRODUCTID    = 'ProductId';
  REGSTR_VAL_PRODUCTTYPE  = 'ProductType';
  REGSTR_VAL_DEVTYPE      = 'DeviceType';
  REGSTR_VAL_REMOVABLE    = 'Removable';
  REGSTR_VAL_CURDRVLET    = 'CurrentDriveLetterAssignment';
  REGSTR_VAL_USRDRVLET    = 'UserDriveLetterAssignment';
  REGSTR_VAL_SYNCDATAXFER = 'SyncDataXfer';
  REGSTR_VAL_AUTOINSNOTE  = 'AutoInsertNotification';
  REGSTR_VAL_DISCONNECT   = 'Disconnect';
  REGSTR_VAL_INT13        = 'Int13';
  REGSTR_VAL_PMODE_INT13  = 'PModeInt13';
  REGSTR_VAL_USERSETTINGS = 'AdapterSettings';
  REGSTR_VAL_NOIDE        = 'NoIDE';

// The foll. class name definitions should be the same as in dirkdrv.inx and
// cdrom.inx

  REGSTR_VAL_DISKCLASSNAME  = 'DiskDrive';
  REGSTR_VAL_CDROMCLASSNAME = 'CDROM';

// The foll. value determines whether a port driver should be force loaded
// or not.

  REGSTR_VAL_FORCELOAD = 'ForceLoadPD';

// The foll. value determines whether or not the FIFO is used on the Floppy
// controller.

  REGSTR_VAL_FORCEFIFO = 'ForceFIFO';
  REGSTR_VAL_FORCECL   = 'ForceChangeLine';

//
// Generic CLASS Entries
//

  REGSTR_VAL_NOUSECLASS     = 'NoUseClass'; // Don't include this class in PnP functions
  REGSTR_VAL_NOINSTALLCLASS = 'NoInstallClass'; // Don't include this class in New Device Wizard
  REGSTR_VAL_NODISPLAYCLASS = 'NoDisplayClass'; // Don't include this class in Device Manager
  REGSTR_VAL_SILENTINSTALL  = 'SilentInstall'; // Always Silent Install devices of this class.

//
//  Class Names
//

  REGSTR_KEY_PCMCIA_CLASS   = 'PCMCIA'; // child of PATH_CLASS
  REGSTR_KEY_SCSI_CLASS     = 'SCSIAdapter';
  REGSTR_KEY_PORTS_CLASS    = 'ports';
  REGSTR_KEY_MEDIA_CLASS    = 'MEDIA';
  REGSTR_KEY_DISPLAY_CLASS  = 'Display';
  REGSTR_KEY_KEYBOARD_CLASS = 'Keyboard';
  REGSTR_KEY_MOUSE_CLASS    = 'Mouse';
  REGSTR_KEY_MONITOR_CLASS  = 'Monitor';
  REGSTR_KEY_MODEM_CLASS    = 'Modem';

//
//  Values under PATH_CLASS\PCMCIA
//

  REGSTR_VAL_PCMCIA_OPT   = 'Options';
  PCMCIA_OPT_HAVE_SOCKET  = $00000001;
  //PCMCIA_OPT_ENABLED      = $00000002;
  //{$EXTERNALSYM PCMCIA_OPT_ENABLED}
  PCMCIA_OPT_AUTOMEM      = $00000004;
  PCMCIA_OPT_NO_SOUND     = $00000008;
  PCMCIA_OPT_NO_AUDIO     = $00000010;
  PCMCIA_OPT_NO_APMREMOVE = $00000020;

  REGSTR_VAL_PCMCIA_MEM = 'Memory'; // Card services shared mem range
  PCMCIA_DEF_MEMBEGIN   = $000C0000; // default 0xC0000 - 0x00FFFFFF
  PCMCIA_DEF_MEMEND     = $00FFFFFF; // (0 - 16meg)
  PCMCIA_DEF_MEMLEN     = $00001000; // default 4k window

  REGSTR_VAL_PCMCIA_ALLOC = 'AllocMemWin'; // PCCard alloced memory Window
  REGSTR_VAL_PCMCIA_ATAD  = 'ATADelay'; // ATA device config start delay

  REGSTR_VAL_PCMCIA_SIZ = 'MinRegionSize'; // Minimum region size
  PCMCIA_DEF_MIN_REGION = $00010000; // 64K minimum region size

// Values in LPTENUM keys

  REGSTR_VAL_P1284MDL = 'Model';
  REGSTR_VAL_P1284MFG = 'Manufacturer';

//
//  Values under PATH_CLASS\ISAPNP
//

  REGSTR_VAL_ISAPNP              = 'ISAPNP'; // ISAPNP VxD name
  REGSTR_VAL_ISAPNP_RDP_OVERRIDE = 'RDPOverRide'; // ReadDataPort OverRide

//
//  Values under PATH_CLASS\PCI
//

  REGSTR_VAL_PCI               = 'PCI'; // PCI VxD name
  REGSTR_PCI_OPTIONS           = 'Options'; // Possible PCI options
  REGSTR_PCI_DUAL_IDE          = 'PCIDualIDE'; // Dual IDE flag
  PCI_OPTIONS_USE_BIOS         = $00000001;
  PCI_OPTIONS_USE_IRQ_STEERING = $00000002;

//
//  Values under PATH_CLASS\AGPxxxx
//
//  note:  These flags affect standard AGP capabilities,
//         and are set in agplib
//

  AGP_FLAG_NO_1X_RATE             = $00000001;
  AGP_FLAG_NO_2X_RATE             = $00000002;
  AGP_FLAG_NO_4X_RATE             = $00000004;
  AGP_FLAG_NO_8X_RATE             = $00000008;
  AGP_FLAG_REVERSE_INITIALIZATION = $00000080;

  AGP_FLAG_NO_SBA_ENABLE          = $00000100;

//
// AGP flags > AGP_SPECIAL_TARGET are platform specific
//

  AGP_FLAG_SPECIAL_TARGET         = $000FFFFF;
  AGP_FLAG_SPECIAL_RESERVE        = $000F0000;

//
// Detection related values
//

  REGSTR_KEY_CRASHES             = 'Crashes'; // key of REGSTR_PATH_DETECT
  REGSTR_KEY_DANGERS             = 'Dangers'; // key of REGSTR_PATH_DETECT
  REGSTR_KEY_DETMODVARS          = 'DetModVars'; // key of REGSTR_PATH_DETECT
  REGSTR_KEY_NDISINFO            = 'NDISInfo'; // key of netcard hw entry
  REGSTR_VAL_PROTINIPATH         = 'ProtIniPath'; // protocol.ini path
  REGSTR_VAL_RESOURCES           = 'Resources'; // resources of crash func.
  REGSTR_VAL_CRASHFUNCS          = 'CrashFuncs'; // detfunc caused the crash
  REGSTR_VAL_CLASS               = 'Class'; // device class
  REGSTR_VAL_DEVDESC             = 'DeviceDesc'; // device description
  REGSTR_VAL_BOOTCONFIG          = 'BootConfig'; // detected configuration
  REGSTR_VAL_DETFUNC             = 'DetFunc'; // specifies detect mod/func.
  REGSTR_VAL_DETFLAGS            = 'DetFlags'; // detection flags
  REGSTR_VAL_COMPATIBLEIDS       = 'CompatibleIDs'; // value of enum\dev\inst
  REGSTR_VAL_DETCONFIG           = 'DetConfig'; // detected configuration
  REGSTR_VAL_VERIFYKEY           = 'VerifyKey'; // key used in verify mode
  REGSTR_VAL_COMINFO             = 'ComInfo'; // com info. for serial mouse
  REGSTR_VAL_INFNAME             = 'InfName'; // INF filename
  REGSTR_VAL_CARDSPECIFIC        = 'CardSpecific'; // Netcard specific info (WORD)
  REGSTR_VAL_NETOSTYPE           = 'NetOSType'; // NetOS type associate w/ card
  REGSTR_DATA_NETOS_NDIS         = 'NDIS'; // Data of REGSTR_VAL_NETOSTYPE
  REGSTR_DATA_NETOS_ODI          = 'ODI'; // Data of REGSTR_VAL_NETOSTYPE
  REGSTR_DATA_NETOS_IPX          = 'IPX'; // Data of REGSTR_VAL_NETOSTYPE
  REGSTR_VAL_MFG                 = 'Mfg';
  REGSTR_VAL_SCAN_ONLY_FIRST     = 'ScanOnlyFirstDrive'; // used with IDE driver
  REGSTR_VAL_SHARE_IRQ           = 'ForceIRQSharing'; // used with IDE driver
  REGSTR_VAL_NONSTANDARD_ATAPI   = 'NonStandardATAPI'; // used with IDE driver
  REGSTR_VAL_IDE_FORCE_SERIALIZE = 'ForceSerialization'; // used with IDE driver
  REGSTR_VAL_MAX_HCID_LEN        = 1024; // Maximum hardware/compat ID len
  REGSTR_VAL_HWREV               = 'HWRevision';
  REGSTR_VAL_ENABLEINTS          = 'EnableInts';

//
// Bit values of REGSTR_VAL_DETFLAGS
//

  REGDF_NOTDETIO        = $00000001; // cannot detect I/O resource
  REGDF_NOTDETMEM       = $00000002; // cannot detect mem resource
  REGDF_NOTDETIRQ       = $00000004; // cannot detect IRQ resource
  REGDF_NOTDETDMA       = $00000008; // cannot detect DMA resource
  REGDF_NOTDETALL       = REGDF_NOTDETIO or REGDF_NOTDETMEM or REGDF_NOTDETIRQ or REGDF_NOTDETDMA;
  REGDF_NEEDFULLCONFIG  = $00000010; // stop devnode if lack resource
  REGDF_GENFORCEDCONFIG = $00000020; // also generate forceconfig
  REGDF_NODETCONFIG     = $00008000; // don't write detconfig to reg.
  REGDF_CONFLICTIO      = $00010000; // I/O res. in conflict
  REGDF_CONFLICTMEM     = $00020000; // mem res. in conflict
  REGDF_CONFLICTIRQ     = $00040000; // IRQ res. in conflict
  REGDF_CONFLICTDMA     = $00080000; // DMA res. in conflict
  REGDF_CONFLICTALL     = REGDF_CONFLICTIO or REGDF_CONFLICTMEM or REGDF_CONFLICTIRQ or REGDF_CONFLICTDMA;
  REGDF_MAPIRQ2TO9      = $00100000; // IRQ2 has been mapped to 9
  REGDF_NOTVERIFIED     = DWORD($80000000); // previous device unverified

//
//  Values in REGSTR_KEY_SYSTEMBOARD
//

  REGSTR_VAL_APMBIOSVER         = 'APMBiosVer';
  REGSTR_VAL_APMFLAGS           = 'APMFlags';
  REGSTR_VAL_SLSUPPORT          = 'SLSupport';
  REGSTR_VAL_MACHINETYPE        = 'MachineType';
  REGSTR_VAL_SETUPMACHINETYPE   = 'SetupMachineType';
  REGSTR_MACHTYPE_UNKNOWN       = 'Unknown';
  REGSTR_MACHTYPE_IBMPC         = 'IBM PC';
  REGSTR_MACHTYPE_IBMPCJR       = 'IBM PCjr';
  REGSTR_MACHTYPE_IBMPCCONV     = 'IBM PC Convertible';
  REGSTR_MACHTYPE_IBMPCXT       = 'IBM PC/XT';
  REGSTR_MACHTYPE_IBMPCXT_286   = 'IBM PC/XT 286';
  REGSTR_MACHTYPE_IBMPCAT       = 'IBM PC/AT';
  REGSTR_MACHTYPE_IBMPS2_25     = 'IBM PS/2-25';
  REGSTR_MACHTYPE_IBMPS2_30_286 = 'IBM PS/2-30 286';
  REGSTR_MACHTYPE_IBMPS2_30     = 'IBM PS/2-30';
  REGSTR_MACHTYPE_IBMPS2_50     = 'IBM PS/2-50';
  REGSTR_MACHTYPE_IBMPS2_50Z    = 'IBM PS/2-50Z';
  REGSTR_MACHTYPE_IBMPS2_55SX   = 'IBM PS/2-55SX';
  REGSTR_MACHTYPE_IBMPS2_60     = 'IBM PS/2-60';
  REGSTR_MACHTYPE_IBMPS2_65SX   = 'IBM PS/2-65SX';
  REGSTR_MACHTYPE_IBMPS2_70     = 'IBM PS/2-70';
  REGSTR_MACHTYPE_IBMPS2_P70    = 'IBM PS/2-P70';
  REGSTR_MACHTYPE_IBMPS2_70_80  = 'IBM PS/2-70/80';
  REGSTR_MACHTYPE_IBMPS2_80     = 'IBM PS/2-80';
  REGSTR_MACHTYPE_IBMPS2_90     = 'IBM PS/2-90';
  REGSTR_MACHTYPE_IBMPS1        = 'IBM PS/1';
  REGSTR_MACHTYPE_PHOENIX_PCAT  = 'Phoenix PC/AT Compatible';
  REGSTR_MACHTYPE_HP_VECTRA     = 'HP Vectra';
  REGSTR_MACHTYPE_ATT_PC        = 'ATandT PC';
  REGSTR_MACHTYPE_ZENITH_PC     = 'Zenith PC';

  REGSTR_VAL_APMMENUSUSPEND = 'APMMenuSuspend';
  APMMENUSUSPEND_DISABLED   = 0; // always disabled
  APMMENUSUSPEND_ENABLED    = 1; // always enabled
  APMMENUSUSPEND_UNDOCKED   = 2; // enabled undocked
  APMMENUSUSPEND_NOCHANGE   = $80; // bitflag - cannot change setting via UI

  REGSTR_VAL_APMACTIMEOUT  = 'APMACTimeout';
  REGSTR_VAL_APMBATTIMEOUT = 'APMBatTimeout';
  APMTIMEOUT_DISABLED      = 0;

  REGSTR_VAL_APMSHUTDOWNPOWER = 'APMShutDownPower';

  REGSTR_VAL_BUSTYPE        = 'BusType';
  REGSTR_VAL_CPU            = 'CPU';
  REGSTR_VAL_NDP            = 'NDP';
  REGSTR_VAL_PNPBIOSVER     = 'PnPBIOSVer';
  REGSTR_VAL_PNPSTRUCOFFSET = 'PnPStrucOffset';
  REGSTR_VAL_PCIBIOSVER     = 'PCIBIOSVer';
  REGSTR_VAL_HWMECHANISM    = 'HWMechanism';
  REGSTR_VAL_LASTPCIBUSNUM  = 'LastPCIBusNum';
  REGSTR_VAL_CONVMEM        = 'ConvMem';
  REGSTR_VAL_EXTMEM         = 'ExtMem';
  REGSTR_VAL_COMPUTERNAME   = 'ComputerName';
  REGSTR_VAL_BIOSNAME       = 'BIOSName';
  REGSTR_VAL_BIOSVERSION    = 'BIOSVersion';
  REGSTR_VAL_BIOSDATE       = 'BIOSDate';
  REGSTR_VAL_MODEL          = 'Model';
  REGSTR_VAL_SUBMODEL       = 'Submodel';
  REGSTR_VAL_REVISION       = 'Revision';

//
//  Values used in the LPT(ECP) device entry
//

  REGSTR_VAL_FIFODEPTH      = 'FIFODepth';
  REGSTR_VAL_RDINTTHRESHOLD = 'RDIntThreshold';
  REGSTR_VAL_WRINTTHRESHOLD = 'WRIntThreshold';

//used in enum\xxx\<devname>\<instname>

  REGSTR_VAL_PRIORITY      = 'Priority';
  REGSTR_VAL_DRIVER        = 'Driver';
  REGSTR_VAL_FUNCDESC      = 'FunctionDesc';
  REGSTR_VAL_FORCEDCONFIG  = 'ForcedConfig';
  REGSTR_VAL_CONFIGFLAGS   = 'ConfigFlags'; // (binary ULONG)
  REGSTR_VAL_CSCONFIGFLAGS = 'CSConfigFlags'; // (binary ULONG)

  CONFIGFLAG_DISABLED            = $00000001; // Set if disabled
  CONFIGFLAG_REMOVED             = $00000002; // Set if a present hardware enum device deleted
  CONFIGFLAG_MANUAL_INSTALL      = $00000004; // Set if the devnode was manually installed
  CONFIGFLAG_IGNORE_BOOT_LC      = $00000008; // Set if skip the boot config
  CONFIGFLAG_NET_BOOT            = $00000010; // Load this devnode when in net boot
  CONFIGFLAG_REINSTALL           = $00000020; // Redo install
  CONFIGFLAG_FAILEDINSTALL       = $00000040; // Failed the install
  CONFIGFLAG_CANTSTOPACHILD      = $00000080; // Can't stop/remove a single child
  CONFIGFLAG_OKREMOVEROM         = $00000100; // Can remove even if rom.
  CONFIGFLAG_NOREMOVEEXIT        = $00000200; // Don't remove at exit.
  CONFIGFLAG_FINISH_INSTALL      = $00000400; // Complete install for devnode running 'raw'
  CONFIGFLAG_NEEDS_FORCED_CONFIG = $00000800; // This devnode requires a forced config
  CONFIGFLAG_NETBOOT_CARD = $00001000; // This is the remote boot network card
  CONFIGFLAG_PARTIAL_LOG_CONF    = $00002000; // This device has a partial logconfig
  CONFIGFLAG_SUPPRESS_SURPRISE   = $00004000; // Set if unsafe removals should be ignored
  CONFIGFLAG_VERIFY_HARDWARE     = $00008000; // Set if hardware should be tested for logo failures

  CSCONFIGFLAG_BITS          = $00000007; // OR of below bits
  CSCONFIGFLAG_DISABLED      = $00000001; // Set if
  CSCONFIGFLAG_DO_NOT_CREATE = $00000002; // Set if
  CSCONFIGFLAG_DO_NOT_START  = $00000004; // Set if

  DMSTATEFLAG_APPLYTOALL = $00000001; // Set if Apply To All check box is checked

//
// Special devnodes name
//

  REGSTR_VAL_ROOT_DEVNODE     = 'HTREE\ROOT\0';
  REGSTR_VAL_RESERVED_DEVNODE = 'HTREE\RESERVED\0';
  REGSTR_PATH_READDATAPORT    = REGSTR_KEY_ISAENUM + '\ReadDataPort\0';

//
// Multifunction definitions
//
  REGSTR_PATH_MULTI_FUNCTION           = 'MF';
  REGSTR_VAL_RESOURCE_MAP              = 'ResourceMap';
  REGSTR_PATH_CHILD_PREFIX             = 'Child';
  NUM_RESOURCE_MAP                     = 256;
  REGSTR_VAL_MF_FLAGS                  = 'MFFlags';
  MF_FLAGS_EVEN_IF_NO_RESOURCE         = $00000001;
  MF_FLAGS_NO_CREATE_IF_NO_RESOURCE    = $00000002;
  MF_FLAGS_FILL_IN_UNKNOWN_RESOURCE    = $00000004;
  MF_FLAGS_CREATE_BUT_NO_SHOW_DISABLED = $00000008;

//
// EISA multi functions add-on
//

  REGSTR_VAL_EISA_RANGES         = 'EISARanges';
  REGSTR_VAL_EISA_FUNCTIONS      = 'EISAFunctions';
  REGSTR_VAL_EISA_FUNCTIONS_MASK = 'EISAFunctionsMask';
  REGSTR_VAL_EISA_FLAGS          = 'EISAFlags';
  REGSTR_VAL_EISA_SIMULATE_INT15 = 'EISASimulateInt15';
  EISAFLAG_NO_IO_MERGE   = $00000001;
  EISAFLAG_SLOT_IO_FIRST = $00000002;
  EISA_NO_MAX_FUNCTION   = $FF;
  NUM_EISA_RANGES        = 4;

//
//  Driver entries
//

  REGSTR_VAL_DRVDESC            = 'DriverDesc'; // value of enum\dev\inst\DRV
  REGSTR_VAL_DEVLOADER          = 'DevLoader'; // value of DRV
  REGSTR_VAL_STATICVXD          = 'StaticVxD'; // value of DRV
  REGSTR_VAL_PROPERTIES         = 'Properties'; // value of DRV
  REGSTR_VAL_MANUFACTURER       = 'Manufacturer';
  REGSTR_VAL_EXISTS             = 'Exists'; // value of HCC\HW\ENUM\ROOT\dev\inst
  REGSTR_VAL_CMENUMFLAGS        = 'CMEnumFlags'; // (binary ULONG)
  REGSTR_VAL_CMDRIVFLAGS        = 'CMDrivFlags'; // (binary ULONG)
  REGSTR_VAL_ENUMERATOR         = 'Enumerator'; // value of DRV
  REGSTR_VAL_DEVICEDRIVER       = 'DeviceDriver'; // value of DRV
  REGSTR_VAL_PORTNAME           = 'PortName'; // VCOMM uses this for it's port names
  REGSTR_VAL_INFPATH            = 'InfPath';
  REGSTR_VAL_INFSECTION         = 'InfSection';
  REGSTR_VAL_INFSECTIONEXT      = 'InfSectionExt';
  REGSTR_VAL_POLLING            = 'Polling'; // SCSI specific
  REGSTR_VAL_DONTLOADIFCONFLICT = 'DontLoadIfConflict'; // SCSI specific
  REGSTR_VAL_PORTSUBCLASS       = 'PortSubClass';
  REGSTR_VAL_NETCLEAN           = 'NetClean'; // Driver required for NetClean boot
  REGSTR_VAL_IDE_NO_SERIALIZE   = 'IDENoSerialize'; // IDE specific
  REGSTR_VAL_NOCMOSORFDPT       = 'NoCMOSorFDPT'; // IDE specific
  REGSTR_VAL_COMVERIFYBASE      = 'COMVerifyBase'; // VCD specific
  REGSTR_VAL_MATCHINGDEVID      = 'MatchingDeviceId';
  REGSTR_VAL_DRIVERDATE         = 'DriverDate'; // value of DRV
  REGSTR_VAL_DRIVERDATEDATA     = 'DriverDateData'; // value of DRV
  REGSTR_VAL_DRIVERVERSION      = 'DriverVersion'; // value of DRV
  REGSTR_VAL_LOCATION_INFORMATION_OVERRIDE = 'LocationInformationOverride';  // value of DRV

//
//  Driver keys
//

  REGSTR_KEY_OVERRIDE = 'Override'; // key under the software section

//used by CONFIGMG

  REGSTR_VAL_CONFIGMG          = 'CONFIGMG'; // Config Manager VxD name
  REGSTR_VAL_SYSDM             = 'SysDM'; // The device installer DLL
  REGSTR_VAL_SYSDMFUNC         = 'SysDMFunc'; // The device installer DLL function
  REGSTR_VAL_PRIVATE           = 'Private'; // The private library
  REGSTR_VAL_PRIVATEFUNC       = 'PrivateFunc'; // The private library function
  REGSTR_VAL_DETECT            = 'Detect'; // The detection library
  REGSTR_VAL_DETECTFUNC        = 'DetectFunc'; // The detection library function
  REGSTR_VAL_ASKFORCONFIG      = 'AskForConfig'; // The AskForConfig library
  REGSTR_VAL_ASKFORCONFIGFUNC  = 'AskForConfigFunc'; // The AskForConfig library function
  REGSTR_VAL_WAITFORUNDOCK     = 'WaitForUndock'; // The WaitForUndock library
  REGSTR_VAL_WAITFORUNDOCKFUNC = 'WaitForUndockFunc'; // The WaitForUndock library function
  REGSTR_VAL_REMOVEROMOKAY     = 'RemoveRomOkay'; // The RemoveRomOkay library
  REGSTR_VAL_REMOVEROMOKAYFUNC = 'RemoveRomOkayFunc'; // The RemoveRomOkay library function

//used in IDCONFIGDB

  REGSTR_VAL_CURCONFIG      = 'CurrentConfig'; // value of idconfigdb
  REGSTR_VAL_FRIENDLYNAME   = 'FriendlyName'; // value of idconfigdb
  REGSTR_VAL_CURRENTCONFIG  = 'CurrentConfig'; // value of idconfigdb
  REGSTR_VAL_MAP            = 'Map'; // value of idconfigdb
  REGSTR_VAL_ID             = 'CurrentID'; // value of idconfigdb
  REGSTR_VAL_DOCKED         = 'CurrentDockedState'; // value of idconfigdb
  REGSTR_VAL_CHECKSUM       = 'CurrentChecksum'; // value of idconfigdb
  REGSTR_VAL_HWDETECT       = 'HardwareDetect'; // value of idconfigdb
  REGSTR_VAL_INHIBITRESULTS = 'InhibitResults'; // value of idconfigdb

//used in HKEY_CURRENT_CONFIG

  REGSTR_VAL_PROFILEFLAGS = 'ProfileFlags'; // value of HKEY_CURRENT_CONFIG

//used in PCMCIA

  REGSTR_KEY_PCMCIA     = 'PCMCIA\'; // PCMCIA dev ID prefix
  REGSTR_KEY_PCUNKNOWN  = 'UNKNOWN_MANUFACTURER'; // PCMCIA dev ID manuf
  REGSTR_VAL_PCSSDRIVER = 'Driver'; // value of DRV
  REGSTR_KEY_PCMTD      = 'MTD-'; // MTD dev ID component
  REGSTR_VAL_PCMTDRIVER = 'MTD'; // value of Mem Tech DRV

//used in hardware\enum\dev\inst by Device Installer

  REGSTR_VAL_HARDWAREID = 'HardwareID'; // value of enum\dev\inst

//value names under class brach REGSTR_KEY_CLASS + class name
// and for the drivers REGSTR_KEY_CLASS\classname\xxxx

  REGSTR_VAL_INSTALLER          = 'Installer'; // 16-bit class installer module/entry point
  REGSTR_VAL_INSTALLER_32       = 'Installer32'; // 32-bit class installer module/entry point
  REGSTR_VAL_INSICON            = 'Icon'; // value of class\name
  REGSTR_VAL_ENUMPROPPAGES      = 'EnumPropPages'; // For Class/Device Properties (16-bit)
  REGSTR_VAL_ENUMPROPPAGES_32   = 'EnumPropPages32'; // For Class/Device Properties (32-bit)
  REGSTR_VAL_BASICPROPERTIES    = 'BasicProperties'; // For CPL basic Properties (16-bit)
  REGSTR_VAL_BASICPROPERTIES_32 = 'BasicProperties32'; // For CPL basic Properties (32-bit)
  REGSTR_VAL_COINSTALLERS_32    = 'CoInstallers32'; // Device-specific co-installer multi-sz list (32-bit)
  REGSTR_VAL_PRIVATEPROBLEM     = 'PrivateProblem'; // For Handling Private Problems

// names used for display driver set information

  REGSTR_KEY_CURRENT = 'Current'; // current mode information
  REGSTR_KEY_DEFAULT = 'Default'; // default configuration
  REGSTR_KEY_MODES   = 'Modes'; // modes subtree

  REGSTR_VAL_MODE        = 'Mode'; // default mode
  REGSTR_VAL_BPP         = 'BPP'; // bits per pixel
  REGSTR_VAL_HRES        = 'HRes'; // horizontal resolution
  REGSTR_VAL_VRES        = 'VRes'; // vertical resolution
  REGSTR_VAL_FONTSIZE    = 'FontSize'; // used in default or override
  REGSTR_VAL_DRV         = 'drv'; // the driver file
  REGSTR_VAL_GRB         = 'grb'; // the grabber file
  REGSTR_VAL_VDD         = 'vdd'; // vdds used here
  REGSTR_VAL_VER         = 'Ver';
  REGSTR_VAL_MAXRES      = 'MaxResolution'; // max res for monitors
  REGSTR_VAL_DPMS        = 'DPMS'; // DPMS enabled
  REGSTR_VAL_RESUMERESET = 'ResumeReset'; // need reset on resume

  REGSTR_VAL_DESCRIPTION = 'Description';

// keys in fontsize tree

  REGSTR_KEY_SYSTEM = 'System'; // entries for system.ini
  REGSTR_KEY_USER   = 'User'; // entries for win.ini
  REGSTR_VAL_DPI    = 'dpi'; // dpi of fontsize

//
// Used by PCIC socket services
//

  REGSTR_VAL_PCICOPTIONS = 'PCICOptions'; // Binary DWORD.  IRQ mask in
                                                // low word.  # skts in high
  PCIC_DEFAULT_IRQMASK = $4EB8; // Default IRQ masks
  PCIC_DEFAULT_NUMSOCKETS = 0; // 0 = Automatic detection
  REGSTR_VAL_PCICIRQMAP   = 'PCICIRQMap'; // Binary 16 byte IRQ map table

// names used for control panel entries

  REGSTR_PATH_APPEARANCE  = 'Control Panel\Appearance';
  REGSTR_PATH_LOOKSCHEMES = 'Control Panel\Appearance\Schemes';
  REGSTR_VAL_CUSTOMCOLORS = 'CustomColors';

  REGSTR_PATH_SCREENSAVE      = 'Control Panel\Desktop';
  REGSTR_VALUE_USESCRPASSWORD = 'ScreenSaveUsePassword';
  REGSTR_VALUE_SCRPASSWORD    = 'ScreenSave_Data';

  REGSTR_VALUE_LOWPOWERTIMEOUT = 'ScreenSaveLowPowerTimeout';
  REGSTR_VALUE_POWEROFFTIMEOUT = 'ScreenSavePowerOffTimeout';
  REGSTR_VALUE_LOWPOWERACTIVE  = 'ScreenSaveLowPowerActive';
  REGSTR_VALUE_POWEROFFACTIVE  = 'ScreenSavePowerOffActive';

// used for Windows applets

  REGSTR_PATH_WINDOWSAPPLETS = 'Software\Microsoft\Windows\CurrentVersion\Applets';

//
// system tray.  Flag values defined in systrap.h
//

  REGSTR_PATH_SYSTRAY           = 'Software\Microsoft\Windows\CurrentVersion\Applets\SysTray';
  REGSTR_VAL_SYSTRAYSVCS        = 'Services';
  REGSTR_VAL_SYSTRAYBATFLAGS    = 'PowerFlags';
  REGSTR_VAL_SYSTRAYPCCARDFLAGS = 'PCMCIAFlags';

//
// Used by system networking components to store per-user values.
// All keys here are under HKCU.
//

  REGSTR_PATH_NETWORK_USERSETTINGS = 'Network';

  REGSTR_KEY_NETWORK_PERSISTENT = '\Persistent';
  REGSTR_KEY_NETWORK_RECENT     = '\Recent';
  REGSTR_VAL_REMOTE_PATH        = 'RemotePath';
  REGSTR_VAL_USER_NAME          = 'UserName';
  REGSTR_VAL_PROVIDER_NAME      = 'ProviderName';
  REGSTR_VAL_CONNECTION_TYPE    = 'ConnectionType';
  REGSTR_VAL_UPGRADE            = 'Upgrade';

  REGSTR_KEY_LOGON           = '\Logon';
  REGSTR_VAL_MUSTBEVALIDATED = 'MustBeValidated';
  REGSTR_VAL_RUNLOGINSCRIPT  = 'ProcessLoginScript';

//
// NetworkProvider entries. These entries are under
// REGSTR_PATH_SERVICES\xxx\NetworkProvider
//

  REGSTR_KEY_NETWORKPROVIDER  = '\NetworkProvider';
  REGSTR_PATH_NW32NETPROVIDER = REGSTR_PATH_SERVICES + '\NWNP32' + REGSTR_KEY_NETWORKPROVIDER;
  REGSTR_PATH_MS32NETPROVIDER = REGSTR_PATH_SERVICES + '\MSNP32' + REGSTR_KEY_NETWORKPROVIDER;
  REGSTR_VAL_AUTHENT_AGENT    = 'AuthenticatingAgent';

//
// Entries under REGSTR_PATH_REALMODENET
//

  REGSTR_VAL_PREFREDIR     = 'PreferredRedir';
  REGSTR_VAL_AUTOSTART     = 'AutoStart';
  REGSTR_VAL_AUTOLOGON     = 'AutoLogon';
  REGSTR_VAL_NETCARD       = 'Netcard';
  REGSTR_VAL_TRANSPORT     = 'Transport';
  REGSTR_VAL_DYNAMIC       = 'Dynamic';
  REGSTR_VAL_TRANSITION    = 'Transition';
  REGSTR_VAL_STATICDRIVE   = 'StaticDrive';
  REGSTR_VAL_LOADHI        = 'LoadHi';
  REGSTR_VAL_LOADRMDRIVERS = 'LoadRMDrivers';
  REGSTR_VAL_SETUPN        = 'SetupN';
  REGSTR_VAL_SETUPNPATH    = 'SetupNPath';

//
// Entries under REGSTR_PATH_CVNETWORK
//

  REGSTR_VAL_WRKGRP_FORCEMAPPING = 'WrkgrpForceMapping';
  REGSTR_VAL_WRKGRP_REQUIRED     = 'WrkgrpRequired';

//
// NT-compatible place where the name of the currently logged-on user is stored.
//

  REGSTR_PATH_CURRENT_CONTROL_SET = 'System\CurrentControlSet\Control';
  REGSTR_VAL_CURRENT_USER         = 'Current User';

// section where password providers are installed (each provider has subkey under this key)

  REGSTR_PATH_PWDPROVIDER              = 'System\CurrentControlSet\Control\PwdProvider';
  REGSTR_VAL_PWDPROVIDER_PATH          = 'ProviderPath';
  REGSTR_VAL_PWDPROVIDER_DESC          = 'Description';
  REGSTR_VAL_PWDPROVIDER_CHANGEPWD     = 'ChangePassword';
  REGSTR_VAL_PWDPROVIDER_CHANGEPWDHWND = 'ChangePasswordHwnd';
  REGSTR_VAL_PWDPROVIDER_GETPWDSTATUS  = 'GetPasswordStatus';
  REGSTR_VAL_PWDPROVIDER_ISNP          = 'NetworkProvider';
  REGSTR_VAL_PWDPROVIDER_CHANGEORDER   = 'ChangeOrder';

//
// Used by administrator configuration tool and various components who enforce
// policies.
//

  REGSTR_PATH_POLICIES = 'Software\Microsoft\Windows\CurrentVersion\Policies';

// used to control remote update of administrator policies

  REGSTR_PATH_UPDATE      = 'System\CurrentControlSet\Control\Update';
  REGSTR_VALUE_ENABLE     = 'Enable';
  REGSTR_VALUE_VERBOSE    = 'Verbose';
  REGSTR_VALUE_NETPATH    = 'NetworkPath';
  REGSTR_VALUE_DEFAULTLOC = 'UseDefaultNetLocation';

//
//      Entries under REGSTR_PATH_POLICIES
//

  REGSTR_KEY_NETWORK   = 'Network';
  // already defined above
  // REGSTR_KEY_SYSTEM    = 'System';
  // {$EXTERNALSYM REGSTR_KEY_SYSTEM}
  REGSTR_KEY_PRINTERS  = 'Printers';
  REGSTR_KEY_WINOLDAPP = 'WinOldApp';

// (following are values REG_DWORD, legal values 0 or 1, treat as TEXT("0") if value not present)
// policies under NETWORK key

  REGSTR_VAL_NOFILESHARING            = 'NoFileSharing'; // TEXT("1") prevents server from loading
  REGSTR_VAL_NOPRINTSHARING           = 'NoPrintSharing';
  REGSTR_VAL_NOFILESHARINGCTRL        = 'NoFileSharingControl'; // TEXT("1") removes sharing ui
  REGSTR_VAL_NOPRINTSHARINGCTRL       = 'NoPrintSharingControl';
  REGSTR_VAL_HIDESHAREPWDS            = 'HideSharePwds'; // TEXT("1") hides share passwords with asterisks
  REGSTR_VAL_DISABLEPWDCACHING        = 'DisablePwdCaching'; // TEXT("1") disables caching
  REGSTR_VAL_ALPHANUMPWDS             = 'AlphanumPwds'; // TEXT("1") forces alphanumeric passwords
  REGSTR_VAL_NETSETUP_DISABLE         = 'NoNetSetup';
  REGSTR_VAL_NETSETUP_NOCONFIGPAGE    = 'NoNetSetupConfigPage';
  REGSTR_VAL_NETSETUP_NOIDPAGE        = 'NoNetSetupIDPage';
  REGSTR_VAL_NETSETUP_NOSECURITYPAGE  = 'NoNetSetupSecurityPage';
  REGSTR_VAL_SYSTEMCPL_NOVIRTMEMPAGE  = 'NoVirtMemPage';
  REGSTR_VAL_SYSTEMCPL_NODEVMGRPAGE   = 'NoDevMgrPage';
  REGSTR_VAL_SYSTEMCPL_NOCONFIGPAGE   = 'NoConfigPage';
  REGSTR_VAL_SYSTEMCPL_NOFILESYSPAGE  = 'NoFileSysPage';
  REGSTR_VAL_DISPCPL_NODISPCPL        = 'NoDispCPL';
  REGSTR_VAL_DISPCPL_NOBACKGROUNDPAGE = 'NoDispBackgroundPage';
  REGSTR_VAL_DISPCPL_NOSCRSAVPAGE     = 'NoDispScrSavPage';
  REGSTR_VAL_DISPCPL_NOAPPEARANCEPAGE = 'NoDispAppearancePage';
  REGSTR_VAL_DISPCPL_NOSETTINGSPAGE   = 'NoDispSettingsPage';
  REGSTR_VAL_SECCPL_NOSECCPL          = 'NoSecCPL';
  REGSTR_VAL_SECCPL_NOPWDPAGE         = 'NoPwdPage';
  REGSTR_VAL_SECCPL_NOADMINPAGE       = 'NoAdminPage';
  REGSTR_VAL_SECCPL_NOPROFILEPAGE     = 'NoProfilePage';
  REGSTR_VAL_PRINTERS_HIDETABS        = 'NoPrinterTabs';
  REGSTR_VAL_PRINTERS_NODELETE        = 'NoDeletePrinter';
  REGSTR_VAL_PRINTERS_NOADD           = 'NoAddPrinter';
  REGSTR_VAL_WINOLDAPP_DISABLED       = 'Disabled';
  REGSTR_VAL_WINOLDAPP_NOREALMODE     = 'NoRealMode';
  REGSTR_VAL_NOENTIRENETWORK          = 'NoEntireNetwork';
  REGSTR_VAL_NOWORKGROUPCONTENTS      = 'NoWorkgroupContents';

// (following are values REG_DWORD, legal values 0 or 1, treat as TEXT("1") if value not present)
// policies under Policies\SYSTEM key
  REGSTR_VAL_UNDOCK_WITHOUT_LOGON     = 'UndockWithoutLogon';

// REG_DWORD, 0=off, otherwise value is minimum # of chars to allow in password

  REGSTR_VAL_MINPWDLEN = 'MinPwdLen';

// REG_DWORD, 0=off, otherwise value is # of days for pwd to expire

  REGSTR_VAL_PWDEXPIRATION = 'PwdExpiration';

  REGSTR_VAL_WIN31PROVIDER = 'Win31Provider'; // REG_SZ

// policies under SYSTEM key

  REGSTR_VAL_DISABLEREGTOOLS = 'DisableRegistryTools';

  REGSTR_PATH_WINLOGON          = 'Software\Microsoft\Windows\CurrentVersion\Winlogon';
  REGSTR_VAL_LEGALNOTICECAPTION = 'LegalNoticeCaption'; // REG_SZ
  REGSTR_VAL_LEGALNOTICETEXT    = 'LegalNoticeText'; // REG_SZ
  REGSTR_VAL_DRIVE_SPINDOWN     = 'NoDispSpinDown';

  REGSTR_VAL_RESTRICTRUN = 'RestrictRun';

//
//  Entries in policy file.  (Won't be in local registry, only policy hive)

  REGSTR_KEY_POL_USERS         = 'Users';
  REGSTR_KEY_POL_COMPUTERS     = 'Computers';
  REGSTR_KEY_POL_USERGROUPS    = 'UserGroups';
  REGSTR_KEY_POL_DEFAULT       = '.default';
  REGSTR_KEY_POL_USERGROUPDATA = 'GroupData\UserGroups\Priority';

//
//      Entries for time zone information under LOCAL_MACHINE
//

  REGSTR_PATH_TIMEZONE       = 'System\CurrentControlSet\Control\TimeZoneInformation';
  REGSTR_VAL_TZBIAS          = 'Bias';
  REGSTR_VAL_TZDLTBIAS       = 'DaylightBias';
  REGSTR_VAL_TZSTDBIAS       = 'StandardBias';
  REGSTR_VAL_TZACTBIAS       = 'ActiveTimeBias';
  REGSTR_VAL_TZDLTFLAG       = 'DaylightFlag';
  REGSTR_VAL_TZSTDSTART      = 'StandardStart';
  REGSTR_VAL_TZDLTSTART      = 'DaylightStart';
  REGSTR_VAL_TZDLTNAME       = 'DaylightName';
  REGSTR_VAL_TZSTDNAME       = 'StandardName';
  REGSTR_VAL_TZNOCHANGESTART = 'NoChangeStart';
  REGSTR_VAL_TZNOCHANGEEND   = 'NoChangeEnd';
  REGSTR_VAL_TZNOAUTOTIME    = 'DisableAutoDaylightTimeSet';

//
//      Entries for floating point processor existence under LOCAL_MACHINE
//

  REGSTR_PATH_FLOATINGPOINTPROCESSOR  = 'HARDWARE\DESCRIPTION\System\FloatingPointProcessor';
  REGSTR_PATH_FLOATINGPOINTPROCESSOR0 = 'HARDWARE\DESCRIPTION\System\FloatingPointProcessor\0';

//
//      Entries for computer name under LOCAL_MACHINE
//

  REGSTR_PATH_COMPUTRNAME = 'System\CurrentControlSet\Control\ComputerName\ComputerName';
  REGSTR_VAL_COMPUTRNAME  = 'ComputerName';

//      Entry so that we force a reboot on shutdown / single instance dos app

  REGSTR_PATH_SHUTDOWN       = 'System\CurrentControlSet\Control\Shutdown';
  REGSTR_VAL_FORCEREBOOT     = 'ForceReboot';
  REGSTR_VAL_SETUPPROGRAMRAN = 'SetupProgramRan';
  REGSTR_VAL_DOES_POLLING    = 'PollingSupportNeeded';

//
//      Entries for known system DLLs under LOCAL_MACHINE
//
//      The VAL keys here are the actual DLL names (FOO.DLL)
//

  REGSTR_PATH_KNOWNDLLS   = 'System\CurrentControlSet\Control\SessionManager\KnownDLLs';
  REGSTR_PATH_KNOWN16DLLS = 'System\CurrentControlSet\Control\SessionManager\Known16DLLs';

//      Entries here for system dlls we need to version check in case overwritten

  REGSTR_PATH_CHECKVERDLLS = 'System\CurrentControlSet\Control\SessionManager\CheckVerDLLs';
  REGSTR_PATH_WARNVERDLLS  = 'System\CurrentControlSet\Control\SessionManager\WarnVerDLLs';

//      Entries here for app ini files we (msgsrv32) need to hack

  REGSTR_PATH_HACKINIFILE = 'System\CurrentControlSet\Control\SessionManager\HackIniFiles';

//      Keys here for bad applications we want to warn the user about before running

  REGSTR_PATH_CHECKBADAPPS = 'System\CurrentControlSet\Control\SessionManager\CheckBadApps';

//      Keys here for applications we need to patch

  REGSTR_PATH_APPPATCH = 'System\CurrentControlSet\Control\SessionManager\AppPatches';

  REGSTR_PATH_CHECKBADAPPS400 = 'System\CurrentControlSet\Control\SessionManager\CheckBadApps400';

  REGSTR_PATH_SHELLSERVICEOBJECT        = 'Software\Microsoft\Windows\CurrentVersion\ShellServiceObject';
  REGSTR_PATH_SHELLSERVICEOBJECTDELAYED = 'Software\Microsoft\Windows\CurrentVersion\ShellServiceObjectDelayLoad';

//
//      Entries for known system VxDs under LOCAL_MACHINE
//
//      The VAL keys here are the full path names of VxDs (c:\app\vapp.vxd)
//      It is suggested that the keynames be the same as the module name of
//      the VxD.
//      This section is used to dyna-load VxDs with
//      CreateFile(\.\vxd_regstr_keyname).
//

  REGSTR_PATH_KNOWNVXDS = 'System\CurrentControlSet\Control\SessionManager\KnownVxDs';

//
// Entries for values in uninstaller keys under REGSTR_PATH_UNINSTALL \ appname
//

  REGSTR_VAL_UNINSTALLER_DISPLAYNAME = 'DisplayName';
  REGSTR_VAL_UNINSTALLER_COMMANDLINE = 'UninstallString';

//
// Entries for values in uninstaller keys under REGSTR_PATH_REINSTALL \ instanceid
//

  REGSTR_VAL_REINSTALL_DISPLAYNAME        = 'DisplayName';
  REGSTR_VAL_REINSTALL_STRING             = 'ReinstallString';
  REGSTR_VAL_REINSTALL_DEVICEINSTANCEIDS  = 'DeviceInstanceIds';

//
//      Entries for known per user settings: Under HKEY_CURRENT_USER
//

  REGSTR_PATH_DESKTOP        = REGSTR_PATH_SCREENSAVE;
  REGSTR_PATH_MOUSE          = 'Control Panel\Mouse';
  REGSTR_PATH_KEYBOARD       = 'Control Panel\Keyboard';
  REGSTR_PATH_COLORS         = 'Control Panel\Colors';
  REGSTR_PATH_SOUND          = 'Control Panel\Sound';
  REGSTR_PATH_METRICS        = 'Control Panel\Desktop\WindowMetrics';
  REGSTR_PATH_ICONS          = 'Control Panel\Icons';
  REGSTR_PATH_CURSORS        = 'Control Panel\Cursors';
  REGSTR_PATH_CHECKDISK      = 'Software\Microsoft\Windows\CurrentVersion\Applets\Check Drive';
  REGSTR_PATH_CHECKDISKSET   = 'Settings';
  REGSTR_PATH_CHECKDISKUDRVS = 'NoUnknownDDErrDrvs';

//
//  Entries under REGSTR_PATH_FAULT
//

  REGSTR_PATH_FAULT        = 'Software\Microsoft\Windows\CurrentVersion\Fault';
  REGSTR_VAL_FAULT_LOGFILE = 'LogFile';

//
//  Entries under REGSTR_PATH_AEDEBUG
//

  REGSTR_PATH_AEDEBUG         = 'Software\Microsoft\Windows NT\CurrentVersion\AeDebug';
  REGSTR_VAL_AEDEBUG_DEBUGGER = 'Debugger';
  REGSTR_VAL_AEDEBUG_AUTO     = 'Auto';

//
//  Entries under REGSTR_PATH_GRPCONV
//

  REGSTR_PATH_GRPCONV = 'Software\Microsoft\Windows\CurrentVersion\GrpConv';

//
//  Entries under the RegItem key in a shell namespace
//

  REGSTR_VAL_REGITEMDELETEMESSAGE = 'Removal Message';

//
//  Entries for the Drives Tools page
//
//  NOTE that these items are not recorded for removable drives. These
//  keys record X=DSKTLSYSTEMTIME where X is the drive letter. Since
//  these tools actually work on the disk in the drive, as opposed to
//  the drive itself, it is pointless to record them on a removable media
//  since if a different disk is inserted in the drive, the data is
//  meaningless.
//

  REGSTR_PATH_LASTCHECK    = 'Software\Microsoft\Windows\CurrentVersion\Explorer\LastCheck';
  REGSTR_PATH_LASTOPTIMIZE = 'Software\Microsoft\Windows\CurrentVersion\Explorer\LastOptimize';
  REGSTR_PATH_LASTBACKUP   = 'Software\Microsoft\Windows\CurrentVersion\Explorer\LastBackup';

//
// The above 3 keys record with the registry value of the drive letter
// a SYSTEMTIME structure
//

//
// Entries under HKEY_LOCAL_MACHINE for Check Drive specific stuff
//

  REGSTR_PATH_CHKLASTCHECK  = 'Software\Microsoft\Windows\CurrentVersion\Applets\Check Drive\LastCheck';
  REGSTR_PATH_CHKLASTSURFAN = 'Software\Microsoft\Windows\CurrentVersion\Applets\Check Drive\LastSurfaceAnalysis';

//
// The above 2 keys record the following binary structure which is
// a system time structure with the addition of a result code field.
// Note that the time part of REGSTR_PATH_CHKLASTCHECK is effectively
// identical to REGSTR_PATH_LASTCHECK under the explorer key
//

type
  _DSKTLSYSTEMTIME = record
    wYear: WORD;
    wMonth: WORD;
    wDayOfWeek: WORD;
    wDay: WORD;
    wHour: WORD;
    wMinute: WORD;
    wSecond: WORD;
    wMilliseconds: WORD;
    wResult: WORD;
  end;
  DSKTLSYSTEMTIME = _DSKTLSYSTEMTIME;
  PDSKTLSYSTEMTIME = ^DSKTLSYSTEMTIME;
  LPDSKTLSYSTEMTIME = ^DSKTLSYSTEMTIME;
  TDsktlSystemTime = _DSKTLSYSTEMTIME;

//
// The following are defines for the wResult field
//

const
  DTRESULTOK  = 0;  // Operation was successful, no errors
  DTRESULTFIX = 1;  // Operation was successful, errors were found
                    //   but all were fixed.
  DTRESULTPROB = 2; // Operation was not successful or errors
                    //   were found and some or all were not fixed.
  DTRESULTPART = 3; // Operation was partially completed but was
                    //   terminated either by the user or an error.

//
//  Entries for persistent shares
//

  REGSTR_KEY_SHARES         = 'Software\Microsoft\Windows\CurrentVersion\Network\LanMan';
  REGSTR_VAL_SHARES_FLAGS   = 'Flags';
  REGSTR_VAL_SHARES_TYPE    = 'Type';
  REGSTR_VAL_SHARES_PATH    = 'Path';
  REGSTR_VAL_SHARES_REMARK  = 'Remark';
  REGSTR_VAL_SHARES_RW_PASS = 'Parm1';
  REGSTR_VAL_SHARES_RO_PASS = 'Parm2';

//
//      Entries for printer settings under LOCAL_MACHINE
//

  REGSTR_PATH_PRINT         = 'System\CurrentControlSet\Control\Print';
  REGSTR_PATH_PRINTERS      = 'System\CurrentControlSet\Control\Print\Printers';
  REGSTR_PATH_PROVIDERS     = 'System\CurrentControlSet\Control\Print\Providers';
  REGSTR_PATH_MONITORS      = 'System\CurrentControlSet\Control\Print\Monitors';
  REGSTR_PATH_ENVIRONMENTS  = 'System\CurrentControlSet\Control\Print\Environments';
  REGSTR_VAL_START_ON_BOOT  = 'StartOnBoot';
  REGSTR_VAL_PRINTERS_MASK  = 'PrintersMask';
  REGSTR_VAL_DOS_SPOOL_MASK = 'DOSSpoolMask';
  REGSTR_KEY_CURRENT_ENV    = '\Windows 4.0';
  REGSTR_KEY_DRIVERS        = '\Drivers';
  REGSTR_KEY_PRINT_PROC     = '\Print Processors';

//
// Entries for MultiMedia under HKEY_CURRENT_USER
//

  REGSTR_PATH_EVENTLABELS      = 'AppEvents\EventLabels';
  REGSTR_PATH_SCHEMES          = 'AppEvents\Schemes';
  REGSTR_PATH_APPS             = REGSTR_PATH_SCHEMES + '\Apps';
  REGSTR_PATH_APPS_DEFAULT     = REGSTR_PATH_SCHEMES + '\Apps\.Default';
  REGSTR_PATH_NAMES            = REGSTR_PATH_SCHEMES + '\Names';
  REGSTR_PATH_MULTIMEDIA       = REGSTR_PATH_SETUP + '\Multimedia';
  REGSTR_PATH_MULTIMEDIA_AUDIO = 'Software\Microsoft\Multimedia\Audio';
  REGSTR_PATH_MULTIMEDIA_AUDIO_IMAGES = REGSTR_PATH_MULTIMEDIA_AUDIO + '\Images';

//
// Entries for MultiMedia under HKEY_LOCAL_MACHINE
//

  REGSTR_PATH_MEDIARESOURCES    = REGSTR_PATH_CURRENT_CONTROL_SET + '\MediaResources';
  REGSTR_PATH_MEDIAPROPERTIES   = REGSTR_PATH_CURRENT_CONTROL_SET + '\MediaProperties';
  REGSTR_PATH_PRIVATEPROPERTIES = REGSTR_PATH_MEDIAPROPERTIES + '\PrivateProperties';
  REGSTR_PATH_PUBLICPROPERTIES  = REGSTR_PATH_MEDIAPROPERTIES + '\PublicProperties';

// joysticks

  REGSTR_PATH_JOYOEM     = REGSTR_PATH_PRIVATEPROPERTIES + '\Joystick\OEM';
  REGSTR_PATH_JOYCONFIG  = REGSTR_PATH_MEDIARESOURCES + '\Joystick';
  REGSTR_KEY_JOYCURR     = 'CurrentJoystickSettings';
  REGSTR_KEY_JOYSETTINGS = 'JoystickSettings';

// joystick values found under REGSTR_PATH_JOYCONFIG

  REGSTR_VAL_JOYUSERVALUES = 'JoystickUserValues';
  REGSTR_VAL_JOYCALLOUT    = 'JoystickCallout';

// joystick values found under REGSTR_KEY_JOYCURR and REGSTR_KEY_JOYSETTINGS

  REGSTR_VAL_JOYNCONFIG     = 'Joystick%dConfiguration';
  REGSTR_VAL_JOYNOEMNAME    = 'Joystick%dOEMName';
  REGSTR_VAL_JOYNOEMCALLOUT = 'Joystick%dOEMCallout';

// joystick values found under keys under REGSTR_PATH_JOYOEM

  REGSTR_VAL_JOYOEMCALLOUT        = 'OEMCallout';
  REGSTR_VAL_JOYOEMNAME           = 'OEMName';
  REGSTR_VAL_JOYOEMDATA           = 'OEMData';
  REGSTR_VAL_JOYOEMXYLABEL        = 'OEMXYLabel';
  REGSTR_VAL_JOYOEMZLABEL         = 'OEMZLabel';
  REGSTR_VAL_JOYOEMRLABEL         = 'OEMRLabel';
  REGSTR_VAL_JOYOEMPOVLABEL       = 'OEMPOVLabel';
  REGSTR_VAL_JOYOEMULABEL         = 'OEMULabel';
  REGSTR_VAL_JOYOEMVLABEL         = 'OEMVLabel';
  REGSTR_VAL_JOYOEMTESTMOVEDESC   = 'OEMTestMoveDesc';
  REGSTR_VAL_JOYOEMTESTBUTTONDESC = 'OEMTestButtonDesc';
  REGSTR_VAL_JOYOEMTESTMOVECAP    = 'OEMTestMoveCap';
  REGSTR_VAL_JOYOEMTESTBUTTONCAP  = 'OEMTestButtonCap';
  REGSTR_VAL_JOYOEMTESTWINCAP     = 'OEMTestWinCap';
  REGSTR_VAL_JOYOEMCALCAP         = 'OEMCalCap';
  REGSTR_VAL_JOYOEMCALWINCAP      = 'OEMCalWinCap';
  REGSTR_VAL_JOYOEMCAL1           = 'OEMCal1';
  REGSTR_VAL_JOYOEMCAL2           = 'OEMCal2';
  REGSTR_VAL_JOYOEMCAL3           = 'OEMCal3';
  REGSTR_VAL_JOYOEMCAL4           = 'OEMCal4';
  REGSTR_VAL_JOYOEMCAL5           = 'OEMCal5';
  REGSTR_VAL_JOYOEMCAL6           = 'OEMCal6';
  REGSTR_VAL_JOYOEMCAL7           = 'OEMCal7';
  REGSTR_VAL_JOYOEMCAL8           = 'OEMCal8';
  REGSTR_VAL_JOYOEMCAL9           = 'OEMCal9';
  REGSTR_VAL_JOYOEMCAL10          = 'OEMCal10';
  REGSTR_VAL_JOYOEMCAL11          = 'OEMCal11';
  REGSTR_VAL_JOYOEMCAL12          = 'OEMCal12';

// Image values under REGSTR_PATH_MULTIMEDIA_AUDIO_IMAGES

  REGSTR_VAL_AUDIO_BITMAP = 'bitmap';
  REGSTR_VAL_AUDIO_ICON   = 'icon';

//
// Entries for Device Installer under HKEY_CURRENT_USER
//

  REGSTR_PATH_DEVICEINSTALLER = 'Software\Microsoft\Windows\CurrentVersion\Device Installer';

// Device Installer values found under REGSTR_PATH_DEVICEINSTALLER

  REGSTR_VAL_SEARCHOPTIONS = 'SearchOptions';

// BiosInfo defines.

  REGSTR_PATH_BIOSINFO = 'System\CurrentControlSet\Control\BiosInfo';

// Pci Irq Routing registry defines.

  REGSTR_PATH_PCIIR        = 'System\CurrentControlSet\Control\Pnp\PciIrqRouting';
  REGSTR_VAL_OPTIONS       = 'Options';
  REGSTR_VAL_STAT          = 'Status';
  REGSTR_VAL_TABLE_STAT    = 'TableStatus';
  REGSTR_VAL_MINIPORT_STAT = 'MiniportStatus';

// Pci Irq Routing Option values.

  PIR_OPTION_ENABLED  = $00000001;
  PIR_OPTION_REGISTRY = $00000002;
  PIR_OPTION_MSSPEC   = $00000004;
  PIR_OPTION_REALMODE = $00000008;
  PIR_OPTION_DEFAULT  = $0000000f;

// Pci Irq Routing Status values.

  PIR_STATUS_ERROR    = $00000000;
  PIR_STATUS_ENABLED  = $00000001;
  PIR_STATUS_DISABLED = $00000002;
  PIR_STATUS_MAX      = $00000003;

  PIR_STATUS_TABLE_REGISTRY = $00000000;
  PIR_STATUS_TABLE_MSSPEC   = $00000001;
  PIR_STATUS_TABLE_REALMODE = $00000002;
  PIR_STATUS_TABLE_NONE     = $00000003;
  PIR_STATUS_TABLE_ERROR    = $00000004;
  PIR_STATUS_TABLE_BAD      = $00000005;
  PIR_STATUS_TABLE_SUCCESS  = $00000006;
  PIR_STATUS_TABLE_MAX      = $00000007;

  PIR_STATUS_MINIPORT_NORMAL     = $00000000;
  PIR_STATUS_MINIPORT_COMPATIBLE = $00000001;
  PIR_STATUS_MINIPORT_OVERRIDE   = $00000002;
  PIR_STATUS_MINIPORT_NONE       = $00000003;
  PIR_STATUS_MINIPORT_ERROR      = $00000004;
  PIR_STATUS_MINIPORT_NOKEY      = $00000005;
  PIR_STATUS_MINIPORT_SUCCESS    = $00000006;
  PIR_STATUS_MINIPORT_INVALID    = $00000007;
  PIR_STATUS_MINIPORT_MAX        = $00000008;

//
// entries for LastKnownGood
// each value name under this key is SubPath/File (note reversal of '\\' to '/')
// each value is an indication of post-processing to be done after files have been recovered
// LASTGOOD_OPERATION bits indicate the primary post-processing operation
// remaining bits may be used as flags (allocate flags from highest bits first)
// a value of 0 is the same as the value being omitted, ie, no post processing.
//

  REGSTR_PATH_LASTGOOD            = 'System\LastKnownGoodRecovery\LastGood';
  REGSTR_PATH_LASTGOODTMP         = 'System\LastKnownGoodRecovery\LastGood.Tmp';

  LASTGOOD_OPERATION              = $000000FF; // operation to perform
  LASTGOOD_OPERATION_NOPOSTPROC   = $00000000; // no post-processing
  LASTGOOD_OPERATION_DELETE       = $00000001; // Delete file during recovery

implementation
//uses ...

//your implementation here

end.
