[CmdletBinding()]
param(
  [Parameter(Position = 0, Mandatory = $true)]
  [string]$Target,

  [Parameter(Position = 1)]
  [string]$Profile,

  [string]$Bootstrap,
  [string]$Make,
  [switch]$DiagnosticMM
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = $PSScriptRoot
$State = Join-Path $Root '.moonbot'
$Toolchain = Join-Path $State 'toolchain'
$IdeToolchain = Join-Path $Toolchain 'ide'
$MmSource = Join-Path $Root 'runtime\mm\mormot.core.fpcx64mm.pas'
$MmUnit = 'mormot.core.fpcx64mm'
$LazarusRepository = 'https://gitlab.com/freepascal.org/lazarus/lazarus.git'
$LazarusCommit = 'ce01e71c34866d83f69ea7cd855ae7eabea49f38'
. (Join-Path $Root 'scripts\Publish-Toolchain.ps1')
. (Join-Path $Root 'scripts\Project-Profile.ps1')

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
  $found = Get-Command fpc.exe -ErrorAction SilentlyContinue
  If ($found) {
    return $found.Source
  }
  throw 'FPC 3.2.2 is required once. Pass -Bootstrap or set MOONBOT_BOOTSTRAP_FPC.'
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
  $oldPath = $env:Path
  $env:Path = "$bootstrapDir;$oldPath"

  New-Item -ItemType Directory -Force -Path $State | Out-Null
  $newToolchain = Join-Path $State "toolchain.new.$PID"
  $oldToolchain = Join-Path $State "toolchain.old.$PID"
  $ideProfile = Join-Path $State "ide-profile.new.$PID"
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
      'OPT=-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', $Root, 'install', "FPC=$bootstrapPath",
      'OPT=-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain")

    # Preserve the ordinary FPC ABI before the product Unicode RTL replaces
    # the installed units.  Lazarus, LCL and compiler tools are built against
    # this profile; product applications continue to use the default profile.
    Copy-Item -LiteralPath $newToolchain -Destination $ideProfile -Recurse

    $fpc = Join-Path $newToolchain 'bin\x86_64-win64\fpc.exe'
    $targetCompiler = Join-Path $newToolchain 'bin\x86_64-win64\ppcx64.exe'
    $config = Join-Path $newToolchain 'bin\x86_64-win64\fpc.cfg'
    $ideConfig = Join-Path $ideProfile 'bin\x86_64-win64\fpc.cfg'
    If (-not (Test-Path -LiteralPath $fpc) -or
        -not (Test-Path -LiteralPath $targetCompiler)) {
      throw 'the installed Win64 toolchain is incomplete'
    }

    # Compiler/IDE tools keep their host representation.  The target RTL and
    # application-facing packages use the modern Delphi Unicode ABI.
    $unicodeOptions = 'OPT=-O2 -dMOONCOMPILER_VANILLA_RUNTIME -dUNICODERTL -dFPC_OS_UNICODE -dENABLE_DELPHI_RTTI -dMOONCOMPILER_DELPHI_CALLBACK_TYPES'
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'clean', "FPC=$targetCompiler",
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), '-j1', 'all', "FPC=$targetCompiler",
      $unicodeOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'install', "FPC=$targetCompiler",
      $unicodeOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain")
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
      "INSTALL_PREFIX=$newToolchain")

    Invoke-Checked $fpcmkcfg @(
      '-d', "basepath=$Toolchain", '-o', $config)
    Add-Content -LiteralPath $config -Encoding Ascii -Value @(
      '# MoonCompiler project ABI: Delphi String and Char are Unicode.',
      '-dMOONCOMPILER_UNICODE_DEFAULT',
      '# Product programs receive the bundled runtime prefix automatically.',
      '-dMOONBOT_MM_PROFILE_REQUIRED',
      '-dFPCMM_BOOSTER',
      '-dFPCMM_MOONSHARD',
      "--pinned-unit=$MmUnit=$MmSource")
    Invoke-Checked $fpcmkcfg @(
      '-d', "basepath=$IdeToolchain", '-o', $ideConfig)
    Add-Content -LiteralPath $ideConfig -Encoding Ascii -Value @(
      '# MoonCompiler IDE ABI: ordinary FPC String and Char representation.',
      '# Do not inject the product memory manager or runtime prefix.',
      '-dMOONCOMPILER_VANILLA_RUNTIME')
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

  New-Item -ItemType Directory -Force -Path $State | Out-Null
  $newToolchain = Join-Path $State "toolchain.new.$PID"
  $oldToolchain = Join-Path $State "toolchain.old.$PID"
  Remove-Item -LiteralPath $newToolchain, $oldToolchain -Recurse -Force `
    -ErrorAction SilentlyContinue
  try {
    [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $newToolchain)
    $bin = Join-Path $newToolchain 'bin\x86_64-win64'
    $ideBin = Join-Path $newToolchain 'ide\bin\x86_64-win64'
    $fpc = Join-Path $bin 'fpc.exe'
    $fpcmkcfg = Join-Path $bin 'fpcmkcfg.exe'
    $ideFpc = Join-Path $ideBin 'fpc.exe'
    $compilerLicense = Join-Path $newToolchain 'share\doc\mooncompiler\COMPILER-GPL-2.0.txt'
    $rtlLicense = Join-Path $newToolchain 'share\doc\mooncompiler\RTL-LGPL-2.1.txt'
    $rtlException = Join-Path $newToolchain 'share\doc\mooncompiler\RTL-EXCEPTION.txt'
    $mmLicense = Join-Path $newToolchain 'share\doc\mooncompiler\MM-LICENSE.md'
    $licenseGuide = Join-Path $newToolchain 'share\doc\mooncompiler\LICENSING.md'
    If (-not (Test-Path -LiteralPath $fpc) -or
        -not (Test-Path -LiteralPath $fpcmkcfg) -or
        -not (Test-Path -LiteralPath $ideFpc) -or
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

    $config = Join-Path $bin 'fpc.cfg'
    $ideConfig = Join-Path $ideBin 'fpc.cfg'
    Invoke-Checked $fpcmkcfg @('-d', "basepath=$Toolchain", '-o', $config)
    Add-Content -LiteralPath $config -Encoding Ascii -Value @(
      '# MoonCompiler project ABI: Delphi String and Char are Unicode.',
      '-dMOONCOMPILER_UNICODE_DEFAULT',
      '# Product programs receive the bundled runtime prefix automatically.',
      '-dMOONBOT_MM_PROFILE_REQUIRED',
      '-dFPCMM_BOOSTER',
      '-dFPCMM_MOONSHARD',
      "--pinned-unit=$MmUnit=$MmSource")
    Invoke-Checked $fpcmkcfg @('-d', "basepath=$IdeToolchain", '-o', $ideConfig)
    Add-Content -LiteralPath $ideConfig -Encoding Ascii -Value @(
      '# MoonCompiler IDE ABI: ordinary FPC String and Char representation.',
      '# Do not inject the product memory manager or runtime prefix.',
      '-dMOONCOMPILER_VANILLA_RUNTIME')

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
  $source = Join-Path $State 'lazarus'
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
  $pcp = Join-Path $State 'lazarus-config'
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

function Get-ProjectId([string]$Project) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Project))
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally {
    $sha.Dispose()
  }
}

function Build-Project(
  [string]$Project,
  [string]$BuildProfile,
  [bool]$UseDiagnosticMM
) {
  If ($BuildProfile -notin @('debug', 'release')) {
    throw 'project profile must be debug or release'
  }
  $projectPath = [IO.Path]::GetFullPath($Project)
  If (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw "project does not exist: $projectPath"
  }
  If ([IO.Path]::GetExtension($projectPath) -ine '.dpr') {
    throw 'the project must be a .dpr file'
  }
  $fpc = Join-Path $Toolchain 'bin\x86_64-win64\fpc.exe'
  $config = Join-Path $Toolchain 'bin\x86_64-win64\fpc.cfg'
  If (-not (Test-Path -LiteralPath $fpc) -or
      -not (Test-Path -LiteralPath $config)) {
    throw 'MoonCompiler is not built. Run .\build.ps1 compiler first.'
  }

  $projectDir = Split-Path -Parent $projectPath
  $projectId = Get-ProjectId $projectPath
  $runtimeMode = 'normal'
  $diagnosticOptions = @()
  If ($UseDiagnosticMM) {
    $runtimeMode = 'diagnostic-mm'
    $diagnosticOptions = @('-dFPCX64MM_DIAGNOSTIC')
  }
  $unitDir = Join-Path $State "units\win64\$projectId\$BuildProfile\$runtimeMode"
  $appUnitDir = Join-Path $unitDir 'app'
  New-Item -ItemType Directory -Force -Path $appUnitDir | Out-Null
  $namespaceOptions = @(
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
    '-UaSystem.RTLConsts=RTLConsts')
  If ($BuildProfile -eq 'debug') {
    $profileOptions = @('-dDEBUG', '-uRELEASE', '-O-', '-gl', '-gw3', '-Ci', '-Co-', '-Cr-', '-Ct-', '-Sa')
  } else {
    $profileOptions = @('-dRELEASE', '-uDEBUG', '-O3', '-gl', '-gw3', '-Ci', '-Co-', '-Cr-', '-Ct-', '-Sa-')
  }
  $options = @(
    '-n', "@$config", '-Mdelphi',
    '-Municodestrings', '-MduplicateLocals', '-Madvancedrecords',
    '-Marrayoperators', '-Munderscoreisseparator', '-Mfunctionreferences',
    '-Manonymousfunctions', '-Minlinevars', '-Mimplicitgenerics', '-Mautoderef',
    '-Px86_64', '-Twin64', '-Rintel', '-B',
    '-dMOONBOT_MM_PROFILE_REQUIRED', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD',
    "--pinned-unit=$MmUnit=$MmSource")
  $options += $namespaceOptions
  $options += @("-FU$appUnitDir", "-FE$projectDir")

  $projectProfile = Resolve-ProjectProfile $projectPath $projectDir $State
  $options += $projectProfile.Options
  $options += $profileOptions
  $options += $diagnosticOptions

  Write-Output "building $projectPath ($BuildProfile, $runtimeMode, Win64 x86-64)"
  Invoke-Checked $fpc ($options + @($projectPath))
}

If ($Target -eq 'compiler') {
  If ($Profile -or $DiagnosticMM) {
    throw 'usage: .\build.ps1 compiler'
  }
  Build-Compiler
} elseif ($Target -eq 'toolchain') {
  If (-not $Profile -or $Bootstrap -or $Make -or $DiagnosticMM) {
    throw 'usage: .\build.ps1 toolchain ARCHIVE'
  }
  Install-Toolchain $Profile
} elseif ($Target -eq 'lazarus') {
  If ($Profile -or $DiagnosticMM) {
    throw 'usage: .\build.ps1 lazarus'
  }
  Build-Lazarus
} else {
  Build-Project $Target $Profile $DiagnosticMM.IsPresent
}
