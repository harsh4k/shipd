# PSScriptAnalyzer settings: CI fails on any Error or Warning not excluded below.
# Each exclusion is a style rule this codebase breaks on purpose.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The dashboard and report are colored terminal UIs; Write-Host is the point.
        'PSAvoidUsingWriteHost'
        # Get-DayCommits, Get-SystemStats, Find-Repos... read better plural; renaming is churn.
        'PSUseSingularNouns'
        # shipd runs on pwsh 7, which reads BOM-less UTF-8. install.ps1 (also run by 5.1) is kept
        # pure ASCII instead, and CI enforces that.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
