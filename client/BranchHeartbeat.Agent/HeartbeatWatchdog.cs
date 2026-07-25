namespace BranchHeartbeat.Agent;

public sealed class HeartbeatWatchdog : BackgroundService
{
    private static readonly TimeSpan CheckInterval = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan StartupGracePeriod = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan StaleThreshold = TimeSpan.FromMinutes(5);

    private readonly AgentStatusStore _statusStore;
    private readonly ILogger<HeartbeatWatchdog> _logger;
    private readonly DateTimeOffset _startedAt = DateTimeOffset.UtcNow;

    public HeartbeatWatchdog(
        AgentStatusStore statusStore,
        ILogger<HeartbeatWatchdog> logger)
    {
        _statusStore = statusStore;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(CheckInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (DateTimeOffset.UtcNow - _startedAt < StartupGracePeriod)
            {
                continue;
            }

            var status = _statusStore.Read();
            if (status is null)
            {
                continue;
            }

            var staleness = DateTimeOffset.UtcNow - status.UpdatedAt;
            if (staleness < StaleThreshold)
            {
                continue;
            }

            _logger.LogCritical(
                "Heartbeat status has not updated for {StalenessSeconds}s " +
                "(threshold {ThresholdSeconds}s); the heartbeat loop appears " +
                "hung. Forcing process exit so Windows Service recovery can " +
                "restart it.",
                (int)staleness.TotalSeconds,
                (int)StaleThreshold.TotalSeconds);

            Environment.Exit(1);
        }
    }
}
