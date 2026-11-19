using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

namespace PhValheim;

internal static class FileAccessDiagnostics
{
    internal static string Describe(string? path, Exception? error, string? operation)
    {
        try { return DescribeCore(path, error, operation); }
        catch
        {
            try { return "File access diagnostics unavailable. " + ErrorDetails(error); }
            catch { return "File access diagnostics unavailable; error details unknown."; }
        }
    }

    private static string DescribeCore(string? path, Exception? error, string? operation)
    {
        var output = new StringBuilder();
        output.AppendLine("Operation: " + (operation ?? "unknown"));
        output.AppendLine("Exception: " + ErrorDetails(error));
        string? fullPath = null;
        try
        {
            if (!string.IsNullOrEmpty(path)) fullPath = Path.GetFullPath(path);
            output.AppendLine("Full path: " + (fullPath ?? "unknown (no path supplied)"));
        }
        catch (Exception e)
        {
            output.AppendLine("Supplied path: " + path);
            output.AppendLine("Full path: unknown; " + ErrorDetails(e));
        }
        if (fullPath == null) return output.ToString();

        output.AppendLine("Filesystem observations are from after the failure and may change.");
        var target = Observe(fullPath, "Target", output, out bool targetNotFound);
        string? parent = null;
        string? nearest = null;
        FileAttributes? parentAttributes = null;
        try
        {
            parent = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(fullPath));
            string? candidate = parent;
            for (int depth = 0; !string.IsNullOrEmpty(candidate) && depth < 128; depth++)
            {
                try
                {
                    var attributes = File.GetAttributes(candidate);
                    if (candidate == parent) parentAttributes = attributes;
                    if ((attributes & FileAttributes.Directory) != 0)
                    {
                        nearest = candidate;
                        break;
                    }
                    output.AppendLine("Ancestor is not a directory: " + candidate);
                }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
                catch (Exception e)
                {
                    output.AppendLine("Ancestor status unknown: " + candidate + "; " + ErrorDetails(e));
                    output.AppendLine("Closer ancestors may exist even when their status cannot be read.");
                }
                candidate = Path.GetDirectoryName(candidate);
            }
            output.AppendLine("Nearest observed existing parent directory: " + (nearest ?? "unknown"));
            if (nearest != null) Observe(nearest, "Parent", output, out _);
        }
        catch (Exception e) { output.AppendLine("Parent lookup: unknown; " + ErrorDetails(e)); }

        DescribeLocations(fullPath, output);
        if (OperatingSystem.IsWindows())
        {
            string? securityPath = target.HasValue ? fullPath : nearest;
            bool directory = target.HasValue ? (target.Value & FileAttributes.Directory) != 0 : true;
            DescribeSecurity(securityPath, directory, output);
        }
        else output.AppendLine("Windows owner/ACL: not applicable on this OS.");

        bool probeDenied = false;
        bool immediateParentExists = parentAttributes.HasValue
            && (parentAttributes.Value & FileAttributes.Directory) != 0;
        if (error is IOException or UnauthorizedAccessException && immediateParentExists && parent != null
            && !InsideMacBundle(parent))
        {
            probeDenied = Probe(parent, output);
        }
        else
        {
            output.AppendLine("Parent probe: create/write/delete not attempted (no access/IO error, "
                + "immediate parent not observed as a directory, or macOS app bundle).");
        }

        bool protectedFolderHint = OperatingSystem.IsWindows() && error is UnauthorizedAccessException && probeDenied
            && targetNotFound && immediateParentExists
            && (string.Equals(operation, "create file", StringComparison.OrdinalIgnoreCase)
                || string.Equals(operation, "create new file", StringComparison.OrdinalIgnoreCase));
        if (protectedFolderHint)
            output.AppendLine("Create-operation evidence: target not found during observation; parent probe denied.");

