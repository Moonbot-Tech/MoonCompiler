param(
  [string]$Compiler = (Join-Path $PSScriptRoot `
    '..\..\toolchain\bin\x86_64-win64\ppcx64.exe'),
  [string]$Config = (Join-Path $PSScriptRoot `
    '..\..\toolchain\bin\x86_64-win64\moon-base.cfg'),
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId
)

# Win64 dynamic packages: build every stage in dependency order, then run the
# hosts and check their exit codes and the lines they must print.
#
# Build order is part of the contract:
#   1. units contained in a package are compiled first, without -FP
#   2. the package (.dpk) is built next and yields <name>.fpl + <name>.fcp
#   3. only hosts consume packages (-FP)
# A host that uses a contained unit without consuming its package links its
# own copy of the class; cross-package `is` then silently returns False. The
# runner derives -FP from each host's `uses` clause so that cannot happen.
#
# Package symbol search (-Fp) is given through the per-stage configuration
# file, which is the path the compiler reads for package directories.

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Config = (Resolve-Path -LiteralPath $Config).Path
$Run = Join-Path $Root "qualification\suite\results\runs\$RunId\dynamic-packages"

If (Test-Path -LiteralPath $Run) { throw "run already exists: $Run" }
New-Item -ItemType Directory -Path $Run | Out-Null

$script:Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
  $script:Failures.Add($Message)
  Write-Host "  [FAIL] $Message"
}

function Invoke-Compiler([string]$Stage, [string]$What, [string[]]$Arguments) {
  $Log = Join-Path $Stage ("compile-" + ($What -replace '[^A-Za-z0-9._-]', '_') + '.log')
  Push-Location $Stage
  try {
    & $Compiler -n '@local.cfg' -vq @Arguments *> $Log
    return $LASTEXITCODE
  } finally {
    Pop-Location
  }
}

function Build-Ok([string]$Stage, [string]$What, [string[]]$Arguments) {
  If ((Invoke-Compiler $Stage $What $Arguments) -ne 0) {
    Get-Content -LiteralPath (Join-Path $Stage ("compile-" + ($What -replace '[^A-Za-z0-9._-]', '_') + '.log')) |
      Select-String -Pattern 'Error|Fatal' | Select-Object -First 8 |
      ForEach-Object { Write-Host "      $_" }
    throw "$(Split-Path -Leaf $Stage)/$What did not compile"
  }
}

function Build-Rejected([string]$Stage, [string]$What, [string]$Message, [string[]]$Arguments) {
  $Code = Invoke-Compiler $Stage $What $Arguments
  $Log = Get-Content -Raw -LiteralPath (Join-Path $Stage ("compile-" + ($What -replace '[^A-Za-z0-9._-]', '_') + '.log'))
  If ($Code -eq 0) {
    Add-Failure "$(Split-Path -Leaf $Stage)/$What compiled but must be rejected with $Message"
  } ElseIf ($Log -notmatch $Message) {
    Add-Failure "$(Split-Path -Leaf $Stage)/$What was rejected, but not with $Message"
  } Else {
    Write-Host "  [OK]   $What rejected with $Message"
  }
}

