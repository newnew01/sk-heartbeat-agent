using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace BranchHeartbeat.Agent;

public sealed class HeartbeatWorker : BackgroundService
{
    private static readonly TimeSpan BlockingOperationTimeout = TimeSpan.FromSeconds(20);

    private readonly ConfigurationStore _configurationStore;
    private readonly HeartbeatApiClient _apiClient;
    private readonly AgentStatusStore _statusStore;
    private readonly ILogger<HeartbeatWorker> _logger;
    private readonly BackgroundLogger _backgroundLogger;

    public HeartbeatWorker(
        ConfigurationStore configurationStore,
        HeartbeatApiClient apiClient,
        AgentStatusStore statusStore,
        ILogger<HeartbeatWorker> logger,
        BackgroundLogger backgroundLogger)
    {
        _configurationStore = configurationStore;
        _apiClient = apiClient;
        _statusStore = statusStore;
        _logger = logger;
        _backgroundLogger = backgroundLogger;
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
                configuration = await RunWithTimeoutAsync(
                    () => _configurationStore.Load(),
                    BlockingOperationTimeout);
                var loadedConfiguration = configuration;
                var deviceKey = await RunWithTimeoutAsync(
                    () => _configurationStore.UnprotectDeviceKey(loadedConfiguration),
                    BlockingOperationTimeout);
                deviceKeyBytes = Encoding.UTF8.GetBytes(deviceKey);

                var result = await _apiClient.SendAsync(
                    configuration,
                    deviceKey,
                    stoppingToken);
                lastSuccess = DateTimeOffset.UtcNow;
                await RunWithTimeoutAsync(() => _statusStore.Write(new AgentStatus
                {
                    State = "healthy",
                    UpdatedAt = DateTimeOffset.UtcNow,
                    LastSuccessAt = lastSuccess,
                    ObservedIp = result.ObservedIp,
                    AllowedUntil = result.AllowedUntil
                }), BlockingOperationTimeout);
                _backgroundLogger.Enqueue(() => _logger.LogInformation(
                    "Heartbeat succeeded. Public IP {ObservedIp}; allowed until {AllowedUntil}.",
                    result.ObservedIp,
                    result.AllowedUntil));

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
                try
                {
                    await RunWithTimeoutAsync(() => _statusStore.Write(new AgentStatus
                    {
                        State = "error",
                        UpdatedAt = DateTimeOffset.UtcNow,
                        LastSuccessAt = lastSuccess,
                        LastError = safeMessage
                    }), BlockingOperationTimeout);
                }
                catch (TimeoutException)
                {
                    // Best-effort: if even the status write is stuck, fall
                    // through to the retry delay rather than compounding
                    // the hang here.
                }
                _backgroundLogger.Enqueue(() => _logger.LogError(
                    "Heartbeat failed: {ErrorType}: {ErrorMessage}",
                    exception.GetType().Name,
                    safeMessage));

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
        var parts = new List<string>();
        var current = exception;
        while (current is not null)
        {
            var detail = current is SocketException socketException
                ? $"{current.GetType().Name}({socketException.SocketErrorCode}): {current.Message}"
                : $"{current.GetType().Name}: {current.Message}";
            parts.Add(detail);
            current = current.InnerException;
        }

        var message = string.Join(" -> ", parts).ReplaceLineEndings(" ");
        return message.Length <= 300 ? message : message[..300];
    }

    private static async Task<T> RunWithTimeoutAsync<T>(
        Func<T> operation,
        TimeSpan timeout)
    {
        var task = Task.Run(operation);
        var completed = await Task.WhenAny(task, Task.Delay(timeout));
        if (completed != task)
        {
            throw new TimeoutException(
                $"Operation timed out after {timeout.TotalSeconds:0}s. " +
                "It may still be running on an abandoned thread.");
        }

        return await task;
    }

    private static Task RunWithTimeoutAsync(Action operation, TimeSpan timeout)
    {
        return RunWithTimeoutAsync(
            () =>
            {
                operation();
                return true;
            },
            timeout);
    }
}
