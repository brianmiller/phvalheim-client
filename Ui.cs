using System.Text;

namespace PhValheim
{
    /// <summary>
    /// Everything this client prints goes through here.
    ///
    /// WHY A LAYER AT ALL. The output had grown into 131 unrelated Console.WriteLine calls with
    /// four different indents, two spellings of "Press the Enter key", ERROR with and without a
    /// leading indent, and raw MD5 hashes presented to players as if they were actionable. The
    /// shape of a line was decided wherever it happened to be written, so it could not be
    /// consistent -- and `Console.WriteLine("\n")` (which emits TWO line breaks, not one) was
    /// scattered through every exit path, which is where most of the ragged vertical space came
    /// from. Centralising it is what makes the format a property of the program rather than of
    /// each call site.
    ///
    /// ASCII ONLY, deliberately. This runs in cmd.exe and PowerShell on most players' machines,
    /// where the default code page is not UTF-8; box-drawing characters and check marks arrive
    /// as mojibake there. Nothing here needs them, and a tidy window that renders everywhere
    /// beats a prettier one that breaks on the commonest platform. Same reason there is no
    /// colour: Console.ForegroundColor on a legacy console leaves the colour set if the process
    /// exits mid-line, which would stain the player's prompt.
    /// </summary>
    public static class Ui
    {
        // Where a status lands on a dotted line. Chosen so the longest label plus the longest
        // status still fits inside 80 columns, which is cmd.exe's default width.
        private const int StatusColumn = 48;
        private const int Width = 76;
        private const string Indent = "  ";

        private static bool lastWasBlank = true;   // true, so a leading Blank() prints nothing
        private static bool stepOpen = false;

        /// <summary>
        /// Developer detail: absolute paths, MD5 hashes, the resolved launch payload.
        ///
        /// An ENVIRONMENT VARIABLE and not a command-line flag, which matters. The launch
        /// payload this client is handed is '?'-delimited and POSITIONAL, with the password at
        /// field 2; an extra argv entry would shift every field after it. A flag here would be
        /// a foot-gun aimed at the one piece of parsing that cannot tolerate it.
        /// </summary>
        public static bool Verbose { get; } =
            !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("PHVALHEIM_VERBOSE"));

        /// <summary>Exactly one blank line, however many times it is called in a row.</summary>
        public static void Blank()
        {
            CloseStep();
            if (lastWasBlank) { return; }
            Console.WriteLine();
            lastWasBlank = true;
        }

        private static void Emit(string line)
        {
            CloseStep();
            Console.WriteLine(line);
            lastWasBlank = false;
        }

        // A step that was opened and never completed would otherwise swallow the next line onto
        // its dotted tail. Rather than trust every path to finish what it started, any other
        // output closes it -- an unfinished step prints as an honest blank status.
        private static void CloseStep()
        {
            if (!stepOpen) { return; }
            stepOpen = false;
            Console.WriteLine();
            lastWasBlank = false;
        }

        public static void Banner(string version)
        {
            Blank();
            Emit(Indent + "PhValheim Client " + version);
            Emit(Indent + new string('-', Width - Indent.Length));
            Blank();
        }

        /// <summary>A label/value pair in the header block: "  Server    value".</summary>
        public static void Field(string label, string value)
        {
            Emit(Indent + label.PadRight(11) + value);
        }

        /// <summary>A section heading, for a phase with several lines of its own.</summary>
        public static void Section(string title)
        {
            Blank();
            Emit(Indent + title);
        }

        /// <summary>An ordinary line of prose, wrapped to the window.</summary>
        public static void Line(string message)
        {
            foreach (string l in WrapLines(message, Indent)) { Emit(l); }
        }

        /// <summary>Secondary detail, indented under whatever it belongs to.</summary>
        public static void Note(string message)
        {
            foreach (string l in WrapLines(message, Indent + "    ")) { Emit(l); }
        }

        /// <summary>
        /// Open a dotted line and leave the cursor on it: "  Checking for updates ....... ".
        /// Finish it with Done/Warn/Fail, or print anything else and it closes itself.
        /// </summary>
        public static void Step(string label)
        {
            CloseStep();
            string head = Indent + label + " ";
            if (head.Length < StatusColumn) { head += new string('.', StatusColumn - head.Length); }
            Console.Write(head + " ");
            stepOpen = true;
            lastWasBlank = false;
        }

        public static void Done(string status)  { EndStep(status); }
        public static void Fail(string status)  { EndStep(status); }

        private static void EndStep(string status)
        {
            if (!stepOpen) { Emit(Indent + status); return; }
            stepOpen = false;
            Console.WriteLine(status);
            lastWasBlank = false;
        }

        /// <summary>
        /// A problem the player may be able to do something about. `hints` are printed under it,
        /// indented, so a remedy is attached to the thing it remedies rather than floating as
        /// another top-level line.
        /// </summary>
        public static void Warning(string message, params string[] hints)
        {
            Blank();
            foreach (string l in WrapLines("WARNING: " + message, Indent)) { Emit(l); }
            foreach (string hint in hints)
            {
                foreach (string l in WrapLines(hint, Indent + "         ")) { Emit(l); }
            }
            Blank();
        }

