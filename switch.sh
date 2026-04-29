#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT=""

create_embedded_py_script() {
  local py_tmp
  py_tmp="$(mktemp -t switch_embedded.XXXXXX.py)"
  cat >"$py_tmp" <<'PY'
#!/usr/bin/env python3
"""Develop/release switch helper.

Primary flow:
1) Generate config once from release/develop working directories.
2) Apply config on current repository with --mode develop|release.
"""

from __future__ import annotations

import argparse
import configparser
import difflib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Sequence, Tuple


@dataclass
class Rule:
    name: str
    file: str
    release: str
    develop: str


def read_config(path: Path) -> List[Rule]:
    def _decode_ini_value(raw: str) -> str:
        # dev_switch config writes as "key = <value>"; remove separator space only.
        return raw[1:] if raw.startswith(" ") else raw

    lines = path.read_text(encoding="utf-8").splitlines()
    sections: dict[str, dict[str, str]] = {}
    current_section = ""
    current_key = ""

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current_section = stripped[1:-1]
            sections.setdefault(current_section, {})
            current_key = ""
            continue
        if not current_section:
            continue
        if not line:
            if current_key:
                sections[current_section][current_key] += "\n"
            continue
        if line[0] in (" ", "\t") and current_key:
            sections[current_section][current_key] += "\n" + line
            continue
        if stripped.startswith("#") or stripped.startswith(";"):
            continue
        if "=" not in line:
            current_key = ""
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        sections[current_section][key] = value
        current_key = key

    rules: List[Rule] = []
    for section, sec in sections.items():
        if not section.startswith("rule."):
            continue
        if "file" not in sec:
            raise ValueError(f"{section} missing key: file")
        rule_release = sec.get("release", sec.get("prod"))
        rule_develop = sec.get("develop", sec.get("dev"))
        if rule_release is None or rule_develop is None:
            raise ValueError(
                f"{section} missing key: release/develop "
                "(prod/dev are accepted as legacy aliases)"
            )
        rule_release = _decode_ini_value(rule_release)
        rule_develop = _decode_ini_value(rule_develop)
        rules.append(
            Rule(
                name=section.split(".", 1)[1],
                file=sec["file"].strip(),
                release=rule_release,
                develop=rule_develop,
            )
        )

    return rules


def normalize_env(value: str) -> str:
    v = value.strip().lower()
    if v in ("develop", "dev"):
        return "develop"
    if v in ("release", "prod", "production"):
        return "release"
    raise ValueError(f"unsupported env: {value}")


def to_pair(source_env: str, target_env: str, rule: Rule) -> Tuple[str, str]:
    source = normalize_env(source_env)
    target = normalize_env(target_env)
    if source == "develop" and target == "release":
        return rule.develop, rule.release
    if source == "release" and target == "develop":
        return rule.release, rule.develop
    raise ValueError(f"unsupported source/target env: {source_env}->{target_env}")


def is_text_file(path: Path) -> bool:
    try:
        raw = path.read_bytes()
    except OSError:
        return False
    return b"\x00" not in raw


def apply_rules(
    repo_dir: Path,
    rules: List[Rule],
    mode: str,
    dry_run: bool,
) -> None:
    if mode == "develop":
        source_env, target_env = "release", "develop"
    elif mode == "release":
        source_env, target_env = "develop", "release"
    else:
        raise ValueError(f"unsupported mode: {mode}")

    print("\n[Rule Apply Plan]")
    print(f"- repository:  {repo_dir}")
    print(f"- conversion:  {source_env} -> {target_env} (--mode {mode})")
    if not rules:
        print("- rules:       0 (no change)")
        return
    print(f"- rules:       {len(rules)}")

    if dry_run:
        for rule in rules:
            src, dst = to_pair(source_env, target_env, rule)
            src_lines = src.count("\n") + 1
            dst_lines = dst.count("\n") + 1
            print(f"  [{rule.name}] {rule.file}")
            print(f"    find:    {src[:90]}")
            print(f"    replace: {dst[:90]}")
            print(f"    lines:   {src_lines} -> {dst_lines}")
        return

    touched = 0
    skipped_missing = 0
    skipped_token = 0
    skipped_ambiguous = 0
    for rule in rules:
        file_path = repo_dir / rule.file
        if not file_path.exists():
            print(f"  [skip:{rule.name}] file not found: {rule.file}")
            skipped_missing += 1
            continue
        src, dst = to_pair(source_env, target_env, rule)
        content = file_path.read_text(encoding="utf-8")
        src_count = _count_line_aligned_occurrences(content, src)
        if src_count == 0:
            updated, changed_lines, skipped_lines = _replace_by_assignment_key_fallback(
                content, src, dst
            )
            if changed_lines > 0 and updated != content:
                file_path.write_text(updated, encoding="utf-8")
                touched += 1
                print(
                    f"  [ok:{rule.name}] fallback-updated {rule.file} "
                    f"(line replacements: {changed_lines}, skipped: {skipped_lines})"
                )
                continue
            print(f"  [skip:{rule.name}] source token not found")
            skipped_token += 1
            continue
        if src_count > 1:
            print(
                f"  [skip:{rule.name}] ambiguous source token: "
                f"matched {src_count} locations"
            )
            skipped_ambiguous += 1
            continue
        if src == dst:
            print(f"  [skip:{rule.name}] source/target token are identical")
            continue
        updated, replaced = _replace_line_aligned_once(content, src, dst)
        if replaced == 1 and updated != content:
            file_path.write_text(updated, encoding="utf-8")
            touched += 1
            print(f"  [ok:{rule.name}] updated {rule.file}")
    print("\n[Applied]")
    print(f"- files touched: {touched}")
    print(f"- skipped (missing file): {skipped_missing}")
    print(f"- skipped (token not found): {skipped_token}")
    print(f"- skipped (ambiguous token): {skipped_ambiguous}")


def _sanitize_rule_name(value: str) -> str:
    return "".join(ch if ch.isalnum() else "_" for ch in value).strip("_").lower()


def _discover_text_files(root: Path) -> Sequence[Path]:
    return sorted(
        p
        for p in root.rglob("*")
        if p.is_file() and ".git" not in p.parts and is_text_file(p)
    )


def _make_multiline(value: str) -> str:
    lines = value.splitlines()
    if not lines:
        return ""
    if len(lines) == 1:
        return lines[0]
    indented = "\n".join(f"\t{line}" for line in lines)
    return f"\n{indented}"


def _extract_replace_rules(
    rel_path: str, release_lines: List[str], develop_lines: List[str]
) -> List[Rule]:
    matcher = difflib.SequenceMatcher(a=release_lines, b=develop_lines)
    rules: List[Rule] = []
    idx = 1
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag != "replace":
            continue
        release_block = "".join(release_lines[i1:i2]).rstrip("\n")
        develop_block = "".join(develop_lines[j1:j2]).rstrip("\n")
        if not release_block or not develop_block:
            continue
        if release_block == develop_block:
            continue
        stem = _sanitize_rule_name(Path(rel_path).stem)
        rules.append(
            Rule(
                name=f"{stem}_{idx:03d}",
                file=rel_path,
                release=release_block,
                develop=develop_block,
            )
        )
        idx += 1
    return rules


_XML_STRING_NUMBER_RE = re.compile(r"^\s*<string>\s*\d+\s*</string>\s*$")
_KEYED_NUMBER_RE = re.compile(
    r"^\s*(?:"
    r"versionCode|version_code|versionName|version_name|debug_local|release_local|"
    r"buildNumber|build_number|build|version|CFBundleVersion|CFBundleShortVersionString"
    r")\s*[:= ]+\s*[\"']?[0-9][0-9A-Za-z.\-_]*[\"']?\s*$"
)


def _is_version_or_build_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    if _XML_STRING_NUMBER_RE.match(stripped):
        return True
    return bool(_KEYED_NUMBER_RE.match(stripped))


def _is_version_or_build_only_change(release_block: str, develop_block: str) -> bool:
    rel_lines = release_block.splitlines()
    dev_lines = develop_block.splitlines()
    if not rel_lines or len(rel_lines) != len(dev_lines):
        return False
    for rel_line, dev_line in zip(rel_lines, dev_lines):
        if rel_line == dev_line:
            continue
        if not _is_version_or_build_line(rel_line):
            return False
        if not _is_version_or_build_line(dev_line):
            return False
    return True


def _count_line_aligned_occurrences(content: str, token: str) -> int:
    if not token:
        return 0
    pattern = re.compile(rf"(?:(?<=\n)|\A){re.escape(token)}(?:(?=\r?\n)|\Z)")
    return sum(1 for _ in pattern.finditer(content))


def _replace_line_aligned_once(content: str, source: str, target: str) -> tuple[str, int]:
    if not source:
        return content, 0
    pattern = re.compile(rf"(?:(?<=\n)|\A){re.escape(source)}(?:(?=\r?\n)|\Z)")
    matches = list(pattern.finditer(content))
    if len(matches) != 1:
        return content, len(matches)
    match = matches[0]
    return content[: match.start()] + target + content[match.end() :], 1


def _extract_assignment_key(line: str) -> str | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("//"):
        return None
    m = re.match(
        r"^(?:public\s+|private\s+|protected\s+)?"
        r"(?:static\s+)?(?:final\s+)?(?:[\w<>\[\],?]+\s+)?"
        r"([A-Za-z_][A-Za-z0-9_]*)\s*=",
        stripped,
    )
    if not m:
        return None
    return m.group(1)


def _replace_unique_line_ignoring_indent(
    content: str, source_line: str, target_line: str
) -> tuple[str, bool]:
    src = source_line.strip()
    dst = target_line.strip()
    if not src or not dst or src == dst:
        return content, False
    pattern = re.compile(rf"(?m)^(?P<indent>[ \t]*){re.escape(src)}[ \t]*\r?$")
    matches = list(pattern.finditer(content))
    if len(matches) != 1:
        return content, False
    m = matches[0]
    replaced = f"{m.group('indent')}{dst}"
    return content[: m.start()] + replaced + content[m.end() :], True


def _replace_unique_assignment_by_key(
    content: str, key: str, target_line: str
) -> tuple[str, bool]:
    dst = target_line.strip()
    if not key or not dst:
        return content, False
    pattern = re.compile(
        rf"(?m)^(?P<indent>[ \t]*)(?!//).*?\b{re.escape(key)}\s*=.*\r?$"
    )
    matches = list(pattern.finditer(content))
    if len(matches) != 1:
        return content, False
    m = matches[0]
    replaced = f"{m.group('indent')}{dst}"
    return content[: m.start()] + replaced + content[m.end() :], True


def _replace_by_assignment_key_fallback(
    content: str, source_block: str, target_block: str
) -> tuple[str, int, int]:
    src_lines = [ln for ln in source_block.splitlines() if ln.strip()]
    dst_lines = [ln for ln in target_block.splitlines() if ln.strip()]
    src_map = {}
    dst_map = {}
    for ln in src_lines:
        key = _extract_assignment_key(ln)
        if key:
            src_map[key] = ln
    for ln in dst_lines:
        key = _extract_assignment_key(ln)
        if key:
            dst_map[key] = ln

    changed = 0
    skipped = 0
    updated = content
    for key in sorted(set(src_map.keys()) & set(dst_map.keys())):
        src_ln = src_map[key]
        dst_ln = dst_map[key]
        if src_ln.strip() == dst_ln.strip():
            continue
        updated, ok = _replace_unique_line_ignoring_indent(updated, src_ln, dst_ln)
        if not ok:
            updated, ok = _replace_unique_assignment_by_key(updated, key, dst_ln)
        if ok:
            changed += 1
        else:
            skipped += 1
    return updated, changed, skipped


GITIGNORE_MARKER = "# dev_switch entries (added by switch.sh generate-config)"
GITIGNORE_ENTRIES_DEFAULT = (
    "/dev_switch.config",
    ".generate-config/",
)


def load_generate_defaults(path: Path) -> dict:
    """Read [repo] from defaults config for clone URL and branch names."""
    parser = configparser.ConfigParser(interpolation=configparser.ExtendedInterpolation())
    parser.optionxform = str
    if not path.exists():
        raise ValueError(f"defaults file not found: {path}")
    parser.read(path, encoding="utf-8")
    if "repo" not in parser:
        raise ValueError(f"{path} missing [repo] section")
    sec = parser["repo"]
    push_url = (sec.get("push_url") or "").strip()
    if not push_url:
        raise ValueError(f"{path} [repo] missing push_url")
    rel_b = (
        sec.get("release_branch")
        or sec.get("production_branch")
        or sec.get("prod_branch")
        or ""
    ).strip()
    if not rel_b:
        raise ValueError(
            f"{path} [repo] missing release_branch or production_branch"
        )
    dev_b = (sec.get("develop_branch") or "").strip()
    if not dev_b:
        raise ValueError(f"{path} [repo] missing develop_branch")
    name = (sec.get("name") or "target-repo").strip()
    return {
        "name": name,
        "release_branch": rel_b,
        "develop_branch": dev_b,
    }


def branch_clone_path(repo_root: Path, branch: str) -> Path:
    """Path under .generate-config/<branch_parts...> for a git ref like develop/kch_develop."""
    p = repo_root / ".generate-config"
    for part in branch.split("/"):
        if part:
            p = p / part
    return p


def _run_git(args: List[str], cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=str(cwd) if cwd else None, check=True)


def ensure_git_clone(repo_root: Path, remote_url: str, branch: str, dest: Path) -> None:
    """Clone or update a single-branch checkout at dest."""
    git_dir = dest / ".git"
    if git_dir.exists():
        print(f"[clone] update existing {dest}")
        _run_git(["git", "-C", str(dest), "fetch", "origin"], cwd=None)
        _run_git(["git", "-C", str(dest), "checkout", branch], cwd=None)
        pr = subprocess.run(
            ["git", "-C", str(dest), "pull", "--ff-only"],
            cwd=None,
        )
        if pr.returncode != 0:
            print(
                f"[clone] warning: pull --ff-only failed (rc={pr.returncode}); "
                "try removing the directory and re-run",
                file=sys.stderr,
            )
        return

    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"[clone] {remote_url} (branch {branch}) -> {dest}")
    shallow = subprocess.run(
        [
            "git",
            "clone",
            "--branch",
            branch,
            "--single-branch",
            "--depth",
            "1",
            remote_url,
            str(dest),
        ],
        cwd=None,
    )
    if shallow.returncode != 0:
        _run_git(
            ["git", "clone", "--branch", branch, "--single-branch", remote_url, str(dest)],
            cwd=None,
        )


