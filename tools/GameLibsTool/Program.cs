using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text.Json;
using System.Xml.Linq;
using System.Text.RegularExpressions;
using Mono.Cecil;
using Mono.Cecil.Cil;

try
{
    if (args.Length == 3 && args[0] == "--strip")
    {
        var source = Path.GetFullPath(args[1]);
        var destination = Path.GetFullPath(args[2]);
        if (source == destination) throw new InvalidOperationException("Cannot overwrite game DLLs.");
        Directory.CreateDirectory(destination);
        using var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(source);
        var count = 0;
        foreach (var file in Directory.GetFiles(source, "*.dll").Order())
        {
            if (Regex.IsMatch(Path.GetFileName(file), @"^(System(?:\.|$)|mscorlib\.|netstandard\.|Mono\.Security\.)")) continue;
            using var assembly = Mono.Cecil.AssemblyDefinition.ReadAssembly(file, new ReaderParameters { AssemblyResolver = resolver });
            foreach (var module in assembly.Modules)
            {
                module.Resources.Clear();
                foreach (var type in module.GetTypes())
                foreach (var method in type.Methods)
                {
                    if (!method.HasBody) continue;
                    method.Body = new Mono.Cecil.Cil.MethodBody(method);
                    var il = method.Body.GetILProcessor();
                    il.Append(il.Create(OpCodes.Ldnull));
                    il.Append(il.Create(OpCodes.Throw));
                    method.NoInlining = true;
                }
            }
            assembly.Write(Path.Combine(destination, Path.GetFileName(file)));
            count++;
        }
        Console.WriteLine($"Generated {count} stripped compiler assemblies with Mono.Cecil 0.11.6.");
        return 0;
    }
    var root = Path.GetFullPath(args.Single());
    using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "provenance.json")));
    var data = manifest.RootElement;
    if (data.GetProperty("steamAppId").GetInt32() != 2768430)
        throw new InvalidDataException("Snapshot does not belong to ATLYSS.");
    var properties = XDocument.Load(Path.Combine(root, "GameLibs.props")).Descendants("PropertyGroup").Single();
    var version = $"0.{properties.Element("SteamBuildId")!.Value}.{properties.Element("PackageRevision")!.Value}";
    if (data.GetProperty("packageVersion").GetString() != version)
        throw new InvalidDataException("Package version and snapshot provenance disagree.");
    var assemblies = data.GetProperty("assemblies").EnumerateArray().ToArray();
    var expected = assemblies.Select(a => a.GetProperty("name").GetString()!).Order().ToArray();
    var directory = Path.Combine(root, "references");
    var actual = Directory.GetFiles(directory, "*.dll").Select(Path.GetFileName).Order().ToArray();
    if (!actual.SequenceEqual(expected) || !expected.Contains("Assembly-CSharp.dll"))
        throw new InvalidDataException("Reference files differ from the recorded snapshot.");
    var methodCount = 0;
    foreach (var entry in assemblies)
    {
        var name = entry.GetProperty("name").GetString()!;
        if (Path.GetFileName(name) != name)
            throw new InvalidDataException($"Invalid assembly filename: {name}");
        using var stream = File.OpenRead(Path.Combine(directory, name));
        if (Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant() != entry.GetProperty("referenceSha256").GetString())
            throw new InvalidDataException($"Reference hash mismatch: {name}");
        stream.Position = 0;
        using var pe = new PEReader(stream);
        var metadata = pe.GetMetadataReader();
        foreach (var handle in metadata.MethodDefinitions)
        {
            var method = metadata.GetMethodDefinition(handle);
            if (method.RelativeVirtualAddress == 0) continue;
            var bytes = pe.GetMethodBody(method.RelativeVirtualAddress).GetILBytes()!;
            if (bytes.Length != 2 || bytes[0] != 0x14 || bytes[1] != 0x7a)
                throw new InvalidDataException($"Executable method body found in {name}.");
            methodCount++;
        }
    }
    Console.WriteLine($"GameLibs {version}: {assemblies.Length} compiler assemblies, {methodCount} stripped method bodies.");
    var output = Environment.GetEnvironmentVariable("GITHUB_OUTPUT");
    if (!string.IsNullOrEmpty(output))
        File.AppendAllText(output, $"version={version}\nsteam_build={data.GetProperty("steamBuildId").GetString()}\nassembly_count={assemblies.Length}\n");
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine(error.Message);
    return 1;
}
