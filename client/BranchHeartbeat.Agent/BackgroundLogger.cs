using System.Threading.Channels;

namespace BranchHeartbeat.Agent;

/// <summary>
/// Runs log actions on a single dedicated thread so a hung logging
/// provider (e.g. Windows Event Log's underlying ReportEvent call, which
/// has no timeout) can never block the heartbeat loop. Unlike spawning a
/// new Task.Run per call, this bounds the damage to at most one stuck
/// thread total instead of leaking one per failed heartbeat.
/// </summary>
public sealed class BackgroundLogger : IDisposable
{
    private readonly Channel<Action> _channel = Channel.CreateBounded<Action>(
        new BoundedChannelOptions(200)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true
        });
    private readonly Thread _thread;

    public BackgroundLogger()
    {
        _thread = new Thread(ProcessQueue)
        {
            IsBackground = true,
            Name = "BranchHeartbeat.Logging"
        };
        _thread.Start();
    }

    public void Enqueue(Action logAction)
    {
        _channel.Writer.TryWrite(logAction);
    }

    private void ProcessQueue()
    {
        foreach (var action in _channel.Reader.ReadAllAsync().ToBlockingEnumerable())
        {
            try
            {
                action();
            }
            catch
            {
                // Logging failures must not affect the heartbeat loop.
            }
        }
    }

    public void Dispose()
    {
        _channel.Writer.TryComplete();
    }
}
