#!/usr/bin/env python3
"""Render servers.template.json from an env file and merge it into ~/.claude.json.

Only the mcpServers key is touched; everything else in the target file is
preserved byte-for-byte in value. Servers whose credentials are still blank are
skipped rather than written as broken entries.
"""
import argparse
import json
import os
import re
import shutil
import sys
import time

VAR = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


def read_env(path):
    """Parse a KEY=value env file. Supports quotes, comments, and $HOME/${VAR}."""
    env = {}
    with open(path) as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            value = os.path.expandvars(os.path.expanduser(value))
            env[key] = value
    return env


def substitute(node, env, missing):
    if isinstance(node, dict):
        return {k: substitute(v, env, missing) for k, v in node.items()}
    if isinstance(node, list):
        return [substitute(v, env, missing) for v in node]
    if isinstance(node, str):
        def repl(match):
            name = match.group(1)
            if name not in env:
                missing.add(name)
                return match.group(0)
            return env[name]
        return VAR.sub(repl, node)
    return node


def has_blank(node):
    if isinstance(node, dict):
        return any(has_blank(v) for v in node.values())
    if isinstance(node, list):
        return any(has_blank(v) for v in node)
    # "Bearer" alone means the token placeholder resolved to an empty string.
    return isinstance(node, str) and node.strip() in ("", "Bearer")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True)
    ap.add_argument("--env-file", required=True)
    ap.add_argument("--target", required=True)
    args = ap.parse_args()

    if not os.path.exists(args.env_file):
        sys.exit(f"env file not found: {args.env_file}")

    env = read_env(args.env_file)
    with open(args.template) as fh:
        template = json.load(fh)

    missing = set()
    rendered = substitute(template, env, missing)
    if missing:
        sys.exit(
            "env file is missing these variables: " + ", ".join(sorted(missing))
        )

    kept = {n: c for n, c in rendered.items() if not has_blank(c)}
    skipped = sorted(set(rendered) - set(kept))

    config = {}
    if os.path.exists(args.target):
        backup = f"{args.target}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(args.target, backup)
        with open(args.target) as fh:
            config = json.load(fh)

    config.setdefault("mcpServers", {}).update(kept)
    with open(args.target, "w") as fh:
        json.dump(config, fh, indent=2)

    print(f"  merged {len(kept)} mcp server(s): {', '.join(kept) or 'none'}")
    if skipped:
        print(f"  skipped (blank credentials): {', '.join(skipped)}")


if __name__ == "__main__":
    main()
