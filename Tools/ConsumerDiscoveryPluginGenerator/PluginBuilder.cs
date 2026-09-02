using Mutagen.Bethesda.Plugins;
using Mutagen.Bethesda.Plugins.Binary.Parameters;
using Mutagen.Bethesda.Plugins.Records;
using Mutagen.Bethesda.Starfield;
using Noggog;

namespace Venworks.Canvas.ConsumerDiscovery.PluginGenerator;

/// <summary>
/// Builds and verifies the deterministic host and consumer plugins used by the VWCANVAS-9 runtime probe.
/// </summary>
internal static class PluginBuilder
{
    /// <summary>
    /// The deterministic local form ID assigned to the only quest in each generated plugin.
    /// </summary>
    private const uint QuestFormId = 0x800;

    /// <summary>
    /// The Starfield record version used by current quest records.
    /// </summary>
    private const ushort QuestFormVersion = 582;

    /// <summary>
    /// Builds all three plugins, reopens them from disk, and rejects any binary that does not preserve the requested structure.
    /// </summary>
    /// <param name="outputDirectory">The directory that receives the generated <c>.esm</c> files.</param>
    /// <returns>The absolute paths of the verified plugins in host, Consumer A, Consumer B order.</returns>
    /// <exception cref="ArgumentException">Thrown when <paramref name="outputDirectory"/> is empty.</exception>
    /// <exception cref="InvalidDataException">Thrown when Mutagen readback does not match the requested plugin structure.</exception>
    public static IReadOnlyList<string> BuildAll(string outputDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputDirectory);

        var resolvedOutputDirectory = Path.GetFullPath(outputDirectory);
        Directory.CreateDirectory(resolvedOutputDirectory);

        var hostModKey = ModKey.FromNameAndExtension("VWCANVAS9-Host.esm");
        var registryQuest = new FormKey(hostModKey, QuestFormId);
        var specifications = new[]
        {
            new PluginSpecification(
                hostModKey.FileName.String,
                "VWCANVAS9_ConsumerDiscoveryRegistry",
                "VWCANVAS-9 Consumer Discovery Registry",
                "Venworks:Canvas:Probes:ConsumerDiscovery:Registry",
                registryQuest: null),
            new PluginSpecification(
                "VWCANVAS9-ConsumerA.esm",
                "VWCANVAS9_ConsumerARegistrar",
                "VWCANVAS-9 Consumer A Registrar",
                "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerARegistrar",
                registryQuest),
            new PluginSpecification(
                "VWCANVAS9-ConsumerB.esm",
                "VWCANVAS9_ConsumerBRegistrar",
                "VWCANVAS-9 Consumer B Registrar",
                "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar",
                registryQuest),
        };

        var outputs = new List<string>(specifications.Length);
        StarfieldMod? hostPlugin = null;
        foreach (var specification in specifications)
        {
            var outputPath = Path.Combine(resolvedOutputDirectory, specification.FileName);
            var plugin = Build(specification, outputPath, hostPlugin);
            Verify(specification, outputPath, hostPlugin);
            outputs.Add(outputPath);

            if (specification.RegistryQuest is null)
            {
                hostPlugin = plugin;
            }
        }

