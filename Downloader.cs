using System.Net;

namespace PhValheim.Downloader
{
    class PhValheim
    {
        public static async void Go(Uri remoteFile,string localFile, string worldName)
        {
            // Carried out of the progress handler so the completion handler can report the real
            // size. e.TotalBytesToReceive is not available on DownloadFileCompleted.
            int lastPercent = -1;
            long lastReceived = 0;
            long lastTotal = 0;

            using (var client = new WebClient())
            using (var completedSignal = new AutoResetEvent(false))
            {
                client.DownloadFileCompleted += (s, e) =>
                {;
                    // log the error if one occurred
                    if (e.Error != null)
                    {
                        Ui.Error("The download stopped: " + e.Error.Message);
                        // log inner exception if one occurred
                        if (e.Error.InnerException != null)
                        {
                            Ui.Detail("inner exception", e.Error.InnerException.Message);
                        }
                    }
                    else
                    {
                        // Finish the progress line with the total actually transferred, so the
                        // last thing on screen is the outcome rather than "100%".
                        Ui.ProgressDone("downloaded " + Ui.Bytes(lastTotal > 0 ? lastTotal : lastReceived));
                    }
                    completedSignal.Set();
                };

                // A bar, a percentage and the real sizes. The old line was a bare percentage,
                // which on a 573 MB payload over a slow link gives no sense of whether it is
                // worth waiting for -- and no way to tell a stalled transfer from a slow one.
                //
                // Throttled to whole percent changes. DownloadProgressChanged fires per packet,
                // and redrawing the line thousands of times per second is visible as flicker
                // and costs real time on a Windows console.
                client.DownloadProgressChanged += (s, e) =>
                {
                    lastReceived = e.BytesReceived;
                    lastTotal = e.TotalBytesToReceive;
                    if (e.ProgressPercentage == lastPercent) { return; }
                    lastPercent = e.ProgressPercentage;

                    const int barWidth = 24;
                    int filled = Math.Clamp(e.ProgressPercentage * barWidth / 100, 0, barWidth);
                    string bar = new string('#', filled) + new string('.', barWidth - filled);

                    string size = e.TotalBytesToReceive > 0
                        ? Ui.Bytes(e.BytesReceived) + " of " + Ui.Bytes(e.TotalBytesToReceive)
                        : Ui.Bytes(e.BytesReceived);

                    Ui.Progress("Downloading  [" + bar + "] "
                                + e.ProgressPercentage.ToString().PadLeft(3) + "%   " + size);
                };
                Ui.Detail("payload url", remoteFile.ToString());
                Ui.Detail("saving to", localFile);
                client.DownloadFileAsync(remoteFile, localFile);

                completedSignal.WaitOne();
            }
        }
    }
}