using Mutagen.Bethesda.Plugins;
using Mutagen.Bethesda.Plugins.Binary.Parameters;
using Mutagen.Bethesda.Plugins.Records;
using Mutagen.Bethesda.Starfield;
using Noggog;

namespace Venworks.Canvas.ConsumerDiscovery.PluginGenerator;

/// <summary>
/// Builds and verifies deterministic host and consumer plugins for each VWCANVAS-9 runtime profile.
/// </summary>
internal static class PluginBuilder
{
    /// <summary>
    /// The Starfield record version used by current quest records.
    /// </summary>
    private const ushort QuestFormVersion = 582;

    /// <summary>
    /// Builds all three plugins for one profile, reopens them from disk, and rejects binaries that do not preserve the requested structure.
    /// </summary>
    /// <param name="outputDirectory">The directory that receives the generated <c>.esm</c> files.</param>
    /// <param name="profile">The exact profile name: <c>Baseline</c>, <c>Faults</c>, or <c>UpdatedA</c>.</param>
    /// <returns>The absolute paths of the verified plugins in host, Consumer A, Consumer B order.</returns>
    /// <exception cref="ArgumentException">Thrown when an argument is empty or the profile is unknown.</exception>
    /// <exception cref="InvalidDataException">Thrown when Mutagen readback does not match the requested plugin structure.</exception>
    public static IReadOnlyList<string> BuildAll(string outputDirectory, string profile)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(profile);

        var resolvedOutputDirectory = Path.GetFullPath(outputDirectory);
        Directory.CreateDirectory(resolvedOutputDirectory);

        var specifications = CreateSpecifications(profile);
        var outputs = new List<string>(specifications.Count);
        StarfieldMod? hostPlugin = null;
        foreach (var specification in specifications)
        {
            var outputPath = Path.Combine(resolvedOutputDirectory, specification.FileName);
            var plugin = Build(specification, outputPath, hostPlugin);
            Verify(specification, outputPath, hostPlugin);
            outputs.Add(outputPath);

            if (specification.Quests.All(quest => quest.RegistryQuest is null))
            {
                hostPlugin = plugin;
            }
        }

