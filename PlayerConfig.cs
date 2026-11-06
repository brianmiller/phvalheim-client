using System.Net.Http;
using System.Text.Json;

namespace PhValheim;

internal static class PlayerConfig
{
    internal sealed class Entry
    {
        public string File { get; set; } = "";
        public string Section { get; set; } = "";
        public string Key { get; set; } = "";
        public string Value { get; set; } = "";
    }
    internal sealed class Snapshot
    {
        public int Version { get; set; }
        public List<Entry> Entries { get; set; } = new();
    }
    internal static List<Entry>? Fetch(string server, string world, string? token)
    {
        if (string.IsNullOrEmpty(token)) return null; // Older servers keep the local-only contract.
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20), MaxResponseContentBufferSize = 131072 };
        using var request = new HttpRequestMessage(HttpMethod.Get, server + "/api.php?mode=getPlayerConfig&world=" + Uri.EscapeDataString(world));
        request.Headers.Add("X-PhValheim-Player-Config", token);
        using var response = client.Send(request);
        if (!response.IsSuccessStatusCode) throw new IOException("Personal settings could not be fetched. Reopen the world page and launch again.");
        var snapshot = JsonSerializer.Deserialize<Snapshot>(response.Content.ReadAsStringAsync().GetAwaiter().GetResult(),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        if (snapshot == null || snapshot.Version != 1 || snapshot.Entries == null || snapshot.Entries.Count > 500)
            throw new InvalidDataException("Invalid personal settings response.");
        foreach (var e in snapshot.Entries)
            if (e == null || e.File == null || e.Section == null || e.Key == null || e.Value == null
                || e.Value.Length > 4096 || e.Value.IndexOfAny(new[] { '\r', '\n', '\0' }) >= 0)
                throw new InvalidDataException("Invalid personal setting.");
        return snapshot.Entries;
    }
}
