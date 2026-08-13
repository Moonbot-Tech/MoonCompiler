param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Destination = Join-Path $Root '.qualification\deps\mormot2-compiler-corpus'
$Commit = 'bc189414f1b9ea163d24029cc8e814405e8e0cb5'
$Url = 'https://github.com/synopse/mORMot2.git'

If (Test-Path $Destination) {
  $Actual = (& git -C $Destination rev-parse HEAD 2>$null)
  $Dirty = (& git -C $Destination status --porcelain 2>$null)
  If ($LASTEXITCODE -eq 0 -and $Actual -eq $Commit -and -not $Dirty) {
    Write-Output "mORMot compiler corpus is ready: $Commit"
    Exit 0
  }
  throw "Dependency directory is not clean mORMot $Commit`: $Destination"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
& git init --quiet $Destination
& git -C $Destination remote add origin $Url
& git -C $Destination fetch --quiet --depth=1 origin $Commit
& git -C $Destination checkout --quiet --detach FETCH_HEAD
$Actual = (& git -C $Destination rev-parse HEAD)
If ($Actual -ne $Commit) {
  throw "Expected mORMot $Commit, got $Actual"
}
If (& git -C $Destination status --porcelain) {
  throw "Prepared mORMot worktree is dirty: $Destination"
}
Write-Output "mORMot compiler corpus is ready: $Commit"
