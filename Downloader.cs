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
using System.Security.Cryptography;

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

        public static bool Check(string localFile)
        {
            //calculate md5 of a local file
            static string CalculateMD5(string filename)
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

            string localMd5 = CalculateMD5(localFile);
            //string remoteMd5 = GetRemoteMD5(worldName);
            string remoteMd5 = "abcd";

            //if local md5 matches remote md5, the file was successfully downloaded, else send false.
            if (localMd5 == remoteMd5)
            {
                return true;
            }
            else
            {
                return false;
            }
        }

    }
}