        if (target.HasValue && (target.Value & FileAttributes.Directory) != 0)
        {
            if (string.Equals(operation, "create file", StringComparison.OrdinalIgnoreCase)
                || string.Equals(operation, "create new file", StringComparison.OrdinalIgnoreCase)
                || string.Equals(operation, "copy file", StringComparison.OrdinalIgnoreCase)
                || string.Equals(operation, "write file", StringComparison.OrdinalIgnoreCase)
                || string.Equals(operation, "write download partial", StringComparison.OrdinalIgnoreCase)
                || string.Equals(operation, "replace download destination", StringComparison.OrdinalIgnoreCase)
                || string.Equals(operation, "write sync record", StringComparison.OrdinalIgnoreCase)
                || (operation != null && operation.StartsWith("write ", StringComparison.OrdinalIgnoreCase)
                    && operation.EndsWith(" file", StringComparison.OrdinalIgnoreCase)))
                output.AppendLine("Possible reason: an existing directory occupies the expected file path.");
        }
        else if (target.HasValue && (target.Value & FileAttributes.ReadOnly) != 0)
        {
            output.AppendLine("Possible reason: the observed read-only attribute may prevent changing this file.");
        }
        if (error is UnauthorizedAccessException)
        {
            output.AppendLine("Possible reason: access permissions may prevent the requested operation.");
        }
        else if (error is IOException && error.HResult is unchecked((int)0x80070020) or unchecked((int)0x80070021))
        {
            output.AppendLine("Possible reason: another open handle may prevent access (sharing/lock error).");
        }
        if (protectedFolderHint)
        {
            output.AppendLine("A protected-folder rule may be involved. Check Windows Security > Ransomware protection > Allow an app.");
        }
        return output.ToString();
    }

    private static FileAttributes? Observe(string path, string label, StringBuilder output, out bool notFound)
    {
        notFound = false;
        try
        {
            var attributes = File.GetAttributes(path);
            bool directory = (attributes & FileAttributes.Directory) != 0;
            bool link = (attributes & FileAttributes.ReparsePoint) != 0;
            output.AppendLine(label + ": " + (directory ? "directory" : link ? "non-directory reparse point/link" : "file")
                + (directory && link ? " (reparse point/link)" : ""));
            output.AppendLine(label + " attributes: read-only=" + ((attributes & FileAttributes.ReadOnly) != 0)
                + ", hidden=" + ((attributes & FileAttributes.Hidden) != 0)
                + ", system=" + ((attributes & FileAttributes.System) != 0) + ", reparse=" + link);
            return attributes;
        }
        catch (FileNotFoundException e)
        {
            notFound = true;
            output.AppendLine(label + ": not found by attribute lookup; " + ErrorDetails(e));
        }
        catch (DirectoryNotFoundException e)
        {
            output.AppendLine(label + ": path component not found by attribute lookup; " + ErrorDetails(e));
        }
        catch (Exception e) { output.AppendLine(label + ": unknown; " + ErrorDetails(e)); }
        return null;
    }

    private static void DescribeLocations(string path, StringBuilder output)
    {
        foreach (var folder in new[] { Environment.SpecialFolder.MyDocuments,
            Environment.SpecialFolder.DesktopDirectory, Environment.SpecialFolder.MyPictures })
        {
            try
            {
                string location = Environment.GetFolderPath(folder, Environment.SpecialFolderOption.DoNotVerify);
                output.AppendLine("Known protected location " + folder + ": "
                    + (string.IsNullOrEmpty(location) ? "unknown (location unavailable)"
                        : (IsWithin(path, Path.GetFullPath(location)) ? "inside " : "outside ") + location));
            }
            catch (Exception e) { output.AppendLine("Known protected location " + folder + ": unknown; " + ErrorDetails(e)); }
        }
        output.AppendLine("Location membership is lexical; links are not resolved and protection status is unknown.");
    }

    private static bool IsWithin(string path, string directory)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        directory = Path.TrimEndingDirectorySeparator(directory);
        return string.Equals(Path.TrimEndingDirectorySeparator(path), directory, comparison)
            || path.StartsWith(Path.EndsInDirectorySeparator(directory) ? directory : directory + Path.DirectorySeparatorChar, comparison);
    }

    private static bool InsideMacBundle(string path)
    {
        if (!OperatingSystem.IsMacOS()) return false;
        return path.Split(Path.DirectorySeparatorChar).Any(part => part.EndsWith(".app", StringComparison.OrdinalIgnoreCase));
    }

    private static void DescribeSecurity(string? path, bool directory, StringBuilder output)
    {
        if (!OperatingSystem.IsWindows()) return;
        if (path == null)
        {
            output.AppendLine("Windows owner/ACL: unknown (no observed target or parent).");
            return;
        }
        output.AppendLine("Windows security path: " + path);
        try
        {
            FileSystemSecurity security = directory
                ? new DirectoryInfo(path).GetAccessControl(AccessControlSections.Owner)
                : new FileInfo(path).GetAccessControl(AccessControlSections.Owner);
            output.AppendLine("Owner SID: " + (security.GetOwner(typeof(SecurityIdentifier))?.Value ?? "unknown"));
        }
        catch (Exception e) { output.AppendLine("Owner SID: unknown; " + ErrorDetails(e)); }
        try
        {
            FileSystemSecurity security = directory
                ? new DirectoryInfo(path).GetAccessControl(AccessControlSections.Access)
                : new FileInfo(path).GetAccessControl(AccessControlSections.Access);
            var rules = security.GetAccessRules(true, true, typeof(SecurityIdentifier));
            output.AppendLine("ACL: " + rules.Count + " access entries; inheritance protected=" + security.AreAccessRulesProtected
                + ". Summary is not an effective-access calculation.");
            for (int i = 0; i < Math.Min(3, rules.Count); i++)
            {
                try
                {
                    if (rules[i] is not FileSystemAccessRule rule)
                    {
                        output.AppendLine("ACL entry: unknown rule type.");
                        continue;
                    }
                    output.AppendLine("ACL entry: " + rule.IdentityReference.Value + "; " + rule.AccessControlType
                        + "; " + rule.FileSystemRights + "; inherited=" + rule.IsInherited);
                }
                catch (Exception e) { output.AppendLine("ACL entry: unknown; " + ErrorDetails(e)); }
            }
            if (rules.Count > 3) output.AppendLine("Remaining ACL entries omitted.");
        }
        catch (Exception e) { output.AppendLine("ACL: unknown; " + ErrorDetails(e)); }
    }

    private static bool Probe(string parent, StringBuilder output)
    {
        FileStream? stream = null;
        string? probePath = null;
        bool denied = false;
        string create = "not attempted", write = "not attempted", delete = "not attempted (no owned file)";
        try
        {
            probePath = Path.Combine(parent, ".phvalheim-access-probe-" + Guid.NewGuid().ToString("N") + ".tmp");
            stream = new FileStream(probePath, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                1, FileOptions.DeleteOnClose);
            create = "succeeded (CreateNew with DeleteOnClose)";
            try
            {
                stream.WriteByte(0);
                stream.Flush();
                write = "succeeded (one byte and flush)";
            }
            catch (Exception e)
            {
                denied = e is UnauthorizedAccessException;
                write = "failed; " + ErrorDetails(e);
            }
        }
        catch (Exception e)
        {
            denied = e is UnauthorizedAccessException;
            create = "failed (CreateNew with DeleteOnClose); " + ErrorDetails(e);
        }
        finally
        {
            if (stream != null)
            {
                try
                {
                    stream.Dispose();
                    try
                    {
                        File.GetAttributes(probePath!);
                        delete = "unconfirmed (path still observed after close): " + probePath;
                    }
                    catch (FileNotFoundException) { delete = "succeeded (probe path not found after close)"; }
                    catch (Exception e) { delete = "unknown after close; " + ErrorDetails(e); }
                }
                catch (Exception e) { delete = "close failed; deletion unknown; " + ErrorDetails(e); }
                // Never delete by path: a replacement could belong to someone else.
            }
        }
        output.AppendLine("Parent probe directory: " + parent);
        output.AppendLine("Parent probe create: " + create);
        output.AppendLine("Parent probe write: " + write);
        output.AppendLine("Parent probe delete: " + delete);
        output.AppendLine("This probe only describes this process and one temporary name; it cannot establish a program-specific block or access to the target.");
        return denied;
    }

    private static string ErrorDetails(Exception? error)
    {
        if (error == null) return "none supplied";
        string type = "unknown exception", message = "unknown message", hresult = "unknown HResult";
        try { type = error.GetType().FullName ?? "unknown exception"; } catch { }
        try { message = error.Message ?? "unknown message"; } catch { }
        try { hresult = "0x" + error.HResult.ToString("X8"); } catch { }
        return type + " (" + hresult + "): " + message;
    }
}
