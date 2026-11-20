<#
.SYNOPSIS
    Test what .template\Update-Project.ps1 adds to an update: the opt-in answers it gives an existing project, and the
    notes it prints.

.DESCRIPTION
    Needs no template snapshot, Copier or network. Prints PASS or FAIL per check and exits 1 on any failure (ADR-0024).
      opt-in    Invoke-TemplateRender, with a stand-in Copier that records its arguments, passes <answer>=false for
                each opt-in answer the answers file lacks and -Data doesn't set, and nothing for one it has.
      adopt     Get-AdoptionAnswers answers node_lint = $false for a Node.js repository, and coverage_gate = $false
                and file_headers = $false for every repository.
      ci-call   Get-CiCallNote says to add workflow_call to ci.yml when tag-release.yml calls it and it lacks the
                 trigger, and says nothing when it has the trigger or the project has no tag-release.yml;
                tools\adopt\Adoption.psm1's copy prints the same.
      ci-perms  Get-CiPermissionNote names each job of ci.yml, or its top-level permissions, that asks for more than
                contents: read when tag-release.yml calls it, and says nothing for contents: read, none or no tag-release.yml;
                tools\adopt\Adoption.psm1's copy prints the same.
      gitversioning Get-GitVersioningWorkflowNote names each job of a workflow other than publish.yml that builds,
                packs, tests without --no-build or pushes packages with an actions/checkout step without
                fetch-depth: 0 or with a -p:Version argument when version.json exists, and says nothing for full
                history, a flow mapping, --no-build, a job that doesn't build, publish.yml or a project without
                version.json.
                tools\adopt\Adoption.psm1's copy prints the same.
      badge     Get-BadgeReminder prints the badge line to add when best_practices_project is set and README.md lacks
                the badge, and nothing when README.md has it or the answer is unset.
      code-review Get-CodeReviewNote names a code-review.yml that pins NCodeGroup/code-review before v1.4.0 or passes
                no approve: true, and an AGENTS.md Landing section that doesn't say draft: yes, and says nothing for a
                current setup or a project without code-review.yml.
      immutable Get-ImmutableReleaseNote says to delete or leave out SECURITY.md's "Releases are immutable" paragraph
                when a workflow runs on a release event or uploads release assets, and nothing otherwise, such as
                for an upload named only in a comment line.
      copies    Get-WorkflowEvents and Test-ReleaseAssetWorkflow in Update-Project.ps1 are character for character
                the ones in tools/Set-RepositoryBaseline.ps1, and Adopt-Project.ps1's copies of those and
                Get-ImmutableReleaseNote are the ones in Update-Project.ps1.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-notes-test-<process ID> in the temp
    folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateNotes.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-notes-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

# opt-in: Invoke-TemplateRender with a stand-in Copier that records its arguments.
$optIns = 'csharp_format', 'node_lint', 'coverage_gate', 'file_headers'
$optInRender = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    foreach ($fnName in 'ConvertTo-CopierValue', 'Get-PreReleaseAnswer', 'Get-Answer', 'Get-OptInData', 'Get-LicenseData', 'Invoke-TemplateRender') {
        $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $recorded = [Collections.Generic.List[string]]::new()
    function Invoke-Copier { $recorded.Clear(); foreach ($a in $args) { $recorded.Add("$a") } }
    # Set-Variable: only the loaded functions read TemplateClone, Data and project, which the script analyzer can't see.
    Set-Variable -Name TemplateClone -Value (Join-Path $Work 'template-repo')
    $allTrue = (($optIns | ForEach-Object { "${_}: true" }) -join "`n") + "`n"
    $cases = [ordered]@{
        'lacking'  = @{ Answers = "stack: node`n"; Data = @{}; Want = ($optIns | ForEach-Object { "$_=false" }) }
        'recorded' = @{ Answers = "stack: node`n$allTrue"; Data = @{}; Want = @() }
        'data-on'  = @{ Answers = "stack: node`n"; Data = @{ node_lint = $true }; Want = ($optIns | ForEach-Object { if ($_ -eq 'node_lint') { "$_=True" } else { "$_=false" } }) }
    }
    foreach ($name in $cases.Keys) {
        $folder = Join-Path $Work "render-$name"
        $null = New-Item -ItemType Directory -Path $folder -Force
        Set-Variable -Name project -Value $folder
        Set-Variable -Name Data -Value $cases[$name].Data
        [IO.File]::WriteAllText((Join-Path $folder '.copier-answers.yml'), $cases[$name].Answers)
        Push-Location $folder
        try { $null = Invoke-TemplateRender v0.1.0 (Join-Path $folder 'out') }
        finally { Pop-Location }
        $got = (@($recorded | Where-Object { $_ -match "^($($optIns -join '|'))=" }) | Sort-Object) -join ','
        $want = (@($cases[$name].Want) | Sort-Object) -join ','
        Check "opt-in: $name" ($got -eq $want) "got [$got], want [$want]"
    }
}
$optInRender

# adopt: a Node.js repository is adopted with node_lint off, and every repository with coverage_gate off.
Import-Module (Join-Path $repoRoot 'tools/adopt/Adoption.psm1') -Force
$adoptNode = Join-Path $Work 'adopt-node'
New-Item -ItemType Directory -Force $adoptNode | Out-Null
[IO.File]::WriteAllText((Join-Path $adoptNode 'package.json'), '{"name":"adopt-node","scripts":{"test":"node --test"}}', [Text.UTF8Encoding]::new($false))
$adoptAnswers = Get-AdoptionAnswers $adoptNode
Check 'adopt: a Node.js repository is adopted with node_lint off' ($adoptAnswers.node_lint -eq $false) ($adoptAnswers | ConvertTo-Json -Compress)
Check 'adopt: a Node.js repository is adopted with coverage_gate off' ($adoptAnswers.coverage_gate -eq $false) ($adoptAnswers | ConvertTo-Json -Compress)
Check 'adopt: a Node.js repository is adopted with file_headers off' ($adoptAnswers.file_headers -eq $false) ($adoptAnswers | ConvertTo-Json -Compress)
$adoptPython = Join-Path $Work 'adopt-python'
New-Item -ItemType Directory -Force $adoptPython | Out-Null
[IO.File]::WriteAllText((Join-Path $adoptPython 'requirements.txt'), "pytest`n", [Text.UTF8Encoding]::new($false))
$pythonAnswers = Get-AdoptionAnswers $adoptPython
Check 'adopt: a Python repository is adopted with coverage_gate off' ($pythonAnswers.stack -eq 'python' -and $pythonAnswers.coverage_gate -eq $false) ($pythonAnswers | ConvertTo-Json -Compress)
Check 'adopt: a Python repository is adopted with file_headers off' ($pythonAnswers.file_headers -eq $false) ($pythonAnswers | ConvertTo-Json -Compress)

# ci-call: Get-CiCallNote, run from inside each fixture folder.
$ciCallNote = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CiCallNote' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $callsCi = "jobs:`n  test:`n    uses: ./.github/workflows/ci.yml`n"
    $ciCases = [ordered]@{
        'no workflow_call'  = @{ Release = $callsCi; Ci = "on:`n  push:`n"; Note = $true }
        'has workflow_call' = @{ Release = $callsCi; Ci = "on:`n  push:`n  workflow_call:`n"; Note = $false }
        'no tag-release'    = @{ Release = $null; Ci = "on:`n  push:`n"; Note = $false }
    }
    foreach ($name in $ciCases.Keys) {
        $folder = Join-Path $Work "ci-call-$($name -replace ' ', '-')"
        $workflows = Join-Path $folder '.github/workflows'
        $null = New-Item -ItemType Directory -Path $workflows -Force
        [IO.File]::WriteAllText((Join-Path $workflows 'ci.yml'), $ciCases[$name].Ci)
        if ($ciCases[$name].Release) { [IO.File]::WriteAllText((Join-Path $workflows 'tag-release.yml'), $ciCases[$name].Release) }
        Push-Location $folder
        try { $note = (Get-CiCallNote) -join "`n"; $adoptNote = (Adoption\Get-CiCallNote) -join "`n" }
        finally { Pop-Location }
        $has = $note.Contains('has no workflow_call trigger')
        $nothing = -not $note.Trim()
        Check "ci-call: $name" ($(if ($ciCases[$name].Note) { $has } else { $nothing })) "got [$note]"
        Check "ci-call: ${name}: the adoption prints the same note" ($adoptNote -eq $note) "update [$note], adopt [$adoptNote]"
    }
}
$ciCallNote

