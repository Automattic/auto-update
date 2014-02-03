# Automatic Updates Everywhere!

![Icons](https://i.cloudup.com/y7FS3OSfUX-3000x3000.jpeg)

The goal of this project is to provide a drop-in solution for silent, automatic, unobstrusive "Chrome-like" updates to a variety of platforms.

This repository holds the client-side code for downloading and installing software updates. For the server-side code, check https://github.com/cloudup/auto-update-server .

Currently, two ports of the client-side library are available:

* An Objective-C / Cocoa port, for OSX 10.6+
* A C# / .NET port, for Windows XP/Vista/7/8/8.1

The .NET port is currently behind the Cocoa port, and is not quite ready for production use. It's temporarily available only under the [`dot-net`](https://github.com/cloudup/auto-update/tree/dot-net) branch. Once it reaches parity with the Cocoa port it will be merged back to master.

We intend to have as many ports as possible.

## Technical Overview

Each port of the client library is responsible for doing an HTTP request to the update server, providing information such as the current application name, application version, operating system version, machine architecture, etc.

The server then iterates over the available updates and responds with the latest version that matches all provided criteria. (For more information about the server operation check [its repository](https://github.com/cloudup/auto-update-server)) 

The client library then handles downloading the update into temporary storage, extracting/decompressing its contents (if applicable), and installing it.

Since replacing the executable file of the current running process is tricky on some platforms, the installation is usually performed via a second stage shell script/batch file.

### Robustness

If possible, the update client library should operate on a separate thread (or even on a separate process) to provide isolation and robustness, so that it's still possible to download updates in case the main thread hangs or crashes.

This is specially useful when delivering updates for continuous integration purposes. (i.e. one build per push to a github repository)

### Relaunching

To finish the installation of the update, an app relaunch is required. The update client library will notify the app when an update is available, and the app can decide whether to relaunch imediately or to wait. For status bar/notification area applications like [Cloudup](https://cloudup.com), that run in the background, an immediate relauch is usually adequate. (As long as the user is not currently using the app, or a critical operation is taking place) For more traditional applications, it might be interesting to delay the relaunch, or to provide a UI to manually relaunch the app.

### Content of update files

On the OS X port, updates are simply the latest application bundle, compressed as a .tar.gz file. For other ports, the content of the update file should probably match the platform conventions, (e.g. MSI files for Windows, .deb or .rpm files for Linux) unless it's more convenient to utilize a non-standard format for performance or other technical reasons.

## Creating New Ports

New ports should be created on a separate git branch, inside a new directory with the `AutoUpdate.XYZ` name, where `XYZ` is the name of the port. For example, for a Python port you should do:

```bash
git checkout -b python
mkdir AutoUpdate.Python
cd AutoUpdate.Python
```

(Keep your port contained in that directory.)

The ports don't need to be literal, exact ports of the Cocoa or .NET versions, you're free to create something that is idiomatic and makes sense under the platform/programming language conventions, while trying to more or less match the style of the API.

Before creating a new port, please open an issue so that we can avoid situations like two people creating ports for the same platform at the same time, and that so we can discuss the approach used for the port.

## Contributors

* [@TooTallNate](https://github.com/TooTallNate)
* [@coreh](https://github.com/coreh)
* [@guille](https://github.com/guille)

## License

The MIT License (MIT)

Copyright (c) 2014 Automattic, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
