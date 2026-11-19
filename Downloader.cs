using System.Diagnostics;
using System.Net.Http;

namespace PhValheim.Downloader
{
    class PhValheim
    {
        private static readonly TimeSpan InactivityTimeout = TimeSpan.FromSeconds(30);

        public static bool Go(Uri remoteFile, string localFile, string worldName,
            Func<string, DiskSpace.Measurement>? measure = null)
        {
            string destination = localFile;
            string? partial = null;
            bool ownsPartial = false;
            long received = 0;
            long? total = null;
            long? required = null;
            string operation = "resolve download destination";
            string? operationPath = localFile;
            bool fileOperation = true;
            Exception? failure = null;
            DiskSpace.Assessment? assessment = null;
            HttpClient? client = null;
            HttpResponseMessage? response = null;
            Stream? source = null;
            FileStream? target = null;

            void RecordFailure(Exception error, string step, string? path, bool fileAccess)
            {
                if (failure != null)
                {
                    DiagnosticLog.Failure(step + ": " + path, error);
                    return;
                }
                failure = error;
                operation = step;
                operationPath = path;
                fileOperation = fileAccess;
            }

            void DisposeResource(IDisposable? resource, string step, string? path, bool fileAccess)
            {
                try { resource?.Dispose(); }
                catch (Exception error) { RecordFailure(error, step, path, fileAccess); }
            }

            void CheckSpace(long? bytes)
            {
                required = bytes;
                // The sibling receives the bytes, even if the final name is a symlink.
                var space = DiskSpace.Inspect(partial, measure) with { DestinationPath = destination };
                assessment = DiskSpace.Assess(space, bytes, "download to " + partial);
                if (assessment.Status == DiskSpace.Availability.Insufficient)
                    throw new DiskSpace.InsufficientDiskSpaceException(assessment);
            }

            try
            {
                destination = Path.GetFullPath(localFile);
                partial = Path.Combine(Path.GetDirectoryName(destination)!,
                    ".phvalheim-download-" + Guid.NewGuid().ToString("N") + ".partial");
                DiagnosticLog.Write("download", "Source: " + remoteFile + "; destination: " + destination);
                Ui.Detail("payload url", DiagnosticLog.Redact(remoteFile.ToString()));
                Ui.Detail("saving to", DiagnosticLog.Redact(destination));

                fileOperation = false;
                operation = "receive download response headers";
                client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
                using var inactivity = new CancellationTokenSource(InactivityTimeout);
                response = client.GetAsync(remoteFile, HttpCompletionOption.ResponseHeadersRead,
                    inactivity.Token).GetAwaiter().GetResult();
                inactivity.CancelAfter(Timeout.InfiniteTimeSpan);
                response.EnsureSuccessStatusCode();
                if (response.StatusCode == System.Net.HttpStatusCode.PartialContent)
                    throw new HttpRequestException("The server returned an unsolicited partial download.");
                total = response.Content.Headers.ContentLength;
                operation = "check download disk space";
                CheckSpace(total);
                DiagnosticLog.Write("download preflight", assessment!.Message);

                operation = "open download response stream";
                inactivity.CancelAfter(InactivityTimeout);
                source = response.Content.ReadAsStreamAsync(inactivity.Token).GetAwaiter().GetResult();
                inactivity.CancelAfter(Timeout.InfiniteTimeSpan);

                operation = "create new file";
                operationPath = partial;
                fileOperation = true;
                target = new FileStream(partial, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                    1, FileOptions.SequentialScan);
                ownsPartial = true;

                var buffer = new byte[64 * 1024];
                var progress = Stopwatch.StartNew();
                int lastPercent = -1;
                long lastDisplayed = -1;
                while (true)
                {
                    operation = "read download response";
                    fileOperation = false;
                    inactivity.CancelAfter(InactivityTimeout);
                    int count = source.ReadAsync(buffer.AsMemory(), inactivity.Token).GetAwaiter().GetResult();
                    inactivity.CancelAfter(Timeout.InfiniteTimeSpan);
                    if (count == 0) break;
                    if (total.HasValue && count > total.Value - received)
                        throw new HttpRequestException("The download exceeded its declared Content-Length.");

                    operation = "check download disk space";
                    CheckSpace(total.HasValue ? total.Value - received : count);
                    operation = "write download partial";
                    fileOperation = true;
                    target.Write(buffer, 0, count);
                    received += count;
                    required = total.HasValue ? total.Value - received : null;

                    int percent = total > 0 ? (int)Math.Min(99, received * 100.0 / total.Value) : -1;
                    bool changed = total.HasValue ? percent != lastPercent : received != lastDisplayed;
                    if (lastDisplayed < 0 || (changed && progress.ElapsedMilliseconds >= 200))
                    {
                        string size = Ui.Bytes(received);
                        if (total.HasValue) size += " of " + Ui.Bytes(total.Value);
                        if (percent >= 0)
                        {
                            const int width = 24;
                            int filled = percent * width / 100;
                            Ui.Progress("Downloading  [" + new string('#', filled)
                                + new string('.', width - filled) + "] " + percent.ToString().PadLeft(3)
                                + "%   " + size);
                        }
                        else Ui.Progress("Downloading  " + size + " (total unknown)");
                        lastPercent = percent;
                        lastDisplayed = received;
                        progress.Restart();
                    }
                }

                if (total.HasValue && received != total.Value)
                    throw new HttpRequestException("The download ended before its declared Content-Length: "
                        + received + " of " + total.Value + " bytes received.");
                operation = "flush download partial";
                fileOperation = true;
                target.Flush();
            }
            catch (Exception error)
            {
                RecordFailure(error, operation, operationPath, fileOperation);
            }
            finally
            {
                DisposeResource(target, "close download partial", partial, true);
                DisposeResource(source, "close download response stream", destination, false);
                DisposeResource(response, "close download response", destination, false);
                DisposeResource(client, "close download client", destination, false);
            }

            if (failure == null)
            {
                try
                {
                    File.Move(partial!, destination, true);
                    ownsPartial = false;
                }
                catch (Exception error) { RecordFailure(error, "replace download destination", destination, true); }
            }

            if (failure != null)
            {
                DiagnosticLog.Failure(operation + "; destination: " + destination
                    + "; partial: " + partial + "; bytes received: " + received, failure);
                assessment = failure is DiskSpace.InsufficientDiskSpaceException shortage
                    ? shortage.Assessment
                    : DiskSpace.Assess(DiskSpace.Inspect(partial ?? destination, measure)
                        with { DestinationPath = destination }, required, "download failure");
                DiagnosticLog.Write("download disk space", assessment.Message);
                string? access = fileOperation && failure is IOException or UnauthorizedAccessException
                    ? FileAccessDiagnostics.Describe(operationPath, failure, operation) : null;
                if (access != null) DiagnosticLog.Write("download file access", access);

                if (ownsPartial)
                {
                    try { File.Delete(partial!); }
                    catch (Exception cleanupError)
                    {
                        DiagnosticLog.Failure("remove download partial: " + partial, cleanupError);
                        DiagnosticLog.Write("download cleanup file access",
                            FileAccessDiagnostics.Describe(partial, cleanupError, "delete download partial"));
                    }
                }

                try
                {
                    Ui.Error(DiagnosticLog.Redact("The download to '" + destination + "' failed after "
                        + received + " bytes: " + failure.Message), DiagnosticLog.Redact(assessment.Message),
                        DiagnosticLog.Redact(access ?? ""));
                }
                catch (Exception displayError) { DiagnosticLog.Failure("display download failure", displayError); }
                return false;
            }

            DiagnosticLog.Write("download complete", "Destination: " + destination + "; bytes: " + received);
            try { Ui.ProgressDone("downloaded " + Ui.Bytes(received)); }
            catch (Exception displayError) { DiagnosticLog.Failure("display download completion", displayError); }
            return true;
        }
    }
}
