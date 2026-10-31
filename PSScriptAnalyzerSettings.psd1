# PSScriptAnalyzer settings for this repository's scripts. tests/Test-ScriptAnalyzer.ps1 runs them on every script, and
# test-template.yml runs that as the suite "Analyze the PowerShell scripts". Every warning and error fails it.
# The rules below are off, each for the reason beside it; anything else that can't be fixed is suppressed where it is,
# with [Diagnostics.CodeAnalysis.SuppressMessageAttribute] and a justification.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The scripts are run by a person at a terminal, and Write-Host is how they talk to that person. Their data goes
        # to the pipeline as objects, as the rule asks.
        'PSAvoidUsingWriteHost',
        # Function names such as Get-ChangedFiles or Get-OriginTags name what they return; the rule is about cmdlets
        # published in a module, which these are not.
        'PSUseSingularNouns',
        # Internal helpers named Set-, New- or Remove- change files in a temporary folder or a plan the user asked to
        # change; the scripts that change anything the user owns take -WhatIf themselves.
        'PSUseShouldProcessForStateChangingFunctions',
        # The scripts run on PowerShell 7, which reads UTF-8 without a byte order mark; a BOM would show up in every diff.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
