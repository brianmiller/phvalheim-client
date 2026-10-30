namespace PhValheim;

/// <summary>
/// Serialize sync + launch + game monitoring across all worlds for this user.
/// The native and Flatpak clients use the same host directory. Keep the file:
/// deleting it would allow another launcher to lock a different inode.
/// OS handle cleanup releases the lock even if the launcher is killed.
/// </summary>
internal static class LaunchGuard
{
    internal static FileStream? Acquire(string directory, out string error)
    {
        try
        {
            Directory.CreateDirectory(directory);
            var lease = new FileStream(Path.Combine(directory, ".launch.lock"),
                FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            error = "";
            return lease;
        }
        catch (IOException)
        {
            error = "Another PhValheim launch is active, or its launch lock could not be opened. "
                + "Close the previous launcher before trying again.";
        }
        catch (UnauthorizedAccessException)
        {
            error = "PhValheim cannot open its launch lock. Check access to your PhValheim folder.";
        }
        return null;
    }
}