def ensure_gitignore_entries(repo_root: Path, entries: Sequence[str]) -> None:
    gi = repo_root / ".gitignore"
    prev = ""
    if gi.exists():
        prev = gi.read_text(encoding="utf-8")
    existing_lines = set(prev.splitlines())
    to_add = [e for e in entries if e and e not in existing_lines]
    if not to_add:
        print("[gitignore]")
        print("- skip: entries already present")
        return
    with gi.open("a", encoding="utf-8") as fp:
        if prev and not prev.endswith("\n"):
            fp.write("\n")
        fp.write(f"\n{GITIGNORE_MARKER}\n")
        for line in to_add:
            fp.write(f"{line}\n")
    print("[gitignore]")
    print(f"- appended ({gi}): {', '.join(to_add)}")


def _git_config_get(repo_root: Path, key: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo_root), "config", "--get", key],
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def detect_repo_remote(repo_root: Path) -> tuple[str, str]:
    current_branch = _git_config_get(repo_root, "init.defaultBranch")
    head = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "--abbrev-ref", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    if head.returncode == 0 and head.stdout.strip() and head.stdout.strip() != "HEAD":
        current_branch = head.stdout.strip()

    remote_name = ""
    if current_branch:
        remote_name = _git_config_get(repo_root, f"branch.{current_branch}.remote")
    if not remote_name:
        remote_name = _git_config_get(repo_root, "remote.pushDefault")
    if not remote_name:
        remote_name = "origin"

    push_url = _git_config_get(repo_root, f"remote.{remote_name}.pushurl")
    if not push_url:
        push_url = _git_config_get(repo_root, f"remote.{remote_name}.url")

    if not push_url:
        raise ValueError(
            f"cannot detect push_url from .git/config (remote={remote_name})"
        )
    return remote_name, push_url


