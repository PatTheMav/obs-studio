[CmdletBinding()]
param(
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo',
    [ValidateSet('x64')]
    [string] $Target,
    [switch] $BuildInstaller = $false
)

$ErrorActionPreference = 'Stop'

if ( $DebugPreference -eq 'Continue' ) {
    $VerbosePreference = 'Continue'
    $InformationPreference = 'Continue'
}

if ( ! ( [System.Environment]::Is64BitOperatingSystem ) ) {
    throw "obs-studio requires a 64bit system to build and run."
}

if ( $PSVersionTable.PSVersion -lt '7.0.0' ) {
    Write-Warning 'The obs-deps PowerShell build script requires PowerShell Core 7. Install or upgrade your PowerShell version: https://aka.ms/pscore6'
    exit 2
}

function Package {
    trap {
        Write-Error $_
        exit 2
    }

    $ScriptHome = $PSScriptRoot
    $ProjectRoot = Resolve-Path -Path "$PSScriptRoot/../.."
    $BuildSpecFile = "${ProjectRoot}/buildspec.json"

    $UtilityFunctions = Get-ChildItem -Path $PSScriptRoot/utils.pwsh/*.ps1 -Recurse

    foreach( $Utility in $UtilityFunctions ) {
        Write-Debug "Loading $($Utility.FullName)"
        . $Utility.FullName
    }

    $BuildSpec = Get-Content -Path ${BuildSpecFile} -Raw | ConvertFrom-Json

    Install-BuildDependencies -WingetFile "${ScriptHome}/.Wingetfile"

    $CmakeArgs = @(
        '--config', "${Configuration}"
    )

    if ( $VerbosePreference -eq 'Continue' ) {
        $CmakeArgs+=('--verbose')
    }

    Log-Information "Packaging obs-studio..."
    Invoke-External cmake --install "build_${Target}" --prefix "${ProjectRoot}/release" @CmakeArgs

    $RemoveArgs = @{
        ErrorAction = 'SilentlyContinue'
        Path = @(
            "${ProjectRoot}/release/obs-studio-windows-x64-*.zip"
        )
    }

    Remove-Item @RemoveArgs

    Invoke-External git fetch origin --tags > $null
    $_GitBranch = Invoke-External  git rev-parse --abbrev-ref HEAD
    $_GitHash = Invoke-External git rev-parse --short HEAD
    $_EAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $_GitTag = Invoke-External git describe --tags --abbrev=0
    $ErrorActionPreference = $_EAP

    $_Version = $(if ( $_GitTag -ne '' ) { $_GitTag } else { $_GitHash })

    $CompressArgs = @{
        Path = (Get-ChildItem -Path "${ProjectRoot}/release" -Exclude "obs-studio-windows-x64-*.zip")
        CompressionLevel = 'Optimal'
        DestinationPath = "${ProjectRoot}/release/obs-studio-windows-x64-${_Version}.zip"
    }

    Compress-Archive -Force @CompressArgs
    Move-Item -Path "${ProjectRoot}/release/obs-studio-windows-x64-${_Version}.zip" -Destination "${ProjectRoot}"
}

Package
