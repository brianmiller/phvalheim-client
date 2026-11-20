using System.Text;

namespace PhValheim;

// Helpers for Windows overwrites of Hidden or System files that plain writes can refuse.
// Write preserves destination attributes and rejects ReadOnly; config-staging Copy applies
// source ordinary attributes after Write succeeds. Elsewhere WriteText and Copy use plain calls.
internal static class ManagedFile
{
    /// <summary>File.WriteAllText (UTF-8, no byte-order mark), Hidden-safe on Windows.</summary>
    internal static void WriteText(string destination, string text)
    {
        if (!OperatingSystem.IsWindows())
        {
            File.WriteAllText(destination, text);
            return;
        }
        byte[] bytes = new UTF8Encoding(false).GetBytes(text);
        Write(destination, stream => stream.Write(bytes, 0, bytes.Length));
    }

    /// <summary>Copy into a disposable config stage, Hidden-safe on Windows.</summary>
    // ConfigPolicy callers target uncommitted archive or enforcement stages only.
    // Preserve File.Copy's source ordinary attributes after Write checks destination protections.
    // Post-copy metadata failures propagate to abort the uncommitted stage.
    internal static void Copy(string source, string destination)
    {
        if (!OperatingSystem.IsWindows() || !File.Exists(destination))
        {
            File.Copy(source, destination, true);
            return;
        }
        const FileAttributes ordinary = FileAttributes.Hidden | FileAttributes.System
            | FileAttributes.Archive | FileAttributes.ReadOnly | FileAttributes.Temporary
            | FileAttributes.Offline | FileAttributes.NotContentIndexed;
        FileAttributes sourceAttributes = File.GetAttributes(source) & ordinary;
        using var input = File.OpenRead(source);
        Write(destination, stream => input.CopyTo(stream));
        File.SetAttributes(destination, sourceAttributes == 0 ? FileAttributes.Normal : sourceAttributes);
    }

    // The caller holds the user launch lock to serialize app-managed writers.
    // Path checks cannot protect against external changes between check and use.
    // Flush and ReplaceFile recovery do not provide a power-loss guarantee.
    // Writers must flush their wrappers and leave the supplied stream open.
    internal static void Write(string destination, Action<Stream> write)
    {
        if (!OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("Managed file replacement requires Windows.");
        ArgumentNullException.ThrowIfNull(write);
        destination = Path.GetFullPath(destination);
        bool existed = CheckDestination(destination).HasValue;
        string directory = Path.GetDirectoryName(destination)!;
        string stage = Path.Combine(directory, ".phvalheim-write-" + Guid.NewGuid().ToString("N") + ".tmp");
        string backup = Path.Combine(directory, ".phvalheim-backup-" + Guid.NewGuid().ToString("N") + ".tmp");
        bool ownsStage = false;
        bool keepRecovery = false;
        bool replaced = false;
        try
        {
            using (var stream = new FileStream(stage, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                ownsStage = true;
                write(stream);
                stream.Flush(true);
            }

            if (GetAttributes(backup).HasValue)
                throw new IOException("Managed file backup path already exists: " + backup);
            FileAttributes? attributes = CheckDestination(destination);
            if (attributes.HasValue != existed)
                throw new IOException("Managed file destination appeared or disappeared while staging: " + destination);

            if (attributes.HasValue)
            {
                // ReplaceFile preserves Windows security, compression and encryption;
                // SetAttributes only applies ordinary flags to our staged file.
                const FileAttributes ordinary = FileAttributes.Hidden | FileAttributes.System
                    | FileAttributes.Archive | FileAttributes.Temporary | FileAttributes.Offline
                    | FileAttributes.NotContentIndexed;
                FileAttributes stagedAttributes = attributes.Value & ordinary;
                File.SetAttributes(stage, stagedAttributes == 0 ? FileAttributes.Normal : stagedAttributes);
                try
                {
                    File.Replace(stage, destination, backup, false);
                    replaced = true;
                }
                catch
                {
                    keepRecovery = !TryRecover(destination, stage, backup);
                    throw;
                }
            }
            else File.Move(stage, destination);
            ownsStage = false;
        }
        finally
        {
            if (!keepRecovery)
            {
                if (ownsStage) Cleanup(stage);
                if (replaced) Cleanup(backup);
            }
        }
    }

    private static FileAttributes? GetAttributes(string path)
    {
        try { return File.GetAttributes(path); }
        catch (FileNotFoundException) { return null; }
    }

    private static void CheckAttributes(string path, FileAttributes attributes)
    {
        if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory | FileAttributes.Device)) != 0)
            throw new IOException("Managed file path is not a regular file: " + path);
        if ((attributes & FileAttributes.ReadOnly) != 0)
            throw new UnauthorizedAccessException("Managed file is read-only: " + path);
    }

    private static FileAttributes? CheckDestination(string destination)
    {
        FileAttributes? attributes = GetAttributes(destination);
        if (attributes.HasValue)
        {
            CheckAttributes(destination, attributes.Value);
            // Open validates actual write access without truncating a Hidden file.
            using var stream = new FileStream(destination, FileMode.Open, FileAccess.Write, FileShare.None);
        }
        return attributes;
    }

    private static bool TryRecover(string destination, string stage, string backup)
    {
        try
        {
            FileAttributes? backupAttributes = GetAttributes(backup);
            FileAttributes? destinationAttributes = GetAttributes(destination);
            if (backupAttributes.HasValue && !destinationAttributes.HasValue)
            {
                CheckAttributes(backup, backupAttributes.Value);
                File.Move(backup, destination);
                return true;
            }
            // With no backup, ReplaceFile leaves the original at its old name.
            if (!backupAttributes.HasValue && destinationAttributes.HasValue)
            {
                CheckAttributes(destination, destinationAttributes.Value);
                return true;
            }
        }
        catch (Exception e)
        {
            DiagnosticLog.Failure("restore managed file: " + destination, e);
        }
        DiagnosticLog.Write("managed file recovery",
            "Replacement failed; retaining recovery files if present. Destination: '" + destination
            + "'; stage: '" + stage + "'; backup: '" + backup + "'.");
        return false;
    }

    private static void Cleanup(string path)
    {
        try
        {
            FileAttributes? attributes = GetAttributes(path);
            if (!attributes.HasValue) return;
            CheckAttributes(path, attributes.Value);
            File.Delete(path);
        }
        catch (Exception e)
        {
            DiagnosticLog.Failure("clean up managed file: " + path, e);
        }
    }
}
