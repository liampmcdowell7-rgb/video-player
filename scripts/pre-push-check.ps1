# Lists every changed file and flags likely secrets. Review the list against the plan before pushing.
# Run it from the project folder after `git init`.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pre-push-check.ps1
$ErrorActionPreference = 'Continue'

# Refuse to run unless git's repository root is exactly this project folder. Outside a repository
# (or inside a bigger one) the file list would be empty or wrong and the scan would pass by accident.
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $projectRoot
$gitRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $gitRoot) {
    Write-Host "!! This folder is not a git repository yet. Run: git init   then run this check again."
    exit 1
}
# --show-prefix is empty only when the project folder itself is the repository root.
$prefix = (git rev-parse --show-prefix 2>$null)
if ($prefix) {
    Write-Host "!! The project folder is inside a bigger git repository ($gitRoot). Run: git init   inside the project folder, then run this check again."
    exit 1
}

Write-Host "== Changed / untracked files =="
git status --porcelain
Write-Host ""

Write-Host "== Secret scan (tracked and untracked files, ignoring .gitignore matches) =="
$files = @(git ls-files -co --exclude-standard)
$found = $false

$secretNames = '\.(p8|p12|pem|cer|mobileprovision)$|(^|/)signing_key(\.pub)?$|(^|/)\.env'
foreach ($f in $files) {
    if ($f -match $secretNames) { Write-Host "!! Secret-looking file name: $f"; $found = $true }
}

# The "password = literal" pattern is skipped inside Tests/ folders, where fixed example
# passwords (RFC test vectors, local test servers) are expected. The other patterns apply everywhere.
$patterns = @(
    @{ re = 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'; testsToo = $true },
    @{ re = 'api[_-]?key\s*[:=]\s*["''][A-Za-z0-9]{16,}'; testsToo = $true },
    @{ re = 'password\s*[:=]\s*["''][^"'']+'; testsToo = $false },
    @{ re = 'AKIA[0-9A-Z]{16}'; testsToo = $true }
)
$binary = '\.(png|jpg|jpeg|gif|ico|webp)$'
foreach ($f in $files) {
    if ($f -match $binary -or -not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    $inTests = ($f -match '(^|/)Tests/') -or ($f -match '(^|/)Vendor/.*.md$')
    foreach ($p in $patterns) {
        if ($inTests -and -not $p.testsToo) { continue }
        $hits = Select-String -LiteralPath $f -Pattern $p.re -ErrorAction SilentlyContinue
        foreach ($h in $hits) { Write-Host "!! ${f}:$($h.LineNumber): $($h.Line.Trim())"; $found = $true }
    }
}

if ($found) { Write-Host "Possible secret found above. Do NOT push."; exit 1 }
Write-Host "No secret patterns found. ($($files.Count) files scanned)"
