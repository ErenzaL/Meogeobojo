#!/usr/bin/env python3
"""Validate a cafeteria CSV and turn it into ONE transactional SQL file.

    python3 import_cafeteria_csv.py meals       meals.csv       > import_meals.sql
    python3 import_cafeteria_csv.py cafeterias  cafeterias.csv  > import_cafeterias.sql
    supabase db query --linked -f import_meals.sql        # runs as the project admin

Why SQL output instead of a client upload: menus may only be written by
administrators. This script never needs (or sees) a service-role key and
nothing here runs inside the Flutter app. Any validation error aborts before
SQL is produced, and the SQL itself re-checks that every cafeteria exists and
belongs to the stated university, inside one transaction (all or nothing).

Only import data you are permitted to publish: an official source, a university
agreement, or a verified manual submission. verified_at is mandatory.
"""
import csv
import datetime as dt
import json
import re
import sys
import uuid

MEAL_TYPES = ("breakfast", "lunch", "dinner")
KINDS = ("student", "dormitory", "staff", "other")
ITEM_KINDS = ("main", "side", "soup", "rice", "other")
STATUSES = ("published", "closed", "no_menu")
ACTIONS = ("upsert", "delete")
# Stable namespace so a cafeteria row without an id gets the same id every run.
NS = uuid.UUID("6f1c2a52-4f43-4f6e-9a3b-0c0a9e5f7d11")

MEAL_COLUMNS = [
    "action", "university_id", "cafeteria_id", "meal_date", "meal_type",
    "option_name", "option_order", "menu_items", "price_krw", "start_time",
    "end_time", "status", "source_url", "verified_at",
]
CAFETERIA_COLUMNS = [
    "university_id", "cafeteria_id", "kind", "name_ko", "name_en", "name_zh",
    "location_description", "sort_order",
]


class CsvError(Exception):
    pass


