#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  $RequiredVars = @(
    $ENV:GITHUB_ACTION_PATH
    $env:ACTION_WORKSPACE
    $env:CI
    $env:CNG_VERSION
    $env:GITHUB_ENV
    $env:GH_TOKEN
    $env:RUNNER_TEMP
    $env:GITHUB_OUTPUT
  )

  . "${env:GITHUB_ACTION_PATH}/Invoke-Executable.ps1"

  if ( ($RequiredVars | Where-Object { $null -eq $_ } ).Count -gt 0 ) {
    throw
  }

  if ( $null -ne $env:RUNNER_DEBUG ) {
    Set-PSDebug -Trace 1
  }

  $Destination = "${env:ACTION_WORKSPACE}/google-cng"
  $GoogleRepository = "GoogleCloudPlatform/kms-integrations"

  if ( ! ( Test-Location $env:ACTION_WORKSPACE ) ) {
    throw "Action workspace does not exist. Ensure Setup-Action is run first."
  }
}

process {
  New-Item -ItemType Directory -Name $Destination

  Push-Location -Stack WindowsSigning Destination
  Invoke-External release download $env:CNG_VERSION --repository $GoogleRepository --pattern "*amd64.zip"
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

  Invoke-External openssl dgst @OpenSSLArguments
  Invoke-External msiexec /qn /norestart /i $MsiPath

  Pop-Location -Stack WindowsSigning

  "googleCngLocation=${Destination}" >> $env:GITHUB_OUTPUT
}

end {
  if ( $null -ne $env:RUNNER_DEBUG) {
    Set-PSDebug -Trace 0
  }
}
