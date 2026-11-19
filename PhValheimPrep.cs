using System.Text;

namespace PhValheim.Prep
{
    public class PhValheim
    {
        public static bool MakeDir(string inputDir, string desc)
        {
            inputDir = Environment.ExpandEnvironmentVariables(inputDir);
            bool inputDirExists = System.IO.Directory.Exists(inputDir);
            // Silent on success, both ways. "PhValheim root directory was found: C:\Users\..."
            // told a player nothing they could act on and cost two of the first four lines on
            // screen; whether our own folder exists is our problem, not theirs. The path is
            // still one PHVALHEIM_VERBOSE away.
            if (!inputDirExists)
            {
                Ui.Detail(desc + " (creating)", inputDir);

                try
                {
                    Directory.CreateDirectory(inputDir);
                    return true;
                }
                catch (Exception e)
                {
                    return ReportFailure(inputDir, e, "create directory",
                        "PhValheim could not create its " + desc + " folder.", directory: true);
                }

            }
            else
            {
                Ui.Detail(desc, inputDir);
                return true;
            }
        }


        //ensure PhValheim's root dir exists, else create it.
        public static bool PhValheimPrep()
        {
            // One step for both folders. They are one concern to the player and they fail for
            // the same handful of reasons.
            Ui.Step("PhValheim folders");

            if (!MakeDir(Platform.State.PhValheimDir, "PhValheim root"))
            {
                return false;
            }

            if (!MakeDir(Platform.State.PhValheimServerRoot, "World root"))
            {
                return false;
            }

            Ui.Done("ready");
            return true;
        }


        // write backenfile to bepinex directory. phvalheim-companion uses this file to send "Player" scene data to phvalheim-server's backend (e.g., world progression (boss heads hung at spawn point)
        public static bool WriteBackendFile(string worldName, string phvalheimHostNoPort, string phvalheimURL)
        {
            return WriteBackendFile(Path.Combine(Platform.State.PhValheimServerWorld,
                "BepInEx", "phvalheim.backend"), phvalheimURL);
        }

        internal static bool WriteBackendFile(string backendFile, string phvalheimURL)
        {
            var encoding = new UTF8Encoding(false, true);
            long? requiredBytes = null;
            try
            {
                requiredBytes = encoding.GetByteCount(phvalheimURL);
                var assessment = DiskSpace.EnsureAvailable(backendFile, requiredBytes,
                    "write phvalheim.backend");
                DiagnosticLog.Write("backend preflight", assessment.Message);
            }
            catch (Exception e)
            {
                if (e is DiskSpace.InsufficientDiskSpaceException insufficient)
                    DiagnosticLog.Write("backend preflight", insufficient.Assessment.Message);
                return ReportFailure(backendFile, e, "check disk space for phvalheim.backend",
                    "PhValheim could not prepare to write phvalheim.backend.", requiredBytes: requiredBytes);
            }

            string bepInExRoot = Path.GetDirectoryName(backendFile)!;
            try
            {
                Directory.CreateDirectory(bepInExRoot);
            }
            catch (Exception e)
            {
                return ReportFailure(bepInExRoot, e, "create directory",
                    "PhValheim could not create the BepInEx folder for phvalheim.backend.", directory: true);
            }

            try
            {
                if (OperatingSystem.IsWindows())
                {
                    byte[] bytes = encoding.GetBytes(phvalheimURL);
                    ManagedFile.Write(backendFile, stream => stream.Write(bytes, 0, bytes.Length));
                }
                else
                {
                    using var outputFile = new StreamWriter(backendFile, false, encoding);
                    outputFile.Write(phvalheimURL);
                }
            }
            catch (Exception e)
            {
                return ReportFailure(backendFile, e, "create file",
                    "PhValheim could not write phvalheim.backend.", requiredBytes: requiredBytes);
            }
            return true;
        }

        private static bool ReportFailure(string path, Exception error, string operation,
            string message, bool directory = false, long? requiredBytes = null)
        {
            DiagnosticLog.Failure(operation + ": " + path, error);
            string evidence = FileAccessDiagnostics.Describe(path, error, operation);
            // The shared helper assumes a file target; an observed directory is not a collision here.
            if (directory)
                evidence = evidence.Replace("Possible reason: an existing directory occupies the expected file path."
                    + Environment.NewLine, "");
            DiagnosticLog.Write(operation, evidence);
            DiagnosticLog.Write(operation + " disk snapshot",
                DiskSpace.Assess(DiskSpace.Inspect(path), requiredBytes, operation).Message);
            Ui.Fail("failed");
            Ui.Error(message, new[] { DiagnosticLog.Redact(error.GetType().Name + ": " + error.Message),
                    DiagnosticLog.Redact(path) }
                .Concat(evidence.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                    .Select(line => line.TrimEnd('\r'))
                    .Where(line => line.StartsWith("Possible reason:", StringComparison.Ordinal)
                        || line.StartsWith("A protected-folder rule may be involved.", StringComparison.Ordinal)))
                .ToArray());
            return false;
        }
    }
}


