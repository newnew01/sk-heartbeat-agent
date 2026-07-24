namespace BranchHeartbeat.Agent;

public sealed record AgentConfiguration
{
    public const string DefaultApiUrl =
        "https://heartbeat.184184184.xyz/api/v1/heartbeat";

    public required string ApiUrl { get; init; }
    public required string DeviceId { get; init; }
    public required string ProtectedDeviceKey { get; init; }
    public int IntervalSeconds { get; init; } = 60;
    public int RetrySeconds { get; init; } = 15;
    public int RequestTimeoutSeconds { get; init; } = 15;
}
