'use strict';

// VS Code binds its IPC socket inside the profile's user-data directory,
// and macOS caps UNIX-socket paths at 103 bytes. The standard darwin temp
// dir (~50 chars of /var/folders/...) plus a descriptive prefix already
// overflows the cap, and VS Code then fails startup with `listen EINVAL`
// on `user-data/<version>-main.sock` before any extension loads. A green
// gate must not depend on the caller exporting a short TMPDIR — GitHub's
// macOS runners use the long form too — so profile roots live in /tmp
// with terse prefixes.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

module.exports.makeShortProfileRoot = (prefix) =>
  fs.mkdtempSync(
    path.join(fs.existsSync('/tmp') ? '/tmp' : os.tmpdir(), prefix),
  );
