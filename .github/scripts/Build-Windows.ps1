[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string] $Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo',
    [switch] $SkipAll,
    [switch] $SkipBuild,
    [switch] $SkipDeps
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

function Build {
    trap {
        Pop-Location -Stack BuildTemp -ErrorAction 'SilentlyContinue'
        Write-Error $_
        Log-Group
        exit 2
    }

    $ScriptHome = $PSScriptRoot
    $ProjectRoot = Resolve-Path -Path "$PSScriptRoot/../.."
    $BuildSpecFile = "${ProjectRoot}/buildspec.json"

    $UtilityFunctions = Get-ChildItem -Path $PSScriptRoot/utils.pwsh/*.ps1 -Recurse

    foreach($Utility in $UtilityFunctions) {
        Write-Debug "Loading $($Utility.FullName)"
        . $Utility.FullName
    }

    $BuildSpec = Get-Content -Path ${BuildSpecFile} -Raw | ConvertFrom-Json

    if ( ! $SkipDeps ) {
        Install-BuildDependencies -WingetFile "${ScriptHome}/.Wingetfile"
    }

    Push-Location -Stack BuildTemp
    if ( ! ( ( $SkipAll ) -or ( $SkipBuild ) ) ) {
        Ensure-Location $ProjectRoot

        $CMakeArgs = @()
        $CmakeBuildArgs = @('--build')
        $CmakeInstallArgs = @()

        if ( $VerbosePreference -eq 'Continue' ) {
            $CmakeBuildArgs += ('--verbose')
            $CmakeInstallArgs += ('--verbose')
        }

        if ( $DebugPreference -eq 'Continue' ) {
            $CmakeArgs += ('--debug-output')
        }

        $Preset = "windows-$(if ( $Env:CI -ne $null ) { 'ci-' })${Target}"

        $CmakeArgs = @(
            '--preset', $Preset
        )

        if ( ( $Env:TWITCH_CLIENTID -ne '' ) -and ( $Env:TWITCH_HASH -ne '' ) ) {
            $CmakeArgs += @(
                "-DTWITCH_CLIENTID:STRING=${Env:TWITCH_CLIENTID}"
                "-DTWITCH_HASH:STRING=${Env:TWITCH_HASH}"
            )
        }

        if ( ( $Env:RESTREAM_CLIENTID -ne '' ) -and ( $Env:RESTREAM_HASH -ne '' ) ) {
            $CmakeArgs += @(
                "-DRESTREAM_CLIENTID:STRING=${Env:RESTREAM_CLIENTID}"
                "-DRESTREAM_HASH:STRING=${Env:RESTREAM_HASH}"
            )
        }

        if ( ( $Env:YOUTUBE_CLIENTID -ne '' ) -and ( $Env:YOUTUBE_CLIENTID_HASH -ne '' ) -and
             ( $Env:YOUTUBE_SECRET -ne '' ) -and ( $Env:YOUTUBE_SECRET_HASH-ne '' ) ) {
            $CmakeArgs += @(
                "-DYOUTUBE_CLIENTID:STRING=${Env:YOUTUBE_CLIENTID}"
                "-DYOUTUBE_CLIENTID_HASH:STRING=${Env:YOUTUBE_CLIENTID_HASH}"
                "-DYOUTUBE_SECRET:STRING=${Env:YOUTUBE_SECRET}"
                "-DYOUTUBE_SECRET_HASH:STRING=${Env:YOUTUBE_SECRET_HASH}"
            )
        }

        if ( $Env:GPU_PRIORITY -ne '' ) {
            $CmakeArgs += @(
                "-DGPU_PRIORITY_VAL:STRING=${Env:GPU_PRIORITY}"
            )
        }

        if ( ( $Env:CI -ne $null ) -and ( $Env:CCACHE_CONFIGPATH -ne '' ) ) {
            $CmakeArgs += @(
                "-DDENABLE_CCACHE:BOOL=TRUE"
            )
        }

        $CmakeBuildArgs += @(
            '--preset', "windows-${Target}"
            '--config', $Configuration
            '--parallel'
            '--', '/consoleLoggerParameters:Summary', '/noLogo'
        )

        $CmakeInstallArgs += @(
            '--install', "build_${Target}"
            '--prefix', "${ProjectRoot}/build_${Target}/install"
            '--config', $Configuration
        )

        Log-Group "Configuring obs-studio..."
        Invoke-External cmake @CmakeArgs

        Log-Group "Building obs-studio..."
        Invoke-External cmake @CmakeBuildArgs
    }

    Log-Group "Installing obs-studio..."
    Invoke-External cmake @CmakeInstallArgs

    Pop-Location -Stack BuildTemp
    Log-Group
}

Build
