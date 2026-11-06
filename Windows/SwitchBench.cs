using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        var smoke = args.SequenceEqual(new[] { "--smoke-test" });
        using (var window = new BenchWindow(smoke))
        {
            if (smoke)
            {
                // Create the real controls and exercise navigation without blocking CI.
                try { var handle = window.Handle; window.CheckNavigation(); }
                catch (Exception) { Environment.ExitCode = 1; }
                return;
            }
            Application.Run(window);
        }
    }
}

internal sealed class BenchWindow : Form
{
    private sealed class Tool
    {
        public readonly string Id, Name, Guidance, Action;
        public readonly bool NeedsKeys;
        public Tool(string id, string name, string guidance, string action, bool needsKeys = false)
        {
            Id = id; Name = name; Guidance = guidance; Action = action; NeedsKeys = needsKeys;
        }
        public override string ToString() { return Name; }
    }

    private static readonly Tool[] Tools = {
        new Tool("update", "Update Games", "Add your original games and their updates. SwitchBench pairs them and creates updated copies.", "Create Updated Copies", true),
        new Tool("inspect", "Check Files", "Read game names and versions, then check stored game data for missing or changed content.", "Check Contents", true),
        new Tool("combine", "Combine Files", "Keep one game, its update and add-ons in a single NSP. The update stays separate inside the file.", "Create Combined File", true),
        new Tool("convert", "Convert to NSP", "Create NSP copies from cartridge or compressed game files. Compressed files are expanded.", "Convert to NSP"),
        new Tool("split", "Split Large Files", "Make parts that fit on drives with a 4 GB file limit. Keep the parts list with the files.", "Split Files"),
        new Tool("join", "Join Split Files", "Choose any one part or its folder to restore the complete file.", "Join Parts"),
        new Tool("trim", "Shrink XCI Files", "Remove unused space at the end of uncompressed XCI files.", "Shrink XCI Files")
    };

