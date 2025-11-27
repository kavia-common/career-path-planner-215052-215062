#!/usr/bin/env python3
"""
PUBLIC_INTERFACE
Main ingestion script to seed/update database from provided spreadsheets and role card text files.

This script:
- Connects to Supabase PostgREST using SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
- Parses:
  * Competency_mapping.xlsx
  * CA_Role_Adjacency.xlsx
  * Role_Navigator_Worksheet.xlsx
  * Role card .txt files
- Upserts into tables: roles, competencies, role_competencies, role_adjacency, role_cards
- Records ingestion_runs with counts and status

Environment variables (request from user and set in .env for this container):
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY

Usage:
  python ingestion/ingest.py --attachments-dir ../../../attachments

Dependencies:
  - pandas
  - openpyxl
  - python-dotenv
  - requests

Note: Do not hardcode secrets; use environment variables.
"""
import argparse
import os
import re
import sys
import glob
import json
from typing import Dict, Any, Optional, Tuple

import pandas as pd
from dotenv import load_dotenv
import requests

# Constants
DEFAULT_ATTACHMENTS_GLOB = "*"
HEADERS_VARIANTS = {
    "role": ["role", "from role", "from_role", "source role", "role name"],
    "to_role": ["to role", "to_role", "target role"],
    "competency": ["competency", "skill", "competence"],
    "level": ["level", "required level", "req level"],
    "weight": ["weight", "priority", "score"],
    "category": ["category", "group"],
    "notes": ["notes", "note", "rationale", "comment"],
    "description": ["description", "desc", "about"],
    "strength": ["strength", "score", "adjacency", "weight"],
}

LEVEL_MAP = {
    "beginner": "beginner", "basic": "beginner", "foundational": "beginner", "novice": "beginner", "l1": "beginner",
    "intermediate": "intermediate", "working": "intermediate", "practitioner": "intermediate", "l2": "intermediate",
    "advanced": "advanced", "expert": "advanced", "authority": "advanced", "l3": "advanced", "senior": "advanced"
}

ROLE_ALIAS = {
    "Chief Information Officer": "cio",
    "Chief Product & Technology Officer": "cpto",
    "Chief Transformation Officer": "ctro",
    "Chief Digital Officer": "cdo",
    "Chief Data & Analytics Officer": "cdao",
    "Chief AI Officer": "caio",
    "Chief Customer Technology Officer": "ccto",
    "Head of AppDev / Engineering": "appdev",
    "Head of Infrastructure & Cloud": "infra",
    "Head of IT Operations": "ops",
    "Head of PMO": "pmo",
    "GM, Digital Product": "digprod",
    "Field / Industry CTO": "fcto",
    "Chief Architect": "ca",
}

class SupabaseClient:
    """Simple Supabase REST client using service role key for admin upserts."""
    def __init__(self, base_url: str, service_key: str):
        self.rest_url = base_url.rstrip("/") + "/rest/v1"
        self.headers = {
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        }

    def upsert(self, table: str, rows: Any, on_conflict: Optional[str] = None):
        params = {}
        if on_conflict:
            params["on_conflict"] = on_conflict
        resp = requests.post(f"{self.rest_url}/{table}", headers=self.headers, params=params, data=json.dumps(rows))
        if not resp.ok:
            raise RuntimeError(f"Upsert failed for {table}: {resp.status_code} {resp.text}")
        return resp.json() if resp.text else []

    def select(self, table: str, query: str = "*", filters: Optional[Dict[str, str]] = None):
        params = {"select": query}
        if filters:
            params.update(filters)
        resp = requests.get(f"{self.rest_url}/{table}", headers=self.headers, params=params)
        if not resp.ok:
            raise RuntimeError(f"Select failed for {table}: {resp.status_code} {resp.text}")
        return resp.json()

def load_env():
    load_dotenv()  # optional .env in container
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise EnvironmentError("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in environment.")
    return url, key

def slugify_code(name: str) -> str:
    name = name.strip()
    # Prefer alias if known
    if name in ROLE_ALIAS:
        return ROLE_ALIAS[name]
    # Use acronym in parentheses if present, e.g., "Chief AI Officer (CAIO)"
    m = re.search(r"\(([^)]+)\)", name)
    if m:
        return re.sub(r"[^a-z0-9]+", "", m.group(1).lower())
    # Fallback: slug on words
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")

def norm_text(s: Optional[str]) -> Optional[str]:
    if s is None:
        return None
    s = str(s).strip()
    return s if s else None

def map_level(val: Any) -> str:
    if pd.isna(val):
        return "intermediate"
    s = str(val).strip().lower()
    return LEVEL_MAP.get(s, "intermediate")