        return outputs;
    }

    /// <summary>
    /// Creates one Starfield master containing a single start-game-enabled quest and writes it in Bethesda binary format.
    /// </summary>
    /// <param name="specification">The expected plugin and quest structure.</param>
    /// <param name="outputPath">The destination file path.</param>
    /// <param name="hostPlugin">The host plugin used to resolve a consumer's explicit master style, or <see langword="null"/> when building the host.</param>
    /// <returns>The in-memory plugin that was written to <paramref name="outputPath"/>.</returns>
    private static StarfieldMod Build(PluginSpecification specification, string outputPath, StarfieldMod? hostPlugin)
    {
        var plugin = new StarfieldMod(specification.ModKey, StarfieldRelease.Starfield, headerVersion: 1.0f, forceUseLowerFormIDRanges: false)
        {
            IsMaster = true,
        };

        if (specification.RegistryQuest is FormKey registryQuest)
        {
            plugin.ModHeader.MasterReferences.Add(new MasterReference
            {
                Master = registryQuest.ModKey,
            });
        }

        var quest = new Quest(new FormKey(specification.ModKey, QuestFormId), StarfieldRelease.Starfield)
        {
            EditorID = specification.QuestEditorId,
            FormVersion = QuestFormVersion,
            Name = specification.QuestName,
            Data = new QuestData
            {
                Flags = Quest.Flag.StartGameEnabled | Quest.Flag.StartsEnabled | Quest.Flag.RunOnce,
                Unused = new MemorySlice<byte>(new byte[3]),
            },
            VirtualMachineAdapter = CreateVirtualMachineAdapter(specification),
        };

        plugin.Quests.Add(quest);
        var writeTarget = plugin.BeginWrite.ToPath(new FilePath(outputPath));
        if (specification.RegistryQuest is null)
        {
            writeTarget.WithNoLoadOrder().Write();
        }
        else
        {
            if (hostPlugin is null)
            {
                throw new InvalidOperationException("The host plugin must be built before either consumer plugin.");
            }

            writeTarget.WithLoadOrder(new IStarfieldModGetter[] { hostPlugin }).Write();
        }

        return plugin;
    }

    /// <summary>
    /// Creates the quest VM adapter and its optional typed host-registry property.
    /// </summary>
    /// <param name="specification">The script and registry-reference requirements.</param>
    /// <returns>A VM adapter containing exactly one attached Papyrus script.</returns>
    private static QuestAdapter CreateVirtualMachineAdapter(PluginSpecification specification)
    {
        var script = new ScriptEntry
        {
            Name = specification.ScriptName,
        };

        if (specification.RegistryQuest is FormKey registryQuest)
        {
            script.Properties.Add(new ScriptObjectProperty
            {
                Name = "Registry",
                Object = new FormLink<IStarfieldMajorRecordGetter>(registryQuest),
            });
        }

        var adapter = new QuestAdapter
        {
            Versioning = QuestAdapter.VersioningBreaks.Break0,
            ExtraBindDataVersion = 0,
            Script = new ScriptEntry
            {
                Name = string.Empty,
            },
        };
        adapter.Scripts.Add(script);
        return adapter;
    }

    /// <summary>
    /// Reopens one generated plugin and verifies its master list, quest flags, script attachment, and typed registry link.
    /// </summary>
    /// <param name="specification">The structure that must survive binary serialization.</param>
    /// <param name="outputPath">The generated plugin path.</param>
    /// <param name="hostPlugin">The host plugin used to interpret a consumer's explicit master style, or <see langword="null"/> for the host itself.</param>
    /// <exception cref="InvalidDataException">Thrown when any requested structure is missing or changed.</exception>
    private static void Verify(PluginSpecification specification, string outputPath, StarfieldMod? hostPlugin)
    {
        BinaryReadParameters readParameters;
        if (specification.RegistryQuest is not null)
        {
            if (hostPlugin is null)
            {
                throw new InvalidOperationException("The host plugin must be available when verifying a consumer plugin.");
            }

            var masterFlags = new Cache<IModMasterStyledGetter, ModKey>(
                plugin => plugin.ModKey,
                EqualityComparer<ModKey>.Default);
            masterFlags.Add(hostPlugin);
            readParameters = new BinaryReadParameters
            {
                MasterFlagsLookup = masterFlags,
            };
        }
        else
        {
            readParameters = new BinaryReadParameters();
        }

        var plugin = StarfieldMod.CreateFromBinary(
            new ModPath(specification.ModKey, new FilePath(outputPath)),
            StarfieldRelease.Starfield,
            readParameters,
            new GroupMask(true));

        Require(plugin.IsMaster, specification, "plugin is not marked as a master");
        var expectedMasters = specification.RegistryQuest is FormKey registryQuest
            ? new[] { registryQuest.ModKey }
            : Array.Empty<ModKey>();
        var actualMasters = plugin.ModHeader.MasterReferences.Select(reference => reference.Master).ToArray();
        Require(actualMasters.SequenceEqual(expectedMasters), specification, $"master list was [{string.Join(", ", actualMasters)}]");

        var quests = plugin.Quests.Records.ToArray();
        Require(quests.Length == 1, specification, $"expected one quest but found {quests.Length}");
        var quest = quests.Single();
        Require(quest.FormKey == new FormKey(specification.ModKey, QuestFormId), specification, $"quest FormKey was {quest.FormKey}");
        Require(quest.EditorID == specification.QuestEditorId, specification, $"quest EditorID was {quest.EditorID}");
        Require(quest.FormVersion == QuestFormVersion, specification, $"quest FormVersion was {quest.FormVersion}");

        var requiredFlags = Quest.Flag.StartGameEnabled | Quest.Flag.StartsEnabled | Quest.Flag.RunOnce;
        Require(quest.Data is not null && quest.Data.Flags == requiredFlags, specification, $"quest flags were {quest.Data?.Flags}");
        Require(quest.VirtualMachineAdapter is not null, specification, "quest VM adapter was missing");

        var scripts = quest.VirtualMachineAdapter!.Scripts.ToArray();
        Require(scripts.Length == 1, specification, $"expected one attached script but found {scripts.Length}");
        var script = scripts.Single();
        Require(script.Name == specification.ScriptName, specification, $"attached script was {script.Name}");

        var objectProperties = script.Properties.OfType<ScriptObjectProperty>().ToArray();
        if (specification.RegistryQuest is FormKey expectedRegistryQuest)
        {
            Require(script.Properties.Count == 1 && objectProperties.Length == 1, specification, "consumer registry property was not the only script property");
            Require(objectProperties[0].Name == "Registry", specification, $"consumer property name was {objectProperties[0].Name}");
            Require(objectProperties[0].Object.FormKey == expectedRegistryQuest, specification, $"consumer registry link was {objectProperties[0].Object.FormKey}");
        }
        else
        {
            Require(script.Properties.Count == 0, specification, "host registry script unexpectedly had properties");
        }
    }

    /// <summary>
    /// Rejects a generated plugin whose readback does not satisfy a required invariant.
    /// </summary>
    /// <param name="condition">Whether the invariant was satisfied.</param>
    /// <param name="specification">The plugin being checked.</param>
    /// <param name="failure">A precise description of the violated invariant.</param>
    /// <exception cref="InvalidDataException">Thrown when <paramref name="condition"/> is <see langword="false"/>.</exception>
    private static void Require(bool condition, PluginSpecification specification, string failure)
    {
        if (!condition)
        {
            throw new InvalidDataException($"{specification.FileName}: {failure}.");
        }
    }
}
