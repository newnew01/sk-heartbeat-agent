using System.Text.Json;

namespace BranchHeartbeat.Agent;

public static class CommandLine
{
    public static int Configure(string[] args, ConfigurationStore store)
    {
        var values = Parse(args);
        var deviceId = Required(values, "--device-id");
        var apiUrl = values.GetValueOrDefault(
            "--api-url",
            AgentConfiguration.DefaultApiUrl);
        var interval = Integer(values, "--interval-seconds", 60);
        var retry = Integer(values, "--retry-seconds", 15);
        var timeout = Integer(values, "--timeout-seconds", 15);

        if (!values.ContainsKey("--key-stdin"))
        {
            throw new ArgumentException(
                "Use --key-stdin and provide the Device Key through standard input.");
        }

        var deviceKey = Console.In.ReadLine()?.Trim();
        if (string.IsNullOrWhiteSpace(deviceKey))
        {
            throw new ArgumentException("Device Key was not provided.");
        }

        store.Save(apiUrl, deviceId, deviceKey, interval, retry, timeout);
        Console.WriteLine("Agent configuration saved securely.");
        return 0;
    }

    public static int Status(AgentStatusStore store)
    {
        var status = store.Read();
        if (status is null)
        {
            Console.WriteLine("{\"state\":\"not-started\"}");
            return 2;
        }

        Console.WriteLine(JsonSerializer.Serialize(
            status,
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = true
            }));
        return string.Equals(status.State, "healthy", StringComparison.Ordinal)
            ? 0
            : 1;
    }

    private static Dictionary<string, string> Parse(string[] args)
    {
        var result = new Dictionary<string, string>(
            StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < args.Length; index++)
        {
            var argument = args[index];
            if (!argument.StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException($"Unexpected argument: {argument}");
            }

            if (string.Equals(argument, "--key-stdin", StringComparison.OrdinalIgnoreCase))
            {
                result[argument] = "true";
                continue;
            }

            if (++index >= args.Length)
            {
                throw new ArgumentException($"Missing value for {argument}.");
            }
            result[argument] = args[index];
        }
        return result;
    }

    private static string Required(
        IReadOnlyDictionary<string, string> values,
        string key)
    {
        if (!values.TryGetValue(key, out var value) ||
            string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"{key} is required.");
        }
        return value;
    }

    private static int Integer(
        IReadOnlyDictionary<string, string> values,
        string key,
        int defaultValue)
    {
        if (!values.TryGetValue(key, out var raw))
        {
            return defaultValue;
        }
        return int.TryParse(raw, out var value)
            ? value
            : throw new ArgumentException($"{key} must be an integer.");
    }
}
