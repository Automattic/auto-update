using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Reflection;
using System.Threading;
using System.Net;
using System.IO;
using System.Diagnostics;

namespace AutoUpdate
{
    public enum UpdaterState
    {
        Idle,
        Downloading,
        Ready,
        Installing
    }

    public class Updater
    {
        private Assembly assembly;
        private String host;
        private String channel;
        private Thread updateThread;
        private SynchronizationContext context;
        private TimeSpan interval;
        private UpdaterState state;
        private bool mainThreadResponding;

        public Updater(Assembly assembly, String host, String channel)
        {
            this.assembly = assembly;
            this.host = host;
            this.channel = channel;
            this.context = SynchronizationContext.Current;
            this.interval = TimeSpan.FromHours(1);

            this.state = UpdaterState.Idle;
        }
        
        public void CheckForUpdates() {

            lock (this)
            {
                if (this.state != UpdaterState.Idle)
                {
                    return;
                }
                this.state = UpdaterState.Downloading;
            }

            updateThread = new Thread(() => {
                Console.Write("Checking for updates.");
                String osVersion = Environment.OSVersion.Version.ToString(3) + "-" + Environment.OSVersion.Version.Revision.ToString();
                String name = assembly.GetName().Name;
                String version = assembly.GetName().Version.ToString(3) + "-" + assembly.GetName().Version.Revision.ToString();
                String osName = "windows";
                String architecture = IntPtr.Size == 4 ? "x86" : "x86-64";
                String path = String.Format("https://{0}/update/{1}/{2}/{3}/{4}/{5}/{6}", host, architecture, osName, osVersion, name, version, channel);
                String localPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), name);
                if (!Directory.Exists(localPath))
                {
                    Directory.CreateDirectory(localPath);
                }
                try 
                {   
                    WebClient webClient = new WebClient();
                    webClient.DownloadFile(path, Path.Combine(localPath, "update.msi"));
                    lock (this)
                    {
                        this.state = UpdaterState.Ready;
                    }
                    for (; ; )
                    {
                        lock (this)
                        {
                            mainThreadResponding = false;
                        }
                        context.Post((object state) =>
                        {
                            this.UpdateReady();
                            lock (this)
                            {
                                mainThreadResponding = true;
                            }
                        }, null);
                        Thread.Sleep(15);
                        lock (this)
                        {
                            if (mainThreadResponding)
                            {
                                continue;
                            }
                        }
                        this.InstallUpdate();
                    }
                } catch (WebException e) {
                    if (e.Response != null && e.Response is HttpWebResponse && ((HttpWebResponse)e.Response).StatusCode == HttpStatusCode.NotFound)
                    {
                        Console.Write("No Updates.");
                    }
                    lock (this)
                    {
                        this.state = UpdaterState.Idle;
                    }
                    Thread.Sleep(interval);
                    context.Post((object state) => this.CheckForUpdates(), null);
                }
            });
            updateThread.Name = "AutoUpdate Thread";
            updateThread.IsBackground = true;
            updateThread.Start();
        }

        public TimeSpan Interval
        {
            get { return interval; }
            set { interval = value; }
        }

        public UpdaterState State
        {
            get {
                lock (this)
                {
                    return state;
                }
            }
        }

        public delegate void UpdateReadyDelegate();

        public event UpdateReadyDelegate UpdateReady;

        public void InstallUpdate()
        {
            String path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), assembly.GetName().Name);
            try
            {
                Stream installUpdateScriptStream = Assembly.GetExecutingAssembly().GetManifestResourceStream("AutoUpdate.InstallUpdate.cmd");
                Stream fileStream = new FileStream(path + "\\InstallUpdate.cmd", FileMode.Create);
                byte[] buffer = new byte[8 * 1024];
                int len;
                while ((len = installUpdateScriptStream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    fileStream.Write(buffer, 0, len);
                }
                fileStream.Close();
            }
            catch (Exception e)
            {
                Console.Write("Failed to write install script.");
                return;
            }
            try
            {
                var process = new Process();
                var startInfo = new ProcessStartInfo("CMD", "/C .\\InstallUpdate.cmd");
                startInfo.WorkingDirectory = path;
                startInfo.CreateNoWindow = true;
                startInfo.UseShellExecute = false;
                startInfo.EnvironmentVariables.Add("WAIT", Path.GetFileName(assembly.Location));
                startInfo.EnvironmentVariables.Add("LAUNCH", assembly.Location);
                process.StartInfo = startInfo;
                process.Start();
            }
            catch (Exception e)
            {
                Console.Write("Failed to start child process.");
                return;
            }
            Environment.Exit(0);
        }
    }
}