def generate_config(
    output_path: Path,
    release_dir: Path,
    develop_dir: Path,
    repo_name: str,
    remote_name: str,
    push_url: str,
    release_branch: str,
    develop_branch: str,
    include_version_diff_rules: bool,
) -> None:
    if not release_dir.exists() or not develop_dir.exists():
        raise ValueError("release/develop directory not found")

    release_files = _discover_text_files(release_dir)
    generated_rules: List[Rule] = []
    skipped_version_build_only = 0
    skipped_ambiguous_rules = 0
    for rel_file in release_files:
        rel_path = rel_file.relative_to(release_dir)
        other = develop_dir / rel_path
        if not other.exists() or not other.is_file() or not is_text_file(other):
            continue
        release_text = rel_file.read_text(encoding="utf-8", errors="ignore")
        develop_text = other.read_text(encoding="utf-8", errors="ignore")
        if release_text == develop_text:
            continue
        release_lines = release_text.splitlines(keepends=True)
        develop_lines = develop_text.splitlines(keepends=True)
        file_rules = _extract_replace_rules(str(rel_path), release_lines, develop_lines)
        for rule in file_rules:
            if (
                not include_version_diff_rules
                and _is_version_or_build_only_change(rule.release, rule.develop)
            ):
                skipped_version_build_only += 1
                continue
            # Keep only deterministic hunks:
            # if a token appears multiple times, apply-mode may hit unintended locations.
            if (
                _count_line_aligned_occurrences(release_text, rule.release) != 1
                or _count_line_aligned_occurrences(develop_text, rule.develop) != 1
            ):
                skipped_ambiguous_rules += 1
                continue
            generated_rules.append(rule)

    if not generated_rules:
        raise ValueError("no reversible replace rules found from directory diff")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as fp:
        fp.write("[repo]\n")
        fp.write(f"name = {repo_name}\n")
        fp.write(f"push_url = {push_url}\n")
        fp.write(f"remote_name = {remote_name}\n")
        fp.write(f"release_branch = {release_branch}\n")
        fp.write(f"develop_branch = {develop_branch}\n\n")
        fp.write("# Generated by switch.sh --mode generate-config\n")
        fp.write(
            "# Rules include only reversible replace hunks (replace opcodes, no insert/delete-only hunks).\n\n"
        )
        for rule in generated_rules:
            fp.write(f"[rule.{rule.name}]\n")
            fp.write(f"file = {rule.file}\n")
            fp.write(f"release = {_make_multiline(rule.release)}\n")
            fp.write(f"develop = {_make_multiline(rule.develop)}\n\n")
    print("[Generated Config]")
    print(f"- output: {output_path}")
    print(f"- rules:  {len(generated_rules)}")
    if not include_version_diff_rules:
        print(f"- skipped version/build-only rules: {skipped_version_build_only}")
    print(f"- skipped ambiguous rules: {skipped_ambiguous_rules}")


