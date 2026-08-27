function Get-ProjectTreeOptions {
  param([Parameter(Mandatory = $true)][string]$Path)

  If (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "project source tree does not exist: $Path"
  }
  $directories = @($Path) + @(
    Get-ChildItem -LiteralPath $Path -Directory -Recurse |
      Where-Object FullName -NotMatch '\\(\.git|\.moonbot|build|dcu)(\\|$)' |
      Sort-Object FullName |
      ForEach-Object FullName)
  $result = @()
  foreach ($directory in $directories) {
    $result += "-Fu$directory"
    $result += "-Fi$directory"
  }
  return $result
}

function Resolve-ProjectManifestPath {
  param([string]$ManifestDirectory, [string]$Value)

  If ([IO.Path]::IsPathRooted($Value)) {
    return [IO.Path]::GetFullPath($Value)
  }
  return [IO.Path]::GetFullPath((Join-Path $ManifestDirectory $Value))
}

function Invoke-PinnedDependencyResolver {
  param([string]$Checkout, [string[]]$Sources)

  $python = $null
  $launcherArguments = @()
  If ($env:MOONCOMPILER_PYTHON) {
    $python = (Resolve-Path -LiteralPath $env:MOONCOMPILER_PYTHON).Path
  } elseif ($env:PYTHON) {
    $python = (Resolve-Path -LiteralPath $env:PYTHON).Path
  } else {
    $command = Get-Command py.exe -ErrorAction SilentlyContinue
    If ($command) {
      $python = $command.Source
      $launcherArguments = @('-3')
    }
    foreach ($name in @('python3.exe', 'python3', 'python.exe', 'python')) {
      If ($python) {
        break
      }
      $command = Get-Command $name -ErrorAction SilentlyContinue
      If ($command -and $command.Source -notmatch '\\Microsoft\\WindowsApps\\') {
        $python = $command.Source
      }
    }
  }
  If (-not $python) {
    throw 'Python 3 is required to validate pinned dependency containment; set PYTHON or MOONCOMPILER_PYTHON'
  }
  $arguments = @($launcherArguments) + @(
    (Join-Path $PSScriptRoot 'resolve_pinned_dependency.py'),
    '--checkout', $Checkout,
    '--format', 'json')
  foreach ($source in $Sources) {
    $arguments += @('--source', $source)
  }
  $json = @(& $python @arguments)
  If ($LASTEXITCODE -ne 0) {
    throw "pinned dependency containment resolver failed for $Checkout"
  }
  return @((($json -join "`n") | ConvertFrom-Json))
}

function Get-PinnedProjectDependency {
  param([string]$Spec, [string]$Manifest, [string]$State)

  $parts = $Spec -split '\|', 4
  $hasEmptyPart = @($parts | Where-Object { -not $_ }).Count -ne 0
  If ($parts.Count -ne 4 -or $hasEmptyPart) {
    throw "invalid dependency entry in ${Manifest}: $Spec"
  }
  $name, $url, $commit, $sourceList = $parts
  If ($name -notmatch '^[A-Za-z0-9._-]+$') {
    throw "invalid dependency name in ${Manifest}: $name"
  }
  If ($commit -notmatch '^[0-9a-fA-F]{40}$') {
    throw "dependency must use a full 40-character commit: $name"
  }
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  If (-not $git) {
    $git = Get-Command git -ErrorAction SilentlyContinue
  }
  If (-not $git) {
    throw "git is required to fetch project dependency: $name"
  }

  $destination = Join-Path $State "dependencies\$name\$($commit.ToLowerInvariant())"
  If (-not (Test-Path -LiteralPath (Join-Path $destination '.git'))) {
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary = "$destination.new.$PID"
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    try {
      & $git.Source init -q $temporary
      If ($LASTEXITCODE -ne 0) { throw 'git init failed' }
      & $git.Source -C $temporary remote add origin $url
      If ($LASTEXITCODE -ne 0) { throw 'git remote add failed' }
      & $git.Source -C $temporary fetch -q --depth=1 origin $commit
      If ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }
      & $git.Source -C $temporary checkout -q --detach FETCH_HEAD
      If ($LASTEXITCODE -ne 0) { throw 'git checkout failed' }
      $head = (& $git.Source -C $temporary rev-parse HEAD).Trim()
      If ($head -ine $commit) {
        throw "dependency $name resolved to $head instead of $commit"
      }
      Move-Item -LiteralPath $temporary -Destination $destination
    } catch {
      Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
      throw "could not fetch pinned dependency $name at ${commit}: $_"
    }
  }

  $head = (& $git.Source -C $destination rev-parse HEAD).Trim()
  If ($LASTEXITCODE -ne 0 -or $head -ine $commit) {
    throw "cached dependency $name is at $head instead of $commit"
  }
  $dirty = @(& $git.Source -C $destination status --porcelain --untracked-files=all)
  If ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
    throw "cached dependency is not clean: $destination"
  }

  $options = @()
  $dependencySources = @($sourceList -split ',')
  foreach ($directory in Invoke-PinnedDependencyResolver $destination $dependencySources) {
    $options += "-Fu$directory"
    $options += "-Fi$directory"
  }
  return $options
}

function Resolve-ProjectProfile {
  param(
    [string]$ProjectPath,
    [string]$ProjectDirectory,
    [string]$State
  )

  $manifest = [IO.Path]::ChangeExtension($ProjectPath, '.mooncompiler')
  If (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    return [pscustomobject]@{
      Options = @(Get-ProjectTreeOptions $ProjectDirectory)
      Manifest = $null
    }
  }

  $manifestDirectory = Split-Path -Parent $manifest
  $sources = @()
  $aliases = @()
  $dependencies = @()
  foreach ($rawLine in Get-Content -LiteralPath $manifest -Encoding UTF8) {
    $line = $rawLine.TrimEnd("`r")
    If (-not $line -or $line.StartsWith('#')) {
      continue
    }
    $separator = $line.IndexOf('=')
    If ($separator -le 0 -or $separator -eq $line.Length - 1) {
      throw "invalid line in ${manifest}: $line"
    }
    $key = $line.Substring(0, $separator)
    $value = $line.Substring($separator + 1)
    switch -CaseSensitive ($key) {
      'source' {
        $sources += Resolve-ProjectManifestPath $manifestDirectory $value
      }
      'alias' { $aliases += $value }
      'dependency' { $dependencies += $value }
      default {
        throw "unknown project manifest directive in ${manifest}: $key"
      }
    }
  }

  $options = @("-Fu$ProjectDirectory", "-Fi$ProjectDirectory")
  foreach ($alias in $aliases) {
    If ($alias -notmatch '^[^=]+=[^=]+$') {
      throw "invalid unit alias in ${manifest}: $alias"
    }
    $options += "-Ua$alias"
  }
  foreach ($dependency in $dependencies) {
    $options += Get-PinnedProjectDependency $dependency $manifest $State
  }
  foreach ($source in $sources) {
    $options += Get-ProjectTreeOptions $source
  }

  return [pscustomobject]@{
    Options = $options
    Manifest = $manifest
  }
}