def find_col(df: pd.DataFrame, key: str) -> Optional[str]:
    cols = [c for c in df.columns]
    for c in cols:
        if c.lower() == key:
            return c
    for variant in HEADERS_VARIANTS.get(key, []):
        for c in cols:
            if c.lower() == variant:
                return c
    # fuzzy contains
    for c in cols:
        if key.replace("_", " ") in c.lower():
            return c
    return None

def ensure_roles(client: SupabaseClient, names_with_desc: Dict[str, Optional[str]]) -> Dict[str, Dict[str, Any]]:
    # Upsert roles by (code, name)
    rows = []
    for name, desc in names_with_desc.items():
        code = slugify_code(name)
        rows.append({"code": code, "name": name, "description": desc})
    if rows:
        client.upsert("roles", rows, on_conflict="code")
    # Fetch back
    role_map = {}
    all_roles = client.select("roles")
    for r in all_roles:
        role_map[r["name"].lower()] = r
        role_map[r["code"].lower()] = r
    return role_map

def ensure_competencies(client: SupabaseClient, entries: Dict[Tuple[str, Optional[str]], Dict[str, Optional[str]]]) -> Dict[str, Dict[str, Any]]:
    rows = []
    for (name, category), meta in entries.items():
        rows.append({"name": name, "category": category, "description": meta.get("description")})
    if rows:
        client.upsert("competencies", rows, on_conflict="name")
    comp_map = {}
    all_comp = client.select("competencies")
    for c in all_comp:
        comp_map[c["name"].lower()] = c
    return comp_map

def upsert_role_competencies(client: SupabaseClient, rc_rows: list):
    if rc_rows:
        client.upsert("role_competencies", rc_rows, on_conflict="role_id,competency_id")

def upsert_role_adjacency(client: SupabaseClient, edges: list):
    if edges:
        client.upsert("role_adjacency", edges, on_conflict="from_role_id,to_role_id")

def upsert_role_cards(client: SupabaseClient, cards: list):
    if cards:
        client.upsert("role_cards", cards, on_conflict="role_id")

def parse_competency_mapping(path: str) -> pd.DataFrame:
    return pd.read_excel(path)

def parse_role_adjacency(path: str) -> pd.DataFrame:
    return pd.read_excel(path)

def parse_role_navigator(path: str) -> pd.DataFrame:
    return pd.read_excel(path)

def parse_role_card_text(path: str) -> Dict[str, str]:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    sections = {
        "thesis": "",
        "scope": "",
        "decisions": "",
        "narrative": "",
        "conversations": "",
        "toolkit": "",
        "signals": "",
        "artifacts": "",
    }
    # naive section splitting by headers
    patterns = {
        "thesis": r"(?:Role Thesis|1\) Role Thesis).*?(?=\n\d\)|\n2\)|\nThe Five Conversations|\n3\)|\Z)",
        "scope": r"(?:Scope.*?:).*?(?=\nTop Decisions|\nExecutive Narrative|\n2\)|\Z)",
        "decisions": r"(?:Top Decisions.*?:).*?(?=\nExecutive Narrative|\n2\)|\Z)",
        "narrative": r"(?:Executive Narrative.*?:).*?(?=\n2\)|\nThe Five Conversations|\Z)",
        "conversations": r"(?:The Five Conversations.*?).*?(?=\n3\)|\nToolkit|\Z)",
        "toolkit": r"(?:Toolkit.*?).*?(?=\n4\)|\nReadiness Signals|\nSignals|\Z)",
        "signals": r"(?:Readiness Signals.*?|Signals.*?).*?(?=\nCore Artifacts|\nArtifacts|\Z)",
        "artifacts": r"(?:Core Artifacts.*?|Artifacts.*?).*",
    }
    for key, pat in patterns.items():
        m = re.search(pat, text, flags=re.IGNORECASE | re.DOTALL)
        if m:
            sections[key] = m.group(0).strip()
    # guess role name from first line
    first_line = text.splitlines()[0].strip()
    return {"role_name": first_line, "raw_text": text, **sections}

def start_ingestion_run(client: SupabaseClient, src: str) -> str:
    data = [{"status": "running", "source": src, "triggered_by": "service_role"}]
    res = client.upsert("ingestion_runs", data)
    return res[0]["id"] if res and isinstance(res, list) else None