def q(v):
    """SQL literal."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def req_uuid(row, col, n):
    v = (row.get(col) or "").strip()
    try:
        return str(uuid.UUID(v))
    except ValueError:
        raise CsvError(f"row {n}: {col} must be a UUID, got {v!r}")


def parse_date(v, n):
    try:
        return dt.date.fromisoformat((v or "").strip()).isoformat()
    except ValueError:
        raise CsvError(f"row {n}: meal_date must be YYYY-MM-DD, got {v!r}")


def parse_time(v, col, n):
    v = (v or "").strip()
    if not v:
        return None
    if not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", v):
        raise CsvError(f"row {n}: {col} must be HH:MM, got {v!r}")
    return v


def parse_items(v, n):
    """`main:김치찌개|side:깍두기|쌀밥`  or a JSON array of objects."""
    v = (v or "").strip()
    if v.startswith("["):
        try:
            items = json.loads(v)
        except json.JSONDecodeError as e:
            raise CsvError(f"row {n}: menu_items is not valid JSON ({e})")
        if not isinstance(items, list) or not all(isinstance(i, dict) and (i.get("name_ko") or "").strip() for i in items):
            raise CsvError(f"row {n}: JSON menu_items must be a list of objects with name_ko")
        return items
    items = []
    for part in filter(None, (p.strip() for p in v.split("|"))):
        kind = "other"
        if ":" in part and part.split(":", 1)[0] in ITEM_KINDS:
            kind, part = part.split(":", 1)
            part = part.strip()
        if not part:
            raise CsvError(f"row {n}: empty menu item")
        items.append({"name_ko": part, "kind": kind})
    return items


def meals(rows):
    out, seen = [], set()
    for n, row in rows:
        action = (row.get("action") or "upsert").strip() or "upsert"
        if action not in ACTIONS:
            raise CsvError(f"row {n}: action must be one of {ACTIONS}")
        r = {
            "action": action,
            "university_id": req_uuid(row, "university_id", n),
            "cafeteria_id": req_uuid(row, "cafeteria_id", n),
            "meal_date": parse_date(row.get("meal_date"), n),
            "meal_type": (row.get("meal_type") or "").strip(),
            "option_name": (row.get("option_name") or "").strip(),
        }
        if r["meal_type"] not in MEAL_TYPES:
            raise CsvError(f"row {n}: meal_type must be one of {MEAL_TYPES}, got {r['meal_type']!r}")
        key = (r["cafeteria_id"], r["meal_date"], r["meal_type"], r["option_name"])
        if key in seen:
            raise CsvError(f"row {n}: duplicate of an earlier row for the same cafeteria/date/meal/option")
        seen.add(key)
        if action == "upsert":
            r["status"] = (row.get("status") or "published").strip() or "published"
            if r["status"] not in STATUSES:
                raise CsvError(f"row {n}: status must be one of {STATUSES}")
            r["menu_items"] = parse_items(row.get("menu_items"), n)
            if r["status"] == "published" and not r["menu_items"]:
                raise CsvError(f"row {n}: a published meal needs menu_items (use status closed / no_menu only when the source says so)")
            p = (row.get("price_krw") or "").strip()
            if p:
                if not re.fullmatch(r"\d{1,6}", p):
                    raise CsvError(f"row {n}: price_krw must be a whole number of won, got {p!r}")
                r["price_krw"] = int(p)
            else:
                r["price_krw"] = None
            r["start_time"] = parse_time(row.get("start_time"), "start_time", n)
            r["end_time"] = parse_time(row.get("end_time"), "end_time", n)
            if r["start_time"] and r["end_time"] and r["start_time"] >= r["end_time"]:
                raise CsvError(f"row {n}: start_time must be before end_time")
            su = (row.get("source_url") or "").strip()
            if su and not su.startswith("https://"):
                raise CsvError(f"row {n}: source_url must start with https://")
            r["source_url"] = su or None
            va = (row.get("verified_at") or "").strip()
            if not va:
                raise CsvError(f"row {n}: verified_at is required (when and by whom/what was this verified?)")
            try:
                parsed = dt.datetime.fromisoformat(va.replace("Z", "+00:00"))
            except ValueError:
                raise CsvError(f"row {n}: verified_at must be an ISO timestamp, got {va!r}")
            if parsed.tzinfo is None:
                raise CsvError(f"row {n}: verified_at needs a time zone, e.g. 2026-11-03T09:00:00+09:00")
            r["verified_at"] = va
            oo = (row.get("option_order") or "0").strip() or "0"
            if not re.fullmatch(r"\d{1,3}", oo):
                raise CsvError(f"row {n}: option_order must be a small whole number")
            r["option_order"] = int(oo)
        out.append(r)
    return out


def cafeterias(rows):
    out, seen = [], set()
    for n, row in rows:
        kind = (row.get("kind") or "other").strip() or "other"
        if kind not in KINDS:
            raise CsvError(f"row {n}: kind must be one of {KINDS}")
        uni = req_uuid(row, "university_id", n)
        name_ko = (row.get("name_ko") or "").strip() or None
        cid = (row.get("cafeteria_id") or "").strip()
        cid = req_uuid(row, "cafeteria_id", n) if cid else str(uuid.uuid5(NS, f"{uni}|{kind}|{name_ko or ''}|{n}"))
        if cid in seen:
            raise CsvError(f"row {n}: duplicate cafeteria_id")
        seen.add(cid)
        so = (row.get("sort_order") or "0").strip() or "0"
        if not re.fullmatch(r"\d{1,3}", so):
            raise CsvError(f"row {n}: sort_order must be a small whole number")
        out.append({
            "university_id": uni, "cafeteria_id": cid, "kind": kind,
            "name_ko": name_ko,
            "name_en": (row.get("name_en") or "").strip() or None,
            "name_zh": (row.get("name_zh") or "").strip() or None,
            "location_description": (row.get("location_description") or "").strip() or None,
            "sort_order": int(so),
        })
    return out


def read(path, columns):
    with open(path, newline="", encoding="utf-8-sig") as f:
        rd = csv.DictReader(f)
        missing = [c for c in columns if c not in (rd.fieldnames or []) and c not in ("action", "option_name", "option_order", "status", "cafeteria_id", "sort_order", "kind")]
        if missing:
            raise CsvError(f"missing column(s): {', '.join(missing)}")
        rows = [(i, r) for i, r in enumerate(rd, start=2) if any((v or "").strip() for v in r.values())]
    if not rows:
        raise CsvError("the CSV has no data rows")
    return rows


def sql_meals(rows):
    values = ",\n  ".join(
        "({}, {}, {}, {}, {}, {})".format(
            q(r["action"]), q(r["university_id"]), q(r["cafeteria_id"]),
            q(r["meal_date"]), q(r["meal_type"]), q(r["option_name"]))
        for r in rows)
    s = ["-- Generated by import_cafeteria_csv.py. Review, then run once.", "begin;",
         "create temp table _keys (action text, university_id uuid, cafeteria_id uuid, meal_date date, meal_type text, option_name text) on commit drop;",
         f"insert into _keys values\n  {values};",
         """do $$ begin
  if exists (
    select 1 from _keys k
    left join public.campus_cafeterias c on c.id = k.cafeteria_id and c.university_id = k.university_id
    where c.id is null
  ) then
    raise exception 'import aborted: a cafeteria_id does not exist or does not belong to the stated university_id';
  end if;
