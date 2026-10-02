# Repository rulesets

These files are the source of truth for the GitHub rulesets on this repo. Keep them in sync with **Settings → Rules → Rulesets**.

Apply them with:

```sh
gh api -X POST repos/coderabbitai/coderabbit-arcade/rulesets --input .github/rulesets/main-protection.json
gh api -X POST repos/coderabbitai/coderabbit-arcade/rulesets --input .github/rulesets/release-tags.json
```

To update a ruleset that already exists, use `-X PUT repos/.../rulesets/<id>`.

- **`main-protection`** applies to the default branch:
  - no deletions or force pushes
  - linear history
  - squash-only PRs, with 1 approval from a code owner
  - stale approvals dismissed, and the last push must be approved by someone else
  - all review threads resolved
  - the `godot-tests`, `lint` and `gitleaks` checks must pass on an up-to-date branch
  - `repo-admins` can bypass only through a PR

  To make CodeRabbit blocking, add `{ "context": "CodeRabbit" }` to the required checks, and enable `reviews.request_changes_workflow` in `.coderabbit.yaml`.
- **`release-tags`** covers `v*` tags: only `repo-admins` can create, move or delete them.
