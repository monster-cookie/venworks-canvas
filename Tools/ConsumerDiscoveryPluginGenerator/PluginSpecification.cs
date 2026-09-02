using Mutagen.Bethesda.Plugins;

namespace Venworks.Canvas.ConsumerDiscovery.PluginGenerator;

/// <summary>
/// Describes one deterministic VWCANVAS-9 probe plugin and the quest script that it owns.
/// </summary>
internal sealed class PluginSpecification
{
    /// <summary>
    /// Initializes a probe plugin specification.
    /// </summary>
    /// <param name="fileName">The plugin file name, including its <c>.esm</c> extension.</param>
    /// <param name="questEditorId">The editor ID assigned to the plugin's start-game-enabled quest.</param>
    /// <param name="questName">The human-readable quest name stored in the plugin.</param>
    /// <param name="scriptName">The fully qualified Papyrus script attached to the quest.</param>
    /// <param name="registryQuest">The host registry quest referenced by a consumer, or <see langword="null"/> for the host plugin.</param>
    public PluginSpecification(
        string fileName,
        string questEditorId,
        string questName,
        string scriptName,
        FormKey? registryQuest)
    {
        FileName = fileName;
        QuestEditorId = questEditorId;
        QuestName = questName;
        ScriptName = scriptName;
        RegistryQuest = registryQuest;
    }

    /// <summary>
    /// Gets the plugin file name, including its <c>.esm</c> extension.
    /// </summary>
    public string FileName { get; }

    /// <summary>
    /// Gets the plugin identity derived from <see cref="FileName"/>.
    /// </summary>
    public ModKey ModKey => ModKey.FromNameAndExtension(FileName);

    /// <summary>
    /// Gets the editor ID assigned to the start-game-enabled quest.
    /// </summary>
    public string QuestEditorId { get; }

    /// <summary>
    /// Gets the human-readable quest name stored in the plugin.
    /// </summary>
    public string QuestName { get; }

    /// <summary>
    /// Gets the fully qualified Papyrus script attached to the quest.
    /// </summary>
    public string ScriptName { get; }

    /// <summary>
    /// Gets the host registry quest referenced by a consumer, or <see langword="null"/> for the host plugin.
    /// </summary>
    public FormKey? RegistryQuest { get; }
}
