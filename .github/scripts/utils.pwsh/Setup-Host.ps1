function Setup-Host {
    if ( ! ( Test-Path function:Log-Output ) ) {
        . $PSScriptRoot/Logger.ps1
    }

    if ( ! ( Test-Path function:Ensure-Location ) ) {
        . $PSScriptRoot/Ensure-Location.ps1
    }

    if ( ! ( Test-Path function:Install-BuildDependencies ) ) {
        . $PSScriptRoot/Install-BuildDependencies.ps1
    }

    if ( ! ( Test-Path function:Expand-ArchiveExt ) ) {
        . $PSScriptRoot/Expand-ArchiveExt.ps1
    }

    Install-BuildDependencies -WingetFile "${ScriptHome}/.Wingetfile"

    if ( $Target -eq '' ) { $Target = $HostArchitecture }

    $script:PlatformSDK = $BuildSpec.platformConfig."windows-${Target}".platformSDK

    if ( ! ( ( $SkipAll ) -or ( $SkipDeps ) ) ) {
        ('prebuilt', 'qt6', 'vlc', 'cef') | ForEach-Object {
            $_Dependency = $_

            $_Version = $BuildSpec.dependencies."${_Dependency}".version
            $_BaseUrl = $BuildSpec.dependencies."${_Dependency}".baseUrl
            $_Label = $BuildSpec.dependencies."${_Dependency}".label
            $_Hash = $BuildSpec.dependencies."${_Dependency}".hashes."windows-${Target}"

            if ( $BuildSpec.dependencies."${_Dependency}".PSobject.Properties.Name -contains "debugSymbols" ) {
                $_PdbHash = $BuildSpec.dependencies."${_Dependency}".'debugSymbols'."$windows-${Target}"
            }

            if ( $_Version -eq '' ) {
                throw "No ${_Dependency} spec found in ${BuildSpecFile}."
            }

            Log-Information "Setting up ${_Label}..."

            Push-Location -Stack BuildTemp
            Ensure-Location -Path "$(Resolve-Path -Path "${ProjectRoot}/..")/obs-build-dependencies"

            switch -wildcard ( $_Dependency ) {
                prebuilt {
                    $_Filename = "windows-deps-${_Version}-${Target}.zip"
                    $_Uri = "${_BaseUrl}/${_Version}/${_Filename}"
                    $_Target = "windows-deps-${_Version}-${Target}"
                    $script:DepsVersion = ${_Version}
                }
                qt6 {
                    $_Filename = "windows-deps-qt6-${_Version}-${Target}.zip"
                    $_Uri = "${_BaseUrl}/${_Version}/${_Filename}"
                    $_Target = "windows-deps-${_Version}-${Target}"
                }
                cef {
                    $_Filename = "cef_binary_${_Version}_windows_${Target}.zip"
                    $_Uri = "${_BaseUrl}/${_Filename}"
                    $_Target = "cef_binary_${_Version}_windows_${Target}"
                    $script:CefVersion = ${_Version}
                }
                vlc {
                    $_Filename = "vlc.zip"
                    $_Uri = 'https://cdn-fastly.obsproject.com/downloads/vlc.zip'
                    $_Target = "vlc-${_Version}"
                    $script:VlcVersion = ${_Version}
                }
            }

            if ( ! ( Test-Path -Path $_Filename ) ) {
                $Params = @{
                    UserAgent = 'NativeHost'
                    Uri = $_Uri
                    OutFile = $_Filename
                    UseBasicParsing = $true
                    ErrorAction = 'Stop'
                }

                Invoke-WebRequest @Params
                Log-Status "Downloaded ${_Label} for ${Target}."
            } else {
                Log-Status "Found downloaded ${_Label}."
            }

            $_FileHash = Get-FileHash -Path $_Filename -Algorithm SHA256

            if ( $_FileHash.Hash.ToLower() -ne $_Hash ) {
                throw "Checksum of downloaded ${_Label} does not match specification. Expected '${_Hash}', 'found $(${_FileHash}.Hash.ToLower())'"
            }
            Log-Status "Checksum of downloaded ${_Label} matches."

            if ( ! ( ( $SkipAll ) -or ( $SkipUnpack ) ) ) {
                Push-Location -Stack BuildTemp
                Ensure-Location -Path $_Target

                Expand-ArchiveExt -Path "../${_Filename}" -DestinationPath . -Force

                Pop-Location -Stack BuildTemp
            }
            Pop-Location -Stack BuildTemp
        }
    } else {
        $script:DepsVersion = $BuildSpec.dependencies.prebuilt.version
        $script:CefVersion = $BuildSpec.dependencies.cef.version
        $script:VlcVersion = $BuildSpec.dependencies.vlc.version
    }
}

function Get-HostArchitecture {
    $HostArchitecture = $($env:PROCESSOR_ARCHITECTURE).ToLower()
    if ( $HostArchitecture -eq 'amd64' ) {
        $HostArchitecture = 'x64'
    }

    return $HostArchitecture
}

$HostArchitecture = Get-HostArchitecture
