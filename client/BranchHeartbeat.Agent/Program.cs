using BranchHeartbeat.Agent;
using Microsoft.Extensions.Logging.Configuration;
using Microsoft.Extensions.Logging.EventLog;

const string serviceName = "BranchHeartbeatAgent";

try
{
    var paths = new AgentPaths();
    var configurationStore = new ConfigurationStore(paths);
    var statusStore = new AgentStatusStore(paths);
    var command = args.FirstOrDefault()?.ToLowerInvariant();

    if (command == "configure")
    {
        return CommandLine.Configure(args[1..], configurationStore);
    }

    if (command == "status")
    {
        return CommandLine.Status(statusStore);
    }

    if (command is not null and not "run")
    {
        Console.Error.WriteLine(
            "Usage: BranchHeartbeat.Agent.exe [run|configure|status]");
        return 64;
    }

    var builder = Host.CreateApplicationBuilder(args);
    builder.Services.AddWindowsService(options =>
    {
        options.ServiceName = serviceName;
    });
    LoggerProviderOptions.RegisterProviderOptions<
        EventLogSettings,
        EventLogLoggerProvider>(builder.Services);

    builder.Services.AddSingleton(paths);
    builder.Services.AddSingleton(configurationStore);
    builder.Services.AddSingleton(statusStore);
    builder.Services.AddSingleton(new HttpClient());
    builder.Services.AddSingleton<HeartbeatApiClient>();
    builder.Services.AddHostedService<HeartbeatWorker>();

    await builder.Build().RunAsync();
    return 0;
}
catch (Exception exception)
{
    Console.Error.WriteLine($"{exception.GetType().Name}: {exception.Message}");
    return 1;
}
