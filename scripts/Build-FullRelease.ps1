[CmdletBinding()]
param(
    [string]$Configuration = "Release",
    [string]$AuthorZipPath = "",
    [string]$OutputRoot = "",
    [string]$PackageName = "CS2BotImprover_fresh_lbtv"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($AuthorZipPath)) {
    $AuthorZipPath = Join-Path $projectRoot "vendor\upstream\CS2BotImprover_upstream_latest.zip"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot "dist"
}

$stagingRoot = Join-Path $OutputRoot $PackageName
$zipPath = Join-Path $OutputRoot ($PackageName + ".zip")
$rebuildOverrideScript = Join-Path $projectRoot "scripts\Rebuild-OverrideVpks.py"

$projects = @(
    "addons\counterstrikesharp\plugins\BotTaunt\BotTaunt.csproj",
    "addons\counterstrikesharp\plugins\BotState\BotState.csproj",
    "addons\counterstrikesharp\plugins\NadeSystem\NadeSystem.csproj",
    "addons\counterstrikesharp\plugins\RoundDamageRecap\RoundDamageRecap.csproj"
)

$pluginOutputs = @(
    @{ Project = "addons\counterstrikesharp\plugins\BotTaunt"; Files = @("BotTaunt.dll", "BotTaunt.deps.json", "BotTaunt.pdb") },
    @{ Project = "addons\counterstrikesharp\plugins\BotState"; Files = @("BotState.dll", "BotState.deps.json", "BotState.pdb") },
    @{ Project = "addons\counterstrikesharp\plugins\NadeSystem"; Files = @("NadeSystem.dll", "NadeSystem.deps.json", "NadeSystem.pdb") },
    @{ Project = "addons\counterstrikesharp\plugins\RoundDamageRecap"; Files = @("RoundDamageRecap.dll", "RoundDamageRecap.deps.json", "RoundDamageRecap.pdb") }
)

if (-not (Test-Path -LiteralPath $AuthorZipPath)) {
    throw "Author release zip not found: $AuthorZipPath"
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

foreach ($relativeProject in $projects) {
    $projectPath = Join-Path $projectRoot $relativeProject
    if (-not (Test-Path -LiteralPath $projectPath)) {
        throw "Project not found: $projectPath"
    }

    dotnet build $projectPath -c $Configuration | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed for: $projectPath"
    }
}

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

Expand-Archive -LiteralPath $AuthorZipPath -DestinationPath $stagingRoot

if (-not (Test-Path -LiteralPath $rebuildOverrideScript)) {
    throw "Override rebuild script not found: $rebuildOverrideScript"
}

$withBotsGameinfo = Join-Path $stagingRoot "backup\WithBots\gameinfo.gi"
if (Test-Path -LiteralPath $withBotsGameinfo) {
    $gameinfoContent = Get-Content -LiteralPath $withBotsGameinfo -Raw
    if ($gameinfoContent -notmatch 'DisallowPgTokens') {
        $gameinfoContent = $gameinfoContent -replace "DisallowTokenContexts\s+1", "`$0`r`n`t`tDisallowPgTokens`t`t1"
        Set-Content -LiteralPath $withBotsGameinfo -Value $gameinfoContent -Encoding UTF8
    }

    Copy-Item -LiteralPath $withBotsGameinfo -Destination (Join-Path $stagingRoot "gameinfo.gi") -Force
}

python $rebuildOverrideScript --repo-root $projectRoot --game-csgo $stagingRoot | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Override VPK rebuild failed for staging root: $stagingRoot"
}

$stagingCoreConfig = Join-Path $stagingRoot "addons\counterstrikesharp\configs\core.json"
if (Test-Path -LiteralPath $stagingCoreConfig) {
    Remove-Item -LiteralPath $stagingCoreConfig -Force
}

$stagingBotCosmetics = Join-Path $stagingRoot "addons\counterstrikesharp\plugins\BotCosmetics"
if (Test-Path -LiteralPath $stagingBotCosmetics) {
    Remove-Item -LiteralPath $stagingBotCosmetics -Recurse -Force
}

foreach ($item in $pluginOutputs) {
    $buildOutputDir = Join-Path $projectRoot ($item.Project + "\bin\" + $Configuration + "\net8.0")
    $releasePluginDir = Join-Path $stagingRoot $item.Project

    if (-not (Test-Path -LiteralPath $buildOutputDir)) {
        throw "Build output not found: $buildOutputDir"
    }

    if (-not (Test-Path -LiteralPath $releasePluginDir)) {
        New-Item -ItemType Directory -Path $releasePluginDir -Force | Out-Null
    }

    foreach ($file in $item.Files) {
        $source = Join-Path $buildOutputDir $file
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Expected build artifact not found: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $releasePluginDir $file) -Force
    }
}

$repoCommands = Join-Path $projectRoot "Commands.txt"
if (Test-Path -LiteralPath $repoCommands) {
    Copy-Item -LiteralPath $repoCommands -Destination (Join-Path $stagingRoot "Commands.txt") -Force
}

$repoReadme = Join-Path $projectRoot "README.md"
if (Test-Path -LiteralPath $repoReadme) {
    Copy-Item -LiteralPath $repoReadme -Destination (Join-Path $stagingRoot "README.md") -Force
}

$repoCfg = Join-Path $projectRoot "cfg"
if (Test-Path -LiteralPath $repoCfg) {
    Copy-Item -LiteralPath (Join-Path $repoCfg "*") -Destination (Join-Path $stagingRoot "cfg") -Recurse -Force
}

$repoCssConfigs = Join-Path $projectRoot "addons\counterstrikesharp\configs"
if (Test-Path -LiteralPath $repoCssConfigs) {
    $stagingCssConfigs = Join-Path $stagingRoot "addons\counterstrikesharp\configs"
    if (-not (Test-Path -LiteralPath $stagingCssConfigs)) {
        New-Item -ItemType Directory -Path $stagingCssConfigs -Force | Out-Null
    }

    Copy-Item -Path (Join-Path $repoCssConfigs "*") -Destination $stagingCssConfigs -Recurse -Force
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stagingRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "Full release package created:"
Write-Host "  Staging: $stagingRoot"
Write-Host "  Zip:     $zipPath"
