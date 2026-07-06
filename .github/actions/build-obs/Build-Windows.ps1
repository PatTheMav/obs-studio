#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -ne $env:RUNNER_DEBUG) {
    Set-PSDebug -Trace 1
  }

  if ($null -eq $env:CI) {
    throw
  }
  $ErrorActionPreference = 'Stop'

  $Checkout = Get-Location | Get-Item

  if (!((Test-Path -Path "${Checkout}/.git") -and (Test-Path -Path "${Checkout}/CMakePresets.json"))) {
    Write-Output '::error::Action needs to be run from the root directory of an obs-studio checkout.'
    throw
  }

  if (!(Test-Path -Path $env:OUTPUT_PATH)) {
    New-Item -Type Directory -Path ${env:OUTPUT_PATH} > $null
  }
  $BuildLocation = $(
    $PresetJson = Get-Content "${Checkout}/CMakePresets.json"
    $PresetBuildLocation = ((($PresetJson | ConvertFrom-JSON).configurePresets) | Where-Object {
      $_.name -eq "windows-${env:BUILD_TARGET}"
    }).binaryDir
    $PresetBuildLocation -replace '\$\{sourceDir\}',"${env:OUTPUT_PATH}"
  )
}

process {
  Write-Output '::group::Configure obs-studio'
  $CmakeArgs = @(
    '--preset', "windows-ci-${env:BUILD_TARGET}"
    '-B', "${BuildLocation}"
    $( if ($null -ne $env:RUNNER_DEBUG) {'--debug-output'} )
  )
  & cmake @CmakeArgs
  Write-Output '::endgroup::'

  Write-Output '::group::Build obs-studio'
  $CmakeBuildArgs = @(
    '--build', "${BuildLocation}"
    '--config', "${env:BUILD_CONFIG}"
    '--parallel'
    '--', '/consoleLoggerParameters:Summary', '/nologo'
    $( if ($null -ne $env:RUNNER_DEBUG) {'--verbose'} )
  )
  & cmake @CmakeBuildArgs
  Write-Output '::endgroup::'
}
