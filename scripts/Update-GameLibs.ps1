[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GameDirectory,
    [ValidateRange(0, 2147483647)][int]$Revision = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$gameRoot = (Resolve-Path -LiteralPath $GameDirectory).Path
$managedRoot = Join-Path $gameRoot 'ATLYSS_Data/Managed'
$manifestPath = [IO.Path]::GetFullPath((Join-Path $gameRoot '../../appmanifest_2768430.acf'))
$manifest = Get-Content -LiteralPath $manifestPath -Raw
if ($manifest -notmatch '"buildid"\s+"(\d+)"') { throw "Steam build ID missing: $manifestPath" }
$buildId = $Matches[1]

# Framework assemblies come from the consumer's SDK, not from the game snapshot.
$allFiles = @(Get-ChildItem -LiteralPath $managedRoot -File -Filter '*.dll' | Sort-Object Name)
$excluded = @($allFiles | Where-Object { $_.Name -match '^(System(?:\.|$)|mscorlib\.|netstandard\.|Mono\.Security\.)' })
$sources = @($allFiles | Where-Object { $_.Name -notmatch '^(System(?:\.|$)|mscorlib\.|netstandard\.|Mono\.Security\.)' })
if (-not ($sources | Where-Object Name -eq 'Assembly-CSharp.dll')) { throw 'Assembly-CSharp.dll missing.' }

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

$sourceHashes = @{}
foreach ($source in $sources) { $sourceHashes[$source.Name] = Get-Sha256 $source.FullName }
$provenancePath = Join-Path $repoRoot 'provenance.json'
$previous = if (Test-Path -LiteralPath $provenancePath) { Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json } else { $null }
if ($previous -and $previous.steamBuildId -eq $buildId -and -not $PSBoundParameters.ContainsKey('Revision')) {
    $Revision = [int]$previous.revision
}
if ($previous -and $previous.steamBuildId -eq $buildId -and $Revision -lt [int]$previous.revision) {
    throw "Cannot decrease the package revision for Steam build $buildId. Current revision: $($previous.revision)."
}
$packageVersion = "0.$buildId.$Revision"
if ($previous -and $previous.packageVersion -eq $packageVersion) {
    $unchanged = @($previous.assemblies).Count -eq $sources.Count
    foreach ($assembly in $previous.assemblies) {
        if ($sourceHashes[$assembly.name] -ne $assembly.sourceSha256) { $unchanged = $false }
    }
    if (-not $unchanged) {
        throw "Inputs changed for package $packageVersion. Verify the game installation or use -Revision $($Revision + 1) for an intentional package revision."
    }
    & dotnet pack (Join-Path $repoRoot 'GameLibs.csproj') --configuration Release --output (Join-Path $repoRoot 'artifacts')
    if ($LASTEXITCODE -ne 0) { throw 'Could not pack the existing snapshot.' }
    Write-Output "GameLibs $packageVersion is already up to date; package ready in artifacts/."
    exit 0
}

$workDirectory = Join-Path $repoRoot '.ci/generated'
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
& dotnet run --project (Join-Path $repoRoot 'tools/GameLibsTool/GameLibsTool.csproj') -- --strip $managedRoot $workDirectory
if ($LASTEXITCODE -ne 0) { throw 'Could not strip game references.' }

$assemblies = @($sources | ForEach-Object {
    $generatedPath = Join-Path $workDirectory $_.Name
    [ordered]@{
        name = $_.Name
        assemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($_.FullName).Version.ToString()
        sourceSha256 = $sourceHashes[$_.Name]
        referenceSha256 = Get-Sha256 $generatedPath
    }
})
$provenance = [ordered]@{
    schemaVersion = 1
    steamAppId = 2768430
    steamBuildId = $buildId
    revision = $Revision
    packageVersion = $packageVersion
    stripTool = 'GameLibsTool using Mono.Cecil 0.11.6; bodies/resources removed; visibility preserved'
    excludedFrameworkAssemblies = @($excluded | ForEach-Object Name)
    assemblies = $assemblies
}

$referenceDirectory = Join-Path $repoRoot 'references'
New-Item -ItemType Directory -Path $referenceDirectory -Force | Out-Null
foreach ($source in $sources) {
    Copy-Item -LiteralPath (Join-Path $workDirectory $source.Name) -Destination (Join-Path $referenceDirectory $source.Name) -Force
}
# Remove only obsolete files in this repository's fixed references directory.
$resolvedReferences = (Resolve-Path -LiteralPath $referenceDirectory).Path
if ($resolvedReferences -ne [IO.Path]::GetFullPath((Join-Path $repoRoot 'references'))) { throw 'Unexpected references directory.' }
Get-ChildItem -LiteralPath $resolvedReferences -File -Filter '*.dll' |
    Where-Object { $_.Name -notin @($sources | ForEach-Object Name) } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName }
[IO.File]::WriteAllText($provenancePath, ($provenance | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
$props = @"
<Project>
  <PropertyGroup>
    <SteamBuildId>$buildId</SteamBuildId>
    <PackageRevision>$Revision</PackageRevision>
    <PackageVersion>0.`$(SteamBuildId).`$(PackageRevision)</PackageVersion>
  </PropertyGroup>
</Project>
"@
[IO.File]::WriteAllText((Join-Path $repoRoot 'GameLibs.props'), $props + [Environment]::NewLine)
$readmePath = Join-Path $repoRoot 'README.md'
if ($previous) {
    $readme = Get-Content -LiteralPath $readmePath -Raw
    $updatedReadme = $readme.Replace([string]$previous.packageVersion, $packageVersion)
    $updatedReadme = $updatedReadme.Replace("from Steam build **$($previous.steamBuildId)**", "from Steam build **$buildId**")
    $updatedReadme = $updatedReadme.Replace("current snapshot contains **$(@($previous.assemblies).Count) DLLs**", "current snapshot contains **$($sources.Count) DLLs**")
    if ($updatedReadme -ne $readme) { [IO.File]::WriteAllText($readmePath, $updatedReadme) }
}
& dotnet pack (Join-Path $repoRoot 'GameLibs.csproj') --configuration Release --output (Join-Path $repoRoot 'artifacts')
if ($LASTEXITCODE -ne 0) { throw 'Could not pack GameLibs.' }
Write-Output "GameLibs $packageVersion ready. Commit references/, provenance.json, GameLibs.props and README.md, then push tag v$packageVersion."
