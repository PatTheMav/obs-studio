#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -eq $env:CI) { throw }
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 1 }

  $ErrorActionPreference = 'Stop'
}

process {
  if ((Test-Path -Path "$(Get-Location)/.git") -and (Test-Path -Path "$(Get-Location)/CMakePresets.json")) {
    $PresetJson = Get-Content "$(Get-Location)/CMakePresets.json"
    $ToolsInfo = (($PresetJson | ConvertFrom-JSON).configurePresets | Where-Object {
      $_.name -eq "dependencies"
      }).vendor.'obsproject.com/obs-studio'.tools
    $PVSStudioInfo = $ToolsInfo.'pvs-studio'
    $BoufInfo = $ToolsInfo.bouf

    "pvs-studio-version=$($PVSStudioInfo.version)" >> $env:GITHUB_OUTPUT
    "pvs-studio-checksum=$($PVSStudioInfo.hash)" >> $env:GITHUB_OUTPUT
    "pvs-studio-url=$($PVSStudioInfo.baseUrl)" >> $env:GITHUB_OUTPUT

    "bouf-version=$($BoufInfo.version)"
    "bouf-checksum=$($BoufInfo.hash)"
    "bouf-nsis-checksum=$($BoufInfo.'nsis-hash')"
    "bouf-url=$($BoufInfo.baseUrl)"
  } else {
    "pvs-studio-version=null" >> $env:GITHUB_OUTPUT
    "pvs-studio-checksum=null" >> $env:GITHUB_OUTPUT
    "pvs-studio-url=null" >> $env:GITHUB_OUTPUT

    "bouf-version=null"
    "bouf-checksum=null"
    "bouf-nsis-checksum=null"
    "bouf-url=null"
  }
}
