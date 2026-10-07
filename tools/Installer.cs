using System;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows.Forms;

class KotobaInstaller : Form
{
    TextBox destination = new TextBox();
    Button install = new Button();
    Label status = new Label();
    ProgressBar progress = new ProgressBar();
    CheckBox shortcut = new CheckBox();
    string installedExe;

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--verify-extract")
        {
            try { Extract(args[1]); return 0; }
            catch { return 1; }
        }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new KotobaInstaller());
        return 0;
    }

    KotobaInstaller()
    {
        Text = "말의 전장 · PC 설치";
        ClientSize = new Size(570, 322);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        BackColor = Color.FromArgb(21, 36, 28);
        ForeColor = Color.FromArgb(231, 218, 190);
        Font = new Font("Malgun Gothic", 10);
        var title = new Label { Text = "말의 전장", Font = new Font("Malgun Gothic", 24, FontStyle.Bold), AutoSize = true, Location = new Point(24, 20) };
        var note = new Label { Text = "전국시대 일본어 랜덤 디펜스\n인터넷 연결 없이 플레이 · PC용 첫 버전", AutoSize = true, Location = new Point(27, 77) };
        var pathLabel = new Label { Text = "설치 폴더", AutoSize = true, Location = new Point(27, 137) };
        destination.Location = new Point(27, 160);
        destination.Size = new Size(420, 28);
        destination.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KotobaSengoku");
        var browse = new Button { Text = "변경", Location = new Point(461, 158), Size = new Size(80, 30) };
        browse.Click += delegate { using (var dialog = new FolderBrowserDialog()) { dialog.Description = "게임을 설치할 폴더를 선택하십시오."; if (dialog.ShowDialog() == DialogResult.OK) destination.Text = Path.Combine(dialog.SelectedPath, "KotobaSengoku"); } };
        shortcut.Text = "바탕 화면에 바로가기 만들기";
        shortcut.Checked = true;
        shortcut.AutoSize = true;
        shortcut.Location = new Point(27, 201);
        progress.Location = new Point(27, 242);
        progress.Size = new Size(338, 16);
        status.AutoSize = false;
        status.Location = new Point(27, 268);
        status.Size = new Size(340, 40);
        status.Text = "설치 후 바로 실행할 수 있습니다.";
        install.Text = "설치";
        install.Location = new Point(393, 237);
        install.Size = new Size(148, 45);
        install.Click += BeginInstall;
        Controls.AddRange(new Control[] { title, note, pathLabel, destination, browse, shortcut, progress, status, install });
    }

    static void Extract(string folder)
    {
        string root = Path.GetFullPath(folder);
        Directory.CreateDirectory(root);
        string prefix = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Read))
        {
            foreach (var entry in archive.Entries)
            {
                string target = Path.GetFullPath(Path.Combine(root, entry.FullName));
                if (!target.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new IOException("잘못된 설치 파일 경로입니다.");
                if (entry.Name.Length == 0) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                using (var input = entry.Open())
                using (var output = new FileStream(target, FileMode.Create, FileAccess.Write)) input.CopyTo(output);
            }
        }
    }

    void BeginInstall(object sender, EventArgs e)
    {
        if (installedExe != null) { Process.Start(installedExe); Close(); return; }
        string target;
        try { target = Path.GetFullPath(destination.Text); }
        catch { status.Text = "유효한 설치 경로를 선택하십시오."; return; }
        if (target.TrimEnd('\\').Equals(Path.GetPathRoot(target).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) { status.Text = "드라이브의 루트에는 설치할 수 없습니다."; return; }
        install.Enabled = false;
        destination.Enabled = false;
        progress.Style = ProgressBarStyle.Marquee;
        status.Text = "게임 파일을 설치하고 있습니다…";
        bool createShortcut = shortcut.Checked;
        var worker = new BackgroundWorker();
        worker.DoWork += delegate { Extract(target); };
        worker.RunWorkerCompleted += delegate(object s, RunWorkerCompletedEventArgs result)
        {
            progress.Style = ProgressBarStyle.Blocks;
            install.Enabled = true;
            if (result.Error != null) { destination.Enabled = true; status.Text = "설치하지 못했습니다. 폴더 권한과 디스크 공간을 확인하십시오."; return; }
            installedExe = Path.Combine(target, "KotobaSengoku.exe");
            string suffix = "";
            if (createShortcut)
            {
                try
                {
                    Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                    object shell = Activator.CreateInstance(shellType);
                    string linkPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "말의 전장.lnk");
                    object link = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { linkPath });
                    Type linkType = link.GetType();
                    linkType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] { installedExe });
                    linkType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] { target });
                    linkType.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
                }
                catch { suffix = " 바로가기는 만들지 못했습니다."; }
            }
            progress.Value = 100;
            status.Text = "설치가 완료되었습니다." + suffix;
            install.Text = "게임 실행";
        };
        worker.RunWorkerAsync();
    }
}
