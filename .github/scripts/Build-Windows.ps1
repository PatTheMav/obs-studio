[CmdletBinding()]
param(
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo',
    [ValidateSet('x64')]
    [string] $Target,
    [ValidateSet('Visual Studio 17 2022', 'Visual Studio 16 2019')]
    [string] $CMakeGenerator,
    [switch] $SkipAll,
    [switch] $SkipBuild,
    [switch] $SkipDeps,
    [switch] $SkipUnpack,
    [switch] $CIRelease
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

    $script:DepsVersion = ''
    $script:CefVersion = ''
    $script:VlcVersion = ''
    $script:PlatformSDK = '10.0.18363.657'

    Setup-Host

    Push-Location -Stack BuildTemp
    if ( ! ( ( $SkipAll ) -or ( $SkipBuild ) ) ) {
        $CmakeArgs = @(
            "-DCMAKE_SYSTEM_VERSION=${PlatformSDK}"
            "-DCMAKE_BUILD_TYPE=${Configuration}"
            "-DCMAKE_INSTALL_PREFIX:PATH=${ProjectRoot}/build_${Target}/install"
            "-DCMAKE_PREFIX_PATH:PATH=$(Resolve-Path -Path "${ProjectRoot}/..")/obs-build-dependencies/windows-deps-${DepsVersion}-${Target}"
            "-DCEF_ROOT_DIR:PATH=$(Resolve-Path -Path "${ProjectRoot}/..")/obs-build-dependencies/cef_binary_${CefVersion}_windows_${Target}"
            "-DVLC_PATH:PATH=$(Resolve-Path -Path "${ProjectRoot}/..")/obs-build-dependencies/vlc-${VlcVersion}"
            "-DQT_VERSION=6"
            '-DENABLE_BROWSER:BOOL=ON'
            '-DENABLE_VLC:BOOL=ON'
        )

        if ( $Env:CI -ne '' ) {
            $_BuildNumber = $(if ( $Env:GITHUB_RUN_ID -gt 0 ) { "${Env:GITHUB_RUN_ID}" } else { '1' })
            $CmakeArgs += @("-DOBS_BUILD_NUMBER:STRING=${_BuildNumber}")
        }

        if ( $CIRelease ) {
            $CmakeArgs += @('-DENABLE_RELEASE_BUILD:BOOL=ON')
        }

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

        if ( $DebugPreference -eq 'Continue' ) {
            $CmakeArgs += @('--debug-output')
        }

        if ( $CmakeGenerator -ne '' ) {
            $CmakeArgs += @("-G ${CmakeGenerator}")
        }

        $NumProcessors = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

        if ( $NumProcessors -gt 1 ) {
            $env:UseMultiToolTask = $true
            $env:EnforceProcessCountAcrossBuilds = $true
        }

        Log-Information "Configuring obs-studio..."
        Log-Debug "Attempting to configure obs-studio with CMake arguments: $($CmakeArgs | Out-String)"
        Invoke-External cmake -S $ProjectRoot --preset=windows-${Target} @CmakeArgs

        Log-Information 'Building obs-studio...'
        $CmakeArgs = @(
            '--config', "$( if ( $Configuration -eq '' ) { 'RelWithDebInfo' } else { $Configuration })"
        )

        if ( $VerbosePreference -eq 'Continue' ) {
            $CmakeArgs+=('--verbose')
        }

        Invoke-External cmake --build build_${Target} @CmakeArgs
    }

    Pop-Location -Stack BuildTemp
}

Build
