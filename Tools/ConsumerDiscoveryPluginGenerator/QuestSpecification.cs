using Mutagen.Bethesda.Plugins;

namespace Venworks.Canvas.ConsumerDiscovery.PluginGenerator;

/// <summary>
/// Describes one deterministic quest and its optional consumer-registration properties.
/// </summary>
internal sealed class QuestSpecification
{
    /// <summary>
    /// Initializes a quest specification.
    /// </summary>
    /// <param name="formId">The deterministic local form ID assigned to the quest.</param>
    /// <param name="editorId">The editor ID assigned to the quest.</param>
    /// <param name="questName">The human-readable quest name stored in the plugin.</param>
    /// <param name="scriptName">The fully qualified Papyrus script attached to the quest.</param>
    /// <param name="registryQuest">The host registry quest referenced by a consumer, or <see langword="null"/> for the host quest.</param>
    /// <param name="registration">The consumer descriptor properties written to VMAD, or <see langword="null"/> for the host quest.</param>
    public QuestSpecification(
        uint formId,
        string editorId,
        string questName,
        string scriptName,
        FormKey? registryQuest,
        ConsumerRegistrationSpecification? registration)
    {
        FormId = formId;
        EditorId = editorId;
        QuestName = questName;
        ScriptName = scriptName;
        RegistryQuest = registryQuest;
        Registration = registration;
    }

    /// <summary>
    /// Gets the deterministic local form ID assigned to the quest.
    /// </summary>
    public uint FormId { get; }

    /// <summary>
    /// Gets the quest editor ID.
    /// </summary>
    public string EditorId { get; }

    /// <summary>
    /// Gets the human-readable quest name.
    /// </summary>
    public string QuestName { get; }

    /// <summary>
    /// Gets the fully qualified attached Papyrus script name.
    /// </summary>
    public string ScriptName { get; }

    /// <summary>
    /// Gets the host registry quest referenced by the consumer, or <see langword="null"/> for the host quest.
    /// </summary>
    public FormKey? RegistryQuest { get; }

    /// <summary>
    /// Gets the consumer registration written to VMAD, or <see langword="null"/> for the host quest.
    /// </summary>
    public ConsumerRegistrationSpecification? Registration { get; }
}

/// <summary>
/// Describes the bounded VMAD values consumed by a configurable probe registrar.
/// </summary>
internal sealed class ConsumerRegistrationSpecification
{
    /// <summary>
    /// Initializes consumer registration values.
    /// </summary>
    /// <param name="consumerId">The stable namespaced consumer identifier.</param>
    /// <param name="displayName">The visible diagnostic name.</param>
    /// <param name="normalMoviePath">The loader-relative normal movie path.</param>
    /// <param name="largeMoviePath">The loader-relative large movie path.</param>
    /// <param name="descriptorVersion">The positive descriptor and movie version.</param>
    /// <param name="expectedRegistration">Whether the registrar expects the registry call to succeed.</param>
    /// <param name="initialDelaySeconds">The bounded delay used to order a fault probe behind healthy registration.</param>
    public ConsumerRegistrationSpecification(
        string consumerId,
        string displayName,
        string normalMoviePath,
        string largeMoviePath,
        int descriptorVersion,
        bool expectedRegistration,
        float initialDelaySeconds)
    {
        ConsumerId = consumerId;
        DisplayName = displayName;
        NormalMoviePath = normalMoviePath;
        LargeMoviePath = largeMoviePath;
        DescriptorVersion = descriptorVersion;
        ExpectedRegistration = expectedRegistration;
        InitialDelaySeconds = initialDelaySeconds;
    }

    /// <summary>
    /// Gets the stable namespaced consumer identifier.
    /// </summary>
    public string ConsumerId { get; }

    /// <summary>
    /// Gets the visible diagnostic name.
    /// </summary>
    public string DisplayName { get; }

    /// <summary>
    /// Gets the loader-relative normal movie path.
    /// </summary>
    public string NormalMoviePath { get; }

    /// <summary>
    /// Gets the loader-relative large movie path.
    /// </summary>
    public string LargeMoviePath { get; }

    /// <summary>
    /// Gets the positive descriptor and movie version.
    /// </summary>
    public int DescriptorVersion { get; }

    /// <summary>
    /// Gets whether the registrar expects the registry call to succeed.
    /// </summary>
    public bool ExpectedRegistration { get; }

    /// <summary>
    /// Gets the bounded delay used before registration attempts.
    /// </summary>
    public float InitialDelaySeconds { get; }
}
