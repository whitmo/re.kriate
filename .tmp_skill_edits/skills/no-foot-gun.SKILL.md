---
name: no-foot-gun
description: Meta-skill that bundles safety checks to prevent self-inflicted damage. Automatically triggers component skills when risky actions are detected. Components include inspect-remote-script (for piping URLs to shells) and security-risk-review (for adopting new tools/dependencies).
---

# No Foot Gun

A meta-skill that ensures safety checks are run before risky actions. This skill delegates to specialized skills based on the situation.

## Automatic triggers

### Remote script execution
When about to run `curl | bash`, `wget | sh`, or any variant:
- **Delegate to:** `inspect-remote-script`
- **Rule:** NEVER execute a remote script without full inspection and user approval

### New tool/dependency adoption
When installing, adding, or evaluating a new package, tool, MCP server, or dependency:
- **Delegate to:** `security-risk-review`
- **Rule:** Surface risks before committing to adoption

## Hard rules

These apply at all times, regardless of whether a specific skill is invoked:

1. **Never pipe remote scripts to a shell without inspection** — always fetch first, read fully, report, and get explicit user approval
2. **Never run destructive commands without confirmation** — `rm -rf`, `git reset --hard`, `git push --force`, dropping databases, killing processes
3. **Never commit secrets** — check for `.env`, credentials, API keys, private keys before staging
4. **Never skip pre-commit hooks** — no `--no-verify`, no `--no-gpg-sign` unless the user explicitly requests it
5. **Never force-push to main/master** — warn and refuse even if asked