def compare_rules(repo_dir: Path, rules: List[Rule]) -> None:
    release_matches = 0
    develop_matches = 0
    for rule in rules:
        file_path = repo_dir / rule.file
        if not file_path.exists():
            continue
        content = file_path.read_text(encoding="utf-8")
        if rule.release in content:
            release_matches += 1
        if rule.develop in content:
            develop_matches += 1
    print("[Compare]")
    print(f"- repository: {repo_dir}")
    print(f"- rules: {len(rules)}")
    print(f"- release tokens matched: {release_matches}")
    print(f"- develop tokens matched: {develop_matches}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Develop/release switch helper")
    parser.add_argument(
        "--config",
        default=None,
        help="Path to switch config (default: <repo-root>/dev_switch.config)",
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Current repository root where patch apply is executed",
    )
    parser.add_argument(
        "--mode",
        choices=["compare", "develop", "release", "generate-config"],
        default="compare",
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview only")
    parser.add_argument("--release-dir", help="release baseline directory (optional if using --defaults-file clone)")
    parser.add_argument("--develop-dir", help="develop baseline directory (optional if using --defaults-file clone)")
    parser.add_argument(
        "--defaults-file",
        default="dev_switch.config.default",
        help=(
            "Path to INI with [repo] push_url, release/production_branch, develop_branch; "
            "used to git clone into .generate-config/... when release/develop dirs are omitted"
        ),
    )
    parser.add_argument("--repo-name", default=None)
    parser.add_argument("--release-branch", default=None)
    parser.add_argument("--develop-branch", default=None)
    parser.add_argument(
        "--include-version-diff-rules",
        action="store_true",
        help="Include rules that only change version/build-number lines (default: skip them)",
    )
    return parser.parse_args()


def _resolve_config_path(args: argparse.Namespace) -> Path:
    repo_root = Path(args.repo_root).resolve()
    if args.config:
        p = Path(args.config).expanduser()
        return p if p.is_absolute() else (repo_root / p).resolve()
    return repo_root / "dev_switch.config"


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    config_path = _resolve_config_path(args)

    if args.mode == "generate-config":
        defaults_path = Path(args.defaults_file)
        if not defaults_path.is_absolute():
            defaults_path = (repo_root / defaults_path).resolve()

        has_rel = bool(args.release_dir)
        has_dev = bool(args.develop_dir)
        if has_rel ^ has_dev:
            raise ValueError(
                "supply both --release-dir and --develop-dir, or neither (for defaults clone)"
            )

        if args.release_dir and args.develop_dir:
            release_dir = Path(args.release_dir).resolve()
            develop_dir = Path(args.develop_dir).resolve()
            remote_name, push_url = detect_repo_remote(repo_root)
            meta = {
                "name": args.repo_name or repo_root.name,
                "remote_name": remote_name,
                "push_url": push_url,
                "release_branch": args.release_branch or "release",
                "develop_branch": args.develop_branch or "develop",
            }
            if args.dry_run:
                print("[Dry-run] generate-config plan")
                print(f"- output: {config_path}")
                print("- source: local directories (--release-dir/--develop-dir)")
                print(f"- release_dir: {release_dir}")
                print(f"- develop_dir: {develop_dir}")
                print(f"- repo_name: {meta['name']}")
                print(f"- remote_name: {meta['remote_name']}")
                print(f"- push_url: {meta['push_url']}")
                print(f"- release_branch(meta): {meta['release_branch']}")
                print(f"- develop_branch(meta): {meta['develop_branch']}")
                print(
                    "- include_version_diff_rules: "
                    f"{args.include_version_diff_rules}"
                )
                print("- no changes applied (no clone, no config write, no .gitignore update)")
                return 0
        else:
            remote_name, push_url = detect_repo_remote(repo_root)
            if args.release_branch and args.develop_branch:
                meta = {
                    "name": args.repo_name or repo_root.name,
                    "remote_name": remote_name,
                    "push_url": push_url,
                    "release_branch": args.release_branch,
                    "develop_branch": args.develop_branch,
                }
            else:
                meta = load_generate_defaults(defaults_path)
                meta["remote_name"] = remote_name
                meta["push_url"] = push_url
                if args.release_branch:
                    meta["release_branch"] = args.release_branch
                if args.develop_branch:
                    meta["develop_branch"] = args.develop_branch
            release_dir = branch_clone_path(repo_root, meta["release_branch"])
            develop_dir = branch_clone_path(repo_root, meta["develop_branch"])
            if args.dry_run:
                print("[Dry-run] generate-config plan")
                print(f"- output: {config_path}")
                print("- source: git clone into .generate-config (preview only)")
                print(f"- repo_root: {repo_root}")
                print(f"- release_branch: {meta['release_branch']}")
                print(f"- develop_branch: {meta['develop_branch']}")
                print(f"- remote_name: {meta['remote_name']}")
                print(f"- push_url: {meta['push_url']}")
                print(f"- release_clone_path: {release_dir}")
                print(f"- develop_clone_path: {develop_dir}")
                print(
                    "- include_version_diff_rules: "
                    f"{args.include_version_diff_rules}"
                )
                print("- no changes applied (no clone, no config write, no .gitignore update)")
                return 0
            ensure_git_clone(repo_root, meta["push_url"], meta["release_branch"], release_dir)
            ensure_git_clone(repo_root, meta["push_url"], meta["develop_branch"], develop_dir)

        generate_config(
            output_path=config_path,
            release_dir=release_dir,
            develop_dir=develop_dir,
            repo_name=meta["name"],
            remote_name=meta["remote_name"],
            push_url=meta["push_url"],
            release_branch=meta["release_branch"],
            develop_branch=meta["develop_branch"],
            include_version_diff_rules=args.include_version_diff_rules,
        )
        ensure_gitignore_entries(repo_root, list(GITIGNORE_ENTRIES_DEFAULT))
        return 0

    if not config_path.exists():
        raise ValueError(
            f"config not found: {config_path} "
            "(pass --config or place dev_switch.config at repo root)"
        )

    rules = read_config(config_path)
    repo_dir = repo_root
    if args.mode == "compare":
        compare_rules(repo_dir, rules)
        return 0
    if args.mode in ("develop", "release"):
        apply_rules(
            repo_dir=repo_dir,
            rules=rules,
            mode=args.mode,
            dry_run=args.dry_run,
        )
        return 0
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # pragma: no cover
        print(f"[ERROR] {exc}", file=sys.stderr)
        sys.exit(1)

PY
  PY_SCRIPT="$py_tmp"
}

