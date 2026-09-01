[CmdletBinding()]
param(
  [string]$Destination = (Join-Path $env:LOCALAPPDATA `
      'MoonCompiler\bootstrap\3.2.2')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Version = '3.2.2'
$Url = 'https://downloads.freepascal.org/fpc/dist/3.2.2/i386-win32/' + `
  'fpc-3.2.2.win32.and.win64.exe'
$ExpectedSha256 = `
  '8C255390544B051388B577EB61C6191A04883264AFE0E3369B3600A56DAF7BDE'
$Bin = Join-Path $Destination 'bin\i386-win32'
$Bootstrap = Join-Path $Bin 'fpc.exe'
$RequiredTools = @(
  'make.exe',
  'fpcmkcfg.exe',
  'x86_64-win64-ar.exe',
  'x86_64-win64-as.exe',
  'x86_64-win64-ld.exe',
  'x86_64-win64-nm.exe',
  'x86_64-win64-objcopy.exe',
  'x86_64-win64-objdump.exe',
  'x86_64-win64-strip.exe',
  'x86_64-win64-windres.exe'
)

function Test-Bootstrap {
  If (-not (Test-Path -LiteralPath $Bootstrap)) {
    return $false
  }
  foreach ($Tool in $RequiredTools) {
    If (-not (Test-Path -LiteralPath (Join-Path $Bin $Tool))) {
      return $false
    }
  }
  return ((& $Bootstrap -iV).Trim() -eq $Version)
}

If (-not (Test-Bootstrap)) {
  $Installer = Join-Path ([IO.Path]::GetTempPath()) `
    'fpc-3.2.2.win32.and.win64.exe'
  $Download = $true
  If (Test-Path -LiteralPath $Installer) {
    $Actual = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash
    $Download = ($Actual -ne $ExpectedSha256)
  }
  If ($Download) {
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Installer
  }
  $Actual = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash
  If ($Actual -ne $ExpectedSha256) {
    throw "FPC installer checksum mismatch: $Actual"
  }

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $Process = Start-Process -FilePath $Installer -ArgumentList @(
      '/verysilent', '/norestart', "/dir=`"$Destination`"") `
    -Wait -PassThru -WindowStyle Hidden
  If ($Process.ExitCode -ne 0) {
    throw "FPC installer failed with exit code $($Process.ExitCode)"
  }
  If (-not (Test-Bootstrap)) {
    throw "FPC $Version bootstrap installation is incomplete: $Destination"
  }
}

Write-Output $Bootstrap
