#!/usr/bin/env python3
"""Generar notas desde FIXES.md por tags; no modifica Git ni publica."""
import argparse
from pathlib import Path
import re
import subprocess

REPOSITORY = Path(__file__).resolve().parent.parent
REGISTER = "FIXES.md"
# Accept the old prefixes when comparing tags created before the unified register.
HEADING = re.compile(r"^### \[((?:GENERAL|APPLE|WINDOWS|FIX|FEAT)-\d+(?:-\d+)?)\](?: \[([^\]]+)\])?\s*-\s*(.+)$", re.MULTILINE)
SCOPES = {"Apple", "Windows", "Compartido"}


def git(*args, root=None):
    result = subprocess.run(["git", *args], cwd=root or REPOSITORY,
                            capture_output=True, text=True, check=True)
    return result.stdout


def get_last_tag(root=None):
    try:
        ref = "HEAD^" if git("tag", "--points-at", "HEAD", root=root).strip() else "HEAD"
        return git("describe", "--tags", "--abbrev=0", ref, root=root).strip()
    except subprocess.CalledProcessError:
        return None


def entries(content):
    matches = list(HEADING.finditer(content))
    result = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(content)
        body = content[match.end():end]
        scope = match.group(2) or {"APPLE": "Apple", "WINDOWS": "Windows"}.get(match.group(1).split("-")[0], "Compartido")
        if scope not in SCOPES:
            raise ValueError(f"Tag de ámbito inválido en {match.group(1)}: {scope}")
        historical = bool(re.search(r"(?im)^- Histórico:\s*sí\b", body)) or "referencia importada" in match.group(3).lower() or "fix histórico" in body.lower()
        aliases = re.findall(r"(?m)^- ID anterior:\s*((?:GENERAL|APPLE|WINDOWS|FIX|FEAT)-\d+)\b", body)
        result.append({"id": match.group(1), "title": match.group(3).strip(), "scope": scope, "historical": historical, "aliases": aliases})
    return result


def extract_fixes_since_tag(last_tag, platform="all", root=None):
    if platform not in ("all", "macos", "windows"):
        raise ValueError(f"Plataforma inválida: {platform}")
    root = Path(root or REPOSITORY)
    file = root / REGISTER
    if not file.exists():
        return []
    current = entries(file.read_text(encoding="utf-8"))
    previous_ids = set()
    if last_tag:
        try:
            for entry in entries(git("show", f"{last_tag}:{REGISTER}", root=root)):
                previous_ids.update([entry["id"], *entry["aliases"]])
        except subprocess.CalledProcessError:
            pass  # The unified register may have been introduced after that tag.
    allowed = SCOPES if platform == "all" else {"Compartido", "Apple" if platform == "macos" else "Windows"}
    return [{"id": entry["id"], "title": entry["title"], "scope": entry["scope"]}
            for entry in current
            if entry["scope"] in allowed and not entry["historical"]
            and not previous_ids.intersection([entry["id"], *entry["aliases"]])]


def generate_markdown(fixes, version):
    lines = [f"### Novedades en Side B v{version}\n"]
    if not fixes:
        lines.append("No hay nuevos fixes registrados para este ámbito desde el último release.")
    else:
        for fix in fixes:
            lines.append(f"- **{fix['title']}** (`{fix['id']}`, {fix['scope']})")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", default="1.0.x")
    parser.add_argument("--platform", choices=("all", "macos", "windows"), default="all")
    args = parser.parse_args()
    print(generate_markdown(extract_fixes_since_tag(get_last_tag(), args.platform), args.version))


if __name__ == "__main__":
    main()
