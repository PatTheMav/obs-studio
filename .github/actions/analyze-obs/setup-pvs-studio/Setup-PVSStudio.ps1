#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -eq $env:CI) { throw }
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 2 }

  $ErrorActionPreference = 'Stop'

  $PVSStudioURL = $env:PVS_STUDIO_URL
  $PVSStudioVersion = $env:PVS_STUDIO_VERSION
  $PVSStudioChecksum = $env:PVS_STUDIO_CHECKSUM.ToLower()
  $PVSStudioUsername = $env:PVS_STUDIO_USERNAME
  $PVSStudioLicense = $env:PVS_STUDIO_LICENSE

  if (($null -eq $PVSStudioUsername) -or ($null -eq $PVSStudioLicense)) {
    Write-Output '::error::PVS-Studio setup requires username and license key.'
    throw
  }

  $UrlRegex = '^https:\/\/files.pvs-studio.com/PVS-Studio_setup.exe$'

  if (!(PVSStudioURL -match $UrlRegex)) {
    Write-Output "::error:Invalid PVS-Studio download url: '${PVSStudioURL}'."
    throw
  }

  $OutputPath = "${env:RUNNER_TEMP}/PVS-Studio_setup_${PVSStudioVersion}.exe"
}

process {
  Write-Output '::group::Download PVS-Studio'
  $WebRequestArguments = @{
    Uri = $PVSStudioURL
    OutFile = $OutputPath
    SkipHttpErrorCheck = $true
  }

  $Result = Invoke-WebRequest @WebRequestArguments

  if (null -ne $Result -and $Result.StatusCode -ne 200) {
    Write-Output "::error::Unable to download PVS-Studio from '${PVSStudioURL}'."
    throw
  }

  $Checksum = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash.ToLower()
  $File = $OutputPath | Get-Item

  if ($Checksum -ne $PVSStudioChecksum {
    Write-Output "::error::$($File.Name) checksum mismatch: ${Checksum} (expected: ${PVSStudioChecksum})."
    throw
  }
  Write-Output '::endgroup::'

  Write-Output '::group::Install PVS-Studio'
  $PVSSetupArguments = @(
    '/components="Core"'
    '/verysilent'
    '/supressmsgboxes'
    '/norestart'
    '/nocloseapplications'
    '/skipNetFrameworkInstallation'
  )

  & $OutputPath @PVSSetupArguments
  Write-Output '::endgroup::'

  Write-Output '::group::Activate PVS-Studio'
  $PVSStudioArguments = @(
    'credentials'
    '-u', $PVSStudioUsername
    '-n', $PVSStudioLicense
  )

  & "C:/Program Files (x86)/PVS-Studio/PVS-Studio_Cmd.exe" @PVSSetupArguments

  Write-Output '::endgroup::'
}
