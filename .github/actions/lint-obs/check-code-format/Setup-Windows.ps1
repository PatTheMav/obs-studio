#Requires -Version 7.3

[CmdletBinding(PositionalBinding=$false)]
param()

begin {
  if ($null -eq $env:CI) { throw }
  if ($null -ne $env:RUNNER_DEBUG) { Set-PSDebug -Trace 1 }

  $ErrorActionPreference = 'Stop'
}

process {
  $WingetArguments = @(
    "--silent"
    "--accept-package-agreements"
    "--accept-source-agreements"
    "--disable-interactivity"
    "--exact"
  )

  case ( $env:LINTER_COMMAND ) {
    clang-format {
      break
    }
    gersemi {
      winget install @WingetArguments BlankSpruce.Gersemi
      break
    }
    zizmor {
      winget install @WingetArguments zizmor.zizmor
      break
    }
    { ( $_ -eq "swift-format" ) -or ( $_ -eq "xmllint" ) } {
      Write-Host "::error::The linter '${env:LINTER_COMMAND}' is supported on macOS and Linux only."
      throw
    }
    default {
      Write-Host "::error::Unsupported linter '${env:LINTER_COMMAND}' provided."
      throw
    }
  }
}
