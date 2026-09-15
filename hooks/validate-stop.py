#!/usr/bin/env python3
"""
validate-stop.py — Claude Stop hook
Validates recent code changes against the detected requirement before
allowing Claude to end a session. Blocks stop and injects fix instructions
if validation fails.

Registered in ~/.claude/settings.json under hooks.Stop.
"""
import json
import os
import subprocess
import sys

# Words that indicate an actionable implementation request
ACTION_WORDS = [
    'fix', 'add', 'change', 'implement', 'make', 'update', 'create',
    'remove', 'refactor', 'move', 'rename', 'style', 'align', 'adjust',
    'replace', 'convert', 'migrate', 'build', 'write', 'edit', 'delete',
    'improve', 'optimize', 'refactor', 'integrate', 'connect', 'set up',
]

# Prefixes that opt out of validation
SKIP_PREFIXES = ('[skip-validate]', '[no-validate]', '[skip_validate]')


def extract_requirement(transcript_path: str) -> str | None:
    """Read JSONL transcript and return the last actionable user requirement."""
    if not transcript_path or not os.path.exists(transcript_path):
        return None

    messages = []
    with open(transcript_path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                messages.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    for entry in reversed(messages):
        # Transcript entries vary — handle both direct message objects and
        # wrapper objects with a "message" key
        msg = entry if entry.get('role') else entry.get('message', {})
        if not isinstance(msg, dict):
            continue
        if msg.get('role') != 'user':
            continue

        content = msg.get('content', '')
        if isinstance(content, list):
            content = ' '.join(
                c.get('text', '') for c in content
                if isinstance(c, dict) and c.get('type') == 'text'
            )

        if not isinstance(content, str) or not content.strip():
            continue

        text = content.strip()

        # Honour opt-out prefix
        if text.lower().startswith(SKIP_PREFIXES):
            return None

        lower = text.lower()
        if any(w in lower for w in ACTION_WORDS):
            return text

    return None



def has_git_diff(workdir: str) -> bool:
    """Return True if there are any staged or unstaged changes in the repo."""
    try:
        for cmd in (['git', 'diff', 'HEAD'], ['git', 'diff', '--cached']):
            result = subprocess.run(
                cmd, capture_output=True, text=True, cwd=workdir, timeout=10
            )
            if result.stdout.strip():
                return True
    except Exception:
        pass
    return False

def run_validation(requirement: str, workdir: str) -> tuple[bool, str, list[str]]:
    """
    Run validate.sh and return (passed, summary, issues).
    On any error we return passed=True so the hook fails open, never stuck.
    """
    validate_script = os.path.expanduser('~/Coding/.claude/validate.sh')
    if not os.path.exists(validate_script):
        return True, 'validate.sh not found — skipping', []

    try:
        result = subprocess.run(
            [validate_script, requirement, workdir],
            capture_output=True,
            text=True,
            timeout=90,
            cwd=workdir,
        )
        raw = result.stdout.strip()

        try:
            report = json.loads(raw)
            passed = bool(report.get('pass', False))
            summary = report.get('summary', 'Validation failed')
            issues = report.get('issues', [])
        except json.JSONDecodeError:
            # Claude returned non-JSON — treat as failure with raw output
            passed = result.returncode == 0
            summary = raw[:200] if raw else 'Validation failed (no output)'
            issues = []

        return passed, summary, issues

    except subprocess.TimeoutExpired:
        return True, 'Validation timed out — skipping', []
    except Exception as exc:
        return True, f'Validation error: {exc}', []


def find_workdir(transcript_path: str) -> str:
    """Try to find the working directory from the transcript session entry."""
    if not transcript_path or not os.path.exists(transcript_path):
        return os.getcwd()

    with open(transcript_path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('type') == 'session' and entry.get('cwd'):
                    return entry['cwd']
            except json.JSONDecodeError:
                continue

    return os.getcwd()


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    transcript_path = data.get('transcript_path', '')
    workdir = find_workdir(transcript_path)

    requirement = extract_requirement(transcript_path)
    if not requirement:
        # No actionable requirement detected — allow stop
        sys.exit(0)

    # No real code changes — nothing to validate, allow stop
    if not has_git_diff(workdir):
        sys.exit(0)

    passed, summary, issues = run_validation(requirement, workdir)

    if passed:
        sys.exit(0)

    # Build the issue list for the feedback message
    if issues:
        issues_text = '\n'.join(f'- {i}' for i in issues)
    else:
        issues_text = f'- {summary}'

    output = {
        'decision': 'block',
        'reason': f'Validation failed: {summary}',
        'systemMessage': (
            'Your implementation does not fully address the requirement.\n\n'
            f'Original requirement: {requirement}\n\n'
            f'Issues found:\n{issues_text}\n\n'
            'Please fix these specific issues and try again.'
        ),
    }
    print(json.dumps(output))


if __name__ == '__main__':
    main()
