# PowerShell Scripts — Session Log

---

## 2026-03-24 — Invoke-DiskSpaceAnalysis.ps1

### Objective
Build a comprehensive disk space analysis script for investigating C:\ fill issues (primary trigger: Docker builds failing due to disk pressure).

### Design decisions

| Decision | Rationale |
|---|---|
| Hierarchical rollup via hashtable | `Group-Object DirectoryName` only gives leaf-dir sizes; rolled-up totals required to see e.g. `C:\ProgramData\Docker` as a single large entry |
| Suppress `Start-Transcript` / `Stop-Transcript` output | Both emit to the pipeline in PS5.1; suppressing with `| Out-Null` keeps the function return value clean (path string only) |
| Scan all user profiles for Docker VHDX | When run as SYSTEM, `$env:LOCALAPPDATA` resolves to the SYSTEM profile, not the interactive user's profile; must enumerate `C:\Users\*` to find Docker Desktop WSL disks |
| `Get-CimInstance` instead of `Get-WmiObject` | PSScriptAnalyzer `PSAvoidUsingWMICmdlet` warning; CimCmdlets ships with PS5.1 |
| Rename `$profile` loop variable to `$userProfile` | `$profile` is a PS automatic variable; `PSAvoidAssignmentToAutomaticVariable` warning |
| Run function once in `BeforeAll`, share via `$script:` | Multiple `It` blocks each invoking the function caused transcript conflicts and ~40s per test; single run keeps suite at ~42s total |

### Script: `scripts/Storage/Invoke-DiskSpaceAnalysis.ps1`
Report sections:
1. Run metadata (identity, file count, error count, coverage warning)
2. Top N directories -- hierarchical rollup (best for root cause analysis)
3. Top N directories -- direct content only (pinpoints exact locations)
4. Top N individual files
5. Known Windows bloat locations (WinSxS, Installer, WU cache, Temp, IIS logs, Event Logs, Recycle Bin)
6. System files (pagefile, hiberfil, swapfile)
7. VSS shadow copy storage (via CIM -- not counted in file scan)
8. Docker data paths (scans system paths + all user profiles; flags VHDX files with reclaim instructions)
9. Top 20 blocked paths (shows coverage gaps for the running account)
10. Remediation notes

### Tests: `tests/Storage/Invoke-DiskSpaceAnalysis.Tests.ps1`
14 Pester 3.4 tests, all passing. PSScriptAnalyzer clean.

### Open items
- Deploy and test on target system (next session).

---

## 2026-03-24 — Project initialization + Sync-Projects.ps1

### Objective
Stand up the project and write the first script as a proof-of-concept for the full CLAUDE.md workflow.

### Work done

**Infrastructure:**
- PSScriptAnalyzer was not installed on this machine. Installed to CurrentUser scope via `Install-Module PSScriptAnalyzer` (now at v1.25.0).
- Created `scripts/Utility/` and `tests/Utility/` category directories.

**Script: `scripts/Utility/Sync-Projects.ps1`**
- PS5.1 port of `C:\Projects\claude-playbooks\scripts\sync-projects.sh`
- Three functions:
  - `Invoke-GitCommand` — thin git wrapper that returns exit code; exists so tests can mock git without hitting the filesystem
  - `Invoke-RepoSync` — clones or pulls a single repo; detects dirty working tree and uses `--rebase` automatically
  - `Sync-Projects` — iterates all 19 repos across both GitHub accounts (6 Fragsrus personal, 13 darrel-wallace professional), creates `ProjectsDir` if missing, prints colored summary

**Tests: `tests/Utility/Sync-Projects.Tests.ps1`**
- 14 Pester 3.4 tests, all passing
- Covers: clone success/failure, clean pull, dirty working tree (rebase), staged-only changes (rebase), pull failure, directory creation, repo count per account, all 19 repos attempted even when some fail

**PSScriptAnalyzer issues resolved:**
- `PSAvoidUsingWriteHost` — suppressed via `SuppressMessageAttribute` (intentional colored console output)
- `PSUseSingularNouns` — suppressed for `Sync-Projects` (plural is semantically correct)
- `PSUseOutputTypeCorrectly` — fixed by adding `[OutputType([bool])]` to `Invoke-RepoSync`
- `PSUseBOMForUnicodeEncodedFile` — caused by an em-dash in a comment; replaced with semicolon (ASCII-only rule going forward)

### Outcome
Script committed and pushed. All repos syncing cleanly by end of session. No open items.

### Decisions made

| Decision | Rationale |
|---|---|
| Wrap git in `Invoke-GitCommand` | Lets Pester mock git calls without touching the filesystem |
| Suppress `PSUseSingularNouns` rather than rename | `Sync-Project` (singular) would be misleading for a bulk operation |
| Use ASCII-only characters in script files | Non-ASCII triggers `PSUseBOMForUnicodeEncodedFile`; avoid by convention |

---

## 2026-03-24 — Post-script sync cleanup

### Objective
Run Sync-Projects.ps1 for the first time and resolve all failures.

### Work done

**Sync run 1 — 13 succeeded, 6 failed:**
- 5 repos missing upstream tracking (`aws-agent-self-heal`, `cloud-resume-challenge`, `ai-agent-command-center`, `private-ai-research-data`, `virtualbox-hybrid-cloud-lab`) — fixed with `git branch --set-upstream-to=origin/main main`
- `aws-windows-onboarding-guide` — stale project with unstaged changes; archived instead of fixing

**Archived `aws-windows-onboarding-guide`:**
- Contents copied to `claude-ai-archive/cold-storage/aws-windows-onboarding-guide/`
- GitHub repo marked read-only via `gh repo archive`
- Local directory deleted
- Removed from `Sync-Projects.ps1` repo list (`9917985`)

**Initialized `cloud-resume-challenge`:**
- Repo existed on GitHub but had no commits on `main` (tracking could not be set)
- Created `CLAUDE.md` (target stack: S3/CloudFront/Lambda/DynamoDB/Route 53, IaC TBD) and `session_log.md`
- Initial commit pushed, upstream tracking set

**Sync run 2 — 18 succeeded, 0 failed.**

### Decisions made

| Decision | Rationale |
|---|---|
| Archive `aws-windows-onboarding-guide` rather than fix | Stale project, no plans to continue |
| Keep `cloud-resume-challenge` in sync list | Active work planned in the near future |

### Commits this session

| Hash | Repo | Description |
|---|---|---|
| `29e7d9e` | powershell-scripts | Add Sync-Projects.ps1 + tests |
| `49ade6a` | powershell-scripts | Add session_log.md |
| `9917985` | powershell-scripts | Remove aws-windows-onboarding-guide from sync list |
| `4f4b642` | claude-ai-archive | Archive aws-windows-onboarding-guide to cold storage |
| `d4bf083` | claude-playbooks | Document per-project session log workflow change |
| `5dc82f8` | claude-playbooks | Update session log rule in user_instructions.md |
| `82525a0` | cloud-resume-challenge | Initial project setup |
