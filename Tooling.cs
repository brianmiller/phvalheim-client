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
                File.Copy(source, destination, true);
            }
            catch (Exception error)
            {
                RecordFailure(error, destination, "copy file", true, required, measure);
                throw;
            }
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
