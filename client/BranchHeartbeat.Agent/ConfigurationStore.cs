using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace BranchHeartbeat.Agent;

public sealed partial class ConfigurationStore
{
    private static readonly byte[] Entropy =
        SHA256.HashData(Encoding.UTF8.GetBytes("BranchHeartbeat.Agent.v1"));

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private readonly AgentPaths _paths;

    public ConfigurationStore(AgentPaths paths)
    {
        _paths = paths;
    }

    public AgentConfiguration Load()
    {
        if (!File.Exists(_paths.ConfigurationFile))
        {
            throw new InvalidOperationException(
                $"Agent is not configured. Missing {_paths.ConfigurationFile}");
        }

        var json = File.ReadAllText(_paths.ConfigurationFile);
        var configuration = JsonSerializer.Deserialize<AgentConfiguration>(
            json,
            JsonOptions) ?? throw new InvalidOperationException(
                "Agent configuration is invalid.");
        Validate(configuration);
        return configuration;
    }

    public string UnprotectDeviceKey(AgentConfiguration configuration)
    {
        var encrypted = Convert.FromBase64String(configuration.ProtectedDeviceKey);
        var decrypted = ProtectedData.Unprotect(
            encrypted,
            Entropy,
            DataProtectionScope.LocalMachine);
        return Encoding.UTF8.GetString(decrypted);
    }

    public void Save(
        string apiUrl,
        string deviceId,
        string deviceKey,
        int intervalSeconds,
        int retrySeconds,
        int requestTimeoutSeconds)
    {
        var plainBytes = Encoding.UTF8.GetBytes(deviceKey);
        try
        {
            var encrypted = ProtectedData.Protect(
                plainBytes,
                Entropy,
                DataProtectionScope.LocalMachine);
            var configuration = new AgentConfiguration
            {
                ApiUrl = apiUrl,
                DeviceId = deviceId,
                ProtectedDeviceKey = Convert.ToBase64String(encrypted),
                IntervalSeconds = intervalSeconds,
                RetrySeconds = retrySeconds,
                RequestTimeoutSeconds = requestTimeoutSeconds
            };
            Validate(configuration);

            Directory.CreateDirectory(_paths.DataDirectory);
            var temporaryFile = _paths.ConfigurationFile + ".tmp";
            File.WriteAllText(
                temporaryFile,
                JsonSerializer.Serialize(configuration, JsonOptions),
                new UTF8Encoding(false));
            File.Move(temporaryFile, _paths.ConfigurationFile, true);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plainBytes);
        }
    }

    public static void Validate(AgentConfiguration configuration)
    {
        if (!Uri.TryCreate(configuration.ApiUrl, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps)
        {
            throw new ArgumentException("API URL must be an absolute HTTPS URL.");
        }

        if (!DeviceIdPattern().IsMatch(configuration.DeviceId))
        {
            throw new ArgumentException(
                "Device ID may contain only letters, numbers, dot, underscore, and dash.");
        }

        if (string.IsNullOrWhiteSpace(configuration.ProtectedDeviceKey))
        {
            throw new ArgumentException("Device Key is required.");
        }

        if (configuration.IntervalSeconds is < 15 or > 300)
        {
            throw new ArgumentOutOfRangeException(
                nameof(configuration.IntervalSeconds),
                "Heartbeat interval must be between 15 and 300 seconds.");
        }

        if (configuration.RetrySeconds is < 5 or > 300)
        {
            throw new ArgumentOutOfRangeException(
                nameof(configuration.RetrySeconds),
                "Retry interval must be between 5 and 300 seconds.");
        }

        if (configuration.RequestTimeoutSeconds is < 5 or > 60)
        {
            throw new ArgumentOutOfRangeException(
                nameof(configuration.RequestTimeoutSeconds),
                "Request timeout must be between 5 and 60 seconds.");
        }
    }

    [GeneratedRegex("^[A-Za-z0-9._-]{1,128}$", RegexOptions.CultureInvariant)]
    private static partial Regex DeviceIdPattern();
}
