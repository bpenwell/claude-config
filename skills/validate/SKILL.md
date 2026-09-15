---
name: validate
description: Validate that recent code changes satisfy a stated requirement. Use after implementing something to confirm it works as intended before finishing.
argument-hint: "[requirement to validate against]"
allowed-tools: [Bash, Read]
---

Validate that the recent code changes in the working directory correctly address a requirement.

## Steps

1. Determine the requirement:
   - If an argument was provided to `/validate`, use it verbatim
   - Otherwise, infer from the last user message or current task context

2. Run the shared validation script:
   ```
   bash ~/Coding/.claude/validate.sh "<requirement>" "$(pwd)"
   ```

3. Report the result clearly:
   - **PASS**: State what was verified and that the implementation looks correct
   - **FAIL**: List each specific issue found and explain what needs to change

4. On FAIL:
   - Fix each issue described in the validation output
   - Re-run `/validate` to confirm the fix worked
   - Repeat until validation passes

## Notes
- Validation checks the current `git diff HEAD` against the requirement
- If there are no uncommitted changes, validation will fail (nothing to check)
- Use `[skip-validate]` prefix on a message to opt out of auto-validation for that task
