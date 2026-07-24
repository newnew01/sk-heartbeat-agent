using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace BranchHeartbeat.Agent;

public sealed record HeartbeatResult(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("branch")] string Branch,
    [property: JsonPropertyName("device")] string Device,
    [property: JsonPropertyName("observedIp")] string ObservedIp,
    [property: JsonPropertyName("allowedUntil")] DateTimeOffset AllowedUntil);

public sealed class HeartbeatApiClient
{
    private readonly HttpClient _httpClient;

    public HeartbeatApiClient(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<HeartbeatResult> SendAsync(
        AgentConfiguration configuration,
        string deviceKey,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            configuration.ApiUrl);
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", deviceKey);
        request.Headers.Add("X-Device-ID", configuration.DeviceId);
        request.Headers.UserAgent.ParseAdd("BranchHeartbeat-Agent/1.0");

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(
            configuration.RequestTimeoutSeconds));

        using var response = await _httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            timeout.Token);

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Heartbeat API returned HTTP {(int)response.StatusCode}.",
                null,
                response.StatusCode);
        }

        var result = await response.Content.ReadFromJsonAsync<HeartbeatResult>(
            cancellationToken: timeout.Token);
        if (result is null ||
            !string.Equals(result.Status, "ok", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Heartbeat API response is invalid.");
        }

        return result;
    }
}
