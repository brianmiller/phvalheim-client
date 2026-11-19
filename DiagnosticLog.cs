using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;

namespace PhValheim;

internal static class DiagnosticLog
{
    private const string FileName = "phvalheim-client.log";
    private const string Hidden = "[REDACTED]";
    private const int FileLimit = 1024 * 1024;
    private const int EntryLimit = 32 * 1024;
    private const int InputLimit = 256 * 1024;
    private const int SecretLimit = 2 * 1024 * 1024;
    private static readonly object Gate = new();
    private static readonly HashSet<string> Secrets = new(StringComparer.Ordinal);
    private static int secretCharacters;
    private static bool suppressText;
    private static bool initialized;
    private static bool warned;
    private static bool usingFallback;
    private static string? logPath;
    private static string? isolatedRoot;

    public static void Initialize(string[]? rawArgs, string? root = null)
    {
        try
        {
            lock (Gate)
            {
                RegisterArguments(rawArgs);
                if (initialized) return;
                initialized = true;
                isolatedRoot = root;
                if (root != null && !Path.IsPathFullyQualified(root))
                    throw new IOException("An isolated diagnostic root must be absolute.");
                if (root != null && new DirectoryInfo(root).LinkTarget != null)
                    throw new IOException("Unsafe isolated diagnostic root.");
                string marker = BeginRun();
                try
                {
                    string directory = root == null ? DefaultDirectory() : Path.Combine(root, "logs");
                    logPath = Path.Combine(Path.GetFullPath(directory), FileName);
                    Append(marker, true);
                    return;
                }
                catch { logPath = null; }
                if (!StartFallback()) Disable();
            }
        }
        catch { Disable(); }
    }

    public static void RegisterSecret(string? secret)
    {
        try
        {
            lock (Gate) { AddSecretForms(secret); }
        }
        catch { suppressText = true; }
    }

    public static string Redact(string? text)
    {
        try
        {
            lock (Gate)
            {
                if (string.IsNullOrEmpty(text)) return "";
                if (suppressText) return "[diagnostic text withheld: secret registration failed]";
                // Never truncate before redaction: the cut could expose half a credential.
                if (text.Length > InputLimit) return "[diagnostic text omitted: input limit exceeded]";
                string result = Sanitize(text);
                result = Replace(result, @"\S*%[0-9a-f]{2}\S*", match =>
                {
                    string decoded = match.Value;
                    for (int i = 0; i < 3; i++)
                    {
                        string next = Uri.UnescapeDataString(decoded);
                        if (next == decoded) break;
                        decoded = next;
                        if (Sanitize(decoded) != decoded) return Hidden;
                        string formDecoded = decoded.Replace('+', ' ');
                        if (Sanitize(formDecoded) != formDecoded) return Hidden;
                    }
                    return match.Value;
                });
                return result;
            }
        }
        catch { return "[diagnostic text withheld: redaction failed]"; }
    }

    public static void Write(string? text) => Write("info", text);

    public static void Write(string? step, string? text)
    {
        try
        {
            lock (Gate)
            {
                if (!initialized || logPath == null) return;
                string entry = Format(Redact(step) + ": " + Redact(text));
                try { Append(entry, false); }
                catch
                {
                    logPath = null;
                    if (usingFallback || !StartFallback(entry)) Disable();
                }
            }
        }
        catch { Disable(); }
    }

    public static void Failure(string? operation, Exception? exception)
    {
        try
        {
            string detail;
            try
            {
                detail = exception == null ? "Exception unavailable."
                    : "HResult=0x" + exception.HResult.ToString("X8", CultureInfo.InvariantCulture)
                        + "\n" + exception.ToString();
            }
            catch { detail = "Exception text unavailable."; }
            Write(operation, detail);
        }
        catch { Disable(); }
    }

    public static string SupportLine
    {
        get
        {
            try
            {
                lock (Gate)
                {
                    return logPath == null ? "Diagnostic logging unavailable."
                        : "Diagnostic log: " + logPath + ". Send this file if you report this.";
                }
            }
            catch { return "Diagnostic logging unavailable."; }
        }
    }

