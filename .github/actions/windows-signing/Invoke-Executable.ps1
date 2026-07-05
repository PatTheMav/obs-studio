function Invoke-Executable {
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true, Position=0)]
  [string] $Command,
  [Parameter(ValueFromRemainingArguments, Position=1)]
  [string[]] $Arguments
)

begin {
  $_EAP = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
}

process {
  Write-Debug "Invoke-Executable: ${Command} ${Arguments} 2>&1"

  & $Command @Arguments 2>&1
  $Result = $LASTEXITCODE
}

end {
  $ErrorActionPreference = $_EAP

  if ( $Result -ne 0 ) {
    throw "${Command} ${Arguments} exited with non-zero code ${Result}."
  }
}
}
