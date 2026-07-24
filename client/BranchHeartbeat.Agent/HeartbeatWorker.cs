using System.Security.Cryptography;
using System.Text;

namespace BranchHeartbeat.Agent;

public sealed class HeartbeatWorker : BackgroundService
{
    private readonly ConfigurationStore _configurationStore;
    private readonly HeartbeatApiClient _apiClient;
    private readonly AgentStatusStore _statusStore;
    private readonly ILogger<HeartbeatWorker> _logger;

    public HeartbeatWorker(
        ConfigurationStore configurationStore,
        HeartbeatApiClient apiClient,
        AgentStatusStore statusStore,
        ILogger<HeartbeatWorker> logger)
    {
        _configurationStore = configurationStore;
        _apiClient = apiClient;
        _statusStore = statusStore;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        DateTimeOffset? lastSuccess = null;

        while (!stoppingToken.IsCancellationRequested)
        {
            AgentConfiguration? configuration = null;
            byte[]? deviceKeyBytes = null;
            try
            {
                configuration = _configurationStore.Load();
                var deviceKey = _configurationStore.UnprotectDeviceKey(configuration);
                deviceKeyBytes = Encoding.UTF8.GetBytes(deviceKey);

                var result = await _apiClient.SendAsync(
                    configuration,
                    deviceKey,
                    stoppingToken);
                lastSuccess = DateTimeOffset.UtcNow;
                _statusStore.Write(new AgentStatus
                {
                    State = "healthy",
                    UpdatedAt = DateTimeOffset.UtcNow,
                    LastSuccessAt = lastSuccess,
                    ObservedIp = result.ObservedIp,
                    AllowedUntil = result.AllowedUntil
                });
                _logger.LogInformation(
                    "Heartbeat succeeded. Public IP {ObservedIp}; allowed until {AllowedUntil}.",
                    result.ObservedIp,
                    result.AllowedUntil);

                await Task.Delay(
                    TimeSpan.FromSeconds(configuration.IntervalSeconds),
                    stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                var safeMessage = SafeError(exception);
                _statusStore.Write(new AgentStatus
                {
                    State = "error",
                    UpdatedAt = DateTimeOffset.UtcNow,
                    LastSuccessAt = lastSuccess,
                    LastError = safeMessage
                });
                _logger.LogError(
                    "Heartbeat failed: {ErrorType}: {ErrorMessage}",
                    exception.GetType().Name,
                    safeMessage);

                var retrySeconds = configuration?.RetrySeconds ?? 15;
                try
                {
                    await Task.Delay(
                        TimeSpan.FromSeconds(retrySeconds),
                        stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    break;
                }
            }
            finally
            {
                if (deviceKeyBytes is not null)
                {
                    CryptographicOperations.ZeroMemory(deviceKeyBytes);
                }
            }
        }
    }

    private static string SafeError(Exception exception)
    {
        var message = exception.Message.ReplaceLineEndings(" ");
        return message.Length <= 300 ? message : message[..300];
    }
}