create_embedded_py_script

# Execute against the repository where this command is run.
# Fallback to current directory if not inside a git repo.
if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  REPO_ROOT="$(pwd)"
fi

ZIP_NAME="dev_switch.config.zip"
CFG_NAME="dev_switch.config"
ZIP_FILE="$REPO_ROOT/$ZIP_NAME"
DEFAULT_CFG="$REPO_ROOT/$CFG_NAME"
# Fixed password for encrypted zip (see README; rotate for your org if needed)
ZIP_PASSWORD="abc123"

usage() {
  cat <<'EOF'
Usage:
  switch.sh --mode {develop|release|compare|verify-develop} [--config PATH] [--dry-run]
  switch.sh --mode generate-config [--config PATH] [--defaults-file PATH] [--release-dir PATH] [--develop-dir PATH] [--release-branch BRANCH] [--develop-branch BRANCH] [--include-version-diff-rules]
  switch.sh --mode verify-develop [--release-branch BRANCH] [--develop-branch BRANCH] [--config PATH]

generate-config without --release-dir/--develop-dir:
  Reads dev_switch.config.default next to this script ([repo] push_url, branches),
  clones into REPO_ROOT/.generate-config/<branch_path>/ for each branch, then diffs.

Without --config:
  Uses <repo-root>/dev_switch.config when that file exists.
  If only dev_switch.config.zip is present, rules are read from the zip (develop: extracts before apply).

Examples:
  switch.sh --mode compare
  switch.sh --mode develop --dry-run
  switch.sh --mode release
  switch.sh --mode generate-config
EOF
}

