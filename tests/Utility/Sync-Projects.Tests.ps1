# Tests for Sync-Projects.ps1
# Pester 3.4.0 syntax (ships with Windows Server 2019/2022)
#
# Run:
#   Invoke-Pester .\tests\Utility\Sync-Projects.Tests.ps1 -Verbose

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $here '..\..\scripts\Utility\Sync-Projects.ps1'

. $scriptPath

# ---------------------------------------------------------------------------
# Invoke-RepoSync
# ---------------------------------------------------------------------------

Describe 'Invoke-RepoSync' {

    $testParams = @{
        RepoName    = 'test-repo'
        SshHost     = 'github-test'
        GitHubUser  = 'TestUser'
        ProjectsDir = 'C:\TestProjects'
    }

    Context 'When repository does not exist locally' {

        Mock Test-Path     { return $false }
        Mock Invoke-GitCommand { return 0 }

        It 'Should call git clone' {
            Invoke-RepoSync @testParams | Out-Null
            Assert-MockCalled Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'clone'
            } -Times 1
        }

        It 'Should return true when clone succeeds' {
            $result = Invoke-RepoSync @testParams
            $result | Should Be $true
        }
    }

    Context 'When repository does not exist and clone fails' {

        Mock Test-Path         { return $false }
        Mock Invoke-GitCommand { return 1 }

        It 'Should return false' {
            $result = Invoke-RepoSync @testParams
            $result | Should Be $false
        }
    }

    Context 'When repository exists and working tree is clean' {

        Mock Test-Path         { return $true }
        # All git calls succeed (diffs return 0 = clean, pull returns 0)
        Mock Invoke-GitCommand { return 0 }

        It 'Should call git pull without --rebase' {
            Invoke-RepoSync @testParams | Out-Null
            Assert-MockCalled Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'pull' -and $Arguments -notcontains '--rebase'
            } -Times 1
        }

        It 'Should return true when pull succeeds' {
            $result = Invoke-RepoSync @testParams
            $result | Should Be $true
        }
    }

    Context 'When repository exists and working tree is dirty' {

        Mock Test-Path { return $true }
        # Working-tree diff returns 1 (dirty); everything else returns 0
        Mock Invoke-GitCommand { return 1 } -ParameterFilter {
            $Arguments -contains 'diff' -and $Arguments -notcontains '--cached'
        }
        Mock Invoke-GitCommand { return 0 }

        It 'Should call git pull --rebase' {
            Invoke-RepoSync @testParams | Out-Null
            Assert-MockCalled Invoke-GitCommand -ParameterFilter {
                $Arguments -contains '--rebase'
            } -Times 1
        }

        It 'Should return true when rebase pull succeeds' {
            $result = Invoke-RepoSync @testParams
            $result | Should Be $true
        }
    }

    Context 'When repository exists and staged changes are present' {

        Mock Test-Path { return $true }
        # Staged diff returns 1 (dirty); everything else returns 0
        Mock Invoke-GitCommand { return 1 } -ParameterFilter {
            $Arguments -contains '--cached'
        }
        Mock Invoke-GitCommand { return 0 }

        It 'Should call git pull --rebase' {
            Invoke-RepoSync @testParams | Out-Null
            Assert-MockCalled Invoke-GitCommand -ParameterFilter {
                $Arguments -contains '--rebase'
            } -Times 1
        }
    }

    Context 'When repository exists and pull fails' {

        Mock Test-Path { return $true }
        # Diffs return 0 (clean), but pull fails
        Mock Invoke-GitCommand { return 0 } -ParameterFilter {
            $Arguments -contains 'diff'
        }
        Mock Invoke-GitCommand { return 1 } -ParameterFilter {
            $Arguments -contains 'pull'
        }

        It 'Should return false' {
            $result = Invoke-RepoSync @testParams
            $result | Should Be $false
        }
    }
}

# ---------------------------------------------------------------------------
# Sync-Projects
# ---------------------------------------------------------------------------

Describe 'Sync-Projects' {

    Context 'When ProjectsDir does not exist' {

        Mock Test-Path      { return $false }
        Mock New-Item       { }
        Mock Invoke-RepoSync { return $true }

        It 'Should create the projects directory' {
            Sync-Projects -ProjectsDir 'C:\TestProjects'
            Assert-MockCalled New-Item -Times 1
        }
    }

    Context 'When ProjectsDir already exists' {

        Mock Test-Path       { return $true }
        Mock New-Item        { }
        Mock Invoke-RepoSync { return $true }

        It 'Should not create the projects directory' {
            Sync-Projects -ProjectsDir 'C:\TestProjects'
            Assert-MockCalled New-Item -Times 0
        }
    }

    Context 'When syncing all repositories' {

        Mock Test-Path       { return $true }
        Mock Invoke-RepoSync { return $true }

        It 'Should sync 6 Fragsrus repositories' {
            Sync-Projects -ProjectsDir 'C:\TestProjects'
            Assert-MockCalled Invoke-RepoSync -ParameterFilter {
                $SshHost -eq 'github-fragsrus'
            } -Times 6
        }

        It 'Should sync 13 darrel-wallace repositories' {
            Sync-Projects -ProjectsDir 'C:\TestProjects'
            Assert-MockCalled Invoke-RepoSync -ParameterFilter {
                $SshHost -eq 'github-darrel-wallace'
            } -Times 13
        }
    }

    Context 'When some repositories fail' {

        $script:syncCallCount = 0

        Mock Test-Path { return $true }
        Mock Invoke-RepoSync {
            $script:syncCallCount++
            # First two calls fail, rest succeed
            if ($script:syncCallCount -le 2) { return $false }
            return $true
        }

        It 'Should still attempt all repositories' {
            $script:syncCallCount = 0
            Sync-Projects -ProjectsDir 'C:\TestProjects'
            # 6 Fragsrus + 13 darrel-wallace = 19 total
            $script:syncCallCount | Should Be 19
        }
    }
}
