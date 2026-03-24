# PowerShell Scripts — Session Log

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
Script committed (`29e7d9e`) and pushed to `darrel-wallace/powershell-scripts` main. No open items.

### Decisions made

| Decision | Rationale |
|---|---|
| Wrap git in `Invoke-GitCommand` | Lets Pester mock git calls without touching the filesystem |
| Suppress `PSUseSingularNouns` rather than rename | `Sync-Project` (singular) would be misleading for a bulk operation |
| Use ASCII-only characters in script files | Non-ASCII triggers `PSUseBOMForUnicodeEncodedFile`; avoid by convention |
