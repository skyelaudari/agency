# Shared journal

Append-only cross-agent activity log. One line per significant event.

Format: `[YYYY-MM-DD HH:MM] [agent-name] description`

Example:
```
[2026-05-07 10:15] [chief-of-staff] Delegated research on vendor X to researcher (id: 2026-05-07T10-15-00-cos-researcher-vendor-x)
[2026-05-07 12:30] [researcher] Returned vendor X analysis to archive
```

(Empty on workspace bootstrap. Will fill as agents log activity.)
