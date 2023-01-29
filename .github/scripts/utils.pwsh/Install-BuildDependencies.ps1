function Install-BuildDependencies {
    <#
        .SYNOPSIS
            Installs required build dependencies.
        .DESCRIPTION
            Additional packages might be needed for successful builds. This module contains additional
            dependencies available for installation via winget and, if possible, adds their locations
            to the environment path for future invocation.
        .EXAMPLE
            Install-BuildDependencies
    #>

    param(
        [string] $WingetFile = "$PSScriptRoot/.Wingetfile"
    )

    if ( ! ( Test-Path function:Log-Warning ) ) {
        . $PSScriptRoot/Logger.ps1
    }

    $Prefixes = @{
        'x64' = ${Env:ProgramFiles}
        'x86' = ${Env:ProgramFiles(x86)}
        'arm32' = ${Env:ProgramFiles(arm)}
    }
    
    $Paths = $Env:Path -split [System.IO.Path]::PathSeparator

    $WingetOptions = @('install', '--accept-package-agreements', '--accept-source-agreements')

    if ( $script:Quiet ) {
        $WingetOptions += '--silent'
    }

    Get-Content $WingetFile | ForEach-Object {
        $_, $Package, $_, $Path, $_, $Binary, $_, $Version = $_ -replace ',','' -split " +(?=(?:[^\']*\'[^\']*\')*[^\']*$)" -replace "'",''

        $Prefixes.Keys | ForEach-Object {
            $Key = $_
            $Prefix = $Prefixes[$Key]
            $FullPath = "${Prefix}\${Path}"
            if ( ( Test-Path $FullPath ) -and ! ( $Paths -contains $FullPath ) ) {
                $Paths = @($FullPath) + $Paths
            }
        }

        $Env:Path = $Paths -join [System.IO.Path]::PathSeparator

        Log-Debug "Checking for command ${Binary}"
        $Found = Get-Command -ErrorAction SilentlyContinue $Binary

        if ( $Found ) {
            Log-Status "Found dependency ${Binary} as $($Found.Source)"
        } else {
            Log-Status "Installing package ${Package}"

            try {
                $Params = $WingetOptions + $Package

                winget @Params
            } catch {
                throw "Error while installing winget package ${Package}: $_"
            }
        }
    }
}
