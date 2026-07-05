#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -eq $env:CI) { throw }
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 1 }
  $ErrorActionPreference = 'Stop'

  $SignToolBinary = "C:/Program Files (x86)/Windows Kits/10/App Certification Kit/signtool.exe"

  if (!(Test-Path -Path $SignToolBinary)) {
    Write-Output "::error::Signtool not found at '${SignToolBinary}'."
    throw
  }

  $GameCapturePath = "${env:ARTIFACT_PATH}/data/obs-plugins/win-capture"

  if (!(Test-Path -Path "${GameCapturePath}/*.dll")) {
    Write-Output "::error::No game capture module found at '${GameCapturePath}'."
    throw
  }
}

process {
  $SignToolArguments = @(
     "sign"
     "/fd",   "sha256"
     "/t",    "http://timestamp.digicert.com"
     "/f",    "${env:GITHUB_ACTION_PATH}/prod-gc.crt"
     "/csp",  "Google Cloud KMS Provider"
     "/kc",   "projects/ci-signing/locations/global/keyRings/production/cryptoKeys/game-capture-release-sign-hsm/cryptoKeyVersions/1"
     "${GameCapturePath}/*.dll"
  )

  & $SignToolBinary @SignToolArguments
}
