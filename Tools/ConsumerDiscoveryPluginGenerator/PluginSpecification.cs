using Mutagen.Bethesda.Plugins;

namespace Venworks.Canvas.ConsumerDiscovery.PluginGenerator;

/// <summary>
/// Describes one deterministic VWCANVAS-9 probe plugin and every quest it owns.
/// </summary>
internal sealed class PluginSpecification
{
    /// <summary>
    /// Initializes a probe plugin specification.
    /// </summary>
    /// <param name="fileName">The plugin file name, including its <c>.esm</c> extension.</param>
    /// <param name="quests">The non-empty ordered quest specifications written into the plugin.</param>
    /// <exception cref="ArgumentException">Thrown when <paramref name="fileName"/> is empty.</exception>
    /// <exception cref="ArgumentNullException">Thrown when <paramref name="quests"/> is <see langword="null"/>.</exception>
    /// <exception cref="ArgumentException">Thrown when <paramref name="quests"/> is empty.</exception>
    public PluginSpecification(string fileName, IReadOnlyList<QuestSpecification> quests)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fileName);
        ArgumentNullException.ThrowIfNull(quests);
        if (quests.Count == 0)
        {
            throw new ArgumentException("A probe plugin must contain at least one quest.", nameof(quests));
        }

        FileName = fileName;
        Quests = quests;
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
    /// Gets the ordered quest specifications written into the plugin.
    /// </summary>
    public IReadOnlyList<QuestSpecification> Quests { get; }
}
