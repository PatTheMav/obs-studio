#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -eq $env:CI) { throw }
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 1 }

  $ErrorActionPreference = 'Stop'

  $BoufUrl = "${env:BOUF_URL}/v${env:BOUF_VERSION}/bouf-windows-v${env:BOUF_VERSION}.zip"
  $BoufNsisUrl = "${env:BOUF_URL}/v${env:BOUF_VERSION}/bouf-nsis-v${env:BOUF_VERSION}.zip"

  $BoufUrlRegex = '^https:\/\/.+\/v[0-9\.]+\/bouf-windows-v[0-9\.]+\.zip$'
  $BoufNsisUrlRegex = '^https:\/\/.+\/v[0-9\.]+\/bouf-nsis-v[0-9\.]+\.zip$'


  if (!($BoufUrl -match $BoufUrlRegex)) {
    Write-Output "::error:Invalid BOUF download url: '${BoufUrl}'."
    throw
  }

  if (!($BoufNsisUrl -match $BoufNsisUrlRegex)) {
    Write-Output "::error:Invalid BOUF download url: '${BoufNsisUrl}'."
    throw
  }

  $OutputPath = "${env:RUNNER_TEMP}/bouf-windows-v${env:BOUF_VERSION}.zip"
  $NsisOutputPath = "${env:RUNNER_TEMP}/bouf-nsis-v${env:BOUF_VERSION}.zip"
}

process {
  Write-Output '::group::Download BOUF'
  $WebRequestArguments = @{
    Uri = $BoufUrl
    OutFile = $OutputPath
    SkipHttpErrorCheck = $true
  }

  $Result = Invoke-WebRequest @WebRequestArguments

  if ($null -ne $Result -and $Result.StatusCode -ne 200) {
    Write-Output "::error::Unable to download BOUF from '${BoufUrl}'."
    throw
  }

  $Checksum = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash.ToLower()
  $File = $OutputPath | Get-Item

  if ($Checksum -ne $env:BOUF_CHECKSUM) {
    Write-Output "::error::$($File.Name) checksum mismatch: ${Checksum} (expected: ${env:BOUF_CHECKSUM})."
    throw
  }
  Write-Output '::endgroup::'

  Write-Output '::group::Download BOUF NSIS Components'
  $WebRequestArguments = @{
    Uri = $BoufNsisUrl
    OutFile = $NsisOutputPath
    SkipHttpErrorCheck = $true
  }

  $Result = Invoke-WebRequest @WebRequestArguments

  if ($null -ne $Result -and $Result.StatusCode -ne 200) {
    Write-Output "::error::Unable to download BOUF from '${BoufNsisUrl}'."
    throw
  }

  $Checksum = (Get-FileHash -Path $NsisOutputPath -Algorithm SHA256).Hash.ToLower()
  $File = $NsisOutputPath | Get-Item

  if ($Checksum -ne $env:BOUF_NSIS_CHECKSUM) {
    Write-Output "::error::$($File.Name) checksum mismatch: ${Checksum} (expected: ${env:BOUF_NSIS_CHECKSUM})."
    throw
  }
  Write-Output '::endgroup::'

  Write-Output '::group::Extract BOUF'
  $ExpandArguments = @{
    Path = $OutputPath
    DestinationPath = "${env:RUNNER_TEMP}/bouf/bin"
  }

  Expand-Archive @ExpandArguments

  $ExpandArguments = @{
    Path = $NsisOutputPath
    DestinationPath = "${env:RUNNER_TEMP}/bouf/nsis"
  }

  Expand-Archive @ExpandArguments
  Write-Output '::endgroup::'

  "bouf-location=${env::RUNNER_TEMP}/bouf" >> $env:GITHUB_OUTPUT
}
