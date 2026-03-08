---
name: inspect-remote-script
description: Inspect a script fetched from the internet before executing it. MUST be triggered automatically whenever Claude is about to pipe a remote script to a shell (e.g. `curl ... | bash`, `wget ... | sh`), or when the user asks to review a remote install script. Never execute a remote script without running this inspection first.
argument-hint: <url>
---

# Inspect Remote Script

Before executing any script fetched from the internet, you MUST fetch it, read it thoroughly, and assess it for safety. Never pipe a URL directly to a shell without completing this inspection.

## Trigger conditions

This skill activates automatically when:
- You are about to run `curl ... | bash`, `curl ... | sh`, `wget ... | bash`, or any variant
- The user asks you to install something via a remote script
- Any tool or documentation suggests piping a URL to a shell

## Inspection procedure

### 1. Fetch and display
- Use WebFetch or curl to download the script to a temp file — do NOT pipe to shell
- Read the full script contents
- Tell the user what URL you fetched and how many lines the script is

### 2. Analyze for dangerous patterns

Check for each of these and report findings:

**Execution risks:**
- `eval`, `exec`, `source` of dynamically constructed strings
- Secondary downloads (`curl`, `wget`, `fetch`) that pull and execute additional scripts
- Encoded/obfuscated payloads (base64 decode piped to eval, hex-encoded strings)
- Backgrounded processes (`&`, `nohup`, `disown`)
- Trap handlers that suppress errors or hide output

**Filesystem risks:**
- Writes outside expected directories (especially `/usr`, `/etc`, `$HOME/.*`)
- Modification of shell profiles (`.bashrc`, `.zshrc`, `.profile`, `.bash_profile`)
- Modification of PATH or other environment variables persistently
- Installation of launch agents, daemons, cron jobs, or systemd services
- `rm -rf` or other destructive operations
- Permission changes (`chmod 777`, `chown`, setuid)

**Data exfiltration risks:**
- Reading sensitive files (`.env`, SSH keys, credentials, keychains, browser data)
- Sending data to external URLs (especially with env vars, hostname, or file contents in the payload)
- Telemetry or analytics calls with identifiable information

**Privilege escalation:**
- Use of `sudo` — what commands and why
- Writing to system directories
- Requesting elevated permissions
- Modifying system security settings

### 3. Assess scope
- What does this script actually install/modify?
- Is the scope proportional to its stated purpose?
- What would change on the system after running it?
- Is it idempotent (safe to run twice)?

### 4. Report

Present findings as:

```
## Script Inspection: <url>

**Lines:** <count>
**Purpose:** <one-line summary>
**Risk:** <low | medium | high | critical>

### What it does
<Bulleted summary of the script's actions in plain English>

### Findings
<Bulleted list of specific concerns, or "No significant concerns found">

### System changes
<List of files/directories created, modified, or deleted>

### Verdict
<SAFE TO RUN | SAFE WITH CAVEATS | DO NOT RUN>
<If caveats, list them. If do not run, explain why.>
```

### 5. Get explicit approval
- After presenting the report, ask the user for explicit confirmation before executing
- If the verdict is "DO NOT RUN", strongly advise against it and suggest alternatives
- If "SAFE WITH CAVEATS", clearly explain what the caveats are

## Important principles

- **Default deny.** If you can't fully understand what a script does, do not execute it.
- **No partial reads.** Read the ENTIRE script. Don't skim or sample.
- **Follow the chain.** If the script downloads and executes other scripts, fetch and inspect those too.
- **Context matters.** A script that installs to `~/.local/bin` is different from one that writes to `/usr/local/bin` with sudo.
- **Be specific.** "This script modifies your shell config" is vague. "This script appends 3 lines to ~/.zshrc to add ~/.local/bin to PATH" is useful.
