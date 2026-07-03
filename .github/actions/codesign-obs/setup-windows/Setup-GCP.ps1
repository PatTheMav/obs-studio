#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 1 }
  if ($null -eq $env:CI) { throw }
  $ErrorActionPreference = 'Stop'

  $Destination = "${env:ACTION_WORKSPACE}/google-cng"
  $GoogleRepository = "GoogleCloudPlatform/kms-integrations"

  if (!(Test-Location $env:ACTION_WORKSPACE)) {
    throw "Action workspace does not exist. Ensure Setup-Action is run first."
  }
}

process {
  New-Item -ItemType Directory -Name $Destination

  Push-Location -Stack WindowsSigning Destination
  & gh release download $env:CNG_VERSION --repository $GoogleRepository --pattern "*amd64.zip"
  Expand-Archive -Path *.zip
  $SignaturePath = Get-ChildItem *.sig -Recurse
  $MsiPath = Get-ChildItem *.msi -Recurse

  $OpenSSLArguments = @(
    '-sha384'
    '--verify'
    "${env:GITHUB_ACTION_PATH}/cng-release-signing-key.pem"
    '-signature'
    $SignaturePath
    $MsiPath
  )

  & openssl dgst @OpenSSLArguments
  & msiexec /qn /norestart /i $MsiPath

  Pop-Location -Stack WindowsSigning

  "google-cng-path=${Destination}" >> $env:GITHUB_OUTPUT
}
