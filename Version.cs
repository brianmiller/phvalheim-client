using Octokit;

namespace PhValheim.Ver
{
    public class PhValheim
    {

        public static async void VersionCheck(string phvalheimLauncherVersion)
        {

            //Get all releases from GitHub
            //Source: https://octokitnet.readthedocs.io/en/latest/getting-started/
            GitHubClient client = new GitHubClient(new ProductHeaderValue("phvalheim-client"));
            IReadOnlyList<Release> releases = await client.Repository.Release.GetAll("brianmiller", "phvalheim-client");

            //Setup the versions
            Version latestGitHubVersion = new Version(releases[0].TagName);
            Version localVersion = new Version(phvalheimLauncherVersion); //Replace this with your local version. 
                                                                          //Only tested with numeric values.

            //Compare the Versions
            int versionComparison = localVersion.CompareTo(latestGitHubVersion);
            if (versionComparison < 0)
            {
                //The version on GitHub is more up to date than this local release.
                Console.WriteLine("\n## A newer version of PhValheim Client is available. ##\n" +
                                    "## It is strongly suggested you upgrade your client version. ##\n");
            }
            else if (versionComparison > 0)
            {
                //This local version is greater than the release version on GitHub.
                Console.WriteLine("\n## You're running a newer version of PhValheim Client than what is published on GitHub. ##\n" +
                                    "## Use at your own risk! ##\n");
            }
            else
            {
                //This local Version and the Version on GitHub are equal.
                Console.WriteLine("\nPhValheim Client is up-to-date.\n");
            }


        }
    }
}