    private static void RegisterArguments(string[]? args)
    {
        try
        {
            if (args == null) return;
            if (args.Length > 256) { suppressText = true; return; }
            for (int index = 0; index < args.Length; index++)
            {
                string? raw = args[index];
                if (string.IsNullOrEmpty(raw)) continue;
                if (raw.Length > InputLimit) { suppressText = true; continue; }
                string decodedUri = Uri.UnescapeDataString(raw);
                if (decodedUri.Contains("phvalheim:", StringComparison.OrdinalIgnoreCase)
                    || (index == 0 && decodedUri.Contains('?')))
                {
                    AddSecretForms(raw);
                    AddSecretForms(decodedUri);
                    int separator = decodedUri.IndexOf('?');
                    string payload = separator >= 0 ? decodedUri[(separator + 1)..]
                        : decodedUri[(decodedUri.IndexOf(':') + 1)..].TrimStart('/');
                    AddSecretForms(payload);
                    RegisterPayload(payload.Split('?')[0]);
                }
                else if (raw == "--phvalheim-launch" && index + 1 < args.Length)
                    RegisterPayload(args[++index]);
                else if (raw.StartsWith("--phvalheim-launch=", StringComparison.OrdinalIgnoreCase))
                {
                    AddSecretForms(raw);
                    RegisterPayload(raw[(raw.IndexOf('=') + 1)..]);
                }
            }
        }
        catch { suppressText = true; }
    }

    private static void RegisterPayload(string? payload)
    {
        AddSecretForms(payload);
        if (string.IsNullOrEmpty(payload) || payload.Length > InputLimit) return;
        string decoded;
        try { decoded = Encoding.UTF8.GetString(Convert.FromBase64String(payload)); }
        catch (FormatException) { return; }
        AddSecretForms(decoded);
        string[] fields = decoded.Split('?');
        foreach (int field in new[] { 2, 10, 12 })
        {
            if (fields.Length <= field) continue;
            AddSecretForms(fields[field]);
            if (field != 2 && fields[field].Contains('='))
                AddSecretForms(fields[field][(fields[field].IndexOf('=') + 1)..]);
        }
        if (fields.Length > 12)
        {
            string companion = string.Join("?", fields.Take(12));
            AddSecretForms(companion);
            AddSecretForms(Convert.ToBase64String(Encoding.UTF8.GetBytes(companion)));
        }
    }

    private static void AddSecretForms(string? secret)
    {
        if (string.IsNullOrEmpty(secret)) return;
        if (secret.Length > InputLimit) { suppressText = true; return; }
        AddSecret(secret);
        string decoded = Uri.UnescapeDataString(secret);
        AddSecret(decoded);
        string encoded = Uri.EscapeDataString(secret);
        AddSecret(encoded);
        AddSecret(encoded.Replace("%20", "+", StringComparison.Ordinal));
        AddSecret(Uri.EscapeDataString(encoded));
        if (decoded != secret) AddSecret(Uri.EscapeDataString(decoded));
    }

    private static void AddSecret(string secret)
    {
        if (secret.Length == 0 || Secrets.Contains(secret)) return;
        if (Secrets.Count >= 4096 || secret.Length > SecretLimit - secretCharacters)
        {
            suppressText = true;
            return;
        }
        Secrets.Add(secret);
        secretCharacters += secret.Length;
    }

