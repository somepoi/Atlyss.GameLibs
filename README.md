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