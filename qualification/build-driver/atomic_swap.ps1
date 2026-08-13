$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $Root 'scripts\Publish-Toolchain.ps1')

$Work = Join-Path ([IO.Path]::GetTempPath()) "mooncompiler-swap-$PID"
$Toolchain = Join-Path $Work 'toolchain'
$OldToolchain = Join-Path $Work 'toolchain.old'
try {
  New-Item -ItemType Directory -Path $Toolchain | Out-Null
  Set-Content -LiteralPath (Join-Path $Toolchain 'sentinel') `
    -Value 'working' -Encoding ascii
  try {
    Publish-Toolchain -NewToolchain (Join-Path $Work 'missing-new') `
      -Toolchain $Toolchain -OldToolchain $OldToolchain
    throw 'publish unexpectedly succeeded'
  } catch {
    If ($_.Exception.Message -eq 'publish unexpectedly succeeded') { throw }
  }
  If ((Get-Content -Raw (Join-Path $Toolchain 'sentinel')).Trim() -ne 'working' -or
      (Test-Path -LiteralPath $OldToolchain)) {
    throw 'working toolchain was not restored'
  }
  Write-Output 'TOOLCHAIN_ATOMIC_SWAP_PASS'
} finally {
  Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}
