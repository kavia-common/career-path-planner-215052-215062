# Ingestion Mapping Specifications

This document describes how the provided spreadsheets and role card documents are parsed and normalized into the database schema.

## Source files
- Excel:
  - Role_Navigator_Worksheet.xlsx
  - Competency_mapping.xlsx
  - CA_Role_Adjacency.xlsx
- Text (role cards):
  - Role_Card_*.txt (AppDev, CAIO, CCTO, CDAO, CDO, CInO, CIO, CPTO, CTrO, DigProd, FCTO, Infra, Ops, PMO, etc.)
- Context PDFs (for reference only; not parsed): Sponsor/Talent/Development guides

## Target Tables
- roles (code, name, description)
- competencies (name, category, description)
- role_competencies (role_id, competency_id, required_level, weight, notes)
- role_adjacency (from_role_id, to_role_id, strength, rationale)
- role_cards (role_id, thesis, scope, decisions, narrative, conversations, toolkit, signals, artifacts, raw_text, source_file)

## Normalization Rules
- Role `code`: 
  - Derived from either an explicit code column (if present) or from role name slug (lowercase, alnum + underscores), e.g., "Chief Information Officer" -> "cio".
  - Role names are title-cased using the document heading; fallback to sheet role name.
- Competency uniqueness is by `name` (case-insensitive); normalize whitespace, title-case significant words.
- Levels:
  - Map free-text to enum values:
    - beginner: ["beginner", "basic", "foundational", "novice", "L1"]
    - intermediate: ["intermediate", "working", "practitioner", "L2"]
    - advanced: ["advanced", "expert", "authority", "L3", "senior"]
  - Default to `intermediate` when ambiguous.
- Weights:
  - If a numeric weight or priority is provided, store as weight (0.0–10.0). Default is 1.0.
- Role adjacency:
  - Interpret adjacency matrix or edge list:
    - If matrix, treat non-empty/positive numeric cells as edges with `strength` ∈ [0, 5].
    - If edge list, map columns: from, to, strength, rationale.
- Role cards parsing:
  - Each text file is structured with headings: "Role Thesis", "Scope", "Top Decisions", "Executive Narrative", "The Five Conversations", "Toolkit", "Readiness Signals & Artifacts".
  - Map to columns:
    - thesis: first paragraph(s) under Role Thesis.
    - scope: bullet lines under "Scope".
    - decisions: bullet lines under "Top Decisions".
    - narrative: paragraph under "Executive Narrative".
    - conversations: section "The Five Conversations" (full text).
    - toolkit: section "Toolkit".
    - signals: section "Signals" or "Readiness Signals".
    - artifacts: section "Core Artifacts".
    - raw_text: entire file text.
  - Role name detection:
    - First line often contains the Role header (e.g., "Chief AI Officer (CAIO)" or "Head of AppDev / Engineering").
    - Use this to set roles.name and roles.code (slug of acronym or concise name).
    - For variants, maintain a mapping override in the script if necessary.

## Column Mappings by File

### Competency_mapping.xlsx
Expected columns (case-insensitive):
- Role, Competency, Level, Weight (optional), Category (optional), Notes (optional)
Mapping:
- roles.name <- Role
- competencies.name <- Competency
- competencies.category <- Category
- role_competencies.required_level <- Level (mapped to enum)
- role_competencies.weight <- Weight
- role_competencies.notes <- Notes

### CA_Role_Adjacency.xlsx
Two possible formats:

1) Edge list:
- From Role, To Role, Strength, Rationale (optional)
Mapping directly to role_adjacency.

2) Matrix:
- First column contains role names (rows), first row contains role names (cols).
- Each cell value numeric/non-empty indicates strength; create edge (row -> col) with strength.

### Role_Navigator_Worksheet.xlsx
May include:
- Role, Description, Competency (optional), Level (optional)
Mapping:
- roles.name <- Role
- roles.description <- Description
- If competency columns present, treat similarly to Competency_mapping.

### Role Card Texts
- Parse per normalization. Each file -> one row in role_cards, linked to its role via roles.code detection or by role name.
- source_file <- original filename.

## Deduplication and Upsert Strategy
- Upsert by natural keys:
  - roles: code (or name if code unavailable)
  - competencies: name (case-insensitive)
  - role_competencies: (role_id, competency_id)
  - role_adjacency: (from_role_id, to_role_id)
  - role_cards: role_id unique
- Use case-insensitive compare for names where appropriate.

## Assumptions
- Provided spreadsheets may have minor header naming variation; script tolerates common variants.
- Some role names in role cards differ slightly from spreadsheet; use fuzzy matching with aliases (e.g., CPTO, CIO, CTrO).
- Missing levels default to `intermediate`.
- In ingestion environment, service role key is available for write operations.

## Idempotence
- Running ingestion multiple times should not create duplicates; upserts based on keys above.
- ingestion_runs table records every attempt with counts and status.

