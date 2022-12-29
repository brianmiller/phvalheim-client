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
        public static void CloneDirectory(string root, string dest)
        {

            if (!Directory.Exists(dest))
            {
                Directory.CreateDirectory(dest);
            }

            foreach (var directory in Directory.GetDirectories(root))
            {
                string dirName = Path.GetFileName(directory);
                if (!Directory.Exists(Path.Combine(dest, dirName)))
                {
                    Directory.CreateDirectory(Path.Combine(dest, dirName));
                }
                CloneDirectory(directory, Path.Combine(dest, dirName));
            }

            foreach (var file in Directory.GetFiles(root))
            {
                File.Copy(file, Path.Combine(dest, Path.GetFileName(file)), true);
            }
        }










    }
}