# ci-permissions: Get-CiPermissionNote, run from inside each fixture folder.
$ciPermissionNote = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CiPermissionNote' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $callsCi = "jobs:`n  test:`n    uses: ./.github/workflows/ci.yml`n"
    $codecov = "name: CI`non:`n  push:`n  workflow_call:`npermissions:`n  contents: read`njobs:`n  build:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: ./x`n        with:`n          permissions: write-all`n  codecov:`n    if: github.event_name == 'push'`n    runs-on: ubuntu-latest`n    permissions:`n      contents: read`n      id-token: write # Codecov's OIDC upload`n    steps:`n      - run: echo upload`n"
    $permissionCases = [ordered]@{
        'a job asks for id-token'  = @{ Release = $callsCi; Ci = $codecov; Want = 'job codecov asks for id-token: write.' }
        'top-level read-all'       = @{ Release = $callsCi; Ci = "on:`n  workflow_call:`npermissions: read-all`njobs:`n  build:`n    runs-on: ubuntu-latest`n"; Want = 'its top-level permissions ask for read-all.' }
        'a flow mapping'           = @{ Release = $callsCi; Ci = "on:`n  workflow_call:`njobs:`n  a:`n    permissions: { contents: write, pull-requests: read }`n    runs-on: ubuntu-latest`n"; Want = 'job a asks for contents: write, pull-requests: read.' }
        'contents read and none'   = @{ Release = $callsCi; Ci = "on:`n  workflow_call:`npermissions:`n  contents: read`njobs:`n  build:`n    permissions: {}`n    runs-on: ubuntu-latest`n  lint:`n    permissions:`n      contents: none`n      checks: 'none'`n    runs-on: ubuntu-latest`n"; Want = $null }
        'quoted flow values'       = @{ Release = $callsCi; Ci = "on:`n  workflow_call:`njobs:`n  a:`n    permissions: { contents: 'read', checks: ""none"" }`n    runs-on: ubuntu-latest`n"; Want = $null }
        'no tag-release'           = @{ Release = $null; Ci = $codecov; Want = $null }
    }
    foreach ($name in $permissionCases.Keys) {
        $folder = Join-Path $Work "ci-permissions-$($name -replace '\W+', '-')"
        $workflows = Join-Path $folder '.github/workflows'
        $null = New-Item -ItemType Directory -Path $workflows -Force
        [IO.File]::WriteAllText((Join-Path $workflows 'ci.yml'), $permissionCases[$name].Ci)
        if ($permissionCases[$name].Release) { [IO.File]::WriteAllText((Join-Path $workflows 'tag-release.yml'), $permissionCases[$name].Release) }
        Push-Location $folder
        try { $note = (Get-CiPermissionNote) -join "`n"; $adoptNote = (Adoption\Get-CiPermissionNote) -join "`n" }
        finally { Pop-Location }
        $want = $permissionCases[$name].Want
        $ok = if ($want) { $note.Contains($want) -and $note.Contains('grants it only contents: read') } else { -not $note.Trim() }
        Check "ci-permissions: $name" $ok "got [$note]"
        Check "ci-permissions: ${name}: the adoption prints the same note" ($adoptNote -eq $note) "update [$note], adopt [$adoptNote]"
    }
}
$ciPermissionNote

