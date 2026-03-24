# PowerShell Scripts — Project Instructions

## Target Environment

- **Runtime**: Windows PowerShell 5.1 (not PowerShell 7/Core)
- **OS**: Windows Server 2019 / Windows Server 2022
- **Constraint**: Scripts must only use components native to Windows — no third-party modules or external dependencies of any kind

## Development Environment

- **Machine**: Windows desktop (native, not WSL)
- **Projects path**: `C:\Projects\powershell-scripts`
- **Testing**: Pester 3.4.0 (ships with Windows Server 2019/2022)
- **Static analysis**: PSScriptAnalyzer (run via VS Code PowerShell extension or manually)

## Script Requirements

### Structure
- Every script must expose one or more **named functions** — no top-level procedural code that runs on dot-sourcing
- Function names must follow PowerShell's `Verb-Noun` convention using approved verbs (`Get-Verb` to check)
- Include comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)

### Native-only rule
Before using any cmdlet, module, or API, verify it is available on Windows Server 2019/2022 without installing anything:
- Built-in modules: `Get-Module -ListAvailable` on a clean Server 2019/2022 install
- Acceptable: WMI/CIM, registry, .NET Framework 4.x, built-in PS modules (ActiveDirectory if role installed, etc.)
- Not acceptable: anything requiring `Install-Module`, external executables, or third-party tools

### PS5.1 compatibility — avoid these PS7-only features
- Ternary operator (`condition ? a : b`)
- Null-coalescing assignment (`??=`)
- `ForEach-Object -Parallel`
- `$PSStyle` and ANSI escape sequences
- Pipeline chain operators (`&&`, `||`)

## Workflow — Every Script

1. **Write the function** in `scripts/<Category>/Verb-Noun.ps1`
2. **Write the Pester test** in `tests/<Category>/Verb-Noun.Tests.ps1`
3. **Run tests**: `Invoke-Pester .\tests\<Category>\Verb-Noun.Tests.ps1 -Verbose`
4. **Run PSScriptAnalyzer**: `Invoke-ScriptAnalyzer -Path .\scripts\<Category>\Verb-Noun.ps1`
5. **Revise** until tests pass and analyzer returns no errors or warnings
6. Only then consider the script complete

## Project Structure

```
powershell-scripts/
├── CLAUDE.md
├── scripts/          # Production scripts, organized by category
│   └── <Category>/
│       └── Verb-Noun.ps1
├── tests/            # Pester test files, mirrors scripts/ structure
│   └── <Category>/
│       └── Verb-Noun.Tests.ps1
└── templates/        # Starting points for new scripts and tests
    ├── script-template.ps1
    └── test-template.Tests.ps1
```

## Pester 3.4 Syntax (not Pester 5)

Windows Server ships with Pester **3.4.0**. Use the older assertion syntax:

```powershell
# Correct (Pester 3.x)
$result | Should Be 'expected'
$result | Should BeNullOrEmpty
{ SomeFunction } | Should Throw

# Wrong (Pester 5.x only)
$result | Should -Be 'expected'
```

## Script Categories (expand as needed)

- `System/` — OS info, services, event logs, performance
- `Network/` — connectivity, DNS, firewall, adapters
- `ActiveDirectory/` — user/group/computer management (requires AD role)
- `Storage/` — disk, volume, share management
- `Security/` — audit, permissions, policy
