namespace PhValheim;

/// <summary>
/// Serialize sync + launch + game monitoring across all worlds for this user.
/// The native and Flatpak clients use the same host directory. Keep the file:
/// deleting it would allow another launcher to lock a different inode.
/// OS handle cleanup releases the lock even if the launcher is killed.
/// </summary>
internal static class LaunchGuard
{
    internal static FileStream? Acquire(string directory, out string error,
        Action<string, Exception, string>? onFailure = null)
    {
        string path = directory;
        string operation = "create directory";
        try
        {
            Directory.CreateDirectory(directory);
            path = Path.Combine(directory, ".launch.lock");
            operation = "open launch lock";
            var lease = new FileStream(path,
                FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            error = "";
            return lease;
        }
        catch (IOException e)
        {
            error = $"PhValheim could not {operation} at '{path}'. {e.GetType().Name}: {e.Message} "
                + "Another PhValheim launch may be active, or a filesystem problem may prevent access.";
            try { onFailure?.Invoke(path, e, operation); }
            catch { }
        }
        catch (UnauthorizedAccessException e)
        {
            error = $"PhValheim could not {operation} at '{path}'. {e.GetType().Name}: {e.Message} "
                + "Check access to your PhValheim folder.";
            try { onFailure?.Invoke(path, e, operation); }
            catch { }
        }
        return null;
    }
}
