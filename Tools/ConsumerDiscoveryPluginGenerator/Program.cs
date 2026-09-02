namespace Venworks.Canvas.ConsumerDiscovery.PluginGenerator;

/// <summary>
/// Provides the command-line entry point for deterministic VWCANVAS-9 probe-plugin generation.
/// </summary>
internal static class Program
{
    /// <summary>
    /// Builds and verifies one profile of host and consumer plugins in the requested output directory.
    /// </summary>
    /// <param name="args">Command-line arguments in the form <c>--output &lt;directory&gt; --profile &lt;name&gt;</c>.</param>
    /// <returns>Zero on success; one when arguments or plugin generation are invalid.</returns>
    private static int Main(string[] args)
    {
        try
        {
            ParseArguments(args, out var outputDirectory, out var profile);
            var outputs = PluginBuilder.BuildAll(outputDirectory, profile);
            foreach (var output in outputs)
            {
                Console.WriteLine($"Verified {output}");
            }

            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
    }

    /// <summary>
    /// Parses the required output-directory and profile options.
    /// </summary>
    /// <param name="args">The raw command-line arguments.</param>
    /// <param name="outputDirectory">Receives the output directory supplied after <c>--output</c>.</param>
    /// <param name="profile">Receives the exact profile supplied after <c>--profile</c>.</param>
    /// <exception cref="ArgumentException">Thrown when a required option is absent, duplicated, or malformed.</exception>
    private static void ParseArguments(string[] args, out string outputDirectory, out string profile)
    {
        outputDirectory = string.Empty;
        profile = string.Empty;
        if (args.Length != 4)
        {
            throw new ArgumentException("Usage: ConsumerDiscoveryPluginGenerator --output <directory> --profile <Baseline|Faults|UpdatedA>");
        }

        for (var index = 0; index < args.Length; index += 2)
        {
            var option = args[index];
            var value = args[index + 1];
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException($"Option '{option}' requires a non-empty value.");
            }
            if (string.Equals(option, "--output", StringComparison.Ordinal) && outputDirectory.Length == 0)
            {
                outputDirectory = value;
            }
            else if (string.Equals(option, "--profile", StringComparison.Ordinal) && profile.Length == 0)
            {
                profile = value;
            }
            else
            {
                throw new ArgumentException($"Unknown or duplicate option '{option}'.");
            }
        }

        if (outputDirectory.Length == 0 || profile.Length == 0)
        {
            throw new ArgumentException("Both --output and --profile are required.");
        }
    }
}
