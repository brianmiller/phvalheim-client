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
                    // log the error if one occurred
                    if (e.Error != null)
                    {
                        Console.WriteLine("  ERROR: " + e.Error.Message);
                        // log inner exception if one occurred
                        if (e.Error.InnerException != null)
                        {
                            Console.WriteLine("  ERROR: " + e.Error.InnerException.Message);
                        }
                    }
                    else
                    {
                        Console.WriteLine("  Download complete.");
                    }
                    completedSignal.Set();
                };

                client.DownloadProgressChanged += (s, e) => Console.Write($"\r  Downloading world files for '" + worldName + "': " + e.ProgressPercentage + "%" );
                Console.WriteLine("\n");
                Console.WriteLine("  Downloading world files for '" + worldName + "'... to "+ localFile + " from " + remoteFile);
                client.DownloadFileAsync(remoteFile, localFile);

                completedSignal.WaitOne();
            }
            Console.WriteLine("\n");
        }
    }
}