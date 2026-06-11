---
description: Run the full design pipeline (PRD → MAS → RTL → verification → docs → review) for a new block
---

Run the complete deliverables pipeline defined in CLAUDE.md §3 for the following design request:

$ARGUMENTS

Steps:
1. Derive a snake_case block name from the request and confirm it in one line.
2. P0: delegate to prd-writer. Present the PRD summary and assumptions to me and WAIT for my approval before continuing (unless I wrote "auto-approve" in the request).
3. P1–P5: proceed phase by phase per CLAUDE.md, enforcing every gate in the deliverables matrix (§1), routing fixes between agents as needed.
4. Finish with the release summary: requirement coverage, assumptions, known limitations, and the full list of artifact paths (D1–D9).
