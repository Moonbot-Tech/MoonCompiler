param()
$ErrorActionPreference = 'Stop'
$Repository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ('moon-clone-contract-' + [guid]::NewGuid().ToString('N'))
$SavedConfig = @{}
foreach ($Name in @('GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0')) {
  $SavedConfig[$Name] = [Environment]::GetEnvironmentVariable($Name)
}
try {
  New-Item -ItemType Directory -Path $Fixture | Out-Null
  $Source = Join-Path $Fixture 'source'
  git init --quiet $Source
  If ($LASTEXITCODE -ne 0) { throw 'fixture init failed' }
  git -C $Source -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet --allow-empty -m fixture
  If ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }
  # Execute the real function without building a compiler or touching the user's mormot.
  $Tokens = $null
  $Errors = $null
  $Ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'build.ps1'), [ref]$Tokens, [ref]$Errors)
  $Function = $Ast.Find({ param($Node)
    $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Ensure-MoonORMot'
  }, $false)
  Invoke-Expression $Function.Extent.Text
  $env:GIT_CONFIG_COUNT = '1'
  $env:GIT_CONFIG_KEY_0 = 'url.' + ($Source -replace '\\', '/') + '.insteadOf'
  $env:GIT_CONFIG_VALUE_0 = 'https://github.com/Moonbot-Tech/MoonORMot'
  $Root = Join-Path $Fixture 'success'
  New-Item -ItemType Directory -Path $Root | Out-Null
  & { Ensure-MoonORMot } 2>&1 | Tee-Object -FilePath (Join-Path $Fixture 'success.log') | Out-Null
  If (-not (Test-Path (Join-Path $Root 'mormot\.git'))) { throw 'clone did not complete' }
  If ($ErrorActionPreference -ne 'Stop') { throw 'error preference leaked' }
  $Root = Join-Path $Fixture 'failure'
  New-Item -ItemType Directory -Path $Root | Out-Null
  $env:GIT_CONFIG_KEY_0 = 'url.' + (($Source + '-missing') -replace '\\', '/') + '.insteadOf'
  & { Ensure-MoonORMot } 2>&1 3>&1 | Tee-Object -FilePath (Join-Path $Fixture 'failure.log') | Out-Null
  If (-not (Select-String -Quiet -Path (Join-Path $Fixture 'failure.log') -Pattern 'MoonORMot clone failed')) {
    throw 'nonzero Git exit was not reported'
  }
  If ($ErrorActionPreference -ne 'Stop') { throw 'failure path leaked error preference' }
  Write-Output 'MOONORMOT_CLONE_CONTRACT_OK'
} finally {
  foreach ($Name in $SavedConfig.Keys) { [Environment]::SetEnvironmentVariable($Name, $SavedConfig[$Name]) }
  $Resolved = [IO.Path]::GetFullPath($Fixture)
  $Temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  If (-not $Resolved.StartsWith($Temp, [StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $Resolved) -notlike 'moon-clone-contract-*') { throw 'unsafe fixture cleanup' }
  Remove-Item -LiteralPath $Resolved -Recurse -Force
}
exit 0
