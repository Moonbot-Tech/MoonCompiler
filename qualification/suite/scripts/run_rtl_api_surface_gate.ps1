param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId
)

$ErrorActionPreference = 'Stop'
$SuiteRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CompilerRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$SourceRoot = Join-Path $SuiteRoot 'tests\rtl-api'
$Run = Join-Path $SuiteRoot "results\runs\$RunId\rtl-api-surface"
$Cases = @(
  @{ Name = 'rtl_api_release231_contracts'; Expected = 'RTL_API_RELEASE231_CONTRACTS_OK' },
  @{ Name = 'rtl_api_freetype_contracts'; Expected = 'RTL_API_FREETYPE_CONTRACTS_OK' },
  @{ Name = 'rtl_api_portability_contracts'; Expected = 'RTL_API_PORTABILITY_PASS' },
  @{ Name = 'rtl_api_regex_contracts'; Expected = 'RTL_API_REGEX_CONTRACTS_OK' },
  @{ Name = 'rtl_api_windows_contracts'; Expected = 'RTL_API_WINDOWS_CONTRACTS_OK' },
  @{ Name = 'rtl_api_compiler_identity'; Expected = 'RTL_API_COMPILER_IDENTITY_OK' },
  @{ Name = 'rtl_api_threading_contracts'; Expected = 'RTL_API_THREADING_CONTRACTS_OK' },
  @{ Name = 'rtl_api_delayed_contracts'; Expected = 'RTL_API_DELAYED_CONTRACTS_OK' },
  @{ Name = 'rtl_api_url_async_contracts'; Expected = 'RTL_API_URL_ASYNC_CONTRACTS_OK' },
  @{ Name = 'rtl_api_json_builder_contracts'; Expected = 'RTL_API_JSON_BUILDER_CONTRACTS_OK' },
  @{ Name = 'rtl_api_release21_contracts'; Expected = 'RTL_API_RELEASE21_CONTRACTS_OK' },
  @{ Name = 'rtl_api_timezone_provider_contracts'; Expected = 'RTL_API_TIMEZONE_PROVIDER_CONTRACTS_OK' },
  @{ Name = 'rtl_api_surface'; Expected = 'RTL_API_SURFACE_OK' },
  @{ Name = 'rtl_api_stringbuilder_contracts'; Expected = 'RTL_API_STRINGBUILDER_CONTRACTS_OK' },
  @{ Name = 'rtl_api_variant_dictionary_contracts'; Expected = 'RTL_API_VARIANT_DICTIONARY_CONTRACTS_OK' },
  @{ Name = 'rtl_api_bcd_value_contracts'; Expected = 'RTL_API_BCD_VALUE_CONTRACTS_OK' },
  @{ Name = 'rtl_api_encoding_contracts'; Expected = 'RTL_API_ENCODING_CONTRACTS_OK' },
  @{ Name = 'rtl_api_sorted_find_contracts'; Expected = 'RTL_API_SORTED_FIND_CONTRACTS_OK' },
  @{ Name = 'rtl_api_datetime_unix_contracts'; Expected = 'RTL_API_DATETIME_UNIX_CONTRACTS_OK' },
  @{ Name = 'rtl_api_utf8_decode_contracts'; Expected = 'RTL_API_UTF8_DECODE_CONTRACTS_OK' },
  @{ Name = 'rtl_api_queue_contracts'; Expected = 'RTL_API_QUEUE_CONTRACTS_OK' },
  @{ Name = 'rtl_api_dictionary_capacity_contracts'; Expected = 'RTL_API_DICTIONARY_CAPACITY_CONTRACTS_OK' },
  @{ Name = 'rtl_api_comparer_factory_contracts'; Expected = 'RTL_API_COMPARER_FACTORY_CONTRACTS_OK' },
  @{ Name = 'rtl_api_text_operations_contracts'; Expected = 'RTL_API_TEXT_OPERATIONS_CONTRACTS_OK' },
  @{ Name = 'rtl_api_dictionary_scan_contracts'; Expected = 'RTL_API_DICTIONARY_SCAN_CONTRACTS_OK' },
  @{ Name = 'rtl_api_dynarray_managed_contracts'; Expected = 'RTL_API_DYNARRAY_MANAGED_CONTRACTS_OK' },
  @{ Name = 'rtl_api_unicode_copy_contracts'; Expected = 'RTL_API_UNICODE_COPY_CONTRACTS_OK' },
  @{ Name = 'rtl_api_array_copy'; Expected = 'RTL_API_ARRAY_COPY_OK' },
  @{ Name = 'rtl_api_fphttp_nodelay'; Expected = 'RTL_API_FPHTTP_NODELAY_OK' },
  @{ Name = 'rtl_api_fphttp_overload_response'; Expected = 'RTL_API_FPHTTP_OVERLOAD_RESPONSE_OK' }
)