# gitversioning: Get-GitVersioningWorkflowNote, run from inside each fixture folder, which is also the project.
$gitVersioningNote = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-GitVersioningWorkflowNote' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $head = "on: push`njobs:`n  build:`n    runs-on: ubuntu-latest`n    steps:`n"
    $shallow = $head + "      - uses: actions/checkout@v4`n      - run: dotnet build --configuration Release /p:Version=`"`${BUILD_VERSION}`"`n      - run: dotnet nuget push out/*.nupkg`n"
    $versionCases = [ordered]@{
        'shallow and version'    = @{ Text = $shallow; Want = @('.github/workflows/main.yml, job build: actions/checkout without fetch-depth: 0', '.github/workflows/main.yml, job build: /p:Version="${BUILD_VERSION}"', 'Shallow clone lacks the objects') }
        'full history'           = @{ Text = $head + "      - uses: actions/checkout@v4`n        with:`n          fetch-depth: 0`n      - run: dotnet pack -c Release`n"; Want = @() }
        'flow mapping'           = @{ Text = $head + "      - uses: actions/checkout@v4`n        with: { fetch-depth: 0 }`n      - run: dotnet build`n"; Want = @() }
        'named step'             = @{ Text = $head + "      - name: Check out`n        uses: actions/checkout@v4`n        with:`n          persist-credentials: false`n      - run: dotnet test`n"; Want = @('job build: actions/checkout without fetch-depth: 0') }
        'tests without a build'  = @{ Text = $head + "      - uses: actions/checkout@v4`n      - run: dotnet test --no-build`n"; Want = @() }
        'other job'              = @{ Text = "on: push`njobs:`n  lint:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: actions/checkout@v4`n      - run: npm run lint`n  pack:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: actions/checkout@v4`n        with:`n          fetch-depth: 0`n      - run: dotnet pack`n"; Want = @() }
        'publish.yml'            = @{ Text = $shallow; File = 'publish.yml'; Want = @() }
        'no version.json'        = @{ Text = $shallow; VersionJson = $false; Want = @() }
    }
    foreach ($name in $versionCases.Keys) {
        $case = $versionCases[$name]
        $folder = Join-Path $Work "gitversioning-$($name -replace '\W+', '-')"
        $workflows = Join-Path $folder '.github/workflows'
        $null = New-Item -ItemType Directory -Path $workflows -Force
        if ($case.VersionJson -ne $false) { [IO.File]::WriteAllText((Join-Path $folder 'version.json'), '{}') }
        [IO.File]::WriteAllText((Join-Path $workflows $(if ($case.File) { $case.File } else { 'main.yml' })), $case.Text)
        Push-Location $folder
        try { $note = (Get-GitVersioningWorkflowNote) -join "`n"; $adoptNote = (Adoption\Get-GitVersioningWorkflowNote) -join "`n" }
        finally { Pop-Location }
        if ($case.Want.Count) {
            $missing = @($case.Want | Where-Object { -not $note.Contains($_) })
            Check "gitversioning: $name" (-not $missing.Count) "missing [$($missing -join '], [')] in [$note]"
        }
        else { Check "gitversioning: $name" (-not $note.Trim()) "got [$note]" }
        Check "gitversioning: ${name}: the adoption prints the same note" ($adoptNote -eq $note) "update [$note], adopt [$adoptNote]"
    }
}
$gitVersioningNote

# badge: Get-BadgeReminder, run from inside each fixture folder, which is also the project.
$badgeReminder = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    foreach ($fnName in 'Get-Answer', 'Get-BadgeReminder') {
        $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $line = '[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/16752/badge)](https://www.bestpractices.dev/projects/16752)'
    $badgeCases = [ordered]@{
        'registered, no badge'   = @{ Answers = "best_practices_project: '16752'`n"; Readme = "# Title`n"; Line = $true }
        'registered, has badge'  = @{ Answers = "best_practices_project: '16752'`n"; Readme = "$line`n# Title`n"; Line = $false }
        'not registered'         = @{ Answers = "stack: node`n"; Readme = "# Title`n"; Line = $false }
    }
    foreach ($name in $badgeCases.Keys) {
        $folder = Join-Path $Work "badge-$($name -replace '\W+', '-')"
        $null = New-Item -ItemType Directory -Path $folder -Force
        [IO.File]::WriteAllText((Join-Path $folder '.copier-answers.yml'), $badgeCases[$name].Answers)
        [IO.File]::WriteAllText((Join-Path $folder 'README.md'), $badgeCases[$name].Readme)
        # Set-Variable: only the loaded function reads project, which the script analyzer can't see.
        Set-Variable -Name project -Value $folder
        Push-Location $folder
        try { $note = (Get-BadgeReminder) -join "`n" }
        finally { Pop-Location }
        if ($badgeCases[$name].Line) { Check "badge: $name" ($note.Contains($line)) "got [$note]" }
        else { Check "badge: $name" (-not $note.Trim()) "got [$note]" }
    }
}
$badgeReminder

