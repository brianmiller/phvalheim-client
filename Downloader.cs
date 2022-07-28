using System.Net;

namespace PhValheim.Downloader
{
    class PhValheim
    {
        public static async void Go(Uri remoteFile,string localFile, string worldName)
        {
            using (var client = new WebClient())
            using (var completedSignal = new AutoResetEvent(false))
            {
                client.DownloadFileCompleted += (s, e) =>
                {;
                    completedSignal.Set();
                };

                client.DownloadProgressChanged += (s, e) => Console.Write($"\r  Downloading world files for '" + worldName + "': " + e.ProgressPercentage + "%" );
                client.DownloadFileAsync(remoteFile, localFile);

                completedSignal.WaitOne();
            }
            Console.WriteLine("\n");
        }
    }
}