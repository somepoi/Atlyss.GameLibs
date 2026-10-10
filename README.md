# ATLYSS GameLibs

## Use in a mod

Use an SDK-style project targeting `netstandard2.1` or newer. Add:

```xml
<ItemGroup>
  <PackageReference Include="Somepoi.Atlyss.GameLibs"
                    Version="0.21474249.0"
                    IncludeAssets="compile"
                    PrivateAssets="all" />
</ItemGroup>
```

Then build normally. Once the package is published on nuget.org, NuGet downloads
the references automatically. Select and reference your own loader, such as
MelonLoader or BepInEx, separately; GameLibs supports either and includes neither.
An unchanged mod stays pinned to its selected snapshot when the game updates.
To adopt a newer snapshot, change the PackageReference version and rebuild.

Before the first public publication, pack this repository and add its `artifacts`
folder as a local NuGet source in the consuming project. Do not copy reference
DLLs into a game's Managed folder. They contain no executable method bodies.
The package has no runtime assets; players need the actual game and loader.

## Maintain the snapshot

Requirements: .NET SDK 10, PowerShell, an installed Steam copy of ATLYSS.
The first update/pack requires internet access to restore the pinned Mono.Cecil dependency.

After Steam updates ATLYSS, run from this repository:

```powershell
./scripts/Update-GameLibs.ps1 -GameDirectory 'D:\GAMES\SteamLibrary\steamapps\common\ATLYSS'
```

The script reads the Steam build ID, scans every managed game DLL, strips the
non-framework assemblies, updates `references/`, `provenance.json` and
`GameLibs.props` and README version examples, validates the generated snapshot, then creates a `.nupkg` in
`artifacts/`. An unchanged snapshot is reused. To pack an existing committed
snapshot without the installed game:

```powershell
dotnet pack GameLibs.csproj -c Release -o artifacts
```

Version format is **0.&lt;Steam build ID&gt;.&lt;package revision&gt;**. New game builds
start at revision 0. If the package layout or intended source DLLs change within
the same game build, explicitly use `-Revision 1`, then 2, and so on. Published
package versions are immutable. This full package has a different version from
the earlier seven-DLL prototype `0.0.21474249`.

Commit the changed snapshot and push its matching tag to publish independently
of all mod repositories:

```powershell
git add references provenance.json GameLibs.props README.md
git commit -m "Update ATLYSS references"
git push origin main
git tag v0.21474249.0
git push origin v0.21474249.0
```

GameLibs updates when its maintainer supplies DLLs from an updated installation;
GitHub runners package the committed snapshot and do not download the paid game.
Consumers only update their NuGet version. They never need to maintain snapshots.

## Configure Trusted Publishing

Publishing uses GitHub OIDC and the official [NuGet/login](https://github.com/NuGet/login)
action to obtain a temporary NuGet API key. No stored `NUGET_API_KEY` secret is needed.

1. In [NuGet Trusted Publishing](https://www.nuget.org/account/trustedpublishing),
   add a GitHub policy owned by your NuGet account:

   | Field | Value |
   | --- | --- |
   | Repository Owner | `somepoi` |
   | Repository | `Atlyss.GameLibs` |
   | Workflow File | `package.yml` (filename only) |
   | Environment | Leave empty |
   | Scopes | Push new packages and package versions |
   | Package glob pattern | `Somepoi.Atlyss.GameLibs` |

2. In the GitHub repository's **Settings → Secrets and variables → Actions →
   Variables**, add `NUGET_USER`: your **nuget.org profile username**, not your
   email address or necessarily your GitHub username. Remove the old
   `NUGET_API_KEY` secret if you previously added it.
3. Commit/push the workflow changes to `main`. To publish the current snapshot,
   push its matching `v0.21474249.0` tag, or select `main` in **Build and publish
   GameLibs → Run workflow** and enable `publish`.

Only the publication job receives `id-token: write`. Branch/PR builds pack
artifacts without requesting NuGet credentials. Publication creates a GitHub
Release with the same `.nupkg`; NuGet validation/indexing may take time before
the package is available for restore. A rerun skips an already published NuGet
version. For a tag release, use a tag that contains the updated workflow.

See the [official Trusted Publishing guide](https://learn.microsoft.com/en-us/nuget/nuget-org/trusted-publishing).