    private static string Sanitize(string text)
    {
        foreach (string secret in Secrets.OrderByDescending(value => value.Length))
            text = text.Replace(secret, Hidden, StringComparison.Ordinal);
        text = Replace(text, @"phvalheim://[^\s\""'<>]*", _ => "phvalheim://" + Hidden);
        text = Replace(text, @"(--phvalheim-launch(?:\s+|=))(?:\""[^\""\r\n]*\""|'[^'\r\n]*'|[^\s\""'<>]+)",
            m => m.Groups[1].Value + Hidden);
        text = Replace(text, @"(\b(?:Bearer|Basic)\s+)[^\s\""'<>;,]+", m => m.Groups[1].Value + Hidden);
        text = Replace(text,
            @"(\b(?:[a-z0-9_-]*(?:password|token|secret|api[_-]?key)|passwd|pwd|auth|authorization|credential|signature|sig|playerConfig|X-PhValheim-Player-Config)\b[\""']?\s*[:=]\s*)(?:\""[^\""\r\n]*\""|'[^'\r\n]*'|[^\s&?#,;\""'<>]+)",
            m => m.Groups[1].Value + Hidden);
        text = Replace(text, @"(https?://[^\s/@:]+:)[^\s/@]+@", m => m.Groups[1].Value + Hidden + "@");
        return text;
    }

    private static string Replace(string text, string pattern, MatchEvaluator replacement) =>
        Regex.Replace(text, pattern, replacement,
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking,
            TimeSpan.FromMilliseconds(250));

    private static string DefaultDirectory()
    {
        string home = Environment.GetFolderPath(OperatingSystem.IsWindows()
            ? Environment.SpecialFolder.ApplicationData : Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home) || !Path.IsPathFullyQualified(home))
            throw new IOException("User directory unavailable.");
        if (OperatingSystem.IsWindows()) return Path.Combine(home, "PhValheim", "logs");
        if (OperatingSystem.IsMacOS()) return Path.Combine(home, "Library", "Application Support", "PhValheim", "logs");
        return Path.Combine(home, ".config", "PhValheim", "logs");
    }

    private static bool StartFallback(string? entry = null)
    {
        try
        {
            usingFallback = true;
            string identity = Environment.UserName + "\n"
                + Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string directory = isolatedRoot == null
                ? Path.Combine(Path.GetTempPath(), "PhValheim-" + Hash(identity), "logs")
                : Path.Combine(isolatedRoot, "temp", "logs");
            logPath = Path.Combine(Path.GetFullPath(directory), FileName);
            Append(BeginRun(), true);
            if (entry != null) Append(entry, false);
            return true;
        }
        catch { logPath = null; return false; }
    }

    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    private static void Append(string entry, bool rotate)
    {
        string path = logPath ?? throw new IOException("Log unavailable.");
        string directory = Path.GetDirectoryName(path)!;
        PrepareDirectory(directory);
        // Keep a stable inode: native and Flatpak launches may have different /tmp
        // namespaces, so a named mutex alone would not serialize their rotations.
        using (var lease = AcquireLease(path + ".lock"))
        {
            for (int i = 0; i <= 3; i++) CheckFile(i == 0 ? path : path + "." + i);
            // Old or externally enlarged owned logs must not defeat the disk bound.
            for (int i = 0; i <= 3; i++)
            {
                string owned = i == 0 ? path : path + "." + i;
                if (File.Exists(owned) && new FileInfo(owned).Length > FileLimit)
                {
                    using var oversized = Open(owned);
                    oversized.SetLength(0);
                }
            }
            byte[] bytes = Encoding.UTF8.GetBytes(entry);
            if (bytes.Length > EntryLimit) bytes = Encoding.UTF8.GetBytes(Format("[entry omitted: size limit exceeded]"));
            long length = File.Exists(path) ? new FileInfo(path).Length : 0;
            if ((rotate && length > 0) || length + bytes.Length > FileLimit)
            {
                for (int i = 2; i >= 0; i--)
                {
                    string source = i == 0 ? path : path + "." + i;
                    if (File.Exists(source)) File.Move(source, path + "." + (i + 1), true);
                }
            }
            using var stream = Open(path);
            stream.Seek(0, SeekOrigin.End);
            stream.Write(bytes);
            stream.Flush();
        }
    }

    private static FileStream AcquireLease(string path)
    {
        for (int attempt = 0; ; attempt++)
        {
            try
            {
                var lease = Open(path, true);
                try { lease.SetLength(0); return lease; }
                catch { lease.Dispose(); throw; }
            }
            catch (IOException) when (attempt < 4) { Thread.Sleep(25); }
        }
    }

    private static FileStream Open(string path, bool exclusive = false)
    {
        CheckFile(path);
        var options = new FileStreamOptions
        {
            Mode = FileMode.OpenOrCreate,
            Access = FileAccess.ReadWrite,
            Share = exclusive ? FileShare.None : FileShare.Read,
            BufferSize = 4096
        };
        if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        var stream = new FileStream(path, options);
        if (stream.CanSeek) return stream;
        stream.Dispose();
        throw new IOException("Diagnostic path is not a regular file.");
    }

    private static void CheckFile(string path)
    {
        try
        {
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory | FileAttributes.Device)) != 0)
                throw new IOException("Unsafe diagnostic file path.");
        }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
    }

    private static void PrepareDirectory(string directory)
    {
        // Reject links at both owned levels; never chmod an existing user directory.
        var info = new DirectoryInfo(directory);
        if (info.LinkTarget != null || info.Parent?.LinkTarget != null)
            throw new IOException("Unsafe diagnostic directory.");
        if (OperatingSystem.IsWindows())
        {
            if (usingFallback)
            {
                using var identity = WindowsIdentity.GetCurrent();
                SecurityIdentifier user = identity.User ?? throw new IOException("User identity unavailable.");
                var security = new DirectorySecurity();
                security.SetAccessRuleProtection(true, false);
                security.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.FullControl,
                    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                    PropagationFlags.None, AccessControlType.Allow));
                foreach (DirectoryInfo owned in info.Parent == null ? new[] { info } : new[] { info.Parent, info })
                {
                    if (!owned.Exists) owned.Create(security);
                    foreach (FileSystemAccessRule rule in owned.GetAccessControl().GetAccessRules(true, true, typeof(SecurityIdentifier)))
                    {
                        if (rule.AccessControlType == AccessControlType.Allow && !rule.IdentityReference.Equals(user)
                            && !rule.IdentityReference.Equals(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null))
                            && !rule.IdentityReference.Equals(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null)))
                            throw new IOException("Diagnostic fallback is not private.");
                    }
                }
            }
            else Directory.CreateDirectory(directory);
        }
        else
        {
            if (usingFallback && info.Parent != null && !info.Parent.Exists)
                Directory.CreateDirectory(info.Parent.FullName, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            Directory.CreateDirectory(directory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            const UnixFileMode otherAccess = UnixFileMode.GroupRead | UnixFileMode.GroupWrite | UnixFileMode.GroupExecute
                | UnixFileMode.OtherRead | UnixFileMode.OtherWrite | UnixFileMode.OtherExecute;
            if ((File.GetUnixFileMode(directory) & otherAccess) != 0)
                throw new IOException("Diagnostic directory is not private.");
            if (usingFallback && info.Parent != null && (File.GetUnixFileMode(info.Parent.FullName) & otherAccess) != 0)
                throw new IOException("Diagnostic fallback is not private.");
        }
    }

    private static string BeginRun()
    {
        try
        {
            Assembly assembly = typeof(DiagnosticLog).Assembly;
            string version = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                ?? assembly.GetName().Version?.ToString() ?? "unknown";
            return Format(Redact("Begin run; version=" + version + "; runtime=" + RuntimeInformation.FrameworkDescription
                + "; platform=" + RuntimeInformation.OSDescription + "; architecture=" + RuntimeInformation.ProcessArchitecture));
        }
        catch { return Format("Begin run; runtime metadata unavailable."); }
    }

    private static string Format(string text)
    {
        const string truncated = "\n[diagnostic text truncated]";
        int budget = EntryLimit - 128 - Encoding.UTF8.GetByteCount(truncated);
        if (Encoding.UTF8.GetByteCount(text) > budget)
        {
            int count = Math.Min(text.Length, budget / 3);
            if (count > 0 && char.IsHighSurrogate(text[count - 1])) count--;
            text = text[..count] + truncated;
        }
        var clean = new StringBuilder(text.Length);
        foreach (char character in text)
            clean.Append(char.IsControl(character) && character != '\n' && character != '\t' ? ' ' : character);
        return DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture) + " " + clean + "\n";
    }

    private static void Disable()
    {
        try
        {
            lock (Gate)
            {
                logPath = null;
                if (warned) return;
                warned = true;
                try { Console.Error.WriteLine("Warning: diagnostic logging unavailable; PhValheim will continue without a log file."); }
                catch { }
            }
        }
        catch { }
    }
}
