namespace Venworks.Canvas.ConsumerDiscovery.PluginGenerator;

/// <summary>
/// Provides the command-line entry point for deterministic VWCANVAS-9 probe-plugin generation.
/// </summary>
internal static class Program
{
    /// <summary>
    /// Builds and verifies the host and consumer plugins in the requested output directory.
    /// </summary>
    /// <param name="args">Command-line arguments in the form <c>--output &lt;directory&gt;</c>.</param>
    /// <returns>Zero on success; one when arguments or plugin generation are invalid.</returns>
    private static int Main(string[] args)
    {
        try
        {
            var outputDirectory = ParseOutputDirectory(args);
            var outputs = PluginBuilder.BuildAll(outputDirectory);
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
    /// Parses the single required output-directory option.
    /// </summary>
    /// <param name="args">The raw command-line arguments.</param>
    /// <returns>The output directory supplied after <c>--output</c>.</returns>
    /// <exception cref="ArgumentException">Thrown when the required option is absent or malformed.</exception>
    private static string ParseOutputDirectory(string[] args)
    {
        if (args.Length != 2 || !string.Equals(args[0], "--output", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(args[1]))
        {
            throw new ArgumentException("Usage: ConsumerDiscoveryPluginGenerator --output <directory>");
        }

        return args[1];
    }
}