CONFIG=""
MODE=""
RELEASE_DIR=""
DEVELOP_DIR=""
RELEASE_BRANCH=""
DEVELOP_BRANCH=""
DEFAULTS_FILE=""
DRY_RUN=""
INCLUDE_VERSION_DIFF_RULES=""
VERIFY_BACKUP_NAME="dev_switch.config.try1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG="$2"; shift 2 ;;
    --mode)
      MODE="$2"; shift 2 ;;
    --release-dir)
      RELEASE_DIR="$2"; shift 2 ;;
    --develop-dir)
      DEVELOP_DIR="$2"; shift 2 ;;
    --release-branch)
      RELEASE_BRANCH="$2"; shift 2 ;;
    --develop-branch)
      DEVELOP_BRANCH="$2"; shift 2 ;;
    --defaults-file)
      DEFAULTS_FILE="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN="--dry-run"; shift ;;
    --include-version-diff-rules)
      INCLUDE_VERSION_DIFF_RULES="--include-version-diff-rules"; shift ;;
    --verify-backup-name)
      VERIFY_BACKUP_NAME="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "${MODE:-}" ]]; then
  MODE="compare"
fi

if [[ "$MODE" == "generate-config" ]]; then
  OUT_CFG="${CONFIG:-$DEFAULT_CFG}"
  GEN_EXTRA=()
  [[ -n "${RELEASE_DIR:-}" ]] && GEN_EXTRA+=(--release-dir "$RELEASE_DIR")
  [[ -n "${DEVELOP_DIR:-}" ]] && GEN_EXTRA+=(--develop-dir "$DEVELOP_DIR")
  [[ -n "${RELEASE_BRANCH:-}" ]] && GEN_EXTRA+=(--release-branch "$RELEASE_BRANCH")
  [[ -n "${DEVELOP_BRANCH:-}" ]] && GEN_EXTRA+=(--develop-branch "$DEVELOP_BRANCH")
  if [[ -n "${DEFAULTS_FILE:-}" ]]; then
    GEN_EXTRA+=(--defaults-file "$DEFAULTS_FILE")
  else
    GEN_EXTRA+=(--defaults-file "$SCRIPT_DIR/dev_switch.config.default")
  fi
  exec python3 "$PY_SCRIPT" \
    --config "$OUT_CFG" \
    --mode generate-config \
    --repo-root "$REPO_ROOT" \
    ${DRY_RUN} \
    ${INCLUDE_VERSION_DIFF_RULES} \
    "${GEN_EXTRA[@]}"
fi