# code-review: Get-CodeReviewNote, run from inside each fixture folder, which is also the project.
$codeReviewNote = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CodeReviewNote' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $pin = 'NCodeGroup/code-review@0123456789abcdef0123456789abcdef01234567'
    $review = { param([string]$Tag, [bool]$Approve) "jobs:`n  review:`n    steps:`n      - uses: $pin # $Tag`n        with:`n$(if ($Approve) { "          approve: true`n" })" }
    $reviewCases = [ordered]@{
        'old pin, no approve, draft no' = @{ Workflow = (& $review 'v1.3.0' $false); Agents = "# P`n`n## Landing`n`n- draft: no`n"; Want = @('pins NCodeGroup/code-review v1.3.0', 'passes no approve: true', 'says draft: no', 'Set-RepositoryBaseline.ps1 again'); Not = @() }
        'current'                       = @{ Workflow = (& $review 'v1.4.0' $true); Agents = "# P`n`n## Landing`n`n- draft: yes`n"; Want = @(); Not = @() }
        'newer, two jobs'               = @{ Workflow = (& $review 'v1.10.0' $true) + "      - uses: $pin # v1.12.1`n"; Agents = "# P`n`n## Landing`n`n- draft: yes`n"; Want = @(); Not = @() }
        'no draft line'                 = @{ Workflow = (& $review 'v1.4.0' $true); Agents = "# P`n`n## Landing`n`n- integrate: pull-request`n"; Want = @('has no draft line'); Not = @('pins', 'passes no approve') }
        'no code-review.yml'            = @{ Workflow = $null; Agents = "# P`n`n## Landing`n`n- draft: no`n"; Want = @(); Not = @() }
    }
    foreach ($name in $reviewCases.Keys) {
        $case = $reviewCases[$name]
        $folder = Join-Path $Work "code-review-$($name -replace '\W+', '-')"
        $workflows = Join-Path $folder '.github/workflows'
        $null = New-Item -ItemType Directory -Path $workflows -Force
        [IO.File]::WriteAllText((Join-Path $folder 'AGENTS.md'), $case.Agents)
        if ($case.Workflow) { [IO.File]::WriteAllText((Join-Path $workflows 'code-review.yml'), $case.Workflow) }
        Push-Location $folder
        try { $note = (Get-CodeReviewNote) -join "`n" }
        finally { Pop-Location }
        if ($case.Want.Count) {
            $missing = @($case.Want | Where-Object { -not $note.Contains($_) })
            $unwanted = @($case.Not | Where-Object { $note.Contains($_) })
            Check "code-review: $name" (-not $missing.Count -and -not $unwanted.Count) "missing [$($missing -join '], [')], unwanted [$($unwanted -join '], [')] in [$note]"
        }
        else { Check "code-review: $name" (-not $note.Trim()) "got [$note]" }
    }
}
$codeReviewNote