        /// <summary>A problem that stops what we were doing.</summary>
        public static void Error(string message, params string[] hints)
        {
            Blank();
            foreach (string l in WrapLines("ERROR: " + message, Indent)) { Emit(l); }
            foreach (string hint in hints)
            {
                foreach (string l in WrapLines(hint, Indent + "       ")) { Emit(l); }
            }
            Blank();
        }

        /// <summary>
        /// A command the player is meant to copy and run. NEVER wrapped.
        ///
        /// This is the one thing in here that must not be reflowed: the Flatpak remedy is a
        /// 95-character `flatpak override` line, and wrapping it to the window broke it into
        /// three pieces that cannot be copied as one command. A line that runs off the edge of
        /// a narrow terminal is a minor annoyance; a remedy that silently does not work when
        /// followed is the whole value of printing it gone.
        /// </summary>
        public static void Command(string command)
        {
            Emit(Indent + "    " + command);
        }

        /// <summary>
        /// Something only a developer wants: a path, a hash, a payload. Printed only under
        /// PHVALHEIM_VERBOSE.
        ///
        /// This exists so the cleanup DELETED NOTHING. Every hash and absolute path the old
        /// output showed every player is still one environment variable away, which is the
        /// difference between tidying the window and losing the ability to debug a report.
        /// </summary>
        public static void Detail(string label, string value)
        {
            if (!Verbose) { return; }
            Emit(Indent + "  [" + label + "] " + value);
        }

        public static void Detail(string message)
        {
            if (!Verbose) { return; }
            Emit(Indent + "  [debug] " + message);
        }

        /// <summary>
        /// A line that is rewritten in place, for progress. Keeps its own CR handling out of
        /// the call sites, and records that the line needs terminating.
        /// </summary>
        public static void Progress(string message)
        {
            CloseStep();
            Console.Write("\r" + Indent + "    " + message);
            lastWasBlank = false;
            stepOpen = true;   // so the next ordinary line does not land on this one
        }

        /// <summary>
        /// Replace the in-place progress line with a final one and terminate it. Padded, so a
        /// shorter closing message cannot leave the tail of the longer progress line behind it
        /// -- which is what a bare "\r" write does, and it looks like corruption.
        /// </summary>
        public static void ProgressDone(string message)
        {
            string line = Indent + "    " + message;
            Console.Write("\r" + line.PadRight(Width + 4));
            Console.WriteLine();
            stepOpen = false;
            lastWasBlank = false;
        }

        public static void PressEnterToExit()
        {
            Blank();
            Emit(Indent + "Press Enter to exit.");
            Console.ReadLine();
        }

        /// <summary>Human-readable bytes, so a payload size is a size and not a digit count.</summary>
        public static string Bytes(long bytes)
        {
            if (bytes <= 0) { return "0 B"; }
            string[] units = { "B", "KB", "MB", "GB" };
            double v = bytes;
            int u = 0;
            while (v >= 1024 && u < units.Length - 1) { v /= 1024; u++; }
            return (u == 0 ? v.ToString("0") : v.ToString(v < 10 ? "0.0" : "0")) + " " + units[u];
        }

        /// <summary>
        /// A password is shown ONLY where the player has to type it themselves. Everywhere else
        /// it is masked.
        ///
        /// The old output printed it in full on every launch -- and twice on a vanilla one --
        /// including modded worlds, where the Companion mod fills the prompt in and the player
        /// never sees or needs it. A terminal window gets screenshotted into Discord when
        /// somebody asks for help, so printing a credential that nobody is going to read is a
        /// disclosure with no upside.
        /// </summary>
        public static string Mask(string secret)
        {
            if (string.IsNullOrEmpty(secret)) { return "(none)"; }
            return new string('*', Math.Min(secret.Length, 16));
        }

        // Wrap on spaces at the window width. A long sentence used to run off the side of a
        // narrow terminal and be re-broken by the console at an arbitrary column, mid-word.
        private static List<string> WrapLines(string message, string indent)
        {
            var outLines = new List<string>();
            foreach (string paragraph in (message ?? "").Replace("\r", "").Split('\n'))
            {
                string[] words = paragraph.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                if (words.Length == 0) { outLines.Add(indent.TrimEnd()); continue; }

                var sb = new StringBuilder(indent);
                bool empty = true;
                foreach (string word in words)
                {
                    if (!empty && sb.Length + 1 + word.Length > Width)
                    {
                        outLines.Add(sb.ToString());
                        sb = new StringBuilder(indent);
                        empty = true;
                    }
                    if (!empty) { sb.Append(' '); }
                    sb.Append(word);
                    empty = false;
                }
                outLines.Add(sb.ToString());
            }
            return outLines;
        }
    }
}
