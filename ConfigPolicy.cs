using System.IO.Compression;
using System.Text.Json;

namespace PhValheim;

/// <summary>Versioned, per-key configuration delivery. Personal files remain ordinary cfg files.</summary>
internal static class ConfigPolicy
{
    internal const string ManifestName = ".phvalheim-policy.json";
    internal sealed class Rule
    {
        public string Section { get; set; } = "";
        public string Key { get; set; } = "";
        public string Value { get; set; } = "";
        public bool Overridable { get; set; } = true;
    }
    internal sealed class ConfigFile
    {
        public string File { get; set; } = "";
        public List<Rule> Entries { get; set; } = new();
    }
    internal sealed class Policy
    {
        public int Version { get; set; }
        public string MinClientVersion { get; set; } = "";
        public List<ConfigFile> Files { get; set; } = new();
        public List<string> ManagedFiles { get; set; } = new();
    }
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private static readonly HashSet<string> SystemFiles = new(StringComparer.OrdinalIgnoreCase)
        { "BepInEx.cfg", "ZeroBandwidth.CustomSeed.cfg", "quick_connect_servers.cfg" };

    private static bool SafeName(string s) => !string.IsNullOrWhiteSpace(s) && s != "." && s != ".."
        && s.IndexOfAny(new[] { '/', '\\', ':', '\0' }) < 0 && !s.StartsWith(".");