# immutable: Get-ImmutableReleaseNote, run from inside each fixture folder, which is also the project.
$immutableNote = & {
    $updateScript = Join-Path $repoRoot 'template\.template\Update-Project.ps1'
    $ast = [Management.Automation.Language.Parser]::ParseFile($updateScript, [ref]$null, [ref]$null)
    foreach ($fnName in 'Get-WorkflowEvents', 'Test-ReleaseAssetWorkflow', 'Get-ImmutableReleaseNote') {
        $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $paragraph = "## Verify a Release`n`nReleases are immutable: once one is published.`n"
    $releaseEvent = "on:`n  release:`n    types: [published]`n"
    $immutableCases = [ordered]@{
        'paragraph, release workflow'    = @{ Security = $paragraph; File = 'publish.yml'; Workflow = $releaseEvent; Offered = $false; Want = @('SECURITY.md says', '.github/workflows/publish.yml', 'Delete the paragraph') }
        'offered, upload workflow'       = @{ Security = "# Security`n"; File = 'attach.yml'; Workflow = "on: workflow_dispatch`njobs:`n  a:`n    steps:`n      - run: gh release upload v1.0.0 dist/app.tgz`n"; Offered = $true; Want = @('The template''s change to SECURITY.md above', 'Leave out the paragraph') }
        'paragraph, no release workflow' = @{ Security = $paragraph; File = 'tag-release.yml'; Workflow = "on:`n  push:`njobs:`n  release:`n    runs-on: x`n"; Offered = $false; Want = @() }
        'no paragraph'                   = @{ Security = "# Security`n"; File = 'publish.yml'; Workflow = $releaseEvent; Offered = $false; Want = @() }
        'paragraph, upload in a comment' = @{ Security = $paragraph; File = 'notes.yml'; Workflow = "on: workflow_dispatch`njobs:`n  a:`n    runs-on: x`n    steps:`n      # gh release upload runs in attach.yml`n      - run: echo hi`n"; Offered = $false; Want = @() }
    }
    foreach ($name in $immutableCases.Keys) {
        $case = $immutableCases[$name]
        $folder = Join-Path $Work "immutable-$($name -replace '\W+', '-')"
        $workflows = Join-Path $folder '.github/workflows'
        $null = New-Item -ItemType Directory -Path $workflows -Force
        [IO.File]::WriteAllText((Join-Path $folder 'SECURITY.md'), $case.Security)
        [IO.File]::WriteAllText((Join-Path $workflows $case.File), $case.Workflow)
        Push-Location $folder
        try { $note = (Get-ImmutableReleaseNote $case.Offered) -join "`n" }
        finally { Pop-Location }
        if ($case.Want.Count) {
            $missing = @($case.Want | Where-Object { -not $note.Contains($_) })
            Check "immutable: $name" (-not $missing.Count) "missing [$($missing -join '], [')] in [$note]"
        }
        else { Check "immutable: $name" (-not $note.Trim()) "got [$note]" }
    }

    # copies: the two functions copied into Update-Project.ps1 match the ones in tools/Set-RepositoryBaseline.ps1.
    $baselineAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'tools\Set-RepositoryBaseline.ps1'), [ref]$null, [ref]$null)
    $differ = foreach ($fnName in 'Get-WorkflowEvents', 'Test-ReleaseAssetWorkflow') {
        $isFn = { param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }
        $copy = $ast.Find($isFn, $true)
        $original = $baselineAst.Find($isFn, $true)
        if (-not $copy -or -not $original -or $copy.Extent.Text -ne $original.Extent.Text) { $fnName }
    }
    Check 'copies: Get-WorkflowEvents and Test-ReleaseAssetWorkflow match tools/Set-RepositoryBaseline.ps1''s' (-not $differ) "differ: [$($differ -join ', ')]"
    $adoptAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'Adopt-Project.ps1'), [ref]$null, [ref]$null)
    $adoptDiffer = foreach ($fnName in 'Get-WorkflowEvents', 'Test-ReleaseAssetWorkflow', 'Get-ImmutableReleaseNote') {
        $isFn = { param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }
        $copy = $adoptAst.Find($isFn, $true)
        $original = $ast.Find($isFn, $true)
        if (-not $copy -or -not $original -or $copy.Extent.Text -ne $original.Extent.Text) { $fnName }
    }
    Check 'copies: Adopt-Project.ps1''s Get-WorkflowEvents, Test-ReleaseAssetWorkflow and Get-ImmutableReleaseNote match Update-Project.ps1''s' (-not $adoptDiffer) "differ: [$($adoptDiffer -join ', ')]"
}
$immutableNote

''
if ($failures.Count) { "Kept the work folder: $Work"; "Update notes tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update notes tests: PASSED'
exit 0
