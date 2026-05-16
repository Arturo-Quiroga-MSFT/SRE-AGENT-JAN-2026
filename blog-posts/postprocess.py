#!/usr/bin/env python3
"""Post-process the pandoc-generated HTML so tables survive the Tech Community editor.

What it does, in order, to BLOG-SRE-AGENT-PRIVATE-AKS-DRAFT.html (or the file passed as argv[1]):
  1. Shortens the third header of table 1 ("SRE Agent access method" -> "SRE Agent access")
     so it doesn't wrap vertically in the Khoros/TinyMCE editor.
  2. For each <table> ... </table> block (in document order), it:
       - replaces the bare <table> with <table style="width:100%; border-collapse:collapse;"
         border="1" cellpadding="6">
       - strips the <colgroup>...</colgroup> block (Tech Community drops it anyway)
       - inserts inline style="width:N%;" on every <th> in the first <thead><tr>
       - styles the header row with a light-grey background
  3. Writes the file back in place.

Run after every pandoc render:
    pandoc BLOG-SRE-AGENT-PRIVATE-AKS-DRAFT.md \
        --standalone --css preview.css \
        --metadata title="..." \
        -o BLOG-SRE-AGENT-PRIVATE-AKS-DRAFT.html
    python postprocess.py

Width configs are positional (table 1, 2, 3, 4). If you add/remove tables in the
markdown, update TABLE_WIDTHS below.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Column widths (in %) for each table, in document order.
TABLE_WIDTHS: list[list[int]] = [
    [26, 18, 28, 28],          # 1. Security spectrum
    [5, 25, 15, 22, 33],       # 2. Four-role pattern
    [28, 30, 42],              # 3. App ID vs Object ID
    [38, 37, 25],              # 4. Capabilities matrix
]

NEW_TABLE_OPEN = (
    '<table style="width:100%; border-collapse:collapse;" '
    'border="1" cellpadding="6">'
)
HEADER_ROW_OPEN = '<tr style="background:#f2f2f2;">'

TABLE_BLOCK_RE = re.compile(r"<table\b[^>]*>.*?</table>", re.DOTALL)
COLGROUP_RE = re.compile(r"<colgroup>.*?</colgroup>\s*", re.DOTALL)
THEAD_TR_RE = re.compile(r"(<thead>\s*)<tr[^>]*>(.*?)</tr>", re.DOTALL)
TH_RE = re.compile(r"<th\b[^>]*>(.*?)</th>", re.DOTALL)


def fix_table(block: str, widths: list[int]) -> str:
    # Replace the opening <table ...> with the safe version.
    block = re.sub(r"<table\b[^>]*>", NEW_TABLE_OPEN, block, count=1)
    # Drop any <colgroup>.
    block = COLGROUP_RE.sub("", block)

    # Inject widths into the <th> cells of the first header row.
    def _replace_header(match: re.Match[str]) -> str:
        thead_open, row_inner = match.group(1), match.group(2)
        ths = TH_RE.findall(row_inner)
        if len(ths) != len(widths):
            print(
                f"  WARN: header has {len(ths)} <th> but {len(widths)} widths configured; "
                "skipping width injection for this table.",
                file=sys.stderr,
            )
            return match.group(0)
        new_ths = "".join(
            f'<th style="width:{w}%;">{cell}</th>' for w, cell in zip(widths, ths)
        )
        return f"{thead_open}{HEADER_ROW_OPEN}{new_ths}</tr>"

    block, n = THEAD_TR_RE.subn(_replace_header, block, count=1)
    if n == 0:
        print("  WARN: no <thead><tr>...</tr> found in table block.", file=sys.stderr)
    return block


def process(path: Path) -> None:
    html = path.read_text(encoding="utf-8")

    # 1. Header text shortening for table 1.
    html = html.replace("SRE Agent access method", "SRE Agent access")

    # 2. Walk tables in document order and apply widths.
    matches = list(TABLE_BLOCK_RE.finditer(html))
    if len(matches) != len(TABLE_WIDTHS):
        print(
            f"WARN: found {len(matches)} <table> blocks but {len(TABLE_WIDTHS)} width "
            "configs. Update TABLE_WIDTHS in postprocess.py.",
            file=sys.stderr,
        )

    # Rebuild by splicing fixed blocks back in (reverse order to keep indices valid).
    out = html
    for i, match in enumerate(reversed(matches)):
        idx = len(matches) - 1 - i
        if idx >= len(TABLE_WIDTHS):
            continue
        widths = TABLE_WIDTHS[idx]
        print(f"Fixing table {idx + 1} (widths={widths})")
        fixed = fix_table(match.group(0), widths)
        out = out[: match.start()] + fixed + out[match.end():]

    path.write_text(out, encoding="utf-8")
    print(f"Wrote {path}")


def main() -> int:
    default = Path(__file__).parent / "BLOG-SRE-AGENT-PRIVATE-AKS-DRAFT.html"
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    if not target.exists():
        print(f"ERROR: {target} not found", file=sys.stderr)
        return 1
    process(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
