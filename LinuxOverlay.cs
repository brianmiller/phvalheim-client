namespace PhValheim;

internal static class LinuxOverlay
{
    // LD_PRELOAD uses colon or whitespace separators (not shell quoting).
    // Remove only Steam's renderer and duplicate doorstop entries; retain other hooks.
    internal static string Preload(string? inherited, string? overlay)
    {
        var libraries = new List<string> { "libdoorstop_x64.so" };
        foreach (string entry in (inherited ?? "").Split(
            new[] { ':', ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            string name = Path.GetFileName(entry);
            if (name is "gameoverlayrenderer.so" or "libdoorstop_x64.so") continue;
            libraries.Add(entry);
        }
        if (overlay != null) libraries.Add(overlay);
        return string.Join(":", libraries);
    }
}
