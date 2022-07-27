using System;
using System.Runtime.ExceptionServices;
using System.IO;
using System.Net.Http;
using System.ComponentModel;

using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using UpdateHOB;
using System.Reflection.Metadata.Ecma335;
using System.Threading.Channels;
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
        }

    }
}