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
}

process {
  $CodeSignFiles = (Get-ChildItem -Path $env:ARTIFACT_PATH -Include *.exe,*.dll,*.pyd -Recurse) | ForEach-Object {
    $_.FullName
  }

  $SignToolArguments = @(
     "sign"
     "/fd",   "sha384"
     "/as"
     "/tr",   "http://timestamp.digicert.com"
     "/td",   "sha256"
     "/f",    "${env:GITHUB_ACTION_PATH}/prod.crt"
     "/csp",  "Google Cloud KMS Provider"
     "/kc",   "projects/ci-signing/locations/global/keyRings/production/cryptoKeys/release-sign-hsm/cryptoKeyVersions/1"
  )

  $ChunkSize = 5.0
  $NumChunks = [Math]::Ceiling($CodeSignFiles.Count / $ChunkSize)

  for ($i = 0; $i -lt $NumChunks; $i++) {
    $StartIndex = $i * $ChunkSize
    $EndIndex = ($i * $ChunkSize * 2) - 1
    $FileList = $CodeSignFiles[${StartIndex}..${EndIndex}]

    & $SignToolBinary @SignToolArguments @FileList
  }
}
