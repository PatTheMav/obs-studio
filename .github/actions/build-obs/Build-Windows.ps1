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

  if (!((Test-Path "${Checkout}/.git") -and (Test-Path "${Checkout}/CMakePresets.json"))) {
    Write-Output '::error:Action needs to be run from an obs-studio checkout root directory'
    throw
  }

  & git fetch origin --no-tags --no-recurse-submodules --quiet 2>&1

  Write-Output '::group::Set Up Environment'
  New-Item -Type Directory ${env:OUTPUT_PATH} > $null
  $BuildLocation = $(
    $PresetJson = Get-Content "${CheckoutDir}/CMakePresets.json"
    $PresetBuildLocation = ((($PresetJson | ConvertFrom-JSON).configurePresets) | Where-Object {
      $_.name -eq "windows-${env:BUILD_TARGET}"
    }).binaryDir
    $PresetBuildLocation -replace '\$\{sourceDir\}',"${env:OUTPUT_PATH}"
  )
  Write-Output '::endgroup::'
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
