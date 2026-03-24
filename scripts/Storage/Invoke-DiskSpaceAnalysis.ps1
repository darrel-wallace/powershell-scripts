function Invoke-DiskSpaceAnalysis {
    <#
    .SYNOPSIS
        Performs a comprehensive disk space analysis to identify space consumers on a given drive.

    .DESCRIPTION
        Designed to investigate disk-filling issues by identifying the largest directories and files.
        Produces two directory views: a hierarchical rollup (total size including all subdirectories,
        best for root cause analysis) and a leaf-directory view (direct file content only, best for
        pinpointing exact locations).

        Also reports on Docker data paths, known Windows bloat locations, VSS shadow storage,
        system files (pagefile/hiberfil), and paths that were inaccessible during the scan.

        Intended to be run as SYSTEM via Task Scheduler. The running account is recorded in the
        report so that coverage gaps can be identified. SYSTEM has full access to service-owned
        paths but cannot see user-profile content that is ACL'd to specific users; running as
        an admin account captures the inverse. Compare both runs for complete coverage.

    .PARAMETER DrivePath
        The root path to analyze, e.g. "C:\".

    .PARAMETER OutputPath
        Directory where the report file and transcript log are saved. Defaults to "C:\temp".
        Created automatically if it does not exist.

    .PARAMETER TopFolderCount
        Number of leaf directories to include in the direct-content section. Defaults to 50.

    .PARAMETER TopFileCount
        Number of individual files to include in the largest-files section. Defaults to 25.

    .PARAMETER TopRollupCount
        Number of directories to include in the hierarchical rollup section. Defaults to 50.

    .EXAMPLE
        Invoke-DiskSpaceAnalysis -DrivePath 'C:\' -OutputPath 'D:\Reports'

        Scans C:\ and writes the report and transcript to D:\Reports.

    .EXAMPLE
        Invoke-DiskSpaceAnalysis -DrivePath 'C:\' -TopRollupCount 100 -TopFileCount 50

        Scans C:\ with expanded rollup and file counts, output to default C:\temp.

    .OUTPUTS
        System.String. The full path to the generated report file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$DrivePath,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = 'C:\temp',

        [Parameter(Mandatory = $false)]
        [int]$TopFolderCount = 50,

        [Parameter(Mandatory = $false)]
        [int]$TopFileCount = 25,

        [Parameter(Mandatory = $false)]
        [int]$TopRollupCount = 50
    )

    # Always emit verbose output so scheduled-task transcripts capture full detail.
    $VerbosePreference = 'Continue'

    # --- IDENTITY ---
    $RunningAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # --- LOGGING ---
    # New-Item -Force creates all intermediate directories, so OutputPath is also created here.
    $LogPath = Join-Path -Path $OutputPath -ChildPath 'logs'
    if (-not (Test-Path -Path $LogPath -PathType Container)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    $Timestamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $TranscriptLog  = Join-Path -Path $LogPath -ChildPath "DiskSpaceAnalysis_$Timestamp.log"
    $OutputFile     = Join-Path -Path $OutputPath -ChildPath "DiskSpaceReport_$Timestamp.txt"
    Start-Transcript -Path $TranscriptLog | Out-Null

    Write-Verbose "=== Disk Space Analysis Started: $(Get-Date) ==="
    Write-Verbose "Running as : $RunningAs"
    Write-Verbose "Target     : $DrivePath"
    Write-Verbose "Output     : $OutputFile"

    # =========================================================================
    # STEP 1 -- GATHER ALL FILES
    # =========================================================================
    Write-Verbose "Step 1/5: Gathering all file information (this may take several minutes)..."
    $SkippedErrors = @()
    $allFiles = Get-ChildItem -Path $DrivePath -Recurse -File -Force `
        -ErrorAction SilentlyContinue -ErrorVariable +SkippedErrors
    Write-Verbose "  Found $($allFiles.Count) files. Access errors: $($SkippedErrors.Count)"

    # =========================================================================
    # STEP 2 -- HIERARCHICAL ROLLUP
    # For each file, accumulate its size into every ancestor directory entry.
    # This gives the total on-disk footprint of every directory at every depth.
    # =========================================================================
    Write-Verbose "Step 2/5: Building hierarchical size rollup..."
    $dirRollup = @{}
    foreach ($file in $allFiles) {
        $current = $file.DirectoryName
        while (-not [string]::IsNullOrEmpty($current)) {
            if ($dirRollup.ContainsKey($current)) {
                $dirRollup[$current] += $file.Length
            }
            else {
                $dirRollup[$current] = $file.Length
            }
            $parent = Split-Path -Path $current -Parent
            # Split-Path returns the same value at the drive root -- stop there.
            if ($parent -eq $current) { break }
            $current = $parent
        }
    }

    $topRollup = $dirRollup.GetEnumerator() |
        Select-Object @{N = 'Directory'; E = { $_.Key } },
                      @{N = 'TotalSizeGB'; E = { [Math]::Round($_.Value / 1GB, 4) } } |
        Sort-Object -Property TotalSizeGB -Descending |
        Select-Object -First $TopRollupCount

    # =========================================================================
    # STEP 3 -- LEAF DIRECTORY SIZES AND TOP FILES
    # =========================================================================
    Write-Verbose "Step 3/5: Calculating leaf directory and individual file sizes..."
    $topFolders = $allFiles | Group-Object DirectoryName |
        Select-Object @{N = 'Directory'; E = { $_.Name } },
                      @{N = 'DirectSizeGB'; E = { [Math]::Round(($_.Group | Measure-Object Length -Sum).Sum / 1GB, 4) } } |
        Sort-Object -Property DirectSizeGB -Descending |
        Select-Object -First $TopFolderCount

    $topFiles = $allFiles |
        Sort-Object -Property Length -Descending |
        Select-Object -First $TopFileCount |
        Select-Object @{N = 'FilePath'; E = { $_.FullName } },
                      @{N = 'SizeGB';   E = { [Math]::Round($_.Length / 1GB, 4) } }

    # =========================================================================
    # STEP 4 -- SUPPLEMENTAL DATA (Docker, VSS, known paths, system files)
    # =========================================================================
    Write-Verbose "Step 4/5: Collecting supplemental data..."

    # --- Blocked paths ---
    # Surface which areas of the drive were inaccessible so the caller knows
    # where coverage gaps exist for this account.
    $topBlocked = $SkippedErrors |
        Where-Object { $null -ne $_.TargetObject } |
        ForEach-Object {
            $raw = $_.TargetObject
            $path = if ($raw -is [System.IO.FileSystemInfo]) { $raw.FullName }
                    elseif ($raw -is [string])               { $raw }
                    else                                     { $_.Exception.Message }
            try { Split-Path -Path $path -Parent } catch { $path }
        } |
        Group-Object |
        Select-Object @{N = 'BlockedUnderPath'; E = { $_.Name } },
                      @{N = 'ErrorCount';       E = { $_.Count } } |
        Sort-Object -Property ErrorCount -Descending |
        Select-Object -First 20

    # --- Known Windows bloat locations ---
    $knownLocations = [ordered]@{
        'WinSxS Component Store'       = 'C:\Windows\WinSxS'
        'Windows Installer Cache'      = 'C:\Windows\Installer'
        'Windows Update Download Cache'= 'C:\Windows\SoftwareDistribution\Download'
        'Windows Temp'                 = 'C:\Windows\Temp'
        'IIS Logs'                     = 'C:\inetpub\logs'
        'Event Logs'                   = 'C:\Windows\System32\winevt\Logs'
        'Recycle Bin'                  = 'C:\$Recycle.Bin'
    }
    $knownBloatRows = foreach ($entry in $knownLocations.GetEnumerator()) {
        if (Test-Path $entry.Value) {
            $bytes = (Get-ChildItem -Path $entry.Value -Recurse -File -Force `
                -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            [PSCustomObject]@{
                Label  = $entry.Key
                Path   = $entry.Value
                SizeGB = [Math]::Round($bytes / 1GB, 4)
            }
        }
    }
    $knownBloatRows = @($knownBloatRows) | Sort-Object -Property SizeGB -Descending

    # --- System files (not enumerated by Get-ChildItem) ---
    $systemFileRows = foreach ($p in @('C:\pagefile.sys', 'C:\hiberfil.sys', 'C:\swapfile.sys')) {
        $item = Get-Item -Path $p -Force -ErrorAction SilentlyContinue
        if ($item) {
            [PSCustomObject]@{
                File   = $item.FullName
                SizeGB = [Math]::Round($item.Length / 1GB, 4)
            }
        }
    }

    # --- VSS shadow storage ---
    $vssText = ''
    try {
        $shadowStorage = @(Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop)
        if ($shadowStorage.Count -gt 0) {
            $vssRows = $shadowStorage | Select-Object `
                @{N = 'Volume';      E = { $_.Volume -replace '\\\\\.\\', '' } },
                @{N = 'UsedGB';      E = { [Math]::Round($_.UsedSpace / 1GB, 2) } },
                @{N = 'AllocatedGB'; E = { [Math]::Round($_.AllocatedSpace / 1GB, 2) } },
                @{N = 'MaxGB';       E = { [Math]::Round($_.MaxSpace / 1GB, 2) } }
            $vssText = $vssRows | Format-Table -AutoSize | Out-String -Width 4096
        }
        else {
            $vssText = '  No VSS shadow storage found.'
        }
    }
    catch {
        $vssText = "  VSS query failed: $($_.Exception.Message)"
    }

    # --- Docker ---
    # Running as SYSTEM: $env:LOCALAPPDATA resolves to the SYSTEM profile, not a user profile.
    # Docker Desktop WSL virtual disks live under each user's own AppData. Scan all profiles.
    $dockerDetected = $false
    $dockerServiceStatus = 'Not detected'
    $dockerDirRows = @()
    $vhdxRows = @()

    $dockerSvc = Get-Service -Name docker -ErrorAction SilentlyContinue
    if ($null -ne $dockerSvc) {
        $dockerDetected = $true
        $dockerServiceStatus = $dockerSvc.Status.ToString()
    }

    $dockerSystemPaths = @('C:\ProgramData\Docker', 'C:\ProgramData\DockerDesktop')
    foreach ($dp in $dockerSystemPaths) {
        if (Test-Path $dp) {
            $dockerDetected = $true
            $bytes = (Get-ChildItem -Path $dp -Recurse -File -Force `
                -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dockerDirRows += [PSCustomObject]@{
                Path   = $dp
                SizeGB = [Math]::Round($bytes / 1GB, 4)
            }
        }
    }

    # Scan all user profiles for Docker AppData (the WSL virtual disk lives here)
    $userProfiles = Get-ChildItem -Path 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue
    foreach ($userProfile in $userProfiles) {
        $userDockerPath = Join-Path -Path $userProfile.FullName -ChildPath 'AppData\Local\Docker'
        if (Test-Path $userDockerPath) {
            $dockerDetected = $true
            $bytes = (Get-ChildItem -Path $userDockerPath -Recurse -File -Force `
                -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dockerDirRows += [PSCustomObject]@{
                Path   = $userDockerPath
                SizeGB = [Math]::Round($bytes / 1GB, 4)
            }
            # Look specifically for WSL virtual disk files -- these grow but never auto-shrink
            $vhdxFound = Get-ChildItem -Path $userDockerPath -Recurse -Filter '*.vhdx' -Force `
                -ErrorAction SilentlyContinue
            foreach ($vhdx in $vhdxFound) {
                $vhdxRows += [PSCustomObject]@{
                    FilePath = $vhdx.FullName
                    SizeGB   = [Math]::Round($vhdx.Length / 1GB, 4)
                }
            }
        }
    }

    # =========================================================================
    # STEP 5 -- COMPOSE AND WRITE REPORT
    # =========================================================================
    Write-Verbose "Step 5/5: Writing report..."

    $dockerBlock = if ($dockerDetected) {
        $dirTable  = if ($dockerDirRows.Count -gt 0) {
            $dockerDirRows | Sort-Object SizeGB -Descending | Format-Table -AutoSize | Out-String -Width 4096
        } else { '  No Docker directories measured.' }

        $vhdxBlock = if ($vhdxRows.Count -gt 0) {
            @"

  WSL Virtual Disk Files (grow on use, do NOT auto-shrink after docker system prune):
$($vhdxRows | Format-Table -AutoSize | Out-String -Width 4096)
  To reclaim WSL disk space:
    1. docker system prune -a --volumes
    2. wsl --shutdown
    3. (Requires Hyper-V tools) Optimize-VHD -Path "<vhdx path>" -Mode Full
    OR (no Hyper-V tools required -- run as Admin):
       diskpart -> select vdisk file="<vhdx path>" -> attach vdisk readonly -> compact vdisk -> detach vdisk
"@
        } else { '' }

        @"

==================================================
DOCKER DATA PATHS
==================================================
Docker service status: $dockerServiceStatus

Directory sizes (system paths + all user profiles scanned):
$dirTable$vhdxBlock
"@
    } else {
        "`r`n  Docker not detected on this system.`r`n"
    }

    $report = @"
==================================================
DISK SPACE ANALYSIS REPORT
==================================================
Analysis Target : $DrivePath
Report Time     : $(Get-Date)
Running As      : $RunningAs
Total Files     : $($allFiles.Count)
Access Errors   : $($SkippedErrors.Count)

IMPORTANT: This report reflects only what the account above could access.
  - SYSTEM account: full visibility into service/OS paths, limited visibility into user profiles.
  - Admin account : full visibility into user profiles, may be blocked from some service paths.
  For complete coverage of an unknown space issue, run once as SYSTEM and once as an admin.
  WinSxS sizes appear inflated due to NTFS hard links -- actual unique data is smaller.

==================================================
TOP $TopRollupCount DIRECTORIES -- HIERARCHICAL ROLLUP
(Total size including all subdirectories. Use this to narrow down the problem area.)
==================================================
$($topRollup | Format-Table -AutoSize | Out-String -Width 4096)
==================================================
TOP $TopFolderCount DIRECTORIES -- DIRECT CONTENT ONLY
(Files directly inside that folder, no subdirectories. Use this to pinpoint exact locations.)
==================================================
$($topFolders | Format-Table -AutoSize | Out-String -Width 4096)
==================================================
TOP $TopFileCount LARGEST INDIVIDUAL FILES
==================================================
$($topFiles | Format-Table -AutoSize | Out-String -Width 4096)
==================================================
KNOWN WINDOWS BLOAT LOCATIONS
==================================================
$($knownBloatRows | Format-Table -AutoSize | Out-String -Width 4096)
==================================================
SYSTEM FILES (not shown in directory scans above)
==================================================
$($systemFileRows | Format-Table -AutoSize | Out-String -Width 4096)
==================================================
VSS SHADOW COPY STORAGE
(Allocated outside the normal file system -- NOT counted in directory sizes above.)
==================================================
$vssText
$dockerBlock
==================================================
TOP 20 BLOCKED PATHS
(Areas this account could not read. Re-run as a different account to cover these.)
==================================================
$($topBlocked | Format-Table -AutoSize | Out-String -Width 4096)
==================================================
REMEDIATION NOTES
==================================================
1. DOCKER WSL VIRTUAL DISK (ext4.vhdx) -- most common cause of silent C:\ growth
   The vhdx grows as images and containers accumulate but never shrinks automatically.
   See the Docker Data Paths section above for reclaim instructions.

2. PAGEFILE.SYS / HIBERFIL.SYS
   Manage pagefile: Advanced System Settings -> Performance -> Virtual Memory.
   Disable hibernation (removes hiberfil.sys): powercfg /h off

3. WINSXS COMPONENT STORE
   Do NOT delete manually. Clean with DISM:
     Dism.exe /online /Cleanup-Image /StartComponentCleanup
     Dism.exe /online /Cleanup-Image /SPSuperseded

4. WINDOWS UPDATE DOWNLOAD CACHE (SoftwareDistribution\Download)
   Safe to clear when Windows Update is not running:
     Stop-Service wuauserv
     Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force
     Start-Service wuauserv

5. WINDOWS INSTALLER CACHE (C:\Windows\Installer)
   Do NOT delete manually. Use Disk Cleanup (cleanmgr.exe) -> Windows Update Cleanup.

6. IIS LOGS
   Review and enforce a log retention policy. Old logs are safe to delete.

7. RECYCLE BIN
   Clear-RecycleBin -Force

8. EVENT LOGS
   Logs have a configured max size; if they are large, review the retention policy in
   Event Viewer -> Windows Logs -> [log name] -> Properties.
--------------------------------------------------
End of Report
"@

    $report | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Verbose "=== Analysis complete. Report: $OutputFile ==="
    Stop-Transcript | Out-Null

    return $OutputFile
}
