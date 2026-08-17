param(
  [string]$Compiler = (Join-Path $PSScriptRoot `
    '..\..\.moonbot\toolchain\bin\x86_64-win64\ppcx64.exe'),
  [string]$Config = (Join-Path $PSScriptRoot `
    '..\..\.moonbot\toolchain\bin\x86_64-win64\fpc.cfg'),
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Config = (Resolve-Path -LiteralPath $Config).Path
$Source = (Resolve-Path (Join-Path $PSScriptRoot 'stack_header_probe.pas')).Path
$Run = Join-Path $Root "qualification\suite\results\runs\$RunId\win-stack-default"

If (Test-Path -LiteralPath $Run) { throw "run already exists: $Run" }
New-Item -ItemType Directory -Path $Run | Out-Null

function Get-StackHeader([string]$Executable) {
  $Bytes = [IO.File]::ReadAllBytes($Executable)
  $PeOffset = [BitConverter]::ToInt32($Bytes, 0x3c)
  If ([Text.Encoding]::ASCII.GetString($Bytes, $PeOffset, 4) -cne "PE`0`0") {
    throw "$Executable is not a PE image"
  }
  $Optional = $PeOffset + 24
  $Magic = [BitConverter]::ToUInt16($Bytes, $Optional)
  If ($Magic -ne 0x20b) { throw "$Executable is not PE32+" }
  return @{
    Reserve = [BitConverter]::ToUInt64($Bytes, $Optional + 72)
    Commit = [BitConverter]::ToUInt64($Bytes, $Optional + 80)
  }
}

function Invoke-Case(
  [string]$Linker,
  [string]$Name,
  [string[]]$Options,
  [UInt64]$Reserve,
  [UInt64]$Commit
) {
  $Case = Join-Path $Run "$Linker-$Name"
  New-Item -ItemType Directory -Path $Case | Out-Null
  $Executable = Join-Path $Case 'stack_header_probe.exe'
  $LinkerOption = If ($Linker -eq 'internal') { '-Xi' } Else { '-Xe' }
  & $Compiler -n "@$Config" -B -Twin64 -Px86_64 -Mdelphi $LinkerOption `
    @Options "-FU$Case" "-FE$Case" "-o$Executable" $Source `
    *> (Join-Path $Case 'compile.log')
  If ($LASTEXITCODE -ne 0) { throw "$Linker/$Name did not compile" }
  If ($Linker -eq 'internal') {
    & $Executable *> (Join-Path $Case 'run.log')
    If (($LASTEXITCODE -ne 0) -or
        ((Get-Content -Raw (Join-Path $Case 'run.log')).Trim() -cne
          'STACK_HEADER_PROBE_OK')) {
      throw "$Linker/$Name did not run"
    }
  }
  $Header = Get-StackHeader $Executable
  If (($Header.Reserve -ne $Reserve) -or ($Header.Commit -ne $Commit)) {
    throw "$Linker/$Name stack header is reserve=$($Header.Reserve) commit=$($Header.Commit), expected reserve=$Reserve commit=$Commit"
  }
  "$Linker`t$Name`t$($Header.Reserve)`t$($Header.Commit)" |
    Add-Content -LiteralPath (Join-Path $Run 'results.tsv') -Encoding ascii
}

"linker`tcase`treserve`tcommit" |
  Set-Content -LiteralPath (Join-Path $Run 'results.tsv') -Encoding ascii
foreach ($Linker in @('internal', 'external')) {
  Invoke-Case $Linker 'default' @() 1048576 16384
  Invoke-Case $Linker 'command-reserve' @('-Cs2097152') 2097152 16384
  Invoke-Case $Linker 'memory-directive' @('-dUSE_MEMORY_DIRECTIVE') 4194304 16384
  Invoke-Case $Linker 'stack-directives' @('-dUSE_STACK_DIRECTIVES') 3145728 32768
}

$Inputs = @($Compiler, $Config, $Source)
$Inputs += Get-ChildItem -File -Recurse -LiteralPath $Run |
  ForEach-Object { $_.FullName }
$Inputs | Sort-Object -Unique | ForEach-Object {
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
  "$Hash *$([IO.Path]::GetFullPath($_))"
} | Set-Content -LiteralPath (Join-Path $Run 'SHA256SUMS') -Encoding ascii

Write-Output 'WIN_STACK_DEFAULT_GATE_OK linkers=2 cases=4 headers=8 runtime=4'