If (Test-Path -LiteralPath $Run) { throw "run already exists: $Run" }
New-Item -ItemType Directory -Path $Run | Out-Null

foreach ($Case in $Cases) {
  $Profiles = @('debug', 'release')
  If ($Case.Name -in @('rtl_api_dynarray_managed_contracts', 'rtl_api_regex_contracts')) {
    $Profiles += 'diagnostic-release'
  }
  If ($Case.Name -eq 'rtl_api_portability_contracts') { $Profiles += 'reverse-uses' }
  foreach ($Profile in $Profiles) {
    $ProfileDir = Join-Path $Run "$($Case.Name)\$Profile"
    New-Item -ItemType Directory -Path $ProfileDir | Out-Null
    $Project = Join-Path $ProfileDir "$($Case.Name).dpr"
    Copy-Item -LiteralPath (Join-Path $SourceRoot "$($Case.Name).dpr") `
      -Destination $Project
    $Options = @('-B', "-Fi$SourceRoot", "-Fi$CompilerRoot/rtl/win", "-FU$ProfileDir", "-FE$ProfileDir")
    If ($Profile -eq 'reverse-uses') { $Options += '-dRTL_API_WINDOWS_FIRST' }
    If ($Profile -ne 'debug') { $Options += '-dRELEASE' }
    If ($Profile -eq 'diagnostic-release') { $Options += '-dFPCX64MM_DIAGNOSTIC' }
    If ($Case.Name -eq 'rtl_api_freetype_contracts') {
      foreach ($Kind in @('good', 'incomplete', 'tail')) {
        $FixtureOptions = $Options + "-omoon-freetype-$Kind.dll"
        If ($Kind -eq 'incomplete') { $FixtureOptions += '-dMISSING_FREETYPE_EXPORT' }
        If ($Kind -eq 'tail') { $FixtureOptions += '-dMISSING_FREETYPE_TAIL' }
        & (Join-Path $CompilerRoot 'toolchain\bin\x86_64-win64\fpc.exe') @FixtureOptions `
          (Join-Path $SourceRoot 'moon_freetype_fixture.dpr') *> (Join-Path $ProfileDir "$Kind-compile.log")
        If ($LASTEXITCODE -ne 0) { throw "FreeType $Kind fixture did not compile" }
      }
    }
    If ($Case.Name -eq 'rtl_api_delayed_contracts') {
      & (Join-Path $CompilerRoot 'toolchain\bin\x86_64-win64\fpc.exe') @Options `
        (Join-Path $SourceRoot 'moon_delay_fixture.dpr') *> (Join-Path $ProfileDir 'dll-compile.log')
      If ($LASTEXITCODE -ne 0) { throw 'delayed-import fixture did not compile' }
    }
    & (Join-Path $CompilerRoot 'toolchain\bin\x86_64-win64\fpc.exe') @Options $Project `
      *> (Join-Path $ProfileDir 'compile.log')
    If ($LASTEXITCODE -ne 0) {
      throw "$($Case.Name)/$Profile did not compile"
    }
    $RunLog = Join-Path $ProfileDir 'run.log'
    $StartInfo = New-Object Diagnostics.ProcessStartInfo
    $StartInfo.FileName = Join-Path $ProfileDir "$($Case.Name).exe"
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $Process = New-Object Diagnostics.Process
    $Process.StartInfo = $StartInfo
    [void]$Process.Start()
    $Stdout = $Process.StandardOutput.ReadToEndAsync()
    $Stderr = $Process.StandardError.ReadToEndAsync()
    If (-not $Process.WaitForExit(30000)) {
      $Process.Kill()
      $Process.WaitForExit()
      throw "$($Case.Name)/$Profile timed out after 30 seconds"
    }
    $ExitCode = $Process.ExitCode
    [IO.File]::WriteAllText($RunLog, $Stdout.Result + $Stderr.Result, [Text.UTF8Encoding]::new($false))
    $Process.Dispose()
    $RunLines = @(Get-Content -LiteralPath (Join-Path $ProfileDir 'run.log'))
    If ($Profile -eq 'diagnostic-release') {
      $OutputIsValid = ($RunLines -contains $Case.Expected) -and
        [bool]($RunLines -match '^FPCX64MM_DIAGNOSTIC live-blocks=0 ')
    } else {
      $OutputIsValid = (($RunLines -join "`n").Trim() -eq $Case.Expected)
    }
    If (($ExitCode -ne 0) -or -not $OutputIsValid) {
      throw "$($Case.Name)/$Profile failed"
    }
  }
}

