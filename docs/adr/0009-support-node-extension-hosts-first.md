---
status: accepted
---

# Support Node Extension Hosts First

The first hardened release will support the desktop VS Code client with an
Extension Project running in either a local or remote Node Extension Host. This
includes the remote-host architecture used by Remote SSH, Dev Containers, and
Codespaces when accessed from desktop VS Code.

The implementation will preserve a browser-compatible architecture, but the
Web Extension Host will not be part of the first release gate. Web support is a
required milestone before 1.0 and must add its own build, compatibility, and
Extension Host test coverage. This sequencing gives Extension Authors a
smaller initial runtime matrix while making the temporary limitation explicit
to Extension Users of browser-based VS Code clients.
