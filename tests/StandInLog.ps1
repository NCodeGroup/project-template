<#
.SYNOPSIS
    The function the gh and glab stand-ins of the tests dot-source to append a line to their logs.

.DESCRIPTION
    workflow/Get-PlanState.ps1 makes its gh and glab calls at the same time, in runspaces or processes of their own, and
    an append to a file while another is open fails with a sharing violation. Add-StandInLog makes the appends to one
    file take turns through a named mutex whose name comes from the file's full path, in any letter case, so the calls
    that log to one file wait on each other and no others do. A call that finds the mutex abandoned, by a process that
    ended while it held it, takes it and goes on. A stand-in finds this script beside it: Copy-StandIn in
    tests/e2e/Fixture.ps1 copies it with each end-to-end stand-in, and tests/Test-PlanState.ps1 copies it into the
    folder it writes its stand-ins to.
#>

function Add-StandInLog([string]$Path, [string]$Line) {
    $file = [IO.Path]::GetFullPath($Path)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($file.ToUpperInvariant())))
    $mutex = [Threading.Mutex]::new($false, "project-template-stand-in-log-$($hash.Substring(0, 32))")
    try {
        try { $null = $mutex.WaitOne() }
        catch [Threading.AbandonedMutexException] { Write-Verbose 'A call ended while it held the log; this call holds it now.' }
        [IO.File]::AppendAllText($file, "$Line`n")
    }
    finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
