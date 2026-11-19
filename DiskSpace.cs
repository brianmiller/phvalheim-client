using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace PhValheim;

internal static class DiskSpace
{
    internal sealed record Measurement(string? VolumePath, long? AvailableBytes, string? Error = null);

    internal sealed record Inspection(string DestinationPath, string? ExistingPath,
        string? VolumePath, long? AvailableBytes, string? Error = null);

    internal enum Availability { Unknown, Sufficient, Insufficient }

    internal sealed record Assessment(Inspection Space, long? RequiredBytes,
        Availability Status, string Message);

    internal sealed class InsufficientDiskSpaceException : IOException
    {
        internal Assessment Assessment { get; }

        internal InsufficientDiskSpaceException(Assessment assessment) : base(assessment.Message)
        {
            Assessment = assessment;
        }
    }

    internal static Inspection Inspect(string? destinationPath, Func<string, Measurement>? measure = null)
    {
        string destination = destinationPath ?? "";
        string? existing = null;
        string? volume = null;
        try
        {
            if (string.IsNullOrWhiteSpace(destinationPath))
                return new(destination, null, null, null, "No destination path was supplied.");

            destination = Path.GetFullPath(destinationPath);
            existing = NearestExistingPath(destination);
            if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
                existing = ResolveUnixPath(existing);
            else if (OperatingSystem.IsWindows())
                existing = ResolveWindowsPath(existing);

            Measurement result = (measure ?? Measure)(existing);
            volume = result.VolumePath;
            if (string.IsNullOrEmpty(volume) || result.AvailableBytes == null || result.AvailableBytes < 0
                || !string.IsNullOrEmpty(result.Error))
                return new(destination, existing, volume, null,
                    result.Error ?? "The destination volume or available byte count is unknown.");

            return new(destination, existing, volume, result.AvailableBytes, result.Error);
        }
        catch (Exception ex)
        {
            return new(destination, existing, volume, null, ex.Message);
        }
    }

    // Required bytes are future allocations only; existing files already reduce available space.
    internal static Assessment Assess(Inspection space, long? requiredBytes, string operation)
    {
        long? required = requiredBytes >= 0 ? requiredBytes : null;
        long? available = space.AvailableBytes >= 0 ? space.AvailableBytes : null;
        Availability status = required == null || available == null
            ? Availability.Unknown
            : required > available ? Availability.Insufficient : Availability.Sufficient;
        string outcome = status switch
        {
            Availability.Insufficient => "Insufficient disk space",
            Availability.Sufficient => "Sufficient disk space at inspection time",
            _ => "Disk space sufficiency is unknown"
        };
        string message = $"{operation}: {outcome}. Destination: '{space.DestinationPath}'; "
            + $"volume: '{space.VolumePath ?? "unknown"}'; "
            + $"required additional bytes: {Bytes(required)}; available bytes: {Bytes(available)}.";
        if (requiredBytes < 0) message += " The required byte count was negative.";
        if (!string.IsNullOrEmpty(space.Error)) message += " " + space.Error;
        return new(space, required, status, message);
    }

    internal static Assessment EnsureAvailable(string? path, long? requiredBytes, string operation,
        Func<string, Measurement>? measure = null)
    {
        Assessment assessment = Assess(Inspect(path, measure), requiredBytes, operation);
        if (assessment.Status == Availability.Insufficient)
            throw new InsufficientDiskSpaceException(assessment);
        return assessment;
    }

    private static string Bytes(long? value) => value?.ToString(CultureInfo.InvariantCulture) ?? "unknown";