def finish_ingestion_run(client: SupabaseClient, run_id: str, status: str, processed: int, upserted: int, error: Optional[str] = None):
    payload = [{"id": run_id, "status": status, "finished_at": pd.Timestamp.utcnow().isoformat(), "items_processed": processed, "items_upserted": upserted, "error_message": error}]
    client.upsert("ingestion_runs", payload, on_conflict="id")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--attachments-dir", type=str, default=os.path.join("..", "..", "..", "attachments"))
    args = parser.parse_args()

    supabase_url, service_key = load_env()
    client = SupabaseClient(supabase_url, service_key)

    attachments_dir = os.path.abspath(args.attachments_dir)
    if not os.path.isdir(attachments_dir):
        print(f"Attachments directory not found: {attachments_dir}", file=sys.stderr)
        sys.exit(1)

    src_summary = "excel: Competency_mapping, CA_Role_Adjacency, Role_Navigator; texts: Role_Card_*.txt"
    run_id = start_ingestion_run(client, src_summary) or ""

    processed = 0
    upserted = 0
    try:
        # Discover files (prefer the latest timestamped copies)
        comp_files = sorted(glob.glob(os.path.join(attachments_dir, "*Competency_mapping.xlsx")))
        adj_files = sorted(glob.glob(os.path.join(attachments_dir, "*CA_Role_Adjacency.xlsx")))
        nav_files = sorted(glob.glob(os.path.join(attachments_dir, "*Role_Navigator_Worksheet.xlsx")))
        card_files = sorted(glob.glob(os.path.join(attachments_dir, "Role_Card_*.txt")))

        # 1) Parse Role Navigator (roles + descriptions)
        roles_dict: Dict[str, Optional[str]] = {}
        if nav_files:
            df_nav = parse_role_navigator(nav_files[-1]).fillna("")
            c_role = find_col(df_nav, "role")
            c_desc = find_col(df_nav, "description")
            if c_role:
                for _, row in df_nav.iterrows():
                    rname = str(row[c_role]).strip()
                    if not rname:
                        continue
                    desc = str(row[c_desc]).strip() if c_desc else None
                    roles_dict[rname] = desc or roles_dict.get(rname)
        # 2) Role cards may define additional roles
        for path in card_files:
            info = parse_role_card_text(path)
            rname = info["role_name"]
            if rname and rname not in roles_dict:
                roles_dict[rname] = None

        role_map = ensure_roles(client, roles_dict) if roles_dict else {}

        processed += len(roles_dict)

        # 3) Competency mapping
        comp_map_entries: Dict[Tuple[str, Optional[str]], Dict[str, Optional[str]]] = {}
        rc_rows = []
        if comp_files:
            df_comp = parse_competency_mapping(comp_files[-1])
            # normalize headers
            c_role = find_col(df_comp, "role")
            c_comp = find_col(df_comp, "competency")
            c_level = find_col(df_comp, "level")
            c_weight = find_col(df_comp, "weight")
            c_cat = find_col(df_comp, "category")
            c_notes = find_col(df_comp, "notes")

            for _, row in df_comp.iterrows():
                role_name = norm_text(row[c_role]) if c_role else None
                comp_name = norm_text(row[c_comp]) if c_comp else None
                if not role_name or not comp_name:
                    continue
                level = map_level(row[c_level]) if c_level else "intermediate"
                weight = None
                if c_weight and not pd.isna(row[c_weight]):
                    try:
                        weight = float(row[c_weight])
                    except Exception:
                        weight = 1.0
                category = norm_text(row[c_cat]) if c_cat else None
                notes = norm_text(row[c_notes]) if c_notes else None

                comp_map_entries[(comp_name, category)] = {"description": None}
                processed += 1

        comp_map = ensure_competencies(client, comp_map_entries) if comp_map_entries else {}

        # Build role_competencies rows
        if comp_files:
            df_comp = parse_competency_mapping(comp_files[-1])
            c_role = find_col(df_comp, "role")
            c_comp = find_col(df_comp, "competency")
            c_level = find_col(df_comp, "level")
            c_weight = find_col(df_comp, "weight")
            c_cat = find_col(df_comp, "category")
            c_notes = find_col(df_comp, "notes")

            for _, row in df_comp.iterrows():
                role_name = norm_text(row[c_role]) if c_role else None
                comp_name = norm_text(row[c_comp]) if c_comp else None
                if not role_name or not comp_name:
                    continue
                level = map_level(row[c_level]) if c_level else "intermediate"
                weight_val = 1.0
                if c_weight and not pd.isna(row[c_weight]):
                    try:
                        weight_val = float(row[c_weight])
                    except Exception:
                        weight_val = 1.0
                notes = norm_text(row[c_notes]) if c_notes else None

                # Resolve IDs (by role name or code)
                rkey = role_name.lower()
                r = role_map.get(rkey) or role_map.get(slugify_code(role_name))
                if not r:
                    # create on the fly if missing
                    r = ensure_roles(client, {role_name: None}).get(role_name.lower())
                    role_map[role_name.lower()] = r
                c = comp_map.get(comp_name.lower())
                if not c:
                    c = ensure_competencies(client, {(comp_name, None): {"description": None}}).get(comp_name.lower())
                    comp_map[comp_name.lower()] = c
                if not r or not c:
                    continue
                rc_rows.append({
                    "role_id": r["id"],
                    "competency_id": c["id"],
                    "required_level": level,
                    "weight": weight_val,
                    "notes": notes
                })
                upserted += 1

        upsert_role_competencies(client, rc_rows)

        # 4) Role adjacency
        edges = []
        if adj_files:
            df_adj = parse_role_adjacency(adj_files[-1])
            # Try edge list first
            c_from = find_col(df_adj, "role") or find_col(df_adj, "from_role") or find_col(df_adj, "from role")
            c_to = find_col(df_adj, "to_role") or find_col(df_adj, "to role")
            c_strength = find_col(df_adj, "strength")
            c_notes = find_col(df_adj, "notes")
            if c_from and c_to:
                for _, row in df_adj.iterrows():
                    from_name = norm_text(row[c_from])
                    to_name = norm_text(row[c_to])
                    if not from_name or not to_name:
                        continue
                    strength = None
                    if c_strength and not pd.isna(row[c_strength]):
                        try:
                            strength = float(row[c_strength])
                        except Exception:
                            strength = 1.0
                    strength = strength if strength is not None else 1.0
                    rationale = norm_text(row[c_notes]) if c_notes else None
                    r_from = role_map.get(from_name.lower()) or role_map.get(slugify_code(from_name))
                    r_to = role_map.get(to_name.lower()) or role_map.get(slugify_code(to_name))
                    if not r_from or not r_to:
                        continue
                    edges.append({
                        "from_role_id": r_from["id"],
                        "to_role_id": r_to["id"],
                        "strength": strength,
                        "rationale": rationale
                    })
                    upserted += 1
            else:
                # Fallback: treat as matrix (first row/column headers)
                df_adj = df_adj.fillna("")
                headers = [str(h).strip() for h in list(df_adj.columns)]
                row_roles = df_adj.iloc[:, 0].astype(str).str.strip().tolist()
                col_roles = headers[1:]
                for i, rname in enumerate(row_roles):
                    for j, cname in enumerate(col_roles):
                        try:
                            val = df_adj.iloc[i, j + 1]
                        except Exception:
                            continue
                        if (isinstance(val, (int, float)) and val > 0) or (isinstance(val, str) and val.strip() != ""):
                            r_from = role_map.get(rname.lower()) or role_map.get(slugify_code(rname))
                            r_to = role_map.get(cname.lower()) or role_map.get(slugify_code(cname))
                            if not r_from or not r_to:
                                continue
                            strength = float(val) if isinstance(val, (int, float)) else 1.0
                            edges.append({
                                "from_role_id": r_from["id"],
                                "to_role_id": r_to["id"],
                                "strength": strength,
                                "rationale": None
                            })
                            upserted += 1

        upsert_role_adjacency(client, edges)

        # 5) Role cards
        cards = []
        for path in card_files:
            parsed = parse_role_card_text(path)
            role_name = parsed["role_name"]
            r = role_map.get(role_name.lower()) or role_map.get(slugify_code(role_name))
            if not r:
                # Create role if new
                r = ensure_roles(client, {role_name: None}).get(role_name.lower())
                role_map[role_name.lower()] = r
            if not r:
                continue
            cards.append({
                "role_id": r["id"],
                "thesis": parsed.get("thesis"),
                "scope": parsed.get("scope"),
                "decisions": parsed.get("decisions"),
                "narrative": parsed.get("narrative"),
                "conversations": parsed.get("conversations"),
                "toolkit": parsed.get("toolkit"),
                "signals": parsed.get("signals"),
                "artifacts": parsed.get("artifacts"),
                "raw_text": parsed.get("raw_text"),
                "source_file": os.path.basename(path)
            })
            upserted += 1

        upsert_role_cards(client, cards)

        finish_ingestion_run(client, run_id, "success", processed, upserted)
        print(f"Ingestion complete. processed={processed} upserted={upserted}")
    except Exception as e:
        finish_ingestion_run(client, run_id, "error", processed, upserted, error=str(e))
        print(f"Ingestion error: {e}", file=sys.stderr)
        sys.exit(2)

if __name__ == "__main__":
    main()
