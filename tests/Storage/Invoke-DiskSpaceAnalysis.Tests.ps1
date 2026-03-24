$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $here)) `
                    -ChildPath 'scripts\Storage\Invoke-DiskSpaceAnalysis.ps1'

. $script

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function New-TestDrive {
    param([string]$Root)
    New-Item -Path $Root -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $Root 'SubA') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $Root 'SubB') -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Root 'root.txt'),        'root content')
    [System.IO.File]::WriteAllText((Join-Path $Root 'SubA\fileA1.txt'), 'A1 content')
    [System.IO.File]::WriteAllText((Join-Path $Root 'SubA\fileA2.txt'), 'A2 content')
    [System.IO.File]::WriteAllText((Join-Path $Root 'SubB\fileB1.log'), 'B1 content')
}

function Remove-TestDrive {
    param([string]$Root)
    if (Test-Path $Root) {
        Remove-Item -Path $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Shared test paths
# ---------------------------------------------------------------------------
$testBase   = Join-Path $env:TEMP 'PesterDiskAnalysis'
$testDrive  = Join-Path $testBase 'drive'
$testOutput = Join-Path $testBase 'output'

# ---------------------------------------------------------------------------
Describe 'Invoke-DiskSpaceAnalysis' {

    BeforeAll {
        New-TestDrive -Root $testDrive
        # Run the function once and share results across all It blocks.
        # This avoids repeated transcript conflicts and keeps the suite fast.
        $script:reportPath    = Invoke-DiskSpaceAnalysis -DrivePath $testDrive -OutputPath $testOutput
        $script:reportContent = if (Test-Path $script:reportPath) {
            [System.IO.File]::ReadAllText($script:reportPath)
        }
        else {
            ''
        }
    }

    AfterAll {
        Remove-TestDrive -Root $testBase
    }

    # --- Availability ---

    It 'is available after dot-sourcing the script' {
        $cmd = Get-Command -Name Invoke-DiskSpaceAnalysis -ErrorAction SilentlyContinue
        $cmd | Should Not BeNullOrEmpty
    }

    # --- Parameter validation ---

    It 'throws when DrivePath does not exist' {
        { Invoke-DiskSpaceAnalysis -DrivePath 'Z:\DoesNotExist_Pester' -OutputPath $testOutput } |
            Should Throw
    }

    # --- Happy path ---

    It 'returns a string path to the report file' {
        $script:reportPath | Should BeOfType 'System.String'
    }

    It 'creates the report file on disk' {
        (Test-Path -Path $script:reportPath -PathType Leaf) | Should Be $true
    }

    It 'creates the transcript log in the logs subdirectory' {
        $logDir  = Join-Path $testOutput 'logs'
        $logFile = Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
                   Select-Object -First 1
        $logFile | Should Not BeNullOrEmpty
    }

    # --- Report content ---

    It 'report contains the hierarchical rollup section header' {
        $script:reportContent | Should Match 'HIERARCHICAL ROLLUP'
    }

    It 'report contains the direct content section header' {
        $script:reportContent | Should Match 'DIRECT CONTENT ONLY'
    }

    It 'report contains the largest files section header' {
        $script:reportContent | Should Match 'LARGEST INDIVIDUAL FILES'
    }

    It 'report contains the blocked paths section header' {
        $script:reportContent | Should Match 'BLOCKED PATHS'
    }

    It 'report contains the remediation notes section' {
        $script:reportContent | Should Match 'REMEDIATION NOTES'
    }

    It 'report records the account the script ran as' {
        $script:reportContent | Should Match 'Running As'
    }

    It 'report lists the test drive path as the analysis target' {
        $escaped = [regex]::Escape($testDrive)
        $script:reportContent | Should Match $escaped
    }

    It 'report contains the VSS shadow copy section header' {
        $script:reportContent | Should Match 'VSS SHADOW COPY'
    }

    It 'report contains the known bloat locations section header' {
        $script:reportContent | Should Match 'KNOWN WINDOWS BLOAT'
    }
}
