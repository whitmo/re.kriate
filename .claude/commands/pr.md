# Create Pull Request

Create a PR for the current branch (or a specified branch). Handles stacked PRs automatically.

## Arguments

$ARGUMENTS — optional: branch name, PR title override, or "all" to create PRs for all unpushed feature branches in the stack.

## Process

1. **Detect context:**
   - Current branch (or specified branch)
   - Find the correct base branch:
     - If this branch was created from another feature branch (stacked), use that as base
     - Otherwise use `main`
   - Check if branch is pushed to origin; push with `-u` if not
   - Check if a PR already exists for this branch (`gh pr view`)

2. **Gather PR content:**
   - Read the spec if one exists in `specs/<feature>/spec.md`
   - Read the plan if one exists in `specs/<feature>/plan.md`
   - Run `git log --oneline <base>..<head>` to see all commits
   - Run `git diff --stat <base>..<head>` for file change summary
   - Count test changes: `git diff <base>..<head> -- specs/`

3. **Generate PR:**
   - Title: feature number + concise description (under 70 chars)
   - Body: summary bullets from spec/commits, test plan from tasks, stacked-on note if applicable
   - Create with `gh pr create`

4. **If `$ARGUMENTS` is "all":**
   - Walk the branch stack from oldest to newest
   - Create PRs for each unpushed branch, each targeting the previous branch as base
   - Report all PR URLs at the end

## PR body format

```
## Summary
<2-4 bullets derived from spec or commits>

## Test plan
<bullets from tasks.md or inferred from test commits>

<if stacked>Stacked on #<PR number> (<base branch>)</if>

Generated via [speckit pipeline](specs/<feature>/) | ralph TDD

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## Rules
- Never create a PR if one already exists for that branch (show the existing URL instead)
- Always push before creating
- Keep title under 70 chars
- If spec exists, use it as the source of truth for the summary
- For stacked PRs, always set the correct base branch
