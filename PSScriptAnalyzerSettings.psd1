# PSScriptAnalyzer settings: CI fails on any Error or Warning not excluded below.
# Each exclusion is a style rule this codebase breaks on purpose.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The dashboard and report are colored terminal UIs; Write-Host is the point.
        'PSAvoidUsingWriteHost'
        # Get-DayCommits, Get-SystemStats, Find-Repos... read better plural; renaming is churn.
        'PSUseSingularNouns'
        # Best-effort probes (GPU counter, PATH broadcast, torn JSON line) deliberately ignore failure.
        'PSAvoidUsingEmptyCatchBlock'
        # pwsh 7 reads BOM-less UTF-8; install.ps1 is fetched as a string by irm, not read from disk.
        'PSUseBOMForUnicodeEncodedFile'
        # New-Panel builds strings; "New-" here doesn't change system state.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
