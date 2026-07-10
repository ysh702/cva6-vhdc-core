#!/usr/bin/env python3
"""Extract section-aware evidence from a local IEEE/SCI hardware-paper corpus."""

from __future__ import annotations

import argparse
import csv
import json
import re
import statistics
from collections import Counter
from pathlib import Path

import pypdf


ROMAN = r"(?:I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)"


def clean_text(text: str) -> str:
    replacements = {
        "\ufb00": "ff",
        "\ufb01": "fi",
        "\ufb02": "fl",
        "\ufb03": "ffi",
        "\ufb04": "ffl",
        "\u00ad": "",
        "\u2013": "-",
        "\u2014": "-",
        "\u2212": "-",
        "\u00d7": "x",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = re.sub(r"(?<=\w)-\s*\n\s*(?=[a-z])", "", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)?", text or ""))


def normalize_heading(text: str) -> str:
    text = compact(text)
    text = re.sub(r"\b([A-Z])\s+(?=[A-Z]\b)", r"\1", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def heading_key(text: str) -> str:
    return re.sub(r"[^A-Z]", "", text.upper())


def heading_candidates(lines: list[str]) -> list[dict[str, object]]:
    found: list[dict[str, object]] = []
    patterns = [
        ("roman", re.compile(rf"^({ROMAN})\.\s+(.{{1,100}})$", re.I)),
        ("number", re.compile(r"^(\d+(?:\.\d+)*)\.?\s+([A-Z][A-Za-z0-9 ,:/&()\-]{1,100})$")),
        ("letter", re.compile(r"^([A-Z])\.\s+([A-Z][A-Za-z0-9 ,:/&()\-]{2,100})$")),
    ]
    for index, raw in enumerate(lines):
        line = normalize_heading(raw)
        if len(line) < 4 or len(line) > 130:
            continue
        for kind, pattern in patterns:
            match = pattern.match(line)
            if not match:
                continue
            title = compact(match.group(2))
            label = match.group(1)
            if kind == "number" and int(label.split(".")[0]) > 20:
                continue
            if kind in {"roman", "number"} and len(heading_key(title)) <= 2 and index + 1 < len(lines):
                continuation = compact(lines[index + 1])
                if 2 <= len(continuation) <= 100 and re.search(r"[A-Za-z]{3}", continuation):
                    title = f"{title}{continuation}"
            if kind == "letter" and not re.search(r"[A-Za-z]{3}", title):
                continue
            if any(token in title.upper() for token in ("IEEE TRANSACTIONS", "VOL.", "DOI", "AUTHORS")):
                continue
            if kind == "roman":
                level = 1
            elif kind == "number":
                level = 1 if "." not in label else 2
            else:
                level = 3
            found.append({"line": index, "level": level, "label": label, "title": title, "raw": line})
            break
    deduped: list[dict[str, object]] = []
    seen: set[tuple[str, str]] = set()
    for item in found:
        key = (str(item["label"]).upper(), str(item["title"]).upper())
        if key not in seen:
            deduped.append(item)
            seen.add(key)
    return deduped


def extract_between(text: str, start_patterns: list[str], end_patterns: list[str]) -> str:
    start = None
    for pattern in start_patterns:
        match = re.search(pattern, text, re.I | re.M)
        if match and (start is None or match.end() < start):
            start = match.end()
    if start is None:
        return ""
    end = len(text)
    tail = text[start:]
    for pattern in end_patterns:
        match = re.search(pattern, tail, re.I | re.M)
        if match:
            end = min(end, start + match.start())
    return text[start:end].strip()


def extract_abstract(text: str) -> str:
    first = text[:30000]
    abstract = extract_between(
        first,
        [r"^\s*Abstract\s*[-.:]?\s*"],
        [
            r"^\s*(?:Index Terms|Keywords)\s*[-.:]",
            r"^\s*(?:Manuscript received|Received \d|This work was supported)",
            r"^\s*(?:1|I)\.?\s+I\s*N\s*T\s*R\s*O\s*D\s*U\s*C\s*T\s*I\s*O\s*N",
            r"^\s*(?:1|I)\.?\s+INTRODUCTION",
        ],
    )
    return compact(abstract)


def abstract_from_lines(
    lines: list[str], headings: list[dict[str, object]], fallback: str
) -> str:
    start_line = None
    prefix = ""
    for index, line in enumerate(lines[:500]):
        match = re.search(r"\bAbstract\s*[-.:]?\s*(.*)$", line, re.I)
        if match:
            start_line = index + 1
            prefix = match.group(1)
            break
    if start_line is None:
        return fallback if word_count(fallback) <= 600 else ""
    end_line = min(len(lines), start_line + 250)
    for index in range(start_line, end_line):
        if re.search(
            r"(?:^\s*(?:Index Terms|Keywords|CCS Concepts)\b|\b(?:Received\s+\d|Manuscript received|This work was supported)\b)",
            lines[index],
            re.I,
        ):
            end_line = index
            break
    for heading in headings:
        if int(heading["line"]) >= start_line and "INTRODUCTION" in heading_key(str(heading["title"])):
            end_line = min(end_line, int(heading["line"]))
            break
    result = compact("\n".join([prefix, *lines[start_line:end_line]]))
    result = re.split(
        r"\b(?:Index Terms|Keywords|CCS Concepts|Received\s+\d|Manuscript received|Digital Object Identifier)\b",
        result,
        maxsplit=1,
        flags=re.I,
    )[0].strip()
    return result if word_count(result) <= 600 else ""


def section_slice(text: str, name: str) -> str:
    spaced = {
        "introduction": r"I\s*N\s*T\s*R\s*O\s*D\s*U\s*C\s*T\s*I\s*O\s*N",
        "conclusion": r"C\s*O\s*N\s*C\s*L\s*U\s*S\s*I\s*O\s*N(?:S)?",
    }
    if name == "introduction":
        starts = [
            rf"^\s*(?:1|I)\.?\s+{spaced['introduction']}\s*$",
            r"^\s*(?:1|I)\.?\s+INTRODUCTION\s*$",
        ]
        ends = [
            rf"^\s*(?:2|II)\.?\s+[A-Z][A-Z\s\-]{{2,}}$",
            rf"^\s*II\.\s+",
        ]
    elif name == "conclusion":
        starts = [
            rf"^\s*(?:{ROMAN}|\d+)\.?\s+{spaced['conclusion']}\s*$",
            rf"^\s*(?:{ROMAN}|\d+)\.?\s+CONCLUSION(?:S)?\s*$",
        ]
        ends = [r"^\s*(?:ACKNOWLEDG|REFERENCES|APPENDIX)"]
    else:
        return ""
    return extract_between(text, starts, ends)


def section_from_headings(
    lines: list[str], headings: list[dict[str, object]], keyword: str
) -> str:
    target = heading_key(keyword)
    for position, heading in enumerate(headings):
        if target not in heading_key(str(heading["title"])):
            continue
        start_line = int(heading["line"]) + 1
        current_level = int(heading["level"])
        end_line = len(lines)
        for later in headings[position + 1 :]:
            later_line = int(later["line"])
            if later_line <= start_line:
                continue
            if int(later["level"]) <= current_level:
                end_line = later_line
                break
        return "\n".join(lines[start_line:end_line]).strip()
    return ""


def sentence_split(text: str) -> list[str]:
    compacted = compact(text)
    if not compacted:
        return []
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+(?=[A-Z0-9])", compacted) if len(s.strip()) > 20]


def contribution_excerpt(intro: str) -> str:
    patterns = [
        r"(?:contributions?|novelty)\s+(?:of\s+this\s+(?:article|paper|work)\s+)?(?:are|is|can be summarized as follows)",
        r"(?:this\s+(?:article|paper|work)\s+)?makes?\s+the\s+following\s+contributions?",
        r"our\s+main\s+contributions?",
        r"in\s+summary,\s+we",
    ]
    start = None
    for pattern in patterns:
        match = re.search(pattern, intro, re.I)
        if match:
            start = match.start()
            break
    if start is None:
        for pattern in (r"In this (?:article|paper|work),", r"This (?:article|paper|work) (?:presents|proposes|introduces)"):
            matches = list(re.finditer(pattern, intro, re.I))
            if matches:
                start = matches[-1].start()
                break
    if start is None:
        return ""
    return compact(intro[start : start + 5000])


def paragraph_topics(section: str, limit: int = 14) -> list[str]:
    paragraphs = [compact(p) for p in re.split(r"\n\s*\n", section) if word_count(p) >= 20]
    topics: list[str] = []
    for paragraph in paragraphs[:limit]:
        sentences = sentence_split(paragraph)
        topics.append((sentences[0] if sentences else paragraph)[:500])
    return topics


def classify(filename: str, text: str) -> str:
    name = filename.lower()
    sample = (name + " " + text[:12000].lower())
    if "hyperdimensional" in sample or name.startswith("hdc-") or "tri-hd" in name or "rehdc" in sample:
        return "HDC"
    if (
        "elliptic" in sample
        or "multiscalar" in sample
        or name.startswith("ecc-")
        or "curve25519" in sample
        or name.startswith("fama_")
        or name.startswith("myosotis_")
    ):
        return "ECC/MSM"
    if "homomorphic" in sample or "privacy-preserving" in sample or name.startswith("fusion-") or "encrypted" in sample:
        return "AI-crypto/fusion"
    return "other"


def venue_hint(text: str) -> str:
    first = text[:18000].upper()
    if re.search(r"10\.1\s*109/ACCESS\.", first):
        return "IEEE Access"
    venues = [
        ("TCAS-I", "IEEE TRANSACTIONS ON CIRCUITS AND SYSTEMS-I"),
        ("TCAD", "IEEE TRANSACTIONS ON COMPUTER-AIDED DESIGN"),
        ("TVLSI", "IEEE TRANSACTIONS ON VERY LARGE SCALE INTEGRATION"),
        ("TC", "IEEE TRANSACTIONS ON COMPUTERS"),
        ("TIFS", "IEEE TRANSACTIONS ON INFORMATION FORENSICS"),
        ("IEEE Access", "IEEE ACCESS"),
        ("IEEE Access", "10.1109/ACCESS."),
        ("ACM TECS", "ACM TRANSACTIONS ON EMBEDDED COMPUTING SYSTEMS"),
        ("Electronics", "ELECTRONICS 20"),
        ("Elsevier", "ELSEVIER LTD. ALL RIGHTS RESERVED"),
        ("HPCA", "HIGH PERFORMANCE COMPUTER ARCHITECTURE"),
        ("DAC", "DESIGN AUTOMATION CONFERENCE"),
        ("DAC", "DAC '"),
        ("FPGA conference", "FPGA '"),
        ("ICCAD", "INTERNATIONAL CONFERENCE ON COMPUTER-AIDED DESIGN"),
    ]
    for short, needle in venues:
        if needle in first:
            return short
    return "unresolved"


def source_weight(venue: str) -> str:
    if venue in {"TCAS-I", "TCAD", "TVLSI", "TC"}:
        return "primary-ieee-transactions"
    if venue in {"IEEE Access", "ACM TECS", "Electronics", "Elsevier"}:
        return "secondary-journal"
    return "conference-or-unresolved"


def section_role(title: str) -> str:
    key = heading_key(title)
    rules = [
        ("introduction", ("INTRODUCTION",)),
        ("background-related", ("BACKGROUND", "PRELIMINAR", "RELATEDWORK")),
        ("motivation", ("MOTIVATION",)),
        ("algorithm-method", ("ALGORITHM", "METHOD", "PROTOCOL", "MODEL", "MULTIPLIER")),
        ("architecture-system", ("ARCHITECTURE", "DESIGN", "ENGINE", "PROCESSOR", "COPROCESSOR", "SYSTEM", "HARDWARE", "IMPLEMENTATION")),
        ("software-runtime", ("SOFTWARE", "RUNTIME", "COMPILER", "INSTRUCTIONSET")),
        ("evaluation-results", ("EXPERIMENT", "EVALUATION", "RESULT", "PERFORMANCE", "COMPARISON")),
        ("discussion", ("DISCUSSION",)),
        ("conclusion", ("CONCLUSION",)),
    ]
    for role, needles in rules:
        if any(needle in key for needle in needles):
            return role
    return "other"


def major_section_map(
    lines: list[str], headings: list[dict[str, object]]
) -> list[dict[str, object]]:
    majors = [h for h in headings if int(h["level"]) == 1]
    sections: list[dict[str, object]] = []
    for position, heading in enumerate(majors):
        role = section_role(str(heading["title"]))
        if role == "other":
            continue
        start = int(heading["line"]) + 1
        end = int(majors[position + 1]["line"]) if position + 1 < len(majors) else len(lines)
        body = "\n".join(lines[start:end]).strip()
        sentences = sentence_split(body)
        subsections = [
            str(h["title"])
            for h in headings
            if start <= int(h["line"]) < end and int(h["level"]) > 1
        ]
        sections.append(
            {
                "label": heading["label"],
                "title": heading["title"],
                "role": role,
                "words": word_count(body),
                "subsections": subsections[:24],
                "opening_sentences": sentences[:3],
                "closing_sentences": sentences[-2:] if len(sentences) >= 2 else sentences,
            }
        )
    return sections


def rhetorical_flags(text: str) -> dict[str, int]:
    patterns = {
        "however": r"\bhowever\b",
        "gap": r"\b(?:remain(?:s|ed)?|lack(?:s|ed)?|limited|challenge|bottleneck|underutili[sz]|overhead)\b",
        "propose": r"\b(?:we\s+)?(?:propose|present|introduce|develop|design)\b",
        "result": r"\b(?:results?\s+(?:show|demonstrate)|achieves?|improves?|reduces?|speedup)\b",
        "contribution": r"\bcontributions?\b",
        "limitation": r"\b(?:limitation|future work|does not|cannot|restricted to)\b",
    }
    return {name: len(re.findall(pattern, text, re.I)) for name, pattern in patterns.items()}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()
    pdf_dir = Path(args.pdf_dir)
    out_dir = Path(args.out_dir)
    text_dir = out_dir / "full_text"
    report_dir = out_dir / "paper_reports"
    text_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)

    corpus: list[dict[str, object]] = []
    for pdf in sorted(pdf_dir.glob("*.pdf")):
        reader = pypdf.PdfReader(str(pdf))
        page_texts: list[str] = []
        for page_number, page in enumerate(reader.pages, start=1):
            # Plain extraction preserves IEEE section markers more reliably than
            # layout mode, whose two-column output often joins headings to body text.
            page_text = page.extract_text() or ""
            page_texts.append(f"\n\n===== PAGE {page_number} =====\n\n{page_text}")
        text = clean_text("".join(page_texts))
        (text_dir / f"{pdf.stem}.txt").write_text(text, encoding="utf-8")
        lines = text.splitlines()
        headings = heading_candidates(lines)
        abstract = abstract_from_lines(lines, headings, extract_abstract(text))
        intro = section_from_headings(lines, headings, "INTRODUCTION") or section_slice(text, "introduction")
        conclusion = section_from_headings(lines, headings, "CONCLUSION") or section_slice(text, "conclusion")
        category = classify(pdf.name, text)
        venue = venue_hint(text)
        report = {
            "file": pdf.name,
            "pages": len(reader.pages),
            "metadata_title": str((reader.metadata or {}).get("/Title", "")),
            "category": category,
            "venue_hint": venue,
            "source_weight": source_weight(venue),
            "total_words": word_count(text),
            "abstract_words": word_count(abstract),
            "introduction_words": word_count(intro),
            "conclusion_words": word_count(conclusion),
            "headings": headings,
            "major_sections": major_section_map(lines, headings),
            "abstract": abstract,
            "introduction_topics": paragraph_topics(intro),
            "contribution_excerpt": contribution_excerpt(intro),
            "conclusion": compact(conclusion),
            "abstract_flags": rhetorical_flags(abstract),
            "introduction_flags": rhetorical_flags(intro),
            "fulltext_flags": rhetorical_flags(text),
        }
        (report_dir / f"{pdf.stem}.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        corpus.append(report)

    rows = [
        {
            "file": r["file"],
            "category": r["category"],
            "venue_hint": r["venue_hint"],
            "source_weight": r["source_weight"],
            "pages": r["pages"],
            "total_words": r["total_words"],
            "abstract_words": r["abstract_words"],
            "introduction_words": r["introduction_words"],
            "intro_topic_count": len(r["introduction_topics"]),
            "heading_count": len(r["headings"]),
            "conclusion_words": r["conclusion_words"],
        }
        for r in corpus
    ]
    with (out_dir / "corpus_index.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    valid_abstracts = [int(r["abstract_words"]) for r in corpus if int(r["abstract_words"]) > 0]
    valid_intros = [int(r["introduction_words"]) for r in corpus if int(r["introduction_words"]) > 0]
    summary = {
        "paper_count": len(corpus),
        "category_counts": Counter(str(r["category"]) for r in corpus),
        "venue_counts": Counter(str(r["venue_hint"]) for r in corpus),
        "source_weight_counts": Counter(str(r["source_weight"]) for r in corpus),
        "section_role_counts": Counter(
            str(section["role"])
            for report in corpus
            for section in report["major_sections"]
        ),
        "abstract_words": {
            "count": len(valid_abstracts),
            "min": min(valid_abstracts) if valid_abstracts else 0,
            "median": statistics.median(valid_abstracts) if valid_abstracts else 0,
            "max": max(valid_abstracts) if valid_abstracts else 0,
        },
        "introduction_words": {
            "count": len(valid_intros),
            "min": min(valid_intros) if valid_intros else 0,
            "median": statistics.median(valid_intros) if valid_intros else 0,
            "max": max(valid_intros) if valid_intros else 0,
        },
    }
    (out_dir / "corpus_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, default=dict), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2, default=dict))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
