# ATLYSS GameLibs

## Use in a mod

Add it as a reference to your project, then build normally.

## Maintain the snapshot

Requirements: .NET SDK 10, PowerShell, an installed Steam copy of ATLYSS.
The first update/pack requires internet access to restore the pinned Mono.Cecil dependency.

After Steam updates ATLYSS, run from this repository:

```powershell
./scripts/Update-GameLibs.ps1 -GameDirectory '<your_atlyss_steam_path>'
```

To pack an existing committed
snapshot without the installed game:

```powershell
dotnet pack GameLibs.csproj -c Release -o artifacts
```

Commit the changed snapshot and push its matching tag to publish independently
of all mod repositories.