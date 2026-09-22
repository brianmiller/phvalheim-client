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

            // This used to be releases[0], which was wrong twice over.
            //
            // GetAll() returns EVERY release, pre-releases and drafts included,
            // ordered by creation date rather than by version. So publishing a
            // pre-release told every stable user to upgrade to a build that was
            // explicitly not ready for them (phvalheim-client#14), and a patch
            // cut against an older branch could out-rank a newer one purely by
            // being published later.
            //
            // Take the highest STABLE version instead. Note that the
            // /releases/latest endpoint would also skip pre-releases, but it
            // returns the most RECENT stable rather than the highest, so it
            // only fixes half of this.
            Version? latestGitHubVersion = releases
                .Where(r => !r.Prerelease && !r.Draft)
                .Select(r => Version.TryParse(r.TagName, out Version? v) ? v : null)
                .Where(v => v != null)
                .Max();

            // No parseable stable release means we have nothing to compare
            // against. Saying nothing is correct; guessing is not.
            if (latestGitHubVersion == null)
            {
                return;
            }

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
                // Ahead of the newest stable. Normally that means a pre-release,
                // which is a deliberate choice rather than a mistake -- now that
                // we compare against stables only, this branch is what every
                // pre-release tester sees on every launch, so it should not read
                // like a warning.
                Console.WriteLine("\nPhValheim Client " + phvalheimLauncherVersion +
                                    " is ahead of the latest stable release (" + latestGitHubVersion + ").\n");
            }
            else
            {
                //This local Version and the Version on GitHub are equal.
                Console.WriteLine("\nPhValheim Client is up-to-date.\n");
            }


        }
    }
}


