#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 2 }
  if ($null -eq $env:CI) { throw }
  $ErrorActionPreference = 'Stop'

  New-Item -ItemType Directory -Path $env:RUNNER_TEMP -Name 'google-cng' | Out-Null
  $GoogleRepository = "GoogleCloudPlatform/kms-integrations"
}

process {
  Push-Location -Stack WindowsSigning "${env:RUNNER_TEMP}/google-cng"
  & gh release download $env:CNG_VERSION --repo $GoogleRepository --pattern "*amd64.zip"
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

  "google-cng-path=${env:RUNNER_TEMP}/google-cng" >> $env:GITHUB_OUTPUT
}
