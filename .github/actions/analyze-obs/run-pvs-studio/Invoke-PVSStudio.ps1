#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -eq $env:CI) { throw }
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 1 }

  $ErrorActionPreference = 'Stop'

  [Flags()] Enum PVSErrorCodes {
    Success = 0
    AnalyzerCrash = 1
    GenericError = 2
    InvalidCommandLine = 4
    FileNotFound = 8
    ConfigurationNotFound = 16
    InvalidProject = 32
    InvalidExtension = 64
    LicenseInvalid = 128
    CodeErrorsFound = 256
    SuppressionFailed = 512
    LicenseExpiringSoon = 1024
  }

  if (!(Test-Path $env:BUILD_SOLUTION)) {
    Write-Output "::error::No Visual Studio solution file found at '${env:BUILD_SOLUTION}'."
    throw
  }
}

process {
  $PVSArguments = @(
    '--progress'
    '--disableLicenseExpirationCheck'
    '--platform', $env:BUILD_ARCHITECTURE
    '--configuration', $env:BUILD_CONFIG
    '--target', $env:BUILD_SOLUTION
    '--output', "${env:RUNNER_TEMP}\pvs-analysis.plog"
    '--rulesConfig', "${env:GITHUB_ACTION_PATH}\obs.pvsconfig"
  )

  $ErrorActionPreference = 'SilentlyContinue'
  & "C:/Program Files (x86)/PVS-Studio/PVS-Studio_Cmd.exe" @PVSArguments
  $Result = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'

  $AcceptableResultCodes = @(
    [PVSErrorCodes]::Success
    [PVSErrorCodes]::LicenseExpiringSoon
    [PVSErrorCodes]::CodeErrorsFound
  )

  $AcceptableResult = 0
  foreach ($Value in $AcceptableResultCodes) {
    $AcceptableResult = $AcceptableResult -bor $Value
  }

  # Success, LicenseExpiringSoon, and CodeErrorsFound are acceptable error codes.
  if (!($Result -band $AcceptableResult)) {
    Write-Output "::error::PVS-Studio exited with error status '$([PVSErrorCodes]$Result)'."
    throw
  }
}

end {
  $PVSConversionArguments = @(
    '--analyzer', 'GA:1,2'
    '--excludedCodes', 'V1042,Renew'
    '--renderTypes', 'Sarif',
    '--outputDir', "${env:RUNNER_TEMP}"
    "${env:RUNNER_TEMP}\pvs-analysis.plog"
    )

  & "C:/Program Files (x86)/PVS-Studio/PlogConverter.exe" @PVSConversionArguments

  if (!(Test-Path -Path "${env:RUNNER_TEMP}/pvs-analysis.plog.sarif")) {
    Write-Host '::error::No generated SARIF file found.'
    throw
  }
}