function Test-Host([string]$Stage, [string]$Exe, [int]$ExitCode, [string[]]$Lines, [string[]]$Arguments = @()) {
  $Log = Join-Path $Stage ($Exe + '.run.log')
  Push-Location $Stage
  try {
    & ".\$Exe" @Arguments *> $Log
    $Code = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  $Text = Get-Content -Raw -LiteralPath $Log
  If ($null -eq $Text) { $Text = '' }
  If ($Code -ne $ExitCode) {
    Add-Failure "$(Split-Path -Leaf $Stage)/$Exe exited $Code, expected $ExitCode"
    return $Text
  }
  foreach ($Line in $Lines) {
    If (-not $Text.Contains($Line)) {
      Add-Failure "$(Split-Path -Leaf $Stage)/$Exe did not print '$Line'"
      return $Text
    }
  }
  Write-Host "  [OK]   $Exe exit $Code"
  return $Text
}

function New-Stage([string]$Name) {
  $Stage = Join-Path $Run $Name
  New-Item -ItemType Directory -Path $Stage | Out-Null
  Copy-Item -Path (Join-Path $PSScriptRoot "$Name\*") -Destination $Stage
  @(
    "#INCLUDE $Config",
    '-Fp.',
    '-Fu.',
    '-FE.',
    '-FU.',
    '-FcUTF8'
  ) | Set-Content -LiteralPath (Join-Path $Stage 'local.cfg') -Encoding ascii
  Write-Host "--- $Name ---"
  return $Stage
}

# Build every package of a stage. $Packages is ordered by dependency; each
# entry is @(name, image base, contained units...).
function Build-Packages([string]$Stage, [object[]]$Packages) {
  Push-Location $Stage
  try {
    foreach ($Package in $Packages) {
      $Name = $Package[0]
      foreach ($Unit in ($Package | Select-Object -Skip 2)) {
        Build-Ok $Stage "$Unit.pas" @("$Unit.pas")
      }
      Build-Ok $Stage "$Name.dpk" @("-WB$($Package[1])", "$Name.dpk")
      foreach ($Ext in @('fpl', 'fcp')) {
        If (-not (Test-Path -LiteralPath "$Name.$Ext")) {
          Add-Failure "$(Split-Path -Leaf $Stage)/$Name.dpk produced no $Name.$Ext"
        }
      }
      Write-Host "  [OK]   $Name.fpl"
    }
  } finally {
    Pop-Location
  }
}

# Build a host with -FP for rtlpkg and for every package whose contained
# unit appears in the host's uses clause.
function Build-Host([string]$Stage, [string]$Source, [object[]]$Packages, [string[]]$Extra = @()) {
  Push-Location $Stage
  try {
    $Text = Get-Content -Raw -LiteralPath $Source
    $Arguments = @('-FPrtlpkg')
    foreach ($Package in $Packages) {
      If ($Package[0] -eq 'rtlpkg') { continue }
      foreach ($Unit in ($Package | Select-Object -Skip 2)) {
        If ($Text -match "(?m)^\s*$Unit\s*[,;]") {
          $Arguments += "-FP$($Package[0])"
          break
        }
      }
    }
    Build-Ok $Stage $Source ($Arguments + $Extra + @($Source))
  } finally {
    Pop-Location
  }
}

function Test-PackageFlags([string]$Stage, [string]$Library, [int]$Expected) {
  $Text = Test-Host $Stage 'Probe.exe' 0 @() @($Library)
  $Match = [regex]::Match($Text, 'PACKAGEFLAGS\s*=\s*(\d+)')
  If (-not $Match.Success) {
    Add-Failure "Probe $Library printed no PACKAGEFLAGS"
  } ElseIf ([int]$Match.Groups[1].Value -ne $Expected) {
    Add-Failure "Probe $Library PACKAGEFLAGS = $($Match.Groups[1].Value), expected $Expected"
  }
}

try {
  # Stage 1: a package that requires the RTL package imports from it.
  $Stage = New-Stage 'stage1'
  $Packages = @(@('rtlpkg', '110000000'), @('TestPkg', '120000000', 'PkgUnit'))
  Build-Packages $Stage $Packages
  Build-Host $Stage 'host.pas' $Packages
  Test-Host $Stage 'host.exe' 0 @('hello from package', 'host ok') | Out-Null

  # Stage 2: inheritance, virtual dispatch, is/as across two packages.
  $Stage = New-Stage 'stage2'
  $Packages = @(@('rtlpkg', '110000000'), @('CommonPkg', '120000000', 'BaseUnit'),
    @('SalesPkg', '130000000', 'SalesUnit'))
  Build-Packages $Stage $Packages
  Build-Host $Stage 'host2.pas' $Packages
  Test-Host $Stage 'host2.exe' 0 @('sales(base:acme)', 'host2 ok') | Out-Null
  # a published field whose class lives in a package
  Build-Host $Stage 'host_fields.pas' $Packages
  Test-Host $Stage 'host_fields.exe' 0 @('host_fields ok') | Out-Null

  # Stage 3: unit initialization inside a load-time package.
  $Stage = New-Stage 'stage3'
  $Packages = @(@('rtlpkg', '110000000'), @('CommonPkg', '120000000', 'InitUnit'))
  Build-Packages $Stage $Packages
  Build-Host $Stage 'host3.pas' $Packages
  Test-Host $Stage 'host3.exe' 0 @() | Out-Null

  # Stage 3rt: run-time LoadPackage/GetClass/UnloadPackage.
  $Stage = New-Stage 'stage3rt'
  $Packages = @(@('rtlpkg', '110000000'), @('CommonPkg', '120000000', 'SharedIntf'),
    @('SalesPkg', '130000000', 'SalesUnit'), @('LazyPkg', '140000000', 'LazyUnit'),
    @('PlainPkg', '150000000', 'PlainUnit'))
  Build-Packages $Stage $Packages
  foreach ($H in @('host5', 'host6', 'host7', 'host10', 'host11', 'host12')) {
    Build-Host $Stage "$H.pas" $Packages
  }
  Test-Host $Stage 'host5.exe' 0 @() | Out-Null
  Test-Host $Stage 'host6.exe' 0 @('host6 ok') | Out-Null
  Test-Host $Stage 'host7.exe' 0 @() | Out-Null
  Test-Host $Stage 'host10.exe' 0 @() | Out-Null
  Test-Host $Stage 'host11.exe' 0 @() | Out-Null
  Test-Host $Stage 'host12.exe' 0 @() | Out-Null

  # Stage 4: package kinds, PACKAGEFLAGS, design-time registration, unload.
  $Stage = New-Stage 'stage4'
  $Packages = @(@('rtlpkg', '110000000'), @('BasePkg', '120000000', 'BaseRegUnit'),
    @('RegPkg', '130000000', 'RegUnit', 'RegUnit2'), @('Reg2Pkg', '140000000', 'Reg2Unit'),
    @('RunPkg', '150000000', 'PlainUnit'), @('DirOk', '160000000'), @('DirRun', '170000000'))
  Build-Packages $Stage $Packages
  Push-Location $Stage
  try {
    Build-Rejected $Stage 'DirBad.dpk' '13030' @('-WB180000000', 'DirBad.dpk')
    Build-Rejected $Stage 'Host1.pas' '13031' @('-FPDirOk', 'Host1.pas')
    If (Test-Path -LiteralPath 'Host1.exe') {
      Add-Failure 'stage4/Host1.exe exists although linking a design-only package must fail'
    }
  } finally {
    Pop-Location
  }
  # host13/host14 link rtlpkg only: linking BasePkg would pin it and the
  # dependency-unmap case they cover would not happen.
  foreach ($H in @('host13', 'host14', 'Probe')) {
    Build-Ok $Stage "$H.pas" @('-FPrtlpkg', "$H.pas")
  }
  Test-PackageFlags $Stage 'DirOk.fpl' 1
  Test-PackageFlags $Stage 'DirRun.fpl' 0
  Test-PackageFlags $Stage 'RunPkg.fpl' 2
  Test-Host $Stage 'host13.exe' 0 @() | Out-Null
  Test-Host $Stage 'host14.exe' 0 @() | Out-Null
} catch {
  Add-Failure $_.Exception.Message
}

If ($script:Failures.Count -gt 0) {
  $script:Failures | Set-Content -LiteralPath (Join-Path $Run 'failures.txt') -Encoding utf8
  Write-Host "dynamic-packages: $($script:Failures.Count) failure(s); logs in $Run"
  exit 1
}
Write-Host "dynamic-packages: all checks passed; logs in $Run"
