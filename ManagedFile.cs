namespace PhValheim;

internal static class ManagedFile
{
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
