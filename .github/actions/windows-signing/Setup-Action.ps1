#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  function Setup-Bouf {
    [CmdletBinding()]
    param(
      [Parameter(Mandatory=$true)]
      [string] $Version,
      [Parameter(Mandatory=$true)]
      [string] $Checksum
    )

    begin {
      $BoufDestination = "${Destination}/bouf"
      New-Item -ItemType Directory -Path $BoufDestination
      Set-Location -Path $BoufDestination

      $FilePattern = "bouf-windows-${Version}.zip"
    }

    process {
      Write-Output '::group::Set up bouf'
      Invoke-Executable gh release download "${Version}" --repo "obsproject/bouf" --pattern $FilePattern

      $FileHash = (Get-FileHash $FilePattern -Algorithm SHA256).Hash

      if ( $FileHash -ne $Checksum ) {
        throw "Checksum of downloaded bouf version ${FilePattern} does not match. Actual: ${FileHash}, expected: ${Checksum}"
      }

      Expand-Archive -Path $FilePattern
      Write-Output '::endgroup::'
    }

    end {
      "boufLocation=${BoufDestination}" >> $env:GITHUB_OUTPUT
    }
  }

  function Setup-NSIS {
    [CmdletBinding()]
    param(
      [Parameter(Mandatory=$true)]
      [string] $Version,
      [Parameter(Mandatory=$true)]
      [string] $Checksum
    )

    begin {
      $NsisBoufDestination = "${Destination}/NSIS"
      New-Item -ItemType Directory -Path $NsisBoufDestination
      Set-Location -Path $NsisBoufDestination

      $FilePattern = "bouf-nsis-windows-${Version}.zip"
    }

    process {
      Write-Output '::group::Set up bouf-NSIS'
      Invoke-Executable gh release download "${Version}" --repo "obsproject/bouf" --pattern $FilePattern

      $FileHash = (Get-FileHash $FilePattern -Algorithm SHA256).Hash

      if ( $FileHash -ne $Checksum ) {
        throw "Checksum of downloaded bouf-NSIS version ${FilePattern} does not match. Actual: ${FileHash}, expected: ${Checksum}"
      }

      Expand-Archive -Path $FilePattern
      Write-Output '::endgroup::'
    }

    end {
      Write-Output '::group::Install NSIS'
      winget install @WingetArguments --id NSIS.NSIS
      Write-Output '::endgroup::'

      "nsisBoufLocation=${NsisBoufDestination}" >> $env:GITHUB_OUTPUT
    }
  }

  $RequiredVars = @(
    $env:CI
    $env:GITHUB_ENV
    $env:GITHUB_OUTPUT
    $env:BUILD_LOCATION
    $env:BOUF_VERSION
    $env:BOUF_CHECKSUM
    $env:NSIS_CHECKSUM
    $env:GH_TOKEN
    $env:RUNNER_TEMP
    $env:GITHUB_ACTION_PATH
  )

  . "${env:GITHUB_ACTION_PATH}/Invoke-Executable.ps1"

  if ( ($RequiredVars | Where-Object { $null -eq $_ } ).Count -gt 0 ) {
    throw
  }

  if ( $null -ne $env:RUNNER_DEBUG ) {
    Set-PSDebug -Trace 1
  }

  $WingetArguments = @(
    '--silent'
    '--accept-package-agreements'
    '--accept-source-agreements'
    '--dsiable-interactivity'
    '--exact'
  )

  $Destination = "${env:RUNNER_TEMP}/windows-signing"
  "ACTION_WORKSPACE=${Destination}" >> $env:GITHUB_ENV
}

process {
  if ( ! ( Test-Location $env:BUILD_LOCATION ) ) {
    throw "Provided build location '${env:BUILD_LOCATION}' does not exist."
  }

  Push-Location -Stack WindowsSigning $env:BUILD_LOCATION
  Expand-Archive -Path *.zip
  Remove-Item -Path *.zip
  Pop-Location -Stack WindowsSigning

  Setup-Bouf -Version $env:BOUF_VERSION -Checksum $env:BOUF_CHECKSUM
  Setup-NSIS -Version $env:BOUF_VERSION -Checksum $env:NSIS_CHECKSUM

  Write-Output '::group::Install rclone'
  winget install @WingetArguments --id Rclone.Rclone
  Write-Output '::endgroup::'
}

end {
  if ( $null -ne $env:RUNNER_DEBUG) {
    Set-PSDebug -Trace 0
  }
}
