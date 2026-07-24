using System.Net;
using System.Text;
using BranchHeartbeat.Agent;

var failures = new List<string>();
Run("configuration round-trip", TestConfigurationRoundTrip, failures);
await RunAsync("heartbeat request", TestHeartbeatRequest, failures);
Run("status round-trip", TestStatusRoundTrip, failures);

if (failures.Count > 0)
{
    Console.Error.WriteLine(string.Join(Environment.NewLine, failures));
    return 1;
}

Console.WriteLine("All Agent tests passed.");
return 0;

static void TestConfigurationRoundTrip()
{
    using var temporary = new TemporaryDirectory();
    var store = new ConfigurationStore(new AgentPaths(temporary.Path));
    store.Save(
        AgentConfiguration.DefaultApiUrl,
        "branch-001-device-01",
        "secret-device-key",
        60,
        15,
        15);
    var configuration = store.Load();
    Assert(configuration.DeviceId == "branch-001-device-01", "Device ID mismatch.");
    Assert(
        store.UnprotectDeviceKey(configuration) == "secret-device-key",
        "DPAPI round-trip failed.");
    Assert(
        !File.ReadAllText(Path.Combine(temporary.Path, "agent.json"))
            .Contains("secret-device-key", StringComparison.Ordinal),
        "Plaintext Device Key was written to disk.");
}

static async Task TestHeartbeatRequest()
{
    var handler = new RecordingHandler();
    var client = new HeartbeatApiClient(new HttpClient(handler));
    var configuration = new AgentConfiguration
    {
        ApiUrl = AgentConfiguration.DefaultApiUrl,
        DeviceId = "device-uid",
        ProtectedDeviceKey = "unused",
        RequestTimeoutSeconds = 15
    };
    var result = await client.SendAsync(
        configuration,
        "device-token",
        CancellationToken.None);
    Assert(result.ObservedIp == "203.0.113.7", "Observed IP mismatch.");
    Assert(
        handler.Authorization == "Bearer device-token",
        "Authorization header mismatch.");
    Assert(handler.DeviceId == "device-uid", "Device ID header mismatch.");
}

static void TestStatusRoundTrip()
{
    using var temporary = new TemporaryDirectory();
    var store = new AgentStatusStore(new AgentPaths(temporary.Path));
    store.Write(new AgentStatus
    {
        State = "healthy",
        UpdatedAt = DateTimeOffset.UtcNow,
        LastSuccessAt = DateTimeOffset.UtcNow,
        ObservedIp = "203.0.113.7",
        AllowedUntil = DateTimeOffset.UtcNow.AddMinutes(10)
    });
    var status = store.Read();
    Assert(status?.State == "healthy", "Status state mismatch.");
    Assert(status?.ObservedIp == "203.0.113.7", "Status IP mismatch.");
}

static void Run(string name, Action test, ICollection<string> failures)
{
    try
    {
        test();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception exception)
    {
        failures.Add($"FAIL {name}: {exception.Message}");
    }
}

static async Task RunAsync(
    string name,
    Func<Task> test,
    ICollection<string> failures)
{
    try
    {
        await test();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception exception)
    {
        failures.Add($"FAIL {name}: {exception.Message}");
    }
}

static void Assert(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

sealed class RecordingHandler : HttpMessageHandler
{
    public string? Authorization { get; private set; }
    public string? DeviceId { get; private set; }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        Authorization = request.Headers.Authorization?.ToString();
        DeviceId = request.Headers.GetValues("X-Device-ID").Single();
        const string json =
            """
            {
              "status": "ok",
              "branch": "branch-001",
              "device": "pos-01",
              "observedIp": "203.0.113.7",
              "allowedUntil": "2026-07-24T06:00:00+00:00"
            }
            """;
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        });
    }
}

sealed class TemporaryDirectory : IDisposable
{
    public TemporaryDirectory()
    {
        Path = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "branch-heartbeat-agent-tests",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, true);
        }
    }
}
