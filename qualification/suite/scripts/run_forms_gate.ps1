param(
  [Parameter(Mandatory = $true)][string]$Compiler,
  [Parameter(Mandatory = $true)][string]$Config,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Config = (Resolve-Path -LiteralPath $Config).Path
$Run = Join-Path $Root "results\runs\$RunId\forms"
$SummaryOracle = Join-Path $Root 'tests\mega\forms_expected_win64.tsv'
$Seeds = @('1', '2', '3', '7885642623054963745',
  '11400714819323198485', '18446744073709551615')
$ExpectedCommon = @(
  'fb1-nan-not-ge', 'fb1-nan-not-lt', 'fb3-braid-demorgan',
  'fb3-neg-zero-plus-zero', 'fb3-ord-complement-sum', 'fb3-ord-mux-nan',
  'fty-anon-varpart-arm-hi', 'fty-anon-varpart-arm-lo',
  'zoo-stoned-cur-litfloat')
$ExpectedOmni = @()

If (Test-Path -LiteralPath $Run) { throw "run already exists: $Run" }
New-Item -ItemType Directory -Path $Run | Out-Null
$ExpectedCommon | Sort-Object -Unique |
  Set-Content -LiteralPath (Join-Path $Run 'expected-mega_forms.txt') -Encoding ascii
($ExpectedCommon + $ExpectedOmni) | Sort-Object -Unique |
  Set-Content -LiteralPath (Join-Path $Run 'expected-omni_forms.txt') -Encoding ascii

$Terminal = @{}
foreach ($Line in Get-Content -LiteralPath $SummaryOracle) {
  $Parts = $Line -split "`t", 3
  $Terminal["$($Parts[0])/$($Parts[1])"] = $Parts[2]
}

function Invoke-Bounded([string]$Executable, [string]$Seed, [string]$Log) {
  $StartInfo = New-Object Diagnostics.ProcessStartInfo
  $StartInfo.FileName = $Executable
  $StartInfo.Arguments = $Seed
  $StartInfo.UseShellExecute = $false
  $StartInfo.CreateNoWindow = $true
  $StartInfo.RedirectStandardOutput = $true
  $StartInfo.RedirectStandardError = $true
  $Process = New-Object Diagnostics.Process
  $Process.StartInfo = $StartInfo
  [void]$Process.Start()
  $Stdout = $Process.StandardOutput.ReadToEndAsync()
  $Stderr = $Process.StandardError.ReadToEndAsync()
  $Finished = $Process.WaitForExit(180000)
  If (-not $Finished) {
    $Process.Kill()
    throw "$Executable seed=$Seed timed out"
  }
  $Text = $Stdout.Result + $Stderr.Result
  [IO.File]::WriteAllText($Log, $Text, [Text.UTF8Encoding]::new($false))
  $ExitCode = $Process.ExitCode
  $Process.Dispose()
  return $ExitCode
}

function Invoke-FormsProgram([string]$Name, [string]$Source) {
  foreach ($Option in @('O2', 'O3')) {
    $Out = Join-Path $Run "$Name-$($Option.ToLowerInvariant())"
    New-Item -ItemType Directory -Path $Out | Out-Null
    $CompileLog = Join-Path $Run "$Name-$($Option.ToLowerInvariant()).compile.log"
    & $Compiler -n "@$Config" -Twin64 -Px86_64 -Mdelphi "-$Option" -dHAS_INLINEVAR `
      -dTRY_OLEVARIANT_UTF8 -dTRY_VARIANT_RESERVED_MEMBER `
      -dTRY_VARIANT_DISTINCT_ORDINAL -dTRY_DELPHI_EQUALITY_COMPARER `
      "-FU$Out" "-FE$Out" "-o$Out\$Name.exe" (Join-Path $Root $Source) `
      *> $CompileLog
    If ($LASTEXITCODE -ne 0) { throw "$Name/$Option did not compile" }

    foreach ($Seed in $Seeds) {
      $Log = Join-Path $Run "$Name-$($Option.ToLowerInvariant()).seed-$Seed.log"
      $ExitCode = Invoke-Bounded (Join-Path $Out "$Name.exe") $Seed $Log
      Set-Content -LiteralPath "$Log.exit" -Value $ExitCode -Encoding ascii
      If ($ExitCode -ne 1) {
        throw "$Name/$Option seed=$Seed exited $ExitCode instead of 1"
      }
      $Observed = @(Get-Content -LiteralPath $Log |
        Where-Object { $_ -like 'FORMS_FAILURE *' } |
        ForEach-Object { $_.Substring(14) } | Sort-Object)
      $Expected = @(Get-Content -LiteralPath (Join-Path $Run "expected-$Name.txt"))
      If ((Compare-Object $Expected $Observed -CaseSensitive).Count -ne 0) {
        throw "$Name/$Option seed=$Seed produced a different failure set"
      }
      $Lines = @(Get-Content -LiteralPath $Log)
      If ($Lines[-1] -cne $Terminal["$Name/$Seed"]) {
        throw "$Name/$Option seed=$Seed has a different terminal summary`n" +
          "expected: $($Terminal["$Name/$Seed"])`n" +
          "observed: $($Lines[-1])"
      }
    }
  }
}

function Invoke-PublicRttiKnownRepro {
  $Expected = @('METHOD=1', 'CODE=1', 'CALLED=1')
  foreach ($Option in @('O2', 'O3')) {
    $Out = Join-Path $Run "rtti-public-method-$($Option.ToLowerInvariant())"
    New-Item -ItemType Directory -Path $Out | Out-Null
    $Source = Join-Path $Root 'tests\known\rtti_public_method_code_address.pas'
    & $Compiler -n "@$Config" -Twin64 -Px86_64 -Mdelphi -B "-$Option" "-FU$Out" "-FE$Out" `
      "-o$Out\rtti_public_method_code_address.exe" $Source `
      *> (Join-Path $Out 'compile.log')
    If ($LASTEXITCODE -ne 0) { throw "RTTI known repro/$Option did not compile" }
    $Log = Join-Path $Out 'run.log'
    $ExitCode = Invoke-Bounded (Join-Path $Out 'rtti_public_method_code_address.exe') '' $Log
    If ($ExitCode -ne 0 -or
        (Compare-Object $Expected @(Get-Content -LiteralPath $Log) -CaseSensitive).Count -ne 0) {
      throw "RTTI known repro/$Option changed"
    }
  }
}

Invoke-FormsProgram 'omni_forms' 'tests\mega\omni\omni_forms.dpr'
Invoke-FormsProgram 'mega_forms' 'tests\mega\integrated-001\mega_forms.dpr'
Invoke-PublicRttiKnownRepro

$Inputs = @($Compiler, $Config, $SummaryOracle,
  (Join-Path $Root 'tests\known\rtti_public_method_code_address.pas'))
$Inputs += Get-ChildItem -File -Recurse -Path `
  (Join-Path $Root 'tests\mega\omni'), `
  (Join-Path $Root 'tests\mega\integrated-001') `
  -Include *.pas,*.pp,*.inc,*.dpr | ForEach-Object FullName
$Inputs += Get-ChildItem -File -Recurse -LiteralPath $Run | ForEach-Object FullName
$Inputs | Sort-Object -Unique | ForEach-Object {
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
  "$Hash *$([IO.Path]::GetFullPath($_))"
} | Set-Content -LiteralPath (Join-Path $Run 'SHA256SUMS') -Encoding ascii
Write-Output "FORMS_GATE_OK common=$($ExpectedCommon.Count) omni_extra=$($ExpectedOmni.Count) modes=2 seeds=$($Seeds.Count) programs=2 standalone=2"