if [[ "$MODE" == "verify-develop" ]]; then
  if [[ "${DRY_RUN}" == "--dry-run" ]]; then
    echo "verify-develop does not support --dry-run" >&2
    exit 1
  fi

  CFG_FOR_VERIFY="${CONFIG:-$DEFAULT_CFG}"
  if [[ ! -f "$CFG_FOR_VERIFY" ]]; then
    echo "verify-develop requires existing config file: $CFG_FOR_VERIFY" >&2
    exit 1
  fi

  BACKUP_PATH="$REPO_ROOT/$VERIFY_BACKUP_NAME"
  if [[ -e "$BACKUP_PATH" ]]; then
    echo "backup already exists, remove or rename first: $BACKUP_PATH" >&2
    exit 1
  fi

  mv "$CFG_FOR_VERIFY" "$BACKUP_PATH"
  echo "[verify] backup config: $CFG_FOR_VERIFY -> $BACKUP_PATH"

  python3 "$PY_SCRIPT" \
    --config "$BACKUP_PATH" \
    --mode develop \
    --repo-root "$REPO_ROOT"

  TMP_DIR="$(mktemp -d -t dev_switch_verify.XXXXXX)"
  TMP_RELEASE_DIR="$TMP_DIR/release"
  TMP_GENERATED_CFG="$TMP_DIR/dev_switch.generated.config"
  mkdir -p "$TMP_RELEASE_DIR"

  cleanup_verify_tmp() {
    rm -rf "$TMP_DIR"
  }
  trap cleanup_verify_tmp EXIT

  REMOTE_NAME="$(git -C "$REPO_ROOT" config --get "branch.$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD).remote" || true)"
  if [[ -z "$REMOTE_NAME" ]]; then
    REMOTE_NAME="$(git -C "$REPO_ROOT" config --get remote.pushDefault || true)"
  fi
  if [[ -z "$REMOTE_NAME" ]]; then
    REMOTE_NAME="origin"
  fi
  REMOTE_URL="$(git -C "$REPO_ROOT" config --get "remote.$REMOTE_NAME.pushurl" || true)"
  if [[ -z "$REMOTE_URL" ]]; then
    REMOTE_URL="$(git -C "$REPO_ROOT" config --get "remote.$REMOTE_NAME.url" || true)"
  fi
  if [[ -z "$REMOTE_URL" ]]; then
    echo "cannot detect remote URL from git config" >&2
    exit 1
  fi

  VERIFY_RELEASE_BRANCH="$RELEASE_BRANCH"
  VERIFY_DEVELOP_BRANCH="$DEVELOP_BRANCH"
  if [[ -z "$VERIFY_RELEASE_BRANCH" || -z "$VERIFY_DEVELOP_BRANCH" ]]; then
    readarray -t CFG_META < <(awk -F'=' '
      /^\[repo\]/{in_repo=1; next}
      /^\[/{in_repo=0}
      in_repo && $1 ~ /^[[:space:]]*release_branch[[:space:]]*$/ {
        v=$2; sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v
      }
      in_repo && $1 ~ /^[[:space:]]*develop_branch[[:space:]]*$/ {
        v=$2; sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v
      }
    ' "$BACKUP_PATH")
    if [[ -z "$VERIFY_RELEASE_BRANCH" ]]; then
      VERIFY_RELEASE_BRANCH="${CFG_META[0]:-}"
    fi
    if [[ -z "$VERIFY_DEVELOP_BRANCH" ]]; then
      VERIFY_DEVELOP_BRANCH="${CFG_META[1]:-}"
    fi
  fi
  if [[ -z "$VERIFY_RELEASE_BRANCH" ]]; then
    echo "verify-develop needs --release-branch or release_branch in config" >&2
    exit 1
  fi
  if [[ -z "$VERIFY_DEVELOP_BRANCH" ]]; then
    VERIFY_DEVELOP_BRANCH="develop"
  fi

  echo "[verify] snapshot remote release branch: $VERIFY_RELEASE_BRANCH"
  git -C "$REPO_ROOT" archive --remote="$REMOTE_URL" "$VERIFY_RELEASE_BRANCH" | tar -x -C "$TMP_RELEASE_DIR"

  python3 "$PY_SCRIPT" \
    --mode generate-config \
    --config "$TMP_GENERATED_CFG" \
    --repo-root "$REPO_ROOT" \
    --release-dir "$TMP_RELEASE_DIR" \
    --develop-dir "$REPO_ROOT" \
    --release-branch "$VERIFY_RELEASE_BRANCH" \
    --develop-branch "$VERIFY_DEVELOP_BRANCH"

  VERIFY_RESULT="$(python3 - "$PY_SCRIPT" "$BACKUP_PATH" "$TMP_GENERATED_CFG" "$TMP_RELEASE_DIR" "$REPO_ROOT" <<'PY'
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

py_script = Path(sys.argv[1]).resolve()
backup = Path(sys.argv[2]).resolve()
generated = Path(sys.argv[3]).resolve()
release_root = Path(sys.argv[4]).resolve()
develop_root = Path(sys.argv[5]).resolve()

spec = importlib.util.spec_from_file_location("switch_embedded", str(py_script))
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot import parser from {py_script}")
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

def norm_block(block: str) -> str:
    return "\n".join(line.lstrip() for line in block.splitlines()).strip()

def key_of(rule) -> tuple[str, str, str]:
    return (rule.file, norm_block(rule.release), norm_block(rule.develop))

def to_rules(path: Path):
    rules = mod.read_config(path)
    return rules, {key_of(r): r for r in rules}

def classify_missing(rule, release_cache, develop_cache):
    file_path = rule.file
    if file_path not in release_cache:
        rpath = release_root / file_path
        release_cache[file_path] = (
            rpath.read_text(encoding="utf-8", errors="ignore") if rpath.exists() else None
        )
    if file_path not in develop_cache:
        dpath = develop_root / file_path
        develop_cache[file_path] = (
            dpath.read_text(encoding="utf-8", errors="ignore") if dpath.exists() else None
        )
    release_text = release_cache[file_path]
    develop_text = develop_cache[file_path]

    if release_text is None and develop_text is None:
        return "file_missing_both"
    if release_text is None:
        return "file_missing_release"
    if develop_text is None:
        return "file_missing_develop"

    src_cnt = mod._count_line_aligned_occurrences(release_text, rule.release)
    dst_cnt = mod._count_line_aligned_occurrences(develop_text, rule.develop)
    if src_cnt == 0 and dst_cnt == 0:
        return "stale_rule_both_missing"
    if src_cnt == 0:
        return "release_token_missing"
    if dst_cnt == 0:
        return "develop_token_missing"
    if src_cnt > 1 or dst_cnt > 1:
        return "ambiguous_token"
    return "normalized_only"

old_rules, old_map = to_rules(backup)
new_rules, new_map = to_rules(generated)

old_set = set(old_map.keys())
new_set = set(new_map.keys())

extra_keys = sorted(new_set - old_set)
missing_keys = sorted(old_set - new_set)

reason_counter = Counter()
reason_samples = {}
release_cache = {}
develop_cache = {}
for key in missing_keys:
    rule = old_map[key]
    reason = classify_missing(rule, release_cache, develop_cache)
    reason_counter[reason] += 1
    reason_samples.setdefault(reason, []).append(rule.name)

extra_names = [new_map[k].name for k in extra_keys]
missing_names = [old_map[k].name for k in missing_keys]

def cap(items, n=20):
    return items[:n]

payload = {
    "ok": len(extra_keys) == 0,
    "generated_rules": len(new_set),
    "backup_rules": len(old_set),
    "missing_rules": len(missing_keys),
    "extra_rules": len(extra_keys),
    "missing_rule_names": cap(missing_names, 40),
    "extra_rule_names": cap(extra_names, 40),
    "missing_reason_counts": dict(reason_counter),
    "missing_reason_samples": {k: cap(v, 10) for k, v in sorted(reason_samples.items())},
    "missing_files": sorted({x[0] for x in missing_keys})[:20],
    "extra_files": sorted({x[0] for x in extra_keys})[:20],
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"

  VERIFY_OK="$(python3 - "$VERIFY_RESULT" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
print("1" if obj.get("ok") else "0")
PY
)"

  echo "[verify] semantic compare: $VERIFY_RESULT"
  if [[ "$VERIFY_OK" != "1" ]]; then
    echo "[verify] failed: generated config has rules not present in backup" >&2
    exit 2
  fi

  cp "$TMP_GENERATED_CFG" "$DEFAULT_CFG"
  echo "[verify] wrote regenerated config: $DEFAULT_CFG"
  exit 0
fi

TMP_CFG=""
cleanup_tmp() {
  if [[ -n "${TMP_CFG:-}" ]]; then
    rm -f "$TMP_CFG"
  fi
  if [[ -n "${PY_SCRIPT:-}" && -f "${PY_SCRIPT}" ]]; then
    rm -f "$PY_SCRIPT"
  fi
}
trap cleanup_tmp EXIT

PYTHON_CFG=""

if [[ -n "${CONFIG:-}" ]]; then
  PYTHON_CFG="$CONFIG"
elif [[ "$MODE" == "develop" && "$DRY_RUN" != "--dry-run" && -f "$ZIP_FILE" ]]; then
  unzip -o -P "$ZIP_PASSWORD" "$ZIP_FILE" -d "$REPO_ROOT"
  PYTHON_CFG="$DEFAULT_CFG"
elif [[ "$MODE" == "develop" && "$DRY_RUN" == "--dry-run" && -f "$ZIP_FILE" ]]; then
  TMP_CFG="$(mktemp -t dev_switch_cfg.XXXXXX)"
  unzip -p -P "$ZIP_PASSWORD" "$ZIP_FILE" "$CFG_NAME" >"$TMP_CFG"
  PYTHON_CFG="$TMP_CFG"
  echo "[preview] rules from $ZIP_FILE (dry-run)"
elif [[ -f "$DEFAULT_CFG" ]]; then
  PYTHON_CFG="$DEFAULT_CFG"
elif [[ -f "$ZIP_FILE" ]]; then
  TMP_CFG="$(mktemp -t dev_switch_cfg.XXXXXX)"
  unzip -p -P "$ZIP_PASSWORD" "$ZIP_FILE" "$CFG_NAME" >"$TMP_CFG"
  PYTHON_CFG="$TMP_CFG"
  echo "[info] rules from $ZIP_FILE"
else
  echo "No config: place $CFG_NAME at repo root, pass --config PATH, or add $ZIP_NAME." >&2
  exit 1
fi

set +e
python3 "$PY_SCRIPT" \
  --config "$PYTHON_CFG" \
  --mode "$MODE" \
    --repo-root "$REPO_ROOT" \
  ${DRY_RUN}
PY_EXIT=$?
set -e

if [[ "$MODE" == "release" && "$DRY_RUN" != "--dry-run" && "$PY_EXIT" -eq 0 ]]; then
  if [[ -f "$DEFAULT_CFG" ]]; then
    (
      cd "$REPO_ROOT"
      rm -f "$ZIP_NAME"
      zip -P "$ZIP_PASSWORD" "$ZIP_NAME" "$CFG_NAME"
      rm -f "$CFG_NAME"
    )
    echo "[release] archived $CFG_NAME -> $ZIP_NAME (zip -P, password is set in switch.sh)"
  fi
fi

exit "$PY_EXIT"
