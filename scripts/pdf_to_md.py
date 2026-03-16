#!/usr/bin/env python3
"""Convert PDF files in meetings-recaps/ to Markdown text files."""

import sys
import os
import glob

try:
    import fitz  # pymupdf
except ImportError:
    print("pymupdf not installed. Installing...")
    os.system(f"{sys.executable} -m pip install pymupdf")
    import fitz

RECAPS_DIR = os.path.join(os.path.dirname(__file__), "..", "meetings-recaps")


def pdf_to_markdown(pdf_path):
    """Extract text from a PDF and write it to a .md file."""
    doc = fitz.open(pdf_path)
    basename = os.path.splitext(os.path.basename(pdf_path))[0]
    # Sanitize filename
    safe_name = basename.replace(" ", "-").replace("(", "").replace(")", "")
    out_path = os.path.join(RECAPS_DIR, safe_name + ".md")

    lines = []
    lines.append(f"# {basename}\n")
    lines.append(f"*Source: {os.path.basename(pdf_path)}*\n")
    lines.append(f"*Pages: {len(doc)}*\n")
    lines.append("---\n")

    for page_num, page in enumerate(doc, 1):
        text = page.get_text("text")
        if text.strip():
            lines.append(f"\n## Page {page_num}\n")
            lines.append(text)

    doc.close()

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"  -> {out_path} ({len(lines)} lines)")
    return out_path


def main():
    pdfs = glob.glob(os.path.join(RECAPS_DIR, "*.pdf"))
    if not pdfs:
        print("No PDF files found in meetings-recaps/")
        sys.exit(1)

    print(f"Found {len(pdfs)} PDF(s):\n")
    for pdf in sorted(pdfs):
        print(f"Converting: {os.path.basename(pdf)}")
        pdf_to_markdown(pdf)

    print("\nDone.")


if __name__ == "__main__":
    main()
