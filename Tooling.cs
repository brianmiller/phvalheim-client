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







    }
}