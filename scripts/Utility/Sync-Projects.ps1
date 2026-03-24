<#
.SYNOPSIS
    Clones or pulls all GitHub repositories for both configured accounts.

.DESCRIPTION
    Iterates over a predefined list of GitHub repositories for the Fragsrus
    (personal) and darrel-wallace (professional) accounts. For each repository,
    clones it if the local directory does not exist, or pulls the latest changes
    if it does. Detects uncommitted local changes and uses git pull --rebase in
    that case to avoid a merge commit.

    Requires git to be installed and on the PATH. SSH keys must be configured
    for both accounts in ~/.ssh/config using the host aliases github-fragsrus
    and github-darrel-wallace.

.PARAMETER ProjectsDir
    Root directory under which all repositories are stored.
    Defaults to C:\Projects.

.EXAMPLE
    Sync-Projects

    Syncs all repositories into C:\Projects using the default directory.

.EXAMPLE
    Sync-Projects -ProjectsDir 'D:\Work'

    Syncs all repositories into D:\Work.

.NOTES
    Target:   Windows PowerShell 5.1
    Requires: git on PATH; SSH config with github-fragsrus and
              github-darrel-wallace host aliases
    Author:   Darrel Wallace
#>

function Invoke-GitCommand {
    <#
    .SYNOPSIS
        Runs a git command and returns the exit code.
    .DESCRIPTION
        Thin wrapper around git to keep the exit code testable without
        relying on $LASTEXITCODE leaking across scopes.
    .PARAMETER Arguments
        Array of arguments to pass to git.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & git @Arguments | Out-Null
    return $LASTEXITCODE
}

function Invoke-RepoSync {
    <#
    .SYNOPSIS
        Clones or pulls a single repository.
    .DESCRIPTION
        Checks whether the repository already exists locally. If it does,
        pulls the latest changes (using --rebase when the working tree is
        dirty). If it does not exist, clones it from the specified SSH host.
    .PARAMETER RepoName
        Name of the repository (also used as the local directory name).
    .PARAMETER SshHost
        SSH host alias as defined in ~/.ssh/config (e.g. github-fragsrus).
    .PARAMETER GitHubUser
        GitHub username that owns the repository.
    .PARAMETER ProjectsDir
        Root directory under which repositories are stored.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$SshHost,

        [Parameter(Mandatory = $true)]
        [string]$GitHubUser,

        [Parameter(Mandatory = $true)]
        [string]$ProjectsDir
    )

    $repoPath = Join-Path $ProjectsDir $RepoName
    $gitDir   = Join-Path $repoPath '.git'

    Write-Host ('-' * 54) -ForegroundColor Cyan
    Write-Host "Repository: $RepoName ($GitHubUser)" -ForegroundColor Cyan

    if (Test-Path -Path $gitDir -PathType Container) {
        Write-Host '-> Pulling latest changes...' -ForegroundColor Yellow

        $diffExit   = Invoke-GitCommand -Arguments @('-C', $repoPath, 'diff', '--quiet')
        $cachedExit = Invoke-GitCommand -Arguments @('-C', $repoPath, 'diff', '--cached', '--quiet')
        $isDirty    = ($diffExit -ne 0) -or ($cachedExit -ne 0)

        if ($isDirty) {
            Write-Host '   ! Uncommitted changes detected, pulling with rebase' -ForegroundColor Yellow
            $pullExit = Invoke-GitCommand -Arguments @('-C', $repoPath, 'pull', '--rebase')
        }
        else {
            $pullExit = Invoke-GitCommand -Arguments @('-C', $repoPath, 'pull')
        }

        if ($pullExit -ne 0) {
            Write-Host '   x Pull failed' -ForegroundColor Red
            return $false
        }

        Write-Host '   + Up to date' -ForegroundColor Green
        return $true
    }
    else {
        Write-Host '-> Cloning...' -ForegroundColor Yellow

        $cloneUri  = "git@${SshHost}:${GitHubUser}/${RepoName}.git"
        $cloneExit = Invoke-GitCommand -Arguments @('clone', $cloneUri, $repoPath)

        if ($cloneExit -ne 0) {
            Write-Host '   x Clone failed' -ForegroundColor Red
            return $false
        }

        Write-Host '   + Cloned successfully' -ForegroundColor Green
        return $true
    }
}

function Sync-Projects {
    # PSUseSingularNouns suppressed: the plural 'Projects' is intentional;
    # this function syncs multiple repositories across multiple accounts.
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectsDir = 'C:\Projects'
    )

    $fragsrusRepos = @(
        'claude-playbooks'
        'notes-processing-pipeline'
        'cyberpunk-2077-ai-guides'
        'claude-ai-archive'
        'neural_heritage'
        'unraid-server'
    )

    $darrelWallaceRepos = @(
        'aws-agent-self-heal'
        'cloud-resume-challenge'
        'ai-agent-command-center'
        'ai-research-engine'
        'ai-platform-lab'
        'dev-environment-config'
        'home-network-config-and-optimization'
        'private-ai-research-data'
        'virtualbox-hybrid-cloud-lab'
        'career-development'
        'aws-unattended-patching'
        'powershell-scripts'
    )

    Write-Host ''
    Write-Host '+======================================================+' -ForegroundColor Green
    Write-Host '|           Project Sync - All Repositories            |' -ForegroundColor Green
    Write-Host '+======================================================+' -ForegroundColor Green
    Write-Host ''
    Write-Host "Projects directory: $ProjectsDir" -ForegroundColor Cyan
    Write-Host ''

    if (-not (Test-Path -Path $ProjectsDir)) {
        New-Item -ItemType Directory -Path $ProjectsDir | Out-Null
    }

    $successCount = 0
    $failedCount  = 0

    Write-Host '> Fragsrus Account (Personal)' -ForegroundColor Green
    foreach ($repo in $fragsrusRepos) {
        $ok = Invoke-RepoSync -RepoName $repo `
                              -SshHost 'github-fragsrus' `
                              -GitHubUser 'Fragsrus' `
                              -ProjectsDir $ProjectsDir
        if ($ok) { $successCount++ } else { $failedCount++ }
    }

    Write-Host ''
    Write-Host '> darrel-wallace Account (Professional)' -ForegroundColor Green
    foreach ($repo in $darrelWallaceRepos) {
        $ok = Invoke-RepoSync -RepoName $repo `
                              -SshHost 'github-darrel-wallace' `
                              -GitHubUser 'darrel-wallace' `
                              -ProjectsDir $ProjectsDir
        if ($ok) { $successCount++ } else { $failedCount++ }
    }

    Write-Host ''
    Write-Host ('-' * 54) -ForegroundColor Cyan
    Write-Host "Summary: $successCount succeeded, $failedCount failed" -ForegroundColor Green
    Write-Host ''
}
