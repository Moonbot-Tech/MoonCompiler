param(
  [string]$Compiler = "$PSScriptRoot\..\..\..\.moonbot\toolchain\bin\x86_64-win64\fpc.exe",
  [string]$Config = "$PSScriptRoot\..\..\..\.moonbot\toolchain\bin\x86_64-win64\fpc.cfg"
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..").Path
$Output = (Resolve-Path "$PSScriptRoot\..\..\..").Path + '\.qualification\extra-corpus'
Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue

foreach ($Option in @('O2', 'O3')) {
  $Target = Join-Path $Output $Option
  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  & $Compiler -n "@$Config" -B "-$Option" '-Mobjfpc' `
    "-FU$Target" "-FE$Target" (Join-Path $Root 'tests\corpus-extra\tgeneric131.pp') `
    *> (Join-Path $Target 'tgeneric131.log')
  If ($LASTEXITCODE -eq 0) {
    throw "tgeneric131 $Option unexpectedly lost its recorded Win64 deviation"
  }
  If (-not (Select-String -LiteralPath (Join-Path $Target 'tgeneric131.log') `
      -SimpleMatch 'Interface type Intf has no valid GUID' -Quiet)) {
    throw "tgeneric131 $Option failed differently"
  }
  & $Compiler -n "@$Config" -B "-$Option" '-Mdelphi' `
    "-FU$Target" "-FE$Target" (Join-Path $Root 'tests\corpus-extra\delphi_tb0728.pas') `
    *> (Join-Path $Target 'delphi_tb0728.log')
  If ($LASTEXITCODE -ne 0) { throw "delphi_tb0728 $Option failed" }
  & (Join-Path $Target 'delphi_tb0728.exe') *> (Join-Path $Target 'delphi_tb0728.out')
  If ($LASTEXITCODE -ne 0 -or
      -not (Select-String -LiteralPath (Join-Path $Target 'delphi_tb0728.out') `
        -SimpleMatch 'DELPHI_TB0728_OK' -Quiet)) {
    throw "delphi_tb0728 $Option runtime failed"
  }
}
Write-Output 'extra corpus Win64: PASS'
