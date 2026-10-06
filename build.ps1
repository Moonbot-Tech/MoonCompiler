[CmdletBinding()]
param(
  [Parameter(Position = 0, Mandatory = $true)]
  [string]$Target,

  [Parameter(Position = 1)]
  [string]$Profile,

  [string]$Bootstrap,
  [string]$Make
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = $PSScriptRoot
$Toolchain = Join-Path $Root 'toolchain'
$IdeToolchain = Join-Path $Toolchain 'ide'
$MmSource = Join-Path $Root 'runtime\mm\mormot.core.fpcx64mm.pas'
$MmUnit = 'mormot.core.fpcx64mm'
$ConfigTemplate = Join-Path $Root 'scripts\fpc.cfg.win64.template'
$LazarusRepository = 'https://gitlab.com/freepascal.org/lazarus/lazarus.git'
$LazarusCommit = 'ce01e71c34866d83f69ea7cd855ae7eabea49f38'
. (Join-Path $Root 'scripts\Publish-Toolchain.ps1')

function Invoke-Checked {
  param([string]$File, [string[]]$Arguments)
  & $File @Arguments
  If ($LASTEXITCODE -ne 0) {
    throw "command failed ($LASTEXITCODE): $File $($Arguments -join ' ')"
  }
}

function Find-Bootstrap {
  If ($Bootstrap) {
    return (Resolve-Path -LiteralPath $Bootstrap).Path
  }
  If ($env:MOONBOT_BOOTSTRAP_FPC) {
    return (Resolve-Path -LiteralPath $env:MOONBOT_BOOTSTRAP_FPC).Path
  }
  $cached = Join-Path $env:LOCALAPPDATA `
    'MoonCompiler\bootstrap\3.2.2\bin\i386-win32\fpc.exe'
  If (Test-Path -LiteralPath $cached) {
    return $cached
  }
  $found = Get-Command fpc.exe -ErrorAction SilentlyContinue
  If ($found) {
    return $found.Source
  }
  throw 'FPC 3.2.2 is required once. Pass -Bootstrap or set MOONBOT_BOOTSTRAP_FPC.'
}

function Read-RtlProfile {
  # scripts/rtl-profile.txt: the option lines (comments start with #) of the
  # product RTL/package profile, one definition for both drivers
  $lines = Get-Content -LiteralPath (Join-Path $Root 'scripts\rtl-profile.txt') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
  If (-not $lines) {
    throw 'scripts\rtl-profile.txt declares no option'
  }
  return ($lines -join ' ')
}

function Find-Make([string]$BootstrapPath) {
  If ($Make) {
    return (Resolve-Path -LiteralPath $Make).Path
  }
  If ($env:MOONBOT_MAKE) {
    return (Resolve-Path -LiteralPath $env:MOONBOT_MAKE).Path
  }
  $nextToBootstrap = Join-Path (Split-Path -Parent $BootstrapPath) 'make.exe'
  If (Test-Path -LiteralPath $nextToBootstrap) {
    return $nextToBootstrap
  }
  throw 'GNU make.exe was not found. Pass -Make or set MOONBOT_MAKE.'
}

# The mormot directory next to the toolchain: the MoonORMot the runtime units
# over mORMot (System.Zip, System.Net.HttpClient, Moon.Diagnostics) compile
# against.  Cloned once when missing; an existing directory, link or junction
# is the user's own and is never touched.  No git or no network is a warning:
# the toolchain works, those units do not until mormot is there.
function Ensure-MoonORMot {
  $mormotDir = Join-Path $Root 'mormot'
  If (Test-Path -LiteralPath $mormotDir) {
    return
  }
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  If (-not $git) {
    Write-Warning "git not found; MoonORMot not cloned."
    Write-Warning "Clone https://github.com/Moonbot-Tech/MoonORMot into $mormotDir for System.Zip/HttpClient."
    return
  }
  Write-Output 'Cloning MoonORMot...'
  # Windows PowerShell 5.1 turns native stderr into ErrorRecords when a
  # caller redirects this script through Tee-Object. Git progress is not
  # a failure: normalize its output and judge the command by its exit code.
  $savedPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $git.Source clone 'https://github.com/Moonbot-Tech/MoonORMot' $mormotDir 2>&1 |
      ForEach-Object { $_.ToString() }
    $cloneExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $savedPreference
  }
  If ($cloneExitCode -ne 0) {
    Write-Warning "MoonORMot clone failed."
    Write-Warning "Clone https://github.com/Moonbot-Tech/MoonORMot into $mormotDir or pass -Fu to use your own."
  }
}

# The IDE profile's fpc.cfg: the template with the installed IDE toolchain as
# basepath (an absolute path: the qualification gates run the product
# compiler with this configuration, so $FPCBINDIR would point elsewhere) plus
# the vanilla-runtime define.  Written by the compiler build and again when
# an archive is installed, because the archive carries the build machine's
# path.
function Write-IdeConfig {
  param(
    [Parameter(Mandatory = $true)][string]$Fpcmkcfg,
    [Parameter(Mandatory = $true)][string]$Config
  )
  Invoke-Checked $Fpcmkcfg @(
    '-t', $ConfigTemplate, '-d', "basepath=$IdeToolchain", '-o', $Config)
  Add-Content -LiteralPath $Config -Encoding Ascii -Value @(
    '# MoonCompiler IDE ABI: ordinary FPC String and Char representation.',
    '# Do not inject the product memory manager or runtime prefix.',
    '-dMOONCOMPILER_VANILLA_RUNTIME')
}

function Build-Compiler {
  $bootstrapPath = Find-Bootstrap
  If ((& $bootstrapPath -iV).Trim() -ne '3.2.2') {
    throw 'the bootstrap compiler must be FPC 3.2.2'
  }
  $makePath = Find-Make $bootstrapPath
  $bootstrapDir = Split-Path -Parent $bootstrapPath
  $fpcmkcfg = Join-Path $bootstrapDir 'fpcmkcfg.exe'
  If (-not (Test-Path -LiteralPath $fpcmkcfg)) {
    throw "fpcmkcfg.exe was not found beside bootstrap compiler: $bootstrapDir"
  }
  # Windows may classify the manifest-less GNU ginstall.exe as an installer
  # solely from its file name and reject a normal user launch with UAC error
  # 740.  A neutral local name keeps the exact same utility non-elevated.
  $portableTools = Join-Path $Root 'tools'
  $portableInstall = Join-Path $portableTools 'gcopy.exe'
  $bootstrapInstall = Join-Path $bootstrapDir 'ginstall.exe'
  If (-not (Test-Path -LiteralPath $bootstrapInstall)) {
    throw "ginstall.exe was not found beside bootstrap compiler: $bootstrapDir"
  }
  $oldPath = $env:Path
  $env:Path = "$bootstrapDir;$oldPath"

  New-Item -ItemType Directory -Force -Path $portableTools | Out-Null
  Copy-Item -LiteralPath $bootstrapInstall -Destination $portableInstall -Force
  $makeInstall = 'GINSTALL='+($portableInstall -replace '\\','/')
  $newToolchain = Join-Path $Root "toolchain.new.$PID"
  $oldToolchain = Join-Path $Root "toolchain.old.$PID"
  $ideProfile = Join-Path $Root "ide-profile.new.$PID"
  Remove-Item -LiteralPath $newToolchain, $oldToolchain, $ideProfile -Recurse -Force `
    -ErrorAction SilentlyContinue
  try {
    foreach ($part in @('compiler', 'rtl', 'packages', 'utils')) {
      Invoke-Checked $makePath @(
        '-C', (Join-Path $Root $part), 'clean',
        "FPC=$bootstrapPath", 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    }
    Get-ChildItem -Path (Join-Path $Root '*build-stamp*') -File |
      Remove-Item -Force
    Invoke-Checked $makePath @(
      '-C', $Root, '-j1', 'all', "FPC=$bootstrapPath",
      'OPT=-n -O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', $Root, 'install', "FPC=$bootstrapPath",
      'OPT=-n -O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain", $makeInstall)

    $fpc = Join-Path $newToolchain 'bin\x86_64-win64\fpc.exe'
    $targetCompiler = Join-Path $newToolchain 'bin\x86_64-win64\ppcx64.exe'
    $config = Join-Path $newToolchain 'bin\x86_64-win64\fpc.cfg'
    If (-not (Test-Path -LiteralPath $fpc) -or
        -not (Test-Path -LiteralPath $targetCompiler)) {
      throw 'the installed Win64 toolchain is incomplete'
    }

    # fpcres is a compiler tool, so build it against the ordinary host ABI
    # before the product Unicode RTL replaces the installed units.
    Invoke-Checked $fpcmkcfg @(
      '-t', $ConfigTemplate, '-d', "basepath=$newToolchain", '-o', $config)
    $fpcresOptions = 'OPT=-O2 -n -dMOONCOMPILER_VANILLA_RUNTIME'
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'utils\fpcres'), 'clean', "FPC=$fpc",
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'utils\fpcres'), 'all', "FPC=$fpc",
      $fpcresOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'utils\fpcres'), 'install', "FPC=$fpc",
      $fpcresOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain", $makeInstall)
    $fpcres = Join-Path $newToolchain 'bin\x86_64-win64\fpcres.exe'
    If (-not (Test-Path -LiteralPath $fpcres)) {
      throw 'the Win64 resource compiler was not installed'
    }

    # Preserve the ordinary FPC ABI before the product Unicode RTL replaces
    # the installed units.  Lazarus, LCL and compiler tools are built against
    # this profile; product applications continue to use the default profile.
    Copy-Item -LiteralPath $newToolchain -Destination $ideProfile -Recurse
    $ideConfig = Join-Path $ideProfile 'bin\x86_64-win64\fpc.cfg'

    # Compiler/IDE tools keep their host representation.  The target RTL and
    # application-facing packages use the modern Delphi Unicode ABI, with the
    # optimisation profile declared once in scripts/rtl-profile.txt (-O3, line
    # information); the exact string is
    # recorded in <toolchain>\profile.txt and rtl_profile_gate.py proves the
    # installed objects against it.
    $rtlProfile = Read-RtlProfile
    $unicodeOptions = "OPT=$rtlProfile -n -dMOONCOMPILER_VANILLA_RUNTIME -dUNICODERTL -dFPC_OS_UNICODE -dENABLE_DELPHI_RTTI -dMOONCOMPILER_DELPHI_CALLBACK_TYPES"
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'clean', "FPC=$targetCompiler",
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), '-j1', 'all', "FPC=$targetCompiler",
      $unicodeOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'install', "FPC=$targetCompiler",
      $unicodeOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain", $makeInstall)
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), 'clean', "FPC=$targetCompiler",
      'FPMAKEOPT=--NoIDE=1', 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), '-j1', 'all',
      "FPC=$targetCompiler", $unicodeOptions, 'FPMAKEOPT=--NoIDE=1',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), 'install',
      "FPC=$targetCompiler", $unicodeOptions, 'FPMAKEOPT=--NoIDE=1',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain", $makeInstall)
    Set-Content -LiteralPath (Join-Path $newToolchain 'profile.txt') -Encoding Ascii -Value @(
      "rtl_packages_opt=$unicodeOptions",
      ("placement_draft=" + [int]($env:MOONCOMPILER_PLACEMENT -ceq '1' -and [string]::IsNullOrEmpty($env:MOONCOMPILER_NO_PLACEMENT))),
      ("compiler_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath $targetCompiler).Hash.ToLowerInvariant()),
      ("sysutils_o_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $newToolchain 'units\x86_64-win64\rtl\sysutils.o')).Hash.ToLowerInvariant()),
      ("generics_hashes_o_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $newToolchain 'units\x86_64-win64\rtl-generics\generics.hashes.o')).Hash.ToLowerInvariant()),
      ("rtl_asm_x86_64_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\x86_64\x86_64.inc')).Hash.ToLowerInvariant()),
      ("rtl_asm_strings_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\x86_64\strings.inc')).Hash.ToLowerInvariant()),
      ("rtl_asm_sets_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\x86_64\set.inc')).Hash.ToLowerInvariant()),
      ("rtl_asm_threadvar_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\win\systhrd.inc')).Hash.ToLowerInvariant()),
      ("rtl_asm_math_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\objpas\math.pp')).Hash.ToLowerInvariant()),
      ("rtl_asm_sysstrings_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\objpas\sysutils\sysstr.inc')).Hash.ToLowerInvariant()),
      ("rtl_asm_hashes_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'packages\rtl-generics\src\generics.hashes.pas')).Hash.ToLowerInvariant()),
      ("rtl_asm_astrings_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\inc\astrings.inc')).Hash.ToLowerInvariant()),
      ("rtl_asm_ustrings_sha256=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'rtl\inc\ustrings.inc')).Hash.ToLowerInvariant()),
      ("built_utc=" + [DateTime]::UtcNow.ToString('o')))

    # Copy the runtime directory into the toolchain so it is self-contained.
    $runtimeDest = Join-Path $newToolchain 'runtime'
    Copy-Item -LiteralPath (Join-Path $Root 'runtime') -Destination $runtimeDest -Recurse

    # The pinned MM source now lives inside the toolchain.  The configuration
    # names it by the published path ($Toolchain), not by the temporary
    # directory the toolchain is assembled in.
    If (-not (Test-Path -LiteralPath (Join-Path $runtimeDest "mm\$MmUnit.pas"))) {
      throw 'the runtime MM source was not copied into the toolchain'
    }
    $toolchainMmSource = Join-Path $Toolchain "runtime\mm\$MmUnit.pas"

    # moon-base.cfg: toolchain paths (from $FPCBINDIR), ABI defines, pinned MM.
    # Qualification gates read this with -n @moon-base.cfg.
    $baseCfg = Join-Path (Split-Path -Parent $config) 'moon-base.cfg'
    Set-Content -LiteralPath $baseCfg -Encoding Ascii -Value @(
      '# MoonCompiler base configuration (moon-base.cfg)',
      '# Paths, parser switches, ABI defines and pinned MM.',
      '# Qualification gates read this file; no directives allowed.',
      '',
      '-Fu$FPCBINDIR/../../units/$fpctarget',
      '-Fu$FPCBINDIR/../../units/$fpctarget/*',
      '-Fu$FPCBINDIR/../../units/$fpctarget/rtl',
      '-FD$FPCBINDIR',
      '-Sgic',
      '-viwn',
      '-dMOONCOMPILER_UNICODE_DEFAULT',
      '-dMOONBOT_MM_PROFILE_REQUIRED',
      '-dFPCMM_BOOSTER',
      '-dFPCMM_MOONSHARD',
      '-dNOPATCHRTL',
      "--pinned-unit=$MmUnit=`$FPCBINDIR/../../runtime/mm/$MmUnit.pas")

    # fpc.cfg: full product profile (Delphi mode, runtime paths, debug/release).
    Set-Content -LiteralPath $config -Encoding Ascii -Value @(
      '# MoonCompiler product configuration',
      '#INCLUDE $FPCBINDIR/moon-base.cfg',
      '-Mdelphi',
      '-Municodestrings',
      '-MduplicateLocals',
      '-Madvancedrecords',
      '-Marrayoperators',
      '-Munderscoreisseparator',
      '-Mfunctionreferences',
      '-Manonymousfunctions',
      '-Minlinevars',
      '-Mimplicitgenerics',
      '-Mautoderef',
      '-Rintel',
      '-FNSystem',
      '-UaSystem.SysUtils=SysUtils',
      '-UaSystem.Variants=Variants',
      '-UaSystem.Classes=Classes',
      '-UaSystem.DateUtils=DateUtils',
      '-UaSystem.Math=Math',
      '-UaSystem.Types=Types',
      '-UaSystem.TypInfo=TypInfo',
      '-UaSystem.Rtti=Rtti',
      '-UaSystem.StrUtils=StrUtils',
      '-UaSystem.Character=Character',
      '-UaSystem.SyncObjs=SyncObjs',
      '-UaSystem.Generics.Defaults=Generics.Defaults',
      '-UaSystem.Generics.Collections=Generics.Collections',
      '-UaSystem.IniFiles=IniFiles',
      '-UaSystem.SysConst=SysConst',
      '-UaSystem.RTLConsts=RTLConsts',
      '-UaZLib=System.ZLib',
      '-UaZip=System.Zip',
      # Both Delphi spellings share the installed Win64 binding and its types.
      '-UaWinapi.Windows=Windows',
      '-UaWinapi.Messages=Messages',
      '-UaWinapi.WinSock=WinSock',
      '-UaWinapi.WinSock2=WinSock2',
      '-UaWinapi.ActiveX=ActiveX',
      '-UaWinapi.CommCtrl=CommCtrl',
      '-UaWinapi.CommDlg=CommDlg',
      '-UaWinapi.DwmApi=DwmApi',
      '-UaWinapi.FlatSB=FlatSB',
      '-UaWinapi.ImageHlp=ImageHlp',
      '-UaWinapi.Imm=Imm',
      '-UaWinapi.MMSystem=MMSystem',
      '-UaWinapi.MultiMon=MultiMon',
      '-UaWinapi.Nb30=Nb30',
      '-UaWinapi.Ole2=Ole2',
      '-UaWinapi.RichEdit=RichEdit',
      '-UaWinapi.ShellAPI=ShellAPI',
      '-UaWinapi.SHFolder=SHFolder',
      '-UaWinapi.ShlObj=ShlObj',
      '-UaWinapi.ShLwApi=ShLwApi',
      '-UaWinapi.UrlMon=UrlMon',
      '-UaWinapi.UxTheme=UxTheme',
      '-UaWinapi.WinHTTP=WinHTTP',
      '-UaWinapi.WinInet=WinInet',
      '-UaWinapi.WinSpool=WinSpool',
      # These headers are shipped by FPC under their JEDI names.
      '-UaWinapi.AccCtrl=JwaAccCtrl',
      '-UaAccCtrl=JwaAccCtrl',
      '-UaWinapi.AclAPI=JwaAclAPI',
      '-UaAclAPI=JwaAclAPI',
      '-UaWinapi.Cpl=JwaCpl',
      '-UaCpl=JwaCpl',
      '-UaWinapi.Dlgs=JwaDlgs',
      '-UaDlgs=JwaDlgs',
      '-UaWinapi.IpExport=JwaIpExport',
      '-UaIpExport=JwaIpExport',
      '-UaWinapi.IpHlpApi=JwaIpHlpApi',
      '-UaIpHlpApi=JwaIpHlpApi',
      '-UaWinapi.IpRtrMib=JwaIpRtrMib',
      '-UaIpRtrMib=JwaIpRtrMib',
      '-UaWinapi.IpTypes=JwaIpTypes',
      '-UaIpTypes=JwaIpTypes',
      '-UaWinapi.PsAPI=JwaPsAPI',
      '-UaPsAPI=JwaPsAPI',
      '-UaWinapi.Qos=JwaQos',
      '-UaQos=JwaQos',
      '-UaWinapi.RegStr=JwaRegStr',
      '-UaRegStr=JwaRegStr',
      '-UaWinapi.TlHelp32=JwaTlHelp32',
      '-UaTlHelp32=JwaTlHelp32',
      '-UaWinapi.UserEnv=JwaUserEnv',
      '-UaUserEnv=JwaUserEnv',
      '-UaWinapi.WinCred=JwaWinCred',
      '-UaWinCred=JwaWinCred',
      '-UaWinapi.Winsafer=JwaWinsafer',
      '-UaWinsafer=JwaWinsafer',
      '-UaWinapi.WinSvc=JwaWinSvc',
      '-UaWinSvc=JwaWinSvc',
      '-UaWinapi.WTSApi32=JwaWTSApi32',
      '-UaWTSApi32=JwaWTSApi32',
      '-Fu$FPCBINDIR/../../runtime/reporting',
      '-Fl$FPCBINDIR/../../runtime/reporting/native',
      '-Fu$FPCBINDIR/../../runtime/mormot',
      '-Fu$FPCBINDIR/../../../mormot/*',
      '-Fl$FPCBINDIR/../../../mormot/static/$FPCTARGET',
      '-gl',
      '-gw3',
      '-Ci',
      '-Co-',
      '-Cr-',
      '-Ct-',
      '#IFDEF RELEASE',
      '-uDEBUG',
      '-O3',
      '-Sa-',
      '#ELSE',
      '-dDEBUG',
      '-O-',
      '-Sa',
      '#ENDIF')

    # IDE profile: rendered from template with vanilla-runtime define.
    Write-IdeConfig -Fpcmkcfg $fpcmkcfg -Config $ideConfig
    $licenseDir = Join-Path $newToolchain 'share\doc\mooncompiler'
    New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root 'compiler\COPYING.txt') `
      -Destination (Join-Path $licenseDir 'COMPILER-GPL-2.0.txt')
    Copy-Item -LiteralPath (Join-Path $Root 'rtl\COPYING.txt') `
      -Destination (Join-Path $licenseDir 'RTL-LGPL-2.1.txt')
    Copy-Item -LiteralPath (Join-Path $Root 'rtl\COPYING.FPC') `
      -Destination (Join-Path $licenseDir 'RTL-EXCEPTION.txt')
    Copy-Item -LiteralPath (Join-Path $Root 'runtime\mm\LICENSE.md') `
      -Destination (Join-Path $licenseDir 'MM-LICENSE.md')
    Copy-Item -LiteralPath (Join-Path $Root 'packages\vcl-compat\native\brotli\LICENSE-brotli.txt') `
      -Destination (Join-Path $licenseDir 'BROTLI-MIT.txt')
    Copy-Item -LiteralPath (Join-Path $Root 'doc\LICENSING.md') `
      -Destination (Join-Path $licenseDir 'LICENSING.md')
    foreach ($tool in @('ar', 'as', 'ld', 'nm', 'objcopy', 'objdump', 'strip', 'windres')) {
      $source = Join-Path $bootstrapDir "x86_64-win64-$tool.exe"
      If (-not (Test-Path -LiteralPath $source)) {
        throw "Win64 binutil is missing from bootstrap toolchain: $source"
      }
      Copy-Item -LiteralPath $source `
        -Destination (Join-Path $newToolchain "bin\x86_64-win64\$tool.exe")
      Copy-Item -LiteralPath $source `
        -Destination (Join-Path $ideProfile "bin\x86_64-win64\$tool.exe")
    }
    Copy-Item -LiteralPath $fpcmkcfg `
      -Destination (Join-Path $newToolchain 'bin\x86_64-win64\fpcmkcfg.exe')
    Copy-Item -LiteralPath $fpcmkcfg `
      -Destination (Join-Path $ideProfile 'bin\x86_64-win64\fpcmkcfg.exe')
    If (-not (Test-Path -LiteralPath $config)) {
      throw 'the installed Win64 toolchain has no fpc.cfg'
    }
    Move-Item -LiteralPath $ideProfile -Destination (Join-Path $newToolchain 'ide')
    Publish-Toolchain -NewToolchain $newToolchain -Toolchain $Toolchain `
      -OldToolchain $oldToolchain
  } finally {
    $env:Path = $oldPath
    If ((Test-Path -LiteralPath $oldToolchain) -and
        -not (Test-Path -LiteralPath $Toolchain)) {
      Move-Item -LiteralPath $oldToolchain -Destination $Toolchain
    }
    Remove-Item -LiteralPath $newToolchain -Recurse -Force `
      -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ideProfile -Recurse -Force `
      -ErrorAction SilentlyContinue
    If (Test-Path -LiteralPath $Toolchain) {
      Remove-Item -LiteralPath $oldToolchain -Recurse -Force `
        -ErrorAction SilentlyContinue
    }
  }
  Write-Output "MoonCompiler installed in $Toolchain"
  Ensure-MoonORMot

  Write-Output ''
  Write-Output 'Build a project:'
  Write-Output "  $Toolchain\bin\x86_64-win64\fpc.exe Project.dpr"
  Write-Output "  $Toolchain\bin\x86_64-win64\fpc.exe -dRELEASE Project.dpr"
}

function Find-DeveloperMake {
  $candidates = @()
  If ($Make) {
    $candidates += (Resolve-Path -LiteralPath $Make).Path
  }
  If ($env:MOONBOT_MAKE) {
    $candidates += (Resolve-Path -LiteralPath $env:MOONBOT_MAKE).Path
  }
  $candidates += Join-Path $env:LOCALAPPDATA `
    'MoonCompiler\bootstrap\3.2.2\bin\i386-win32\make.exe'
  $found = Get-Command make.exe -ErrorAction SilentlyContinue
  If ($found) {
    $candidates += $found.Source
  }
  foreach ($candidate in $candidates | Select-Object -Unique) {
    If (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      continue
    }
    $version = @(& $candidate --version 2>$null)
    If ($LASTEXITCODE -eq 0 -and $version.Count -gt 0 -and
        $version[0] -like 'GNU Make*') {
      return $candidate
    }
  }
  throw 'GNU make.exe was not found. Pass -Make or set MOONBOT_MAKE.'
}

function Get-CompilerSourceFingerprint {
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  If (-not $git) {
    throw 'Git is required to record developer-backend provenance'
  }
  $paths = @(& $git.Source -C $Root ls-files -co --exclude-standard -- compiler)
  If ($LASTEXITCODE -ne 0) {
    throw 'could not enumerate compiler sources for provenance'
  }
  $description = New-Object Text.StringBuilder
  foreach ($relative in $paths | Sort-Object -Unique) {
    $path = Join-Path $Root $relative
    $hash = If (Test-Path -LiteralPath $path -PathType Leaf) {
      (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    } else {
      'missing'
    }
    [void]$description.Append($relative.Replace('\', '/'))
    [void]$description.Append("`0$hash`n")
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($description.ToString())
    return (($sha.ComputeHash($bytes) |
      ForEach-Object { $_.ToString('x2') }) -join '')
  } finally {
    $sha.Dispose()
  }
}

function Build-DeveloperBackend {
  $ideBin = Join-Path $IdeToolchain 'bin\x86_64-win64'
  $parent = Join-Path $ideBin 'ppcx64.exe'
  $config = Join-Path $ideBin 'fpc.cfg'
  $msg2inc = Join-Path $ideBin 'msg2inc.exe'
  foreach ($required in @($parent, $config, $msg2inc)) {
    If (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw 'the IDE profile is incomplete; run .\build.ps1 compiler first'
    }
  }
  If ((& $parent -iTP).Trim() -ne 'x86_64' -or
      (& $parent -iTO).Trim() -ne 'win64') {
    throw 'the IDE profile is not a Win64 x86-64 compiler'
  }
  $configText = Get-Content -LiteralPath $config -Raw
  If ($configText -notmatch 'MOONCOMPILER_VANILLA_RUNTIME' -or
      $configText -match 'MOONCOMPILER_UNICODE_DEFAULT|MOONBOT_MM_PROFILE_REQUIRED|--pinned-unit') {
    throw 'the IDE profile configuration contains product-ABI options'
  }

  $makePath = Find-DeveloperMake
  $git = (Get-Command git.exe -ErrorAction Stop).Source
  $head = (& $git -C $Root rev-parse HEAD).Trim()
  If ($LASTEXITCODE -ne 0) {
    throw 'could not read Git HEAD for developer-backend provenance'
  }
  $status = @(& $git -C $Root status --short -- compiler)
  If ($LASTEXITCODE -ne 0) {
    throw 'could not read compiler source status for provenance'
  }
  $sourceFingerprint = Get-CompilerSourceFingerprint
  $sourceFiles = @(& $git -C $Root ls-files -co --exclude-standard -- compiler |
    Where-Object {
      Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf
    } |
    Sort-Object -Unique)
  If ($LASTEXITCODE -ne 0 -or $sourceFiles.Count -eq 0) {
    throw 'could not enumerate compiler sources for the isolated build'
  }

  $backend = Join-Path $Root 'dev-backend'
  $newBackend = Join-Path $Root "dev-backend.new.$PID"
  $oldBackend = Join-Path $Root "dev-backend.old.$PID"
  Remove-Item -LiteralPath $newBackend, $oldBackend -Recurse -Force `
    -ErrorAction SilentlyContinue
  try {
    $sourceRoot = Join-Path $newBackend 'source'
    $sourceCompiler = Join-Path $sourceRoot 'compiler'
    New-Item -ItemType Directory -Force -Path $sourceCompiler | Out-Null
    foreach ($relative in $sourceFiles) {
      $destination = Join-Path $sourceRoot $relative
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) |
        Out-Null
      Copy-Item -LiteralPath (Join-Path $Root $relative) -Destination $destination
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $sourceRoot 'rtl') |
      Out-Null

    Push-Location $sourceCompiler
    try {
      Invoke-Checked $msg2inc @('msg\errore.msg', 'msg', 'msg')
    } finally {
      Pop-Location
    }
    Invoke-Checked $makePath @(
      '-C', $sourceCompiler, 'compiler', "FPC=$parent",
      "FPCDIR=$sourceRoot", 'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "OPT=-n @$config -O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME")

    $candidate = Join-Path $sourceCompiler 'ppcx64.exe'
    If (-not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
        (& $candidate -iV).Trim() -ne (& $parent -iV).Trim() -or
        (& $candidate -iTP).Trim() -ne 'x86_64' -or
        (& $candidate -iTO).Trim() -ne 'win64') {
      throw 'the developer backend failed its identity check'
    }

    $smokeDir = Join-Path $newBackend 'smoke'
    $smokeUnits = Join-Path $smokeDir 'units'
    New-Item -ItemType Directory -Force -Path $smokeUnits | Out-Null
    $smokeSource = Join-Path $smokeDir 'backend_smoke.pas'
    [IO.File]::WriteAllText($smokeSource,
      "program backend_smoke;`r`nbegin`r`n  Halt(0);`r`nend.`r`n",
      (New-Object Text.UTF8Encoding($false)))
    Invoke-Checked $candidate @(
      '-n', "@$config", '-B', "-FU$smokeUnits", "-FE$smokeDir", $smokeSource)
    Invoke-Checked (Join-Path $smokeDir 'backend_smoke.exe') @()

    $bin = Join-Path $newBackend 'bin\x86_64-win64'
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $published = Join-Path $bin 'ppcx64.exe'
    Copy-Item -LiteralPath $candidate -Destination $published
    $provenance = @(
      'format=1',
      'platform=x86_64-win64',
      'profile=ide-fpc-abi',
      "git_head=$head",
      "compiler_dirty=$($status.Count -gt 0)",
      "compiler_source_sha256=$sourceFingerprint",
      "parent_backend_sha256=$((Get-FileHash $parent -Algorithm SHA256).Hash.ToLowerInvariant())",
      "parent_config_sha256=$((Get-FileHash $config -Algorithm SHA256).Hash.ToLowerInvariant())",
      "backend_sha256=$((Get-FileHash $published -Algorithm SHA256).Hash.ToLowerInvariant())",
      "built_at_utc=$([DateTime]::UtcNow.ToString('o'))")
    [IO.File]::WriteAllLines((Join-Path $newBackend 'provenance.txt'),
      $provenance, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllLines((Join-Path $newBackend 'git-status.txt'),
      $status, (New-Object Text.UTF8Encoding($false)))

    Remove-Item -LiteralPath $sourceRoot, $smokeDir -Recurse -Force
    Publish-Toolchain -NewToolchain $newBackend -Toolchain $backend `
      -OldToolchain $oldBackend
  } finally {
    If ((Test-Path -LiteralPath $oldBackend) -and
        -not (Test-Path -LiteralPath $backend)) {
      Move-Item -LiteralPath $oldBackend -Destination $backend
    }
    Remove-Item -LiteralPath $newBackend -Recurse -Force `
      -ErrorAction SilentlyContinue
    If (Test-Path -LiteralPath $backend) {
      Remove-Item -LiteralPath $oldBackend -Recurse -Force `
        -ErrorAction SilentlyContinue
    }
  }
  Write-Output "Developer backend: $backend\bin\x86_64-win64\ppcx64.exe"
  Write-Output "Provenance: $backend\provenance.txt"
}

function Install-Toolchain([string]$Archive) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archivePath = [IO.Path]::GetFullPath($Archive)
  If (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "toolchain archive does not exist: $archivePath"
  }
  If ([IO.Path]::GetExtension($archivePath) -ine '.zip') {
    throw 'Win64 toolchain archive must be a .zip file'
  }

  $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
    foreach ($entry in $zip.Entries) {
      $entryPath = $entry.FullName.Replace('\', '/')
      $parts = $entryPath.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
      If ([IO.Path]::IsPathRooted($entryPath) -or $parts -contains '..') {
        throw "unsafe path in toolchain archive: $entryPath"
      }
    }
  } finally {
    $zip.Dispose()
  }

  $newToolchain = Join-Path $Root "toolchain.new.$PID"
  $oldToolchain = Join-Path $Root "toolchain.old.$PID"
  Remove-Item -LiteralPath $newToolchain, $oldToolchain -Recurse -Force `
    -ErrorAction SilentlyContinue
  try {
    [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $newToolchain)
    $bin = Join-Path $newToolchain 'bin\x86_64-win64'
    $ideBin = Join-Path $newToolchain 'ide\bin\x86_64-win64'
    $fpc = Join-Path $bin 'fpc.exe'
    $fpcmkcfg = Join-Path $bin 'fpcmkcfg.exe'
    $fpcres = Join-Path $bin 'fpcres.exe'
    $ideFpc = Join-Path $ideBin 'fpc.exe'
    $ideFpcres = Join-Path $ideBin 'fpcres.exe'
    $compilerLicense = Join-Path $newToolchain 'share\doc\mooncompiler\COMPILER-GPL-2.0.txt'
    $rtlLicense = Join-Path $newToolchain 'share\doc\mooncompiler\RTL-LGPL-2.1.txt'
    $rtlException = Join-Path $newToolchain 'share\doc\mooncompiler\RTL-EXCEPTION.txt'
    $mmLicense = Join-Path $newToolchain 'share\doc\mooncompiler\MM-LICENSE.md'
    $licenseGuide = Join-Path $newToolchain 'share\doc\mooncompiler\LICENSING.md'
    If (-not (Test-Path -LiteralPath $fpc) -or
        -not (Test-Path -LiteralPath $fpcmkcfg) -or
        -not (Test-Path -LiteralPath $fpcres) -or
        -not (Test-Path -LiteralPath $ideFpc) -or
        -not (Test-Path -LiteralPath $ideFpcres) -or
        -not (Test-Path -LiteralPath $compilerLicense) -or
        -not (Test-Path -LiteralPath $rtlLicense) -or
        -not (Test-Path -LiteralPath $rtlException) -or
        -not (Test-Path -LiteralPath $mmLicense) -or
        -not (Test-Path -LiteralPath $licenseGuide)) {
      throw 'the archive is not a complete Win64 x86-64 MoonCompiler toolchain'
    }
    $targetCpu = (& $fpc -iTP).Trim()
    $targetOs = (& $fpc -iTO).Trim()
    $version = (& $fpc -iV).Trim()
    $ideVersion = (& $ideFpc -iV).Trim()
    If ($targetCpu -ne 'x86_64' -or $targetOs -ne 'win64' -or
        $version -ne $ideVersion) {
      throw 'the archive compiler target or IDE profile version is invalid'
    }

    # The archive carries moon-base.cfg and fpc.cfg with $FPCBINDIR-relative
    # paths.  Pinned-unit uses $FPCBINDIR macro — no rewriting needed.
    $baseCfg = Join-Path $bin 'moon-base.cfg'
    $config = Join-Path $bin 'fpc.cfg'
    $ideConfig = Join-Path $ideBin 'fpc.cfg'
    $runtimeMm = Join-Path $newToolchain "runtime\mm\$MmUnit.pas"
    If (-not (Test-Path -LiteralPath $baseCfg) -or
        -not (Test-Path -LiteralPath $config) -or
        -not (Test-Path -LiteralPath $runtimeMm)) {
      throw 'the archive is missing moon-base.cfg, fpc.cfg or the runtime MM source'
    }
    # The IDE profile's fpc.cfg names its toolchain by an absolute path (the
    # gates run the product compiler with this configuration, so it cannot be
    # relative to the compiler's own directory): render it for this clone.
    Write-IdeConfig -Fpcmkcfg $fpcmkcfg -Config $ideConfig

    Publish-Toolchain -NewToolchain $newToolchain -Toolchain $Toolchain `
      -OldToolchain $oldToolchain
  } finally {
    If ((Test-Path -LiteralPath $oldToolchain) -and
        -not (Test-Path -LiteralPath $Toolchain)) {
      Move-Item -LiteralPath $oldToolchain -Destination $Toolchain
    }
    Remove-Item -LiteralPath $newToolchain -Recurse -Force `
      -ErrorAction SilentlyContinue
    If (Test-Path -LiteralPath $Toolchain) {
      Remove-Item -LiteralPath $oldToolchain -Recurse -Force `
        -ErrorAction SilentlyContinue
    }
  }
  Write-Output "MoonCompiler toolchain installed in $Toolchain"
  Ensure-MoonORMot
}

function Build-Lazarus {
  $ideFpc = Join-Path $IdeToolchain 'bin\x86_64-win64\fpc.exe'
  If (-not (Test-Path -LiteralPath $ideFpc)) {
    throw 'the IDE profile is missing; run .\build.ps1 compiler first'
  }
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  If (-not $git) {
    throw 'Git is required to fetch the pinned Lazarus source'
  }
  $source = Join-Path $Root 'lazarus-src'
  If (-not (Test-Path -LiteralPath (Join-Path $source '.git'))) {
    If (Test-Path -LiteralPath $source) {
      throw "the managed Lazarus directory exists but is not a Git checkout: $source"
    }
    Invoke-Checked $git.Source @(
      'clone', '--filter=blob:none', '--no-checkout',
      $LazarusRepository, $source)
    Invoke-Checked $git.Source @('-C', $source, 'checkout', '--detach', $LazarusCommit)
  }
  $head = (& $git.Source -C $source rev-parse HEAD).Trim()
  If ($LASTEXITCODE -ne 0 -or $head -ne $LazarusCommit) {
    throw "managed Lazarus checkout is not at the supported commit $LazarusCommit"
  }

  $bootstrapPath = Find-Bootstrap
  $makePath = Find-Make $bootstrapPath
  $pcp = Join-Path $Root 'lazarus-config'
  New-Item -ItemType Directory -Force -Path $pcp | Out-Null
  $lazbuildOptions = 'LAZBUILDOPTS=--lazarusdir=. --compiler=$(PP) ' +
    '--cpu=$(CPU_TARGET) --os=$(OS_TARGET) --opt="$(OPT)" ' +
    '--pcp="$(MOON_LAZARUS_PCP)"'
  $ideBin = Split-Path -Parent $ideFpc
  $oldPath = $env:Path
  $oldPP = $env:PP
  $oldPpcConfigPath = $env:PPC_CONFIG_PATH
  $oldFpcDir = $env:FPCDIR
  $oldLazarusDir = $env:LAZARUSDIR
  $env:Path = "$ideBin;$oldPath"
  $env:PP = $ideFpc
  $env:PPC_CONFIG_PATH = $ideBin
  Remove-Item Env:FPCDIR -ErrorAction SilentlyContinue
  $env:LAZARUSDIR = $source
  try {
    Invoke-Checked $makePath @('-C', $source, 'clean', "FPC=$ideFpc")
    Invoke-Checked $makePath @('-C', $source, '-j1', 'bigide',
      "FPC=$ideFpc", 'OPT=-O3', "MOON_LAZARUS_PCP=$pcp", $lazbuildOptions)
  } finally {
    $env:Path = $oldPath
    $env:PP = $oldPP
    $env:PPC_CONFIG_PATH = $oldPpcConfigPath
    $env:FPCDIR = $oldFpcDir
    $env:LAZARUSDIR = $oldLazarusDir
  }

  $lazarusExe = Join-Path $source 'lazarus.exe'
  If (-not (Test-Path -LiteralPath $lazarusExe)) {
    throw 'the Lazarus build finished without lazarus.exe'
  }
  $compilerXml = [Security.SecurityElement]::Escape($ideFpc)
  $sourceXml = [Security.SecurityElement]::Escape($source)
  $fpcSourceXml = [Security.SecurityElement]::Escape($Root)
  $makeXml = [Security.SecurityElement]::Escape($makePath)
  Set-Content -LiteralPath (Join-Path $pcp 'environmentoptions.xml') `
    -Encoding UTF8 -Value @"
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <EnvironmentOptions>
    <LazarusDirectory Value="$sourceXml"/>
    <CompilerFilename Value="$compilerXml"/>
    <FPCSourceDirectory Value="$fpcSourceXml"/>
    <MakeFilename Value="$makeXml"/>
    <Version Value="112" Lazarus="4.99"/>
  </EnvironmentOptions>
</CONFIG>
"@
  Write-Output "Lazarus $LazarusCommit built in $source"
  Write-Output 'Launch it with .\lazarus.ps1'
}

If ($Target -eq 'compiler') {
  If ($Profile) {
    throw 'usage: .\build.ps1 compiler'
  }
  Build-Compiler
} elseif ($Target -eq 'backend-dev') {
  If ($Profile -or $Bootstrap) {
    throw 'usage: .\build.ps1 backend-dev [-Make GNU-MAKE]'
  }
  Build-DeveloperBackend
} elseif ($Target -eq 'toolchain') {
  If (-not $Profile -or $Bootstrap -or $Make) {
    throw 'usage: .\build.ps1 toolchain ARCHIVE'
  }
  Install-Toolchain $Profile
} elseif ($Target -eq 'lazarus') {
  If ($Profile) {
    throw 'usage: .\build.ps1 lazarus'
  }
  Build-Lazarus
} else {
  throw "unknown target: $Target`nUsage: .\build.ps1 compiler | backend-dev | toolchain ARCHIVE | lazarus"
}
