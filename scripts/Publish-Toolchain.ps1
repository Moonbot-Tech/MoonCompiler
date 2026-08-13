function Publish-Toolchain {
  param(
    [Parameter(Mandatory = $true)][string]$NewToolchain,
    [Parameter(Mandatory = $true)][string]$Toolchain,
    [Parameter(Mandatory = $true)][string]$OldToolchain
  )

  If (Test-Path -LiteralPath $Toolchain) {
    Move-Item -LiteralPath $Toolchain -Destination $OldToolchain
  }
  try {
    Move-Item -LiteralPath $NewToolchain -Destination $Toolchain
  } catch {
    If ((Test-Path -LiteralPath $OldToolchain) -and
        -not (Test-Path -LiteralPath $Toolchain)) {
      Move-Item -LiteralPath $OldToolchain -Destination $Toolchain
    }
    throw
  }
  Remove-Item -LiteralPath $OldToolchain -Recurse -Force `
    -ErrorAction SilentlyContinue
}
