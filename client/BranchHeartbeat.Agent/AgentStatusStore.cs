using System.Text;
using System.Text.Json;

namespace BranchHeartbeat.Agent;

public sealed record AgentStatus
{
    public required string State { get; init; }
    public DateTimeOffset UpdatedAt { get; init; }
    public DateTimeOffset? LastSuccessAt { get; init; }
    public string? ObservedIp { get; init; }
    public DateTimeOffset? AllowedUntil { get; init; }
    public string? LastError { get; init; }
}

public sealed class AgentStatusStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private readonly AgentPaths _paths;

    public AgentStatusStore(AgentPaths paths)
    {
        _paths = paths;
    }

    public void Write(AgentStatus status)
    {
        Directory.CreateDirectory(_paths.DataDirectory);
        var temporaryFile = _paths.StatusFile + ".tmp";
        File.WriteAllText(
            temporaryFile,
            JsonSerializer.Serialize(status, JsonOptions),
            new UTF8Encoding(false));
        File.Move(temporaryFile, _paths.StatusFile, true);
    }

    public AgentStatus? Read()
    {
        if (!File.Exists(_paths.StatusFile))
        {
            return null;
        }

        return JsonSerializer.Deserialize<AgentStatus>(
            File.ReadAllText(_paths.StatusFile),
            JsonOptions);
    }
}
