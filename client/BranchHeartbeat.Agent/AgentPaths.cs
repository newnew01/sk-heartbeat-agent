namespace BranchHeartbeat.Agent;

public sealed class AgentPaths
{
    public AgentPaths(string? dataDirectory = null)
    {
        DataDirectory =
            dataDirectory ??
            Environment.GetEnvironmentVariable("BRANCH_HEARTBEAT_DATA_DIR") ??
            Path.Combine(
                Environment.GetFolderPath(
                    Environment.SpecialFolder.CommonApplicationData),
                "BranchHeartbeat");
    }

    public string DataDirectory { get; }
    public string ConfigurationFile => Path.Combine(DataDirectory, "agent.json");
    public string StatusFile => Path.Combine(DataDirectory, "status.json");
}
