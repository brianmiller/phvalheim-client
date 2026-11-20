using System.Security.Cryptography;

namespace PhValheim.Tooling
{
    public class PhValheim
    {
        //calculate md5 of a local file
        public static string getMD5(string filename)
        {
            using (var md5 = MD5.Create())
            {
                using (var stream = File.OpenRead(filename))
                {
                    var hash = md5.ComputeHash(stream);
                    return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
                }
            }
        }

        //copy directory and files recursivley
        public static void CloneDirectory(string root, string dest) => CloneDirectory(root, dest, null);

        internal static void CloneDirectory(string root, string dest,
            Func<string, DiskSpace.Measurement>? measure = null)
        {
            string[] directories;
            string[] files;
            try
            {
                if ((File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Cannot recursively copy a source directory reparse point: " + root);
                directories = Directory.GetDirectories(root);
                files = Directory.GetFiles(root);
            }
            catch (Exception error)
            {
                RecordFailure(error, root, "read source directory");
                throw;
            }

            try
            {
                if (!Directory.Exists(dest))
                    Directory.CreateDirectory(dest);
            }
            catch (Exception error)
            {
                RecordFailure(error, dest, "create directory", true, null, measure);
                throw;
            }

            foreach (var directory in directories)
            {
                string dirName = Path.GetFileName(directory);
                CloneDirectory(directory, Path.Combine(dest, dirName), measure);
            }

            foreach (var file in files)
            {
                CopyFile(file, Path.Combine(dest, Path.GetFileName(file)), measure);
            }
        }

        internal static void CopyFile(string source, string destination,
            Func<string, DiskSpace.Measurement>? measure = null)
        {
            long required;
            try
            {
                required = new FileInfo(source).Length;
            }
            catch (Exception error)
            {
                RecordSourceAttributes(source);
                RecordFailure(error, source, "read source file length");
                throw;
            }

            try
            {
                var assessment = DiskSpace.Assess(DiskSpace.Inspect(destination, measure), required, "copy file");
                DiagnosticLog.Write("copy file", "Source: '" + source + "'; destination: '" + destination + "'.");
                DiagnosticLog.Write("copy disk space", assessment.Message);
                if (assessment.Status == DiskSpace.Availability.Insufficient)
                    throw new DiskSpace.InsufficientDiskSpaceException(assessment);
                if (OperatingSystem.IsWindows())
                {
                    using var sourceFileStream = File.OpenRead(source);
                    ManagedFile.Write(destination, stream => sourceFileStream.CopyTo(stream));
                }
                else if (OperatingSystem.IsMacOS()) CopyFilePreservingHidden(source, destination);
                else File.Copy(source, destination, true);
            }
            catch (Exception error)
            {
                RecordSourceAttributes(source);
                RecordFailure(error, destination, "copy file", true, required, measure);
                throw;
            }
        }

        private static void CopyFilePreservingHidden(string source, string destination)
        {
            FileAttributes? original = null;
            try { original = File.GetAttributes(destination); }
            catch (FileNotFoundException) { }
            if (original.HasValue) CheckCopyDestination(destination, original.Value);

            try { File.Copy(source, destination, true); }
            catch
            {
                if (original.HasValue)
                {
                    try { RestoreCopyHidden(destination, original.Value); }
                    catch (Exception error)
                    {
                        try { DiagnosticLog.Failure("restore copy destination Hidden; path: '" + destination + "'", error); }
                        catch { }
                    }
                }
                throw;
            }
            if (original.HasValue) RestoreCopyHidden(destination, original.Value);
        }

        private static void CheckCopyDestination(string destination, FileAttributes attributes)
        {
            if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory | FileAttributes.Device)) != 0)
                throw new IOException("Copy destination is not a regular file: " + destination);
        }

        private static void RestoreCopyHidden(string destination, FileAttributes original)
        {
            // Path checks cannot exclude an external replacement between check and use.
            var current = File.GetAttributes(destination);
            CheckCopyDestination(destination, current);
            var retained = (current & ~FileAttributes.Hidden) | (original & FileAttributes.Hidden);
            if (retained != current) File.SetAttributes(destination, retained);
        }

        private static void RecordSourceAttributes(string source)
        {
            try
            {
                string details;
                try
                {
                    var attributes = File.GetAttributes(source);
                    details = "Source attributes: hidden=" + ((attributes & FileAttributes.Hidden) != 0)
                        + ", read-only=" + ((attributes & FileAttributes.ReadOnly) != 0)
                        + ", system=" + ((attributes & FileAttributes.System) != 0)
                        + ", reparse=" + ((attributes & FileAttributes.ReparsePoint) != 0);
                }
                catch (Exception error)
                {
                    details = "Source attributes unavailable; " + error.GetType().FullName
                        + "; HResult=0x" + error.HResult.ToString("X8") + "; " + error.Message;
                }
                DiagnosticLog.Write("copy source attributes", "Source: '" + source + "'; " + details
                    + ". Observed after the failure; attributes may change.");
            }
            catch { }
        }

        private static void RecordFailure(Exception error, string path, string operation,
            bool writing = false, long? required = null, Func<string, DiskSpace.Measurement>? measure = null)
        {
            try
            {
                error.Data["PhValheim.Path"] = path;
                error.Data["PhValheim.Operation"] = operation;
            }
            catch { }
            try { DiagnosticLog.Failure(operation + "; path: '" + path + "'", error); }
            catch { }
            if (!writing) return;
            try
            {
                DiagnosticLog.Write("file access", FileAccessDiagnostics.Describe(path, error, operation));
            }
            catch { }
            try
            {
                DiagnosticLog.Write("disk space after failure",
                    DiskSpace.Assess(DiskSpace.Inspect(path, measure), required, operation).Message);
            }
            catch { }
        }
    }
}
