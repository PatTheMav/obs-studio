#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ( $null -ne $env:RUNNER_DEBUG ) {
    Set-PSDebug -Trace 1
  }

  if ($null -eq $env:CI) {
    throw
  }
  $ErrorActionPreference = 'Stop'

  $Checkout = Get-Location | Get-Item

  if (!(Test-Path "${Checkout}/.git") -and (Test-Path "${Checkout}/CMakePresets.json")) {
    Write-Output '::error::Action needs to be run from an obs-studio checkout root directory'
    throw
  }

  $BuildLocation = $(
    $PresetJson = Get-Content "${Checkout}/CMakePresets.json"
    $PresetBuildLocation = ((($PresetJson | ConvertFrom-Json).configurePresets) | Where-Object {
        $_.name -eq "windows-${env:BUILD_TARGET}"
    }).binaryDir

    $PresetBuildLocation -replace '\$\{sourceDir\}',"${env:OUTPUT_PATH}"
  )

  $CommitInfo = $(
    $GitDescription = git describe --tags --long 2>&1
    $GitDescription -match '^([0-9]+\.[0-9]+\.[0-9]+(?:-(?:rc|beta)[0-9]+)?)-([0-9]+)-(.+)$'

    @{
      Version  = $Matches.Item(1)
      Distance = $Matches.Item(2)
      Hash     = $Matches.Item(3)
    }
  )
}

process {
  Write-Output '::group::Package obs-studio'
  $OutputName = $null

  if ($null -ne $env:OUTPUT_NAME) {
    $OutputName = $env:OUTPUT_NAME
  } else {
    $OutputName = "obs-studio-windows-${env:BUILD_TARGET}-$($CommitInfo.Hash)"
  }

  Push-Location -Stack PackageTemp $BuildLocation

  $CpackArgs = @(
    '-C', "${env:BUILD_CONFIG}"
    $( if ($null -ne $env:RUNNER_DEBUG) {'--verbose'} )
  )

  & cpack @CpackArgs

  $Package = Get-ChildItem -filter "obs-studio-*-windows-${env:BUILD_TARGET}.zip" -File
  Move-Item -Path $Package -Destination "${env:OUTPUT_PATH}/${OutputName}.zip"

  Pop-Location -Stack PackageTemp
  Write-Output '::endgroup::'

  if ("${env:BUILD_CONFIG}" -eq 'Release') {
    Write-Output '::group::Create Libraries For Plugin Development'

    $InstallDestination = "${env:OUTPUT_PATH}/libobs_release"
    $CmakeArgs = @(
      '--install', ${BuildLocation}
      '--component', 'Development'
      '--config', 'Release'
      '--prefix', ${InstallDestination}
      )
    & cmake @CmakeArgs

    $LibraryOutputName = "${OutputName}-plugin-dev.zip"

    Push-Location -Stack PackageTemp "${InstallDestination}"

    $Params = @{
      Path = (Get-ChildItem -Exclude "${LibraryOutputName}")
      DestinationPath = "${env:OUTPUT_PATH}/${LibraryOutputName}"
      CompressionLevel = "Optimal"
    }

    Compress-Archive @Params

    Pop-Location -Stack PackageTemp
    Write-Output '::endgroup::'
  }
}