end $$;"""]
    for r in rows:
        if r["action"] == "delete":
            s.append("delete from public.cafeteria_meals where cafeteria_id = {} and meal_date = {} and meal_type = {} and option_name = {};".format(
                q(r["cafeteria_id"]), q(r["meal_date"]), q(r["meal_type"]), q(r["option_name"])))
            continue
        s.append(
            "insert into public.cafeteria_meals (cafeteria_id, meal_date, meal_type, option_name, option_order, menu_items, price_krw, start_time, end_time, status, source_url, verified_at)\n"
            "values ({}, {}, {}, {}, {}, {}::jsonb, {}, {}, {}, {}, {}, {})\n"
            "on conflict (cafeteria_id, meal_date, meal_type, option_name) do update set\n"
            "  option_order = excluded.option_order, menu_items = excluded.menu_items, price_krw = excluded.price_krw,\n"
            "  start_time = excluded.start_time, end_time = excluded.end_time, status = excluded.status,\n"
            "  source_url = excluded.source_url, verified_at = excluded.verified_at;".format(
                q(r["cafeteria_id"]), q(r["meal_date"]), q(r["meal_type"]), q(r["option_name"]),
                r["option_order"], q(json.dumps(r["menu_items"], ensure_ascii=False)), q(r["price_krw"]),
                q(r["start_time"]), q(r["end_time"]), q(r["status"]), q(r["source_url"]), q(r["verified_at"])))
    s.append("commit;")
    return "\n".join(s) + "\n"


def sql_cafeterias(rows):
    s = ["-- Generated by import_cafeteria_csv.py. Review, then run once.", "begin;"]
    for r in rows:
        s.append(
            "do $$ begin if not exists (select 1 from public.universities where id = {u}) then raise exception 'unknown university_id %', {u}; end if; end $$;\n"
            "insert into public.campus_cafeterias (id, university_id, kind, name_ko, name_en, name_zh, location_description, sort_order)\n"
            "values ({}, {}, {}, {}, {}, {}, {}, {})\n"
            "on conflict (id) do update set kind = excluded.kind, name_ko = excluded.name_ko, name_en = excluded.name_en,\n"
            "  name_zh = excluded.name_zh, location_description = excluded.location_description, sort_order = excluded.sort_order\n"
            "where public.campus_cafeterias.university_id = excluded.university_id;".format(
                q(r["cafeteria_id"]), q(r["university_id"]), q(r["kind"]), q(r["name_ko"]), q(r["name_en"]),
                q(r["name_zh"]), q(r["location_description"]), r["sort_order"], u=q(r["university_id"])))
    s.append("commit;")
    return "\n".join(s) + "\n"


def main(argv):
    if len(argv) != 3 or argv[1] not in ("meals", "cafeterias"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if argv[1] == "meals":
            print(sql_meals(meals(read(argv[2], MEAL_COLUMNS))), end="")
        else:
            print(sql_cafeterias(cafeterias(read(argv[2], CAFETERIA_COLUMNS))), end="")
    except (CsvError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