    private static Policy? Read(string directory)
    {
        string path = Path.Combine(directory, ManifestName);
        if (!File.Exists(path)) return null;
        var p = JsonSerializer.Deserialize<Policy>(File.ReadAllText(path), JsonOptions)
            ?? throw new InvalidDataException("The server supplied an empty config policy.");
        if (p.Version != 1 || !Version.TryParse(p.MinClientVersion, out var minimum)
            || minimum > new Version(2, 0, 17))
            throw new InvalidDataException("This world needs a newer PhValheim Client. Update the client before launching.");
        if (p.Files == null || p.ManagedFiles == null) throw new InvalidDataException("Incomplete config policy.");
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in p.Files)
        {
            if (f == null || !SafeName(f.File) || !f.File.EndsWith(".cfg", StringComparison.OrdinalIgnoreCase)
                || SystemFiles.Contains(f.File) || !names.Add(f.File) || f.Entries == null)
                throw new InvalidDataException("Invalid config filename in server policy.");
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (var r in f.Entries)
            {
                if (r == null || r.Section == null || string.IsNullOrWhiteSpace(r.Key) || r.Value == null
                    || r.Section.IndexOfAny(new[] { '\r', '\n', '\0', '[', ']' }) >= 0
                    || r.Key.IndexOfAny(new[] { '\r', '\n', '\0', '=' }) >= 0
                    || r.Value.IndexOfAny(new[] { '\r', '\n', '\0' }) >= 0
                    || !keys.Add(r.Section + "\x1f" + r.Key))
                    throw new InvalidDataException("Invalid or duplicate setting in server policy.");
            }
        }
        if (p.ManagedFiles.Any(n => !SystemFiles.Contains(n)))
            throw new InvalidDataException("Unknown managed config file.");
        return p;
    }

    // Preserve comments, unrelated settings, spacing, and the file's newline convention.
    internal static string Edit(string text, string section, string key, string? value, bool onlyMissing = false,
                                string? removeIfValue = null)
    {
        string nl = text.Contains("\r\n") ? "\r\n" : "\n";
        var lines = text.Replace("\r\n", "\n").Split('\n').ToList();
        string current = "";
        bool found = false;
        int insert = -1;
        for (int i = 0; i < lines.Count; i++)
        {
            string trimmed = lines[i].Trim().TrimStart('\ufeff');
            if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
            {
                if (current == section && insert < 0) insert = i;
                current = trimmed[1..^1];
                continue;
            }
            int eq = lines[i].IndexOf('=');
            if (current != section || eq < 0 || trimmed.StartsWith("#") || trimmed.StartsWith(";")
                || lines[i][..eq].Trim() != key) continue;
            found = true;
            if (onlyMissing) continue;
            if (value == null)
            {
                if (removeIfValue == null || lines[i][(eq + 1)..].Trim() == removeIfValue)
                    lines[i] = "";
            }
            else
            {
                int start = eq + 1;
                while (start < lines[i].Length && char.IsWhiteSpace(lines[i][start])) start++;
                lines[i] = lines[i][..start] + value;
            }
        }
        if (!found && value != null)
        {
            if (current == section) insert = lines.Count;
            if (insert < 0)
            {
                lines.Add("");
                if (section.Length > 0) lines.Add("[" + section + "]");
                insert = lines.Count;
            }
            lines.Insert(insert, key + " = " + value);
        }
        return string.Join(nl, lines);
    }

    private static void CopyPersonal(string source, string target)
    {
        if (!Directory.Exists(source)) return;
        Directory.CreateDirectory(target);
        foreach (string path in Directory.EnumerateFileSystemEntries(source))
        {
            var attrs = File.GetAttributes(path);
            if ((attrs & FileAttributes.ReparsePoint) != 0)
                throw new IOException("A config path is a symbolic link; the existing install was kept: " + path);
            string name = Path.GetFileName(path);
            if (name == ManifestName || SystemFiles.Contains(name)) continue;
            string dst = Path.Combine(target, name);
            if ((attrs & FileAttributes.Directory) != 0) CopyPersonal(path, dst);
            else File.Copy(path, dst, true);
        }
    }

    private static void Apply(string directory, Policy policy, Policy? previous)
    {
        var active = policy.Files.ToDictionary(f => f.File, StringComparer.OrdinalIgnoreCase);
        if (previous != null)
        {
            foreach (var f in previous.Files)
            {
                string path = Path.Combine(directory, f.File);
                if (!File.Exists(path)) continue;
                string text = File.ReadAllText(path);
                foreach (var rule in f.Entries.Where(r => !r.Overridable))
                {
                    bool remains = active.TryGetValue(f.File, out var next)
                        && next.Entries.Any(r => r.Section == rule.Section && r.Key == rule.Key && !r.Overridable);
                    if (!remains) text = Edit(text, rule.Section, rule.Key, null, removeIfValue: rule.Value);
                }
                File.WriteAllText(path, text);
            }
        }
        foreach (var f in policy.Files)
        {
            string path = Path.Combine(directory, f.File);
            string text = File.Exists(path) ? File.ReadAllText(path) : "";
            foreach (var r in f.Entries) text = Edit(text, r.Section, r.Key, r.Value, onlyMissing: r.Overridable);
            File.WriteAllText(path, text);
        }
    }

    private static void Commit(string stage, string target)
    {
        string backup = target + ".previous-" + Guid.NewGuid().ToString("N");
        bool existed = Directory.Exists(target);
        if (existed) Directory.Move(target, backup);
        try { Directory.Move(stage, target); }
        catch
        {
            if (existed) Directory.Move(backup, target);
            throw;
        }
        // Successful installation is not invalidated by cleanup (e.g. antivirus holds a file).
        if (existed) { try { Directory.Delete(backup, true); } catch { } }
    }

    internal static void InstallArchive(string archive, string world, bool full)
    {
        string parent = Path.GetDirectoryName(world)!;
        Directory.CreateDirectory(parent);
        string stage = Path.Combine(parent, ".phvalheim-stage-" + Guid.NewGuid().ToString("N"));
        try
        {
            ZipFile.ExtractToDirectory(archive, stage);
            string incoming = Path.Combine(stage, "BepInEx", "config");
            string existing = Path.Combine(world, "BepInEx", "config");
            var policy = Read(incoming);
            if (policy != null)
            {
                var previous = Read(existing);
                CopyPersonal(existing, incoming);
                Apply(incoming, policy, previous);
            }
            if (full) Commit(stage, world);
            else
            {
                if (!Directory.Exists(incoming)) throw new InvalidDataException("The settings archive has no config directory.");
                Directory.CreateDirectory(Path.GetDirectoryName(existing)!);
                Commit(incoming, existing);
            }
        }
        finally { if (Directory.Exists(stage)) Directory.Delete(stage, true); }
    }

    internal static void Enforce(string world)
    {
        string directory = Path.Combine(world, "BepInEx", "config");
        var policy = Read(directory);
        if (policy == null) return;
        // Nothing to enforce when every value is personal. Missing defaults still get seeded.
        string stage = directory + ".apply-" + Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(stage);
            CopyPersonal(directory, stage);
            foreach (string name in SystemFiles.Append(ManifestName))
                if (File.Exists(Path.Combine(directory, name)))
                    File.Copy(Path.Combine(directory, name), Path.Combine(stage, name));
            Apply(stage, policy, null);
            Commit(stage, directory);
        }
        finally { if (Directory.Exists(stage)) Directory.Delete(stage, true); }
    }
}
