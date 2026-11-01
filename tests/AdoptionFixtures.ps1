<#
.SYNOPSIS
    The helpers the adoption suites dot-source: Git with a test identity, fixture folders and repositories, and a PNG.

.DESCRIPTION
    Dot-source it from tests/Test-Adoption.ps1 or tests/Test-AdoptEdgeCases.ps1, which set $Work: New-TestFolder and
    New-Fixture create their folders in it. $png is a 1x1 PNG image, base64-encoded, for a fixture file whose name
    ends in .png.
#>

function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}
# Creates $Work\$Name with the given files (relative paths with forward slashes) and returns its path.
function New-TestFolder([string]$Name, [hashtable]$Files) {
    $folder = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($relative in $Files.Keys) {
        $file = Join-Path $folder $relative
        New-Item -ItemType Directory -Force (Split-Path -Parent $file) | Out-Null
        if ($relative.EndsWith('.png')) { [IO.File]::WriteAllBytes($file, [Convert]::FromBase64String($Files[$relative])) }
        else { [IO.File]::WriteAllText($file, $Files[$relative], [Text.UTF8Encoding]::new($false)) }
    }
    $folder
}
# Creates $Work\$Name as New-TestFolder does, commits it as a repository with the remote origin, and returns its path.
function New-Fixture([string]$Name, [hashtable]$Files, [string]$Remote) {
    $folder = New-TestFolder $Name $Files
    Push-Location $folder
    try { Invoke-Git init -q -b main; Invoke-Git remote add origin $Remote; Invoke-Git add -A; Invoke-Git commit -q -m 'Initial' }
    finally { Pop-Location }
    $folder
}

$script:png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