    private readonly ListBox navigation = new ListBox();
    private readonly ListBox inputs = new ListBox();
    private readonly ListView results = new ListView();
    private readonly Label heading = new Label();
    private readonly Label guidance = new Label();
    private readonly Label saveLabel = new Label();
    private readonly Label keysLabel = new Label();
    private readonly Label status = new Label();
    private readonly Button addFiles = ButtonWith("Add Files…");
    private readonly Button addFolder = ButtonWith("Add Folder…");
    private readonly Button remove = ButtonWith("Remove Selected");
    private readonly Button chooseKeys = ButtonWith("Choose Key File…");
    private readonly Button extraKeys = ButtonWith("Choose Additional Keys…");
    private readonly Button destination = ButtonWith("Choose Save Folder…");
    private readonly Button preview = ButtonWith("Preview");
    private readonly Button start = ButtonWith("Start");
    private readonly Button stop = ButtonWith("Stop");
    private readonly Button reveal = ButtonWith("Open Saved Location");
    private readonly TextBox details = new TextBox();
    private readonly ProgressBar progress = new ProgressBar();
    private readonly FlowLayoutPanel keysPane;
    private readonly FlowLayoutPanel savePane;
    private readonly Dictionary<string, List<string>> files = new Dictionary<string, List<string>>();
    private readonly Dictionary<string, ListViewItem> rows = new Dictionary<string, ListViewItem>();
    private readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 4000000 };
    private readonly string settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SwitchBench", "settings.json");
    private Preferences preferences = new Preferences();
    private string sessionTitleKeys;
    private bool needsExtraKeys;
    private Process worker;
    private bool closing;

    public sealed class Preferences
    {
        public string Keys { get; set; }
        public string Tool { get; set; }
        public Dictionary<string, string> Folders { get; set; }
        public Preferences() { Folders = new Dictionary<string, string>(); }
    }

    public sealed class WorkerEvent
    {
        public string kind { get; set; }
        public string id { get; set; }
        public string title { get; set; }
        public string status { get; set; }
        public string message { get; set; }
        public string detail { get; set; }
        public string output { get; set; }
        public string issue { get; set; }
        public double? progress { get; set; }
    }

    private Tool Active { get { return (Tool)navigation.SelectedItem; } }
    private string SaveFolder
    {
        get
        {
            string folder;
            return preferences.Folders.TryGetValue(Active.Id, out folder) ? folder :
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        }
    }

    private readonly bool smoke;

    public BenchWindow(bool smoke)
    {
        this.smoke = smoke;
        Text = "SwitchBench";
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = SystemFonts.MessageBoxFont;
        MinimumSize = new Size(850, 650);
        Size = new Size(1040, 780);
        StartPosition = FormStartPosition.CenterScreen;
        try
        {
            if (!smoke && File.Exists(settings)) preferences = json.Deserialize<Preferences>(File.ReadAllText(settings)) ?? new Preferences();
            if (preferences.Folders == null) preferences.Folders = new Dictionary<string, string>();
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        catch (ArgumentException) { }
        catch (InvalidOperationException) { }

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(14) };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 178));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(layout);
        navigation.Dock = DockStyle.Fill;
        navigation.AccessibleName = "SwitchBench tools";
        navigation.IntegralHeight = false;
        foreach (var tool in Tools) { navigation.Items.Add(tool); files.Add(tool.Id, new List<string>()); }
        layout.Controls.Add(navigation, 0, 0);

        var task = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, Padding = new Padding(12, 0, 0, 0) };
        task.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.Controls.Add(task, 1, 0);
        heading.Font = new Font(Font.FontFamily, 19, FontStyle.Bold);
        AddRow(task, heading);
        AddRow(task, guidance);
        keysPane = Line(chooseKeys, keysLabel, extraKeys);
        AddRow(task, keysPane);
        AddRow(task, Line(addFiles, addFolder, remove));
        inputs.AccessibleName = "Selected game files";
        inputs.SelectionMode = SelectionMode.MultiExtended;
        inputs.IntegralHeight = false;
        inputs.HorizontalScrollbar = true;
        AddRow(task, inputs, SizeType.Percent, 31);
        savePane = Line(destination, saveLabel);
        AddRow(task, savePane);

        results.AccessibleName = "Preview and results";
        results.View = View.Details;
        results.FullRowSelect = true;
        results.MultiSelect = false;
        results.HideSelection = false;
        results.Columns.Add("File or game", 265);
        results.Columns.Add("Status", 130);
        results.Columns.Add("Result", 500);
        AddRow(task, results, SizeType.Percent, 47);
        details.Multiline = true;
        details.ReadOnly = true;
        details.ScrollBars = ScrollBars.Vertical;
        details.AccessibleName = "Selected result details";
        AddRow(task, details, SizeType.Percent, 22);
        AddRow(task, status);
        progress.Height = 10;
        AddRow(task, progress, SizeType.Absolute, 15);
        AddRow(task, Line(preview, start, stop, reveal));
        AddRow(task, new Label { Text = "Your original files stay unchanged.", AutoSize = true });

        navigation.SelectedIndexChanged += delegate { ChangeTool(); };
        inputs.SelectedIndexChanged += delegate { RefreshButtons(); };
        results.SelectedIndexChanged += delegate { ShowDetails(); };
        addFiles.Click += delegate { PickFiles(); };
        addFolder.Click += delegate { PickFolder(false); };
        destination.Click += delegate { PickFolder(true); };
        chooseKeys.Click += delegate { PickKeys(false); };
        extraKeys.Click += delegate { PickKeys(true); };
        remove.Click += delegate
        {
            foreach (string path in inputs.SelectedItems.Cast<string>().ToArray()) files[Active.Id].Remove(path);
            LoadInputs();
        };
        preview.Click += async delegate { await Run(true); };
        start.Click += async delegate { await Run(false); };
        stop.Click += delegate { Stop(); };
        reveal.Click += delegate { Reveal(); };
        FormClosing += delegate(object sender, FormClosingEventArgs e)
        {
            if (worker == null) return;
            e.Cancel = true;
            closing = true;
            Stop();
        };
        foreach (Control target in new Control[] { this, inputs })
        {
            target.AllowDrop = true;
            target.DragEnter += delegate(object sender, DragEventArgs e)
            {
                if (worker == null && e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect = DragDropEffects.Copy;
            };
            target.DragDrop += delegate(object sender, DragEventArgs e)
            {
                if (worker == null) AddPaths((string[])e.Data.GetData(DataFormats.FileDrop));
            };
        }

        var selected = Array.FindIndex(Tools, tool => tool.Id == preferences.Tool);
        navigation.SelectedIndex = selected < 0 ? 1 : selected;
        AcceptButton = start;
        CancelButton = stop;
    }

    private static Button ButtonWith(string text) { return new Button { Text = text, AutoSize = true }; }
    private static FlowLayoutPanel Line(params Control[] controls)
    {
        var panel = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Dock = DockStyle.Fill };
        foreach (var control in controls)
        {
            var label = control as Label;
            if (label != null)
            {
                label.AutoSize = true;
                label.MaximumSize = new Size(440, 0);
                label.Margin = new Padding(6, 9, 6, 3);
            }
            panel.Controls.Add(control);
        }
        return panel;
    }

    private static void AddRow(TableLayoutPanel panel, Control control, SizeType type = SizeType.AutoSize, float size = 0)
    {
        var row = panel.RowCount++;
        panel.RowStyles.Add(new RowStyle(type, size));
        control.Dock = DockStyle.Fill;
        var label = control as Label;
        if (label != null) label.AutoSize = true;
        panel.Controls.Add(control, 0, row);
    }

    private void ChangeTool()
    {
        heading.Text = Active.Name;
        guidance.Text = Active.Guidance;
        start.Text = Active.Action;
        preferences.Tool = Active.Id;
        needsExtraKeys = false;
        LoadInputs();
        SavePreferences();
    }

    private void LoadInputs()
    {
        inputs.Items.Clear();
        foreach (var file in files[Active.Id]) inputs.Items.Add(file);
        ResetResults();
        RefreshButtons();
    }

    private void ResetResults()
    {
        rows.Clear();
        results.Items.Clear();
        details.Clear();
        progress.Value = 0;
        status.Text = "Add files, then preview or start.";
    }

    private void RefreshButtons()
    {
        if (Active == null) return;
        var idle = worker == null;
        navigation.Enabled = addFiles.Enabled = addFolder.Enabled = chooseKeys.Enabled = destination.Enabled = idle;
        remove.Enabled = idle && inputs.SelectedItems.Count > 0;
        keysPane.Visible = Active.NeedsKeys;
        extraKeys.Visible = Active.NeedsKeys && needsExtraKeys;
        extraKeys.Enabled = idle;
        keysLabel.Text = File.Exists(preferences.Keys) ? Path.GetFileName(preferences.Keys) : "Choose the prod.keys file you use with your emulator.";
        savePane.Visible = Active.Id != "inspect";
        saveLabel.Text = SaveFolder;
        preview.Enabled = start.Enabled = idle && inputs.Items.Count > 0 &&
            (!Active.NeedsKeys || File.Exists(preferences.Keys)) && (Active.Id == "inspect" || Directory.Exists(SaveFolder));
        stop.Enabled = !idle;
        ShowDetails();
    }

    private void AddPaths(IEnumerable<string> paths)
    {
        var selected = files[Active.Id];
        if (Active.Id == "join") selected.Clear();
        foreach (string path in Active.Id == "join" ? paths.Take(1) : paths)
            if (!selected.Contains(path, StringComparer.OrdinalIgnoreCase)) selected.Add(path);
        LoadInputs();
    }

    private void PickFiles()
    {
        using (var dialog = new OpenFileDialog { Multiselect = Active.Id != "join", CheckFileExists = true,
            Filter = Active.Id == "join" ? "All files|*.*" : "Game files|*.nsp;*.xci;*.nsz;*.xcz|All files|*.*" })
            if (dialog.ShowDialog(this) == DialogResult.OK) AddPaths(dialog.FileNames);
    }

    private void PickFolder(bool save)
    {
        using (var dialog = new FolderBrowserDialog { Description = save ? "Choose where to save copies" : "Choose a folder containing game files or parts",
            ShowNewFolderButton = save, SelectedPath = save ? SaveFolder : "" })
        {
            if (dialog.ShowDialog(this) != DialogResult.OK) return;
            if (save)
            {
                preferences.Folders[Active.Id] = dialog.SelectedPath;
                SavePreferences();
                ResetResults();
                RefreshButtons();
            }
            else AddPaths(new[] { dialog.SelectedPath });
        }
    }

    private void PickKeys(bool additional)
    {
        using (var dialog = new OpenFileDialog { Filter = "Key files|*.keys|All files|*.*",
            Title = additional ? "Choose title.keys" : "Choose prod.keys" })
        {
            if (dialog.ShowDialog(this) != DialogResult.OK) return;
            if (additional) sessionTitleKeys = dialog.FileName;
            else
            {
                preferences.Keys = dialog.FileName;
                sessionTitleKeys = null;
                needsExtraKeys = false;
                SavePreferences();
            }
            ResetResults();
            RefreshButtons();
        }
    }

    private void SavePreferences()
    {
        if (smoke) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(settings));
            File.WriteAllText(settings, json.Serialize(preferences), Encoding.UTF8);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private async Task Run(bool previewOnly)
    {
        if (worker != null || !start.Enabled) return;
        ResetResults();
        status.Text = "Reading files…";
        var request = json.Serialize(new {
            tool = Active.Id, files = files[Active.Id].ToArray(), folder = Active.Id == "inspect" ? null : SaveFolder,
            keys = Active.NeedsKeys ? preferences.Keys : null, titleKeys = sessionTitleKeys, previewOnly = previewOnly
        });
        var executable = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Engine", "SwitchBenchWorker.exe");
        var info = new ProcessStartInfo(executable) {
            WorkingDirectory = Path.GetDirectoryName(executable), UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        using (var process = new Process { StartInfo = info })
        {
            try
            {
                process.Start();
                worker = process;
                RefreshButtons();
                var diagnostics = process.StandardError.ReadToEndAsync();
                WriteRequest(request);
                string line;
                bool finished = false;
                while ((line = await process.StandardOutput.ReadLineAsync()) != null)
                {
                    var entry = json.Deserialize<WorkerEvent>(line);
                    Receive(entry);
                    finished |= entry.kind == "finished" || entry.kind == "error";
                }
                await Task.Run(delegate { process.WaitForExit(); });
                if (!finished || process.ExitCode != 0)
                {
                    status.Text = "SwitchBench’s processing component stopped unexpectedly.";
                    var report = await diagnostics;
                    details.Text = report.Length > 4000 ? report.Substring(report.Length - 4000) : report;
                }
            }
            catch (Exception error)
            {
                status.Text = "SwitchBench couldn’t complete this task.";
                details.Text = error.Message;
                // Closing the request pipe also asks the worker to stop.
                if (worker != null)
                {
                    process.StandardInput.Close();
                    await Task.Run(delegate { process.WaitForExit(); });
                }
            }
            finally
            {
                worker = null;
                RefreshButtons();
                if (closing) Close();
            }
        }
    }

    private void WriteRequest(string line)
    {
        var stream = worker.StandardInput.BaseStream;
        var bytes = Encoding.UTF8.GetBytes(line + "\n");
        stream.Write(bytes, 0, bytes.Length);
        stream.Flush();
    }

    private void Stop()
    {
        if (worker == null) return;
        try { WriteRequest("stop"); status.Text = "Stopping safely…"; stop.Enabled = false; }
        catch (IOException) { }
        catch (InvalidOperationException) { }
    }

    private void Receive(WorkerEvent entry)
    {
        if (entry.issue == "extraKeys") needsExtraKeys = true;
        if (entry.kind == "progress")
        {
            if (stop.Enabled) status.Text = entry.message;
            if (entry.progress.HasValue) progress.Value = (int)Math.Max(0, Math.Min(100, entry.progress.Value * 100));
        }
        else if (entry.kind == "plan" || entry.kind == "result")
        {
            ListViewItem row;
            if (!rows.TryGetValue(entry.id, out row))
            {
                row = new ListViewItem(new[] { entry.title, "", "" });
                rows.Add(entry.id, row);
                results.Items.Add(row);
            }
            var previous = row.Tag as WorkerEvent;
            if (entry.message == null && previous != null) entry.message = previous.message;
            row.SubItems[1].Text = entry.status;
            row.SubItems[2].Text = (entry.message ?? "").Replace("\n", " · ");
            row.Tag = entry;
            if (row.Selected) ShowDetails();
        }
        else
        {
            status.Text = entry.message;
            if (entry.kind == "error") details.Text = entry.detail ?? entry.message;
        }
    }

    private void ShowDetails()
    {
        var entry = results.SelectedItems.Count == 1 ? results.SelectedItems[0].Tag as WorkerEvent : null;
        if (entry != null)
            details.Text = string.Join(Environment.NewLine + Environment.NewLine,
                new[] { entry.message, entry.output, entry.detail }.Where(text => !string.IsNullOrWhiteSpace(text))).Replace("\n", Environment.NewLine);
        reveal.Enabled = worker == null && entry != null && !string.IsNullOrEmpty(entry.output);
    }

    private void Reveal()
    {
        if (results.SelectedItems.Count != 1) return;
        var entry = results.SelectedItems[0].Tag as WorkerEvent;
        if (entry == null || string.IsNullOrEmpty(entry.output)) return;
        var folder = Directory.Exists(entry.output) ? entry.output : Path.GetDirectoryName(entry.output);
        if (Directory.Exists(folder)) Process.Start(new ProcessStartInfo(folder) { UseShellExecute = true });
    }

    internal void CheckNavigation()
    {
        if (navigation.Items.Count != 7) throw new InvalidOperationException("Seven tools expected.");
        for (int i = 0; i < navigation.Items.Count; i++)
        {
            navigation.SelectedIndex = i;
            if (heading.Text != Active.Name || start.Enabled) throw new InvalidOperationException("Invalid initial tool state.");
        }
    }
}
