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
    /// ASCII ONLY for the GLYPHS, deliberately. This runs in cmd.exe and PowerShell on most
    /// players' machines, where the default code page is not UTF-8; box-drawing characters and
    /// check marks arrive as mojibake there. Nothing here needs them, and a tidy window that
    /// renders everywhere beats a prettier one that breaks on the commonest platform.
    ///
    /// Colour IS used, via Console.ForegroundColor -- see the colour section below for why that
    /// and not ANSI, and for how the "exits mid-line and stains the player's prompt" hazard is
    /// handled (a finally on every write, plus ProcessExit and Ctrl-C hooks).
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

        // An in-place progress line, tracked SEPARATELY from stepOpen.
        //
        // It used to reuse stepOpen, and that is what stopped the download bar staying on one
        // line: Progress() opens with CloseStep() and closed by setting stepOpen = true, so the
        // SECOND update found a step open, wrote a newline, and the "\r" returned to the start
        // of a fresh line. One line per percent for the whole download. The flag meant to stop
        // ordinary output landing on the progress line was defeating the rewrite itself.
        //
        // progressLen is how much to erase: an update shorter than the one it replaces must
        // blank the remainder, or "5%   29 MB" over "100%   573 MB of 573 MB" reads as
        // "5%   29 MBof 573 MB". Erasing by the tracked length rather than padding to Width
        // matters on a narrow window -- a pad that wraps puts the cursor on the next row, and
        // then "\r" returns to the start of the WRAPPED fragment, which scrolls all over again.
        private static bool progressOpen = false;
        private static int progressLen = 0;

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

        // ---- colour -----------------------------------------------------------------------
        //
        // Console.ForegroundColor, NOT ANSI escape codes. That is the whole cross-platform
        // decision: .NET maps this to Win32 console attributes on Windows and to ANSI on Unix,
        // so it works in cmd.exe, PowerShell, Windows Terminal, macOS Terminal, and every Linux
        // terminal. Writing ANSI ourselves would need ENABLE_VIRTUAL_TERMINAL_PROCESSING turned
        // on via P/Invoke, and on a legacy conhost without it the player would read raw
        // "<ESC>[32m" litter instead of a status. Same reason there is no 256-colour or RGB
        // here: the sixteen ConsoleColors are the set every platform actually has.
        //
        // COLOUR IS NEVER THE ONLY SIGNAL. Every status still reads in words -- "ready",
        // "found", "up to date" -- and warnings and errors still carry the literal WARNING and
        // ERROR prefixes. Colour-blind players, redirected output and a `| tee` into a bug
        // report all lose nothing but decoration.
        private static readonly bool Colour = DetectColour();

        private static bool DetectColour()
        {
            // NO_COLOR is the de-facto standard: set to anything, and well-behaved tools stop
            // colouring.
            //
            // CLICOLOR_FORCE / PHVALHEIM_FORCE_COLOR only lift OUR gate, and cannot force
            // colour through a pipe: .NET's own Unix implementation of Console.ForegroundColor
            // emits nothing when stdout is redirected, and nothing when TERM is unset or
            // unknown, because it resolves the sequence from terminfo. Measured, not assumed --
            // forcing it through a pipe produced zero escape sequences, and the same preview in
            // a pty with TERM set produced 163. So these two are for a pty where our own gate
            // would otherwise have said no; reviewing the output needs a real terminal either
            // way. Both behaviours are the safe direction: a redirected log never gets litter.
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("NO_COLOR"))) { return false; }
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("PHVALHEIM_FORCE_COLOR"))
                || !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("CLICOLOR_FORCE")))
            {
                return true;
            }

            // Redirected output is a file or a pipe, not a terminal. On Unix .NET will happily
            // write escape sequences into it, which turns a pasted log into noise.
            try
            {
                if (Console.IsOutputRedirected) { return false; }
            }
            catch { return false; }

            // TERM=dumb is a terminal telling us it cannot do this.
            string term = Environment.GetEnvironmentVariable("TERM") ?? "";
            if (term == "dumb") { return false; }

            return true;
        }

        // The colour must not outlive the process. If this exits mid-line -- an unhandled
        // exception, a Ctrl-C, a killed terminal -- an unreset attribute stains the player's
        // shell prompt until they type `reset`. Every write resets in a finally, and these two
        // hooks cover the paths that never reach one.
        static Ui()
        {
            if (!Colour) { return; }
            AppDomain.CurrentDomain.ProcessExit += (s, e) => SafeReset();
            Console.CancelKeyPress += (s, e) => SafeReset();
        }

        private static void SafeReset()
        {
            try { Console.ResetColor(); } catch { /* a closed handle is not worth crashing for */ }
        }

        /// <summary>Write one coloured fragment, with no newline, always resetting after.</summary>
        private static void Paint(string text, ConsoleColor? colour)
        {
            if (!Colour || colour == null)
            {
                Console.Write(text);
                return;
            }
            try
            {
                Console.ForegroundColor = colour.Value;
                Console.Write(text);
            }
            finally
            {
                SafeReset();
            }
        }

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
            Emit(line, null);
        }

        private static void Emit(string line, ConsoleColor? colour)
        {
            CloseStep();
            Paint(line, colour);
            Console.WriteLine();
            lastWasBlank = false;
        }

        // A step that was opened and never completed would otherwise swallow the next line onto
        // its dotted tail. Rather than trust every path to finish what it started, any other
        // output closes it -- an unfinished step prints as an honest blank status.
        private static void CloseStep()
        {
            // A progress line is unterminated too, and for the same reason: anything else that
            // prints has to get off it first, or it overwrites the figure the player is reading.
            if (progressOpen)
            {
                progressOpen = false;
                progressLen = 0;
                Console.WriteLine();
                lastWasBlank = false;
            }
            if (!stepOpen) { return; }
            stepOpen = false;
            Console.WriteLine();
            lastWasBlank = false;
        }

        public static void Banner(string version)
        {
            Blank();
            Emit(Indent + "PhValheim Client " + version, ConsoleColor.Cyan);
            Emit(Indent + new string('-', Width - Indent.Length), ConsoleColor.DarkGray);
            Blank();
        }

        /// <summary>A label/value pair in the header block: "  Server    value".</summary>
        public static void Field(string label, string value)
        {
            // Label dim, value normal: the eye should land on the value, which is the part
            // that differs between runs.
            CloseStep();
            Paint(Indent + label.PadRight(11), ConsoleColor.DarkGray);
            Console.WriteLine(value);
            lastWasBlank = false;
        }

        /// <summary>A section heading, for a phase with several lines of its own.</summary>
        public static void Section(string title)
        {
            Blank();
            Emit(Indent + title, ConsoleColor.Cyan);
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
            string dots = "";
            if (head.Length < StatusColumn) { dots = new string('.', StatusColumn - head.Length); }
            Console.Write(head);
            // The leader dots are scaffolding, not information -- dimming them is most of what
            // makes a column of these readable at a glance.
            Paint(dots + " ", ConsoleColor.DarkGray);
            stepOpen = true;
            lastWasBlank = false;
        }

        /// <summary>A step that succeeded.</summary>
        public static void Done(string status) { EndStep(status, ConsoleColor.Green); }

        /// <summary>
        /// A step that did not do what was asked but is not fatal -- "kept yours" when an
        /// updated config could not be fetched. Amber, because red would say the launch is
        /// over and it is not.
        /// </summary>
        public static void Warn(string status) { EndStep(status, ConsoleColor.Yellow); }

        /// <summary>A step that failed. The launch usually stops after one of these.</summary>
        public static void Fail(string status) { EndStep(status, ConsoleColor.Red); }

        private static void EndStep(string status, ConsoleColor colour)
        {
            if (!stepOpen) { Emit(Indent + status, colour); return; }
            stepOpen = false;
            Paint(status, colour);
            Console.WriteLine();
            lastWasBlank = false;
        }

        /// <summary>
        /// A verbose checksum comparison that states its own verdict.
        ///
        /// Two checksums printed side by side is an invitation to eyeball them, so the display
        /// has to draw the same conclusion the code does. It did not: "local payload" and
        /// "server payload" were shown as a pair, nothing compares them, and once a repackage
        /// has happened they never match again -- so a correct, fully synced install read as
        /// permanently out of sync. Anything shown as a pair now says SAME or DIFFER itself,
        /// and names the decision it drives, so the reader never has to guess which pair is
        /// load-bearing.
        /// </summary>
        public static void Compare(string what, string decides, string local, string server)
        {
            if (!Verbose) { return; }

            bool same = (local == server);
            string head = Indent + "  [compare] " + what + " ";
            string dots = "";
            if (head.Length < StatusColumn) { dots = new string('.', StatusColumn - head.Length); }

            CloseStep();
            Paint(head, ConsoleColor.DarkGray);
            Paint(dots + " ", ConsoleColor.DarkGray);
            Paint(same ? "SAME" : "DIFFER", same ? ConsoleColor.Green : ConsoleColor.Yellow);
            Console.WriteLine();
            lastWasBlank = false;

            Emit(Indent + "            decides  " + decides, ConsoleColor.DarkGray);
            Emit(Indent + "            yours    " + Shown(local), ConsoleColor.DarkGray);
            Emit(Indent + "            server   " + Shown(server), ConsoleColor.DarkGray);
        }

        /// <summary>
        /// A verbose checksum that is NOT part of any comparison, labelled as such.
        ///
        /// Exists so a value can be reported without implying a verdict. An unexplained
        /// checksum next to a compared one gets read as another comparison.
        /// </summary>
        public static void Reference(string what, string value, string why)
        {
            if (!Verbose) { return; }
            Emit(Indent + "  [value]   " + what + " " + Shown(value), ConsoleColor.DarkGray);
            foreach (string l in WrapLines("not compared -- " + why, Indent + "            "))
            {
                Emit(l, ConsoleColor.DarkGray);
            }
        }

        /// <summary>An empty checksum is a real state ("I have no record"), not a blank line.</summary>
        private static string Shown(string value)
        {
            return (value == null || value.Length == 0) ? "(none recorded)" : value;
        }

        /// <summary>
        /// A problem the player may be able to do something about. `hints` are printed under it,
        /// indented, so a remedy is attached to the thing it remedies rather than floating as
        /// another top-level line.
        /// </summary>
        public static void Warning(string message, params string[] hints)
        {
            Blank();
            foreach (string l in WrapLines("WARNING: " + message, Indent))
            {
                Emit(l, ConsoleColor.Yellow);
            }
            // Hints in the default colour, not amber. They are instructions, and a wall of one
            // colour hides which line is the problem and which is the remedy.
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
            foreach (string l in WrapLines("ERROR: " + message, Indent))
            {
                Emit(l, ConsoleColor.Red);
            }
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
            Emit(Indent + "    " + command, ConsoleColor.Cyan);
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
            Emit(Indent + "  [" + label + "] " + value, ConsoleColor.DarkGray);
        }

        public static void Detail(string message)
        {
            if (!Verbose) { return; }
            Emit(Indent + "  [debug] " + message, ConsoleColor.DarkGray);
        }

        /// <summary>
        /// A line that is rewritten in place, for progress. Keeps its own CR handling out of
        /// the call sites, and records that the line needs terminating.
        /// </summary>
        public static void Progress(string message)
        {
            // Close a STEP, but never the progress line itself -- it is the thing being
            // rewritten. CloseStep() handles only an open step here because the progress flag
            // is cleared first; calling it unguarded would newline every update, which is the
            // bug this replaced.
            if (stepOpen) { CloseStep(); }

            string line = Indent + "    " + message;
            int erase = progressLen - line.Length;
            Console.Write("\r" + line + (erase > 0 ? new string(' ', erase) : string.Empty));
            progressLen = line.Length;
            progressOpen = true;
            lastWasBlank = false;
        }

        /// <summary>
        /// Replace the in-place progress line with a final one and terminate it. Padded, so a
        /// shorter closing message cannot leave the tail of the longer progress line behind it
        /// -- which is what a bare "\r" write does, and it looks like corruption.
        /// </summary>
        public static void ProgressDone(string message)
        {
            string line = Indent + "    " + message;
            // Erase by the tracked length, not PadRight(Width + 4). That constant is 80 -- the
            // full width of cmd.exe's default window -- so on an 80-column terminal the pad
            // filled the row exactly and the console wrapped, leaving a stray blank line under
            // every finished download.
            int erase = progressLen - line.Length;
            Console.Write("\r" + line + (erase > 0 ? new string(' ', erase) : string.Empty));
            Console.WriteLine();
            progressOpen = false;
            progressLen = 0;
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