    private static string NearestExistingPath(string path)
    {
        string root = Path.GetPathRoot(path)
            ?? throw new IOException("The destination has no filesystem root.");
        string existing = root;
        FileAttributes attributes = File.GetAttributes(existing);
        foreach (string part in path[root.Length..].Split(
            new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar },
            StringSplitOptions.RemoveEmptyEntries))
        {
            if ((attributes & FileAttributes.Directory) == 0)
                throw new IOException("A destination ancestor is not a directory: " + existing);
            string candidate = Path.Combine(existing, part);
            try
            {
                attributes = File.GetAttributes(candidate);
            }
            catch (FileNotFoundException) { return existing; }
            catch (DirectoryNotFoundException) { return existing; }
            // Access errors and broken links must not silently fall back to another volume.
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                candidate = OperatingSystem.IsWindows()
                    ? ResolveWindowsPath(candidate) : ResolveUnixPath(candidate);
            existing = candidate;
            attributes = File.GetAttributes(existing);
        }
        return existing;
    }

    private static string ResolveUnixPath(string path)
    {
        IntPtr resolved = RealPath(path, IntPtr.Zero);
        if (resolved == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastPInvokeError());
        try
        {
            return Marshal.PtrToStringUTF8(resolved)
                ?? throw new IOException("The destination path could not be resolved.");
        }
        finally { Free(resolved); }
    }

    private static string ResolveWindowsPath(string path)
    {
        // OPEN_EXISTING, shared read/write/delete, FILE_FLAG_BACKUP_SEMANTICS for directories.
        // No requested access and no OPEN_REPARSE_POINT: follow links without modifying anything.
        using SafeFileHandle handle = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastPInvokeError());
        var resolved = new StringBuilder(32768);
        uint length = GetFinalPathNameByHandle(handle, resolved, (uint)resolved.Capacity, 0);
        if (length == 0) throw new Win32Exception(Marshal.GetLastPInvokeError());
        if (length >= resolved.Capacity) throw new IOException("The resolved destination path is too long.");
        return resolved.ToString();
    }

    private static Measurement Measure(string path)
    {
        if (OperatingSystem.IsWindows()) return MeasureWindows(path);
        if (OperatingSystem.IsMacOS()) return MeasureMacOS(path);
        if (!OperatingSystem.IsLinux())
            return new(null, null, "Disk space inspection is unsupported on this operating system.");

        string? mount = DriveInfo.GetDrives()
            .Select(d => Path.TrimEndingDirectorySeparator(d.Name))
            .Where(m => path == m || path.StartsWith(Path.EndsInDirectorySeparator(m) ? m : m + "/",
                StringComparison.Ordinal))
            .OrderByDescending(m => m.Length)
            .FirstOrDefault();
        if (mount == null) return new(null, null, "No destination mount was found.");
        try
        {
            // Query the destination itself, including file bind mounts.
            return new(mount, new DriveInfo(path).AvailableFreeSpace);
        }
        catch (Exception ex) { return new(mount, null, ex.Message); }
    }

    private static Measurement MeasureWindows(string path)
    {
        var volume = new StringBuilder(32768);
        if (!GetVolumePathName(path, volume, volume.Capacity))
            return new(null, null, new Win32Exception(Marshal.GetLastPInvokeError()).Message);
        string mount = volume.ToString();
        try
        {
            string directory = (File.GetAttributes(path) & FileAttributes.Directory) != 0
                ? path : Path.GetDirectoryName(path)
                    ?? throw new IOException("The destination has no parent directory.");
            if (!Path.EndsInDirectorySeparator(directory)) directory += Path.DirectorySeparatorChar;
            if (!GetDiskFreeSpaceEx(directory, out ulong available, out _, out _))
                return new(mount, null, new Win32Exception(Marshal.GetLastPInvokeError()).Message);
            return available <= long.MaxValue
                ? new(mount, (long)available)
                : new(mount, null, "Available bytes exceed the supported numeric range.");
        }
        catch (Exception ex) { return new(mount, null, ex.Message); }
    }

    private static Measurement MeasureMacOS(string path)
    {
        // Darwin's 64-bit statfs ABI: 2168 bytes, f_mntonname at offset 88 (1024 bytes).
        // statfs resolves APFS firmlinks, which a lexical mount-prefix lookup cannot do.
        var info = new byte[2168];
        int result = RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => StatFsMacX64(path, info),
            Architecture.Arm64 => StatFsMacArm64(path, info),
            _ => throw new PlatformNotSupportedException("Unsupported macOS architecture.")
        };
        if (result != 0)
            return new(null, null, new Win32Exception(Marshal.GetLastPInvokeError()).Message);
        int end = Array.IndexOf(info, (byte)0, 88, 1024);
        if (end <= 88) return new(null, null, "The destination mount name is unavailable.");
        string mount = Encoding.UTF8.GetString(info, 88, end - 88);
        try
        {
            return new(mount, new DriveInfo(path).AvailableFreeSpace);
        }
        catch (Exception ex) { return new(mount, null, ex.Message); }
    }

    [DllImport("libc", EntryPoint = "realpath", SetLastError = true)]
    private static extern IntPtr RealPath([MarshalAs(UnmanagedType.LPUTF8Str)] string path, IntPtr buffer);

    [DllImport("libc", EntryPoint = "free")]
    private static extern void Free(IntPtr pointer);

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode,
        ExactSpelling = true, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", CharSet = CharSet.Unicode,
        ExactSpelling = true, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path,
        uint length, uint flags);

    [DllImport("kernel32.dll", EntryPoint = "GetVolumePathNameW", CharSet = CharSet.Unicode,
        ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetVolumePathName(string path, StringBuilder volume, int length);

    [DllImport("kernel32.dll", EntryPoint = "GetDiskFreeSpaceExW", CharSet = CharSet.Unicode,
        ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetDiskFreeSpaceEx(string path, out ulong available,
        out ulong total, out ulong free);

    [DllImport("libc", EntryPoint = "statfs$INODE64", SetLastError = true)]
    private static extern int StatFsMacX64([MarshalAs(UnmanagedType.LPUTF8Str)] string path, [Out] byte[] info);

    [DllImport("libc", EntryPoint = "statfs", SetLastError = true)]
    private static extern int StatFsMacArm64([MarshalAs(UnmanagedType.LPUTF8Str)] string path, [Out] byte[] info);
}
