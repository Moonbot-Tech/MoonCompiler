[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$LazarusArguments
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$State = Join-Path $Root '.moonbot'
$IdeToolchain = Join-Path $State 'toolchain\ide'
$IdeFpc = Join-Path $IdeToolchain 'bin\x86_64-win64\fpc.exe'
$LazarusSource = Join-Path $State 'lazarus'
$LazarusExe = Join-Path $LazarusSource 'lazarus.exe'
$PrimaryConfig = Join-Path $State 'lazarus-config'

If (-not (Test-Path -LiteralPath $IdeFpc)) {
  & (Join-Path $Root 'build.ps1') compiler
}
If (-not (Test-Path -LiteralPath $LazarusExe)) {
  & (Join-Path $Root 'build.ps1') lazarus
}

$oldPath = $env:Path
$oldPP = $env:PP
$oldPpcConfigPath = $env:PPC_CONFIG_PATH
$oldFpcDir = $env:FPCDIR
$oldLazarusDir = $env:LAZARUSDIR
$env:Path = "$(Split-Path -Parent $IdeFpc);$oldPath"
$env:PP = $IdeFpc
$env:PPC_CONFIG_PATH = Split-Path -Parent $IdeFpc
Remove-Item Env:FPCDIR -ErrorAction SilentlyContinue
$env:LAZARUSDIR = $LazarusSource
try {
  & $LazarusExe "--pcp=$PrimaryConfig" @LazarusArguments
  exit $LASTEXITCODE
} finally {
  $env:Path = $oldPath
  $env:PP = $oldPP
  $env:PPC_CONFIG_PATH = $oldPpcConfigPath
  $env:FPCDIR = $oldFpcDir
  $env:LAZARUSDIR = $oldLazarusDir
}