$Inputs = @(
  (Join-Path $SourceRoot 'rtl_api_release231_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_freetype_contracts.dpr'),
  (Join-Path $SourceRoot 'moon_freetype_fixture.dpr'),
  (Join-Path $SourceRoot 'rtl_api_portability_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_regex_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_windows_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_compiler_identity.dpr'),
  (Join-Path $SourceRoot 'rtl_api_delayed_contracts.dpr'),
  (Join-Path $SourceRoot 'moon_delay_fixture.dpr'),
  (Join-Path $SourceRoot 'rtl_api_url_async_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_json_builder_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_release21_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_timezone_provider_contracts.dpr'),
  (Join-Path $CompilerRoot 'rtl/win/timezone.inc'),
  (Join-Path $SourceRoot 'rtl_api_surface.dpr'),
  (Join-Path $SourceRoot 'rtl_api_stringbuilder_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_variant_dictionary_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_bcd_value_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_encoding_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_utf8_decode_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_datetime_unix_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_sorted_find_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_queue_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_dictionary_capacity_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_comparer_factory_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_text_operations_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_text_guard.inc'),
  (Join-Path $SourceRoot 'rtl_api_dictionary_scan_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_dynarray_managed_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_unicode_copy_contracts.dpr'),
  (Join-Path $SourceRoot 'rtl_api_array_copy.dpr'),
  (Join-Path $SourceRoot 'rtl_api_fphttp_nodelay.dpr'),
  (Join-Path $SourceRoot 'rtl_api_fphttp_overload_response.dpr'),
  (Join-Path $CompilerRoot 'runtime\mm\mormot.core.fpcx64mm.pas'),
  (Join-Path $CompilerRoot 'toolchain\bin\x86_64-win64\fpc.exe'),
  (Join-Path $CompilerRoot 'toolchain\bin\x86_64-win64\fpc.cfg'),
  (Join-Path $CompilerRoot 'toolchain\bin\x86_64-win64\moon-base.cfg'))
$Inputs += Get-ChildItem -File -Recurse -LiteralPath $Run |
  ForEach-Object { $_.FullName }
$Inputs | Sort-Object -Unique | ForEach-Object {
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
  "$Hash *$([IO.Path]::GetFullPath($_))"
} | Set-Content -LiteralPath (Join-Path $Run 'SHA256SUMS') -Encoding ascii

Write-Output "RTL_API_SURFACE_GATE_OK cases=$($Cases.Count) executions=$($Cases.Count * 2 + 3)"