        return outputs;
    }

    /// <summary>
    /// Creates the exact three plugin specifications for a runtime profile.
    /// </summary>
    /// <param name="profile">The exact profile name.</param>
    /// <returns>The ordered host, Consumer A, and Consumer B plugin specifications.</returns>
    /// <exception cref="ArgumentException">Thrown when <paramref name="profile"/> is unknown.</exception>
    private static IReadOnlyList<PluginSpecification> CreateSpecifications(string profile)
    {
        if (profile is not ("Baseline" or "Faults" or "UpdatedA"))
        {
            throw new ArgumentException($"Unknown profile '{profile}'. Expected Baseline, Faults, or UpdatedA.", nameof(profile));
        }

        var hostModKey = ModKey.FromNameAndExtension("VWCANVAS9-Host.esm");
        var registryQuest = new FormKey(hostModKey, 0x800);
        var consumerAVersion = profile == "UpdatedA" ? 2 : 1;
        var consumerADisplayName = profile == "UpdatedA"
            ? "VWCANVAS-9 Consumer A UPDATED"
            : "VWCANVAS-9 Consumer A";

        var host = new PluginSpecification(
            hostModKey.FileName.String,
            new[]
            {
                new QuestSpecification(
                    0x800,
                    "VWCANVAS9_ConsumerDiscoveryRegistry",
                    "VWCANVAS-9 Consumer Discovery Registry",
                    "Venworks:Canvas:Probes:ConsumerDiscovery:Registry",
                    registryQuest: null,
                    registration: null),
            });

        var consumerA = new PluginSpecification(
            "VWCANVAS9-ConsumerA.esm",
            new[]
            {
                new QuestSpecification(
                    0x800,
                    "VWCANVAS9_ConsumerARegistrar",
                    "VWCANVAS-9 Consumer A Registrar",
                    "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerARegistrar",
                    registryQuest,
                    CreateRegistration(
                        "venworks.canvas.probe.consumer-a",
                        consumerADisplayName,
                        consumerAVersion,
                        expectedRegistration: true,
                        initialDelaySeconds: 0.0f)),
            });

        var consumerBQuests = new List<QuestSpecification>
        {
            new QuestSpecification(
                0x800,
                "VWCANVAS9_ConsumerBRegistrar",
                "VWCANVAS-9 Consumer B Registrar",
                "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar",
                registryQuest,
                CreateRegistration(
                    "venworks.canvas.probe.consumer-b",
                    "VWCANVAS-9 Consumer B",
                    descriptorVersion: 1,
                    expectedRegistration: true,
                    initialDelaySeconds: 0.0f)),
        };
        if (profile == "Faults")
        {
            consumerBQuests.Add(new QuestSpecification(
                0x801,
                "VWCANVAS9_ConsumerBCollisionProbe",
                "VWCANVAS-9 Consumer B Collision Probe",
                "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar",
                registryQuest,
                CreateRegistration(
                    "venworks.canvas.probe.consumer-a",
                    "VWCANVAS-9 Duplicate Consumer A",
                    descriptorVersion: 1,
                    expectedRegistration: false,
                    initialDelaySeconds: 2.0f)));
            consumerBQuests.Add(new QuestSpecification(
                0x802,
                "VWCANVAS9_ConsumerBMissingProbe",
                "VWCANVAS-9 Missing Consumer Probe",
                "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar",
                registryQuest,
                CreateRegistration(
                    "venworks.canvas.probe.missing",
                    "VWCANVAS-9 Missing Consumer",
                    descriptorVersion: 1,
                    expectedRegistration: true,
                    initialDelaySeconds: 1.0f)));
        }

        var consumerB = new PluginSpecification("VWCANVAS9-ConsumerB.esm", consumerBQuests);
        return new[] { host, consumerA, consumerB };
    }

    /// <summary>
    /// Creates a registration specification whose normal and large paths are derived from its validated consumer ID.
    /// </summary>
    /// <param name="consumerId">The stable namespaced consumer identifier.</param>
    /// <param name="displayName">The visible diagnostic name.</param>
    /// <param name="descriptorVersion">The positive descriptor and movie version.</param>
    /// <param name="expectedRegistration">Whether the registry call is expected to succeed.</param>
    /// <param name="initialDelaySeconds">The bounded initial delay used by fault probes.</param>
    /// <returns>A complete registration specification.</returns>
    private static ConsumerRegistrationSpecification CreateRegistration(
        string consumerId,
        string displayName,
        int descriptorVersion,
        bool expectedRegistration,
        float initialDelaySeconds)
    {
        var prefix = $"VenworksCanvas/Consumers/{consumerId}/";
        return new ConsumerRegistrationSpecification(
            consumerId,
            displayName,
            prefix + "normal.swf",
            prefix + "large.swf",
            descriptorVersion,
            expectedRegistration,
            initialDelaySeconds);
    }

    /// <summary>
    /// Creates one Starfield master and writes it in Bethesda binary format.
    /// </summary>
    /// <param name="specification">The expected plugin and quest structure.</param>
    /// <param name="outputPath">The destination file path.</param>
    /// <param name="hostPlugin">The host plugin used to resolve consumer master style, or <see langword="null"/> when building the host.</param>
    /// <returns>The in-memory plugin that was written to <paramref name="outputPath"/>.</returns>
    private static StarfieldMod Build(PluginSpecification specification, string outputPath, StarfieldMod? hostPlugin)
    {
        var plugin = new StarfieldMod(specification.ModKey, StarfieldRelease.Starfield, headerVersion: 1.0f, forceUseLowerFormIDRanges: false)
        {
            IsMaster = true,
        };
        var registryQuest = specification.Quests.Select(quest => quest.RegistryQuest).FirstOrDefault(value => value is not null);
        if (registryQuest is FormKey registryFormKey)
        {
            plugin.ModHeader.MasterReferences.Add(new MasterReference
            {
                Master = registryFormKey.ModKey,
            });
        }

        foreach (var questSpecification in specification.Quests)
        {
            var quest = new Quest(new FormKey(specification.ModKey, questSpecification.FormId), StarfieldRelease.Starfield)
            {
                EditorID = questSpecification.EditorId,
                FormVersion = QuestFormVersion,
                Name = questSpecification.QuestName,
                Data = new QuestData
                {
                    Flags = Quest.Flag.StartGameEnabled | Quest.Flag.StartsEnabled | Quest.Flag.RunOnce,
                    Unused = new MemorySlice<byte>(new byte[3]),
                },
                VirtualMachineAdapter = CreateVirtualMachineAdapter(questSpecification),
            };
            plugin.Quests.Add(quest);
        }

        var writeTarget = plugin.BeginWrite.ToPath(new FilePath(outputPath));
        if (registryQuest is null)
        {
            writeTarget.WithNoLoadOrder().Write();
        }
        else
        {
            if (hostPlugin is null)
            {
                throw new InvalidOperationException("The host plugin must be built before a consumer plugin.");
            }

            writeTarget.WithLoadOrder(new IStarfieldModGetter[] { hostPlugin }).Write();
        }

        return plugin;
    }

    /// <summary>
    /// Creates a quest VM adapter and its typed registry and descriptor properties.
    /// </summary>
    /// <param name="specification">The script, registry reference, and optional registration values.</param>
    /// <returns>A VM adapter containing exactly one attached Papyrus script.</returns>
    private static QuestAdapter CreateVirtualMachineAdapter(QuestSpecification specification)
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
        if (specification.Registration is ConsumerRegistrationSpecification registration)
        {
            script.Properties.Add(new ScriptStringProperty { Name = "ConsumerId", Data = registration.ConsumerId });
            script.Properties.Add(new ScriptStringProperty { Name = "DisplayName", Data = registration.DisplayName });
            script.Properties.Add(new ScriptStringProperty { Name = "NormalMoviePath", Data = registration.NormalMoviePath });
            script.Properties.Add(new ScriptStringProperty { Name = "LargeMoviePath", Data = registration.LargeMoviePath });
            script.Properties.Add(new ScriptIntProperty { Name = "DescriptorVersion", Data = registration.DescriptorVersion });
            script.Properties.Add(new ScriptBoolProperty { Name = "ExpectedRegistration", Data = registration.ExpectedRegistration });
            script.Properties.Add(new ScriptFloatProperty { Name = "InitialDelaySeconds", Data = registration.InitialDelaySeconds });
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
    /// Reopens one generated plugin and verifies its master list, quests, script attachments, and typed properties.
    /// </summary>
    /// <param name="specification">The structure that must survive binary serialization.</param>
    /// <param name="outputPath">The generated plugin path.</param>
    /// <param name="hostPlugin">The host plugin used to interpret consumer master style, or <see langword="null"/> for the host.</param>
    /// <exception cref="InvalidDataException">Thrown when the readback violates an invariant.</exception>
    private static void Verify(PluginSpecification specification, string outputPath, StarfieldMod? hostPlugin)
    {
        BinaryReadParameters readParameters;
        var registryQuest = specification.Quests.Select(quest => quest.RegistryQuest).FirstOrDefault(value => value is not null);
        if (registryQuest is not null)
        {
            if (hostPlugin is null)
            {
                throw new InvalidOperationException("The host plugin must be available when verifying a consumer plugin.");
            }

            var masterFlags = new Cache<IModMasterStyledGetter, ModKey>(plugin => plugin.ModKey, EqualityComparer<ModKey>.Default);
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
        var expectedMasters = registryQuest is FormKey registryFormKey
            ? new[] { registryFormKey.ModKey }
            : Array.Empty<ModKey>();
        var actualMasters = plugin.ModHeader.MasterReferences.Select(reference => reference.Master).ToArray();
        Require(actualMasters.SequenceEqual(expectedMasters), specification, $"master list was [{string.Join(", ", actualMasters)}]");

        var quests = plugin.Quests.Records.ToArray();
        Require(quests.Length == specification.Quests.Count, specification, $"expected {specification.Quests.Count} quest(s) but found {quests.Length}");
        foreach (var questSpecification in specification.Quests)
        {
            var expectedFormKey = new FormKey(specification.ModKey, questSpecification.FormId);
            var quest = quests.SingleOrDefault(candidate => candidate.FormKey == expectedFormKey);
            Require(quest is not null, specification, $"quest {expectedFormKey} was missing");
            Require(quest!.EditorID == questSpecification.EditorId, specification, $"quest {expectedFormKey} EditorID was {quest.EditorID}");
            Require(quest.FormVersion == QuestFormVersion, specification, $"quest {expectedFormKey} FormVersion was {quest.FormVersion}");
            var requiredFlags = Quest.Flag.StartGameEnabled | Quest.Flag.StartsEnabled | Quest.Flag.RunOnce;
            Require(quest.Data is not null && quest.Data.Flags == requiredFlags, specification, $"quest {expectedFormKey} flags were {quest.Data?.Flags}");
            Require(quest.VirtualMachineAdapter is not null, specification, $"quest {expectedFormKey} VM adapter was missing");

            var scripts = quest.VirtualMachineAdapter!.Scripts.ToArray();
            Require(scripts.Length == 1, specification, $"quest {expectedFormKey} expected one attached script but found {scripts.Length}");
            var script = scripts.Single();
            Require(script.Name == questSpecification.ScriptName, specification, $"quest {expectedFormKey} attached script was {script.Name}");
            VerifyScriptProperties(specification, questSpecification, script);
        }
    }

    /// <summary>
    /// Verifies one quest script's registry and descriptor properties.
    /// </summary>
    /// <param name="plugin">The owning plugin specification used in failures.</param>
    /// <param name="quest">The expected quest values.</param>
    /// <param name="script">The script entry read from the generated plugin.</param>
    private static void VerifyScriptProperties(PluginSpecification plugin, QuestSpecification quest, ScriptEntry script)
    {
        var properties = script.Properties.ToDictionary(property => property.Name, StringComparer.Ordinal);
        if (quest.RegistryQuest is FormKey registryQuest)
        {
            Require(properties.TryGetValue("Registry", out var registryValue) && registryValue is ScriptObjectProperty registryProperty && registryProperty.Object.FormKey == registryQuest, plugin, $"quest {quest.EditorId} registry link was missing or incorrect");
        }
        else
        {
            Require(properties.Count == 0, plugin, $"host quest {quest.EditorId} unexpectedly had properties");
            return;
        }

        Require(quest.Registration is not null, plugin, $"consumer quest {quest.EditorId} did not declare registration values");
        var registration = quest.Registration!;
        Require(properties.Count == 8, plugin, $"consumer quest {quest.EditorId} had {properties.Count} properties instead of 8");
        Require(properties.TryGetValue("ConsumerId", out var consumerId) && consumerId is ScriptStringProperty consumerIdProperty && consumerIdProperty.Data == registration.ConsumerId, plugin, $"quest {quest.EditorId} ConsumerId was incorrect");
        Require(properties.TryGetValue("DisplayName", out var displayName) && displayName is ScriptStringProperty displayNameProperty && displayNameProperty.Data == registration.DisplayName, plugin, $"quest {quest.EditorId} DisplayName was incorrect");
        Require(properties.TryGetValue("NormalMoviePath", out var normalPath) && normalPath is ScriptStringProperty normalPathProperty && normalPathProperty.Data == registration.NormalMoviePath, plugin, $"quest {quest.EditorId} NormalMoviePath was incorrect");
        Require(properties.TryGetValue("LargeMoviePath", out var largePath) && largePath is ScriptStringProperty largePathProperty && largePathProperty.Data == registration.LargeMoviePath, plugin, $"quest {quest.EditorId} LargeMoviePath was incorrect");
        Require(properties.TryGetValue("DescriptorVersion", out var version) && version is ScriptIntProperty versionProperty && versionProperty.Data == registration.DescriptorVersion, plugin, $"quest {quest.EditorId} DescriptorVersion was incorrect");
        Require(properties.TryGetValue("ExpectedRegistration", out var expected) && expected is ScriptBoolProperty expectedProperty && expectedProperty.Data == registration.ExpectedRegistration, plugin, $"quest {quest.EditorId} ExpectedRegistration was incorrect");
        Require(properties.TryGetValue("InitialDelaySeconds", out var delay) && delay is ScriptFloatProperty delayProperty && Math.Abs(delayProperty.Data - registration.InitialDelaySeconds) < 0.0001f, plugin, $"quest {quest.EditorId} InitialDelaySeconds was incorrect");
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
