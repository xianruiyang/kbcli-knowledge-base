[CmdletBinding()]
param(
    [string]$SkillDir
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SkillDir)) {
    $SkillDir = Split-Path -Parent $PSScriptRoot
}

$resolvedSkillDir = (Resolve-Path -LiteralPath $SkillDir).Path
$runtimeDir = Join-Path $resolvedSkillDir "assets\kbcli\win-x64-release"
$kbExe = Join-Path $runtimeDir "kb.exe"
$vectorExe = Join-Path $runtimeDir "kb-vector-service.exe"
$modelRegistry = Join-Path $runtimeDir "kb-models.json"

$missing = @()
foreach ($path in @($kbExe, $vectorExe)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $missing += $path
    }
}

if ($missing.Count -gt 0) {
    throw "kbcli skill package incomplete. Missing bundled runtime file(s): $($missing -join ', ')"
}

[ordered]@{
    ok = $true
    skill_dir = $resolvedSkillDir
    runtime_dir = $runtimeDir
    kb_exe = $kbExe
    vector_exe = $vectorExe
    model_registry = $modelRegistry
} | ConvertTo-Json -Depth 3
