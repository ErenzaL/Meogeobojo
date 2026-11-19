"""Turns the collected review CSV (restaurants_reviews.csv: Naver, Kakao Map and the provided delivery-app reviews,
already matched to Kakao place ids) into SQL for public.collected_reviews (migration 20261128000100).

The CSV holds third-party review text, so neither it nor the generated SQL is committed. Run the parts in the Supabase
SQL editor in order; part 01 empties the table first, so running everything again replaces the data:

    python3 scripts/collected_reviews/build_collected_reviews.py restaurants_reviews.csv --out-dir out
"""
import argparse
import csv
import os
import re
import sys
from datetime import date

# CSV `platform` (provided delivery-app rows) or `source` (scraped rows) -> collected_reviews.platform
PLATFORMS = {
    "naver": "naver",
    "NAVER": "naver",
    "kakao": "kakao",
    "BAEMIN": "baemin",
    "CPEATS": "coupangeats",
    "YOGIYO": "yogiyo",
}
WEEKDAYS = "월화수목금토일"
MAX_BODY = 4000
ROWS_PER_PART = 2000


def rating_of(value):
    try:
        x = float(value)
    except ValueError:
        return None
    return x if 0.5 <= x <= 5 else None


def date_of(value, this_year):
    """'2026-06-13 14:15:39', or Naver's '10.29.목' (this year or last) and '25.3.4.화' (two-digit year)."""
    value = value.strip()
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", value)
    if m:
        return date(*map(int, m.groups()))
    m = re.fullmatch(r"(?:(\d{2})\.)?(\d{1,2})\.(\d{1,2})\.(\S)", value)
    if not m:
        return None
    yy, month, day, weekday = m.groups()
    # A Naver date without a year is from the last 12 months; the weekday says which year.
    for year in [2000 + int(yy)] if yy else [this_year, this_year - 1]:
        try:
            d = date(year, int(month), int(day))
        except ValueError:
            continue
        if WEEKDAYS[d.weekday()] == weekday:
            return d
    return None


def reviews(rows, this_year):
    """(kakao_place_id, platform, rating, body, reviewed_on) per review, duplicates dropped, newest first per place."""
    seen = set()
    out = []
    for r in rows:
        place = (r.get("kakao_place_id") or "").strip()
        platform = PLATFORMS.get(r.get("platform") or r.get("source") or "")
        if r.get("record_type") != "review" or not re.fullmatch(r"[0-9]{1,20}", place) or platform is None:
            continue
        body = (r.get("review_text") or "").replace("\x00", "").strip()[:MAX_BODY] or None
        rating = rating_of(r.get("rating") or "")
        review_id = (r.get("source_review_id") or "").strip()
        key = (place, platform, review_id) if review_id else (place, platform, rating, body, r.get("review_date"))
        if key in seen:
            continue
        seen.add(key)
        out.append((place, platform, rating, body, date_of(r.get("review_date") or "", this_year)))
    out.sort(key=lambda x: (x[0], -(x[4] or date.min).toordinal()))
    return out


def sql_text(v):
    return "null" if v is None else "'" + v.replace("'", "''") + "'"


def sql_parts(items, rows_per_part=ROWS_PER_PART):
    parts = []
    for i in range(0, max(len(items), 1), rows_per_part):
        chunk = items[i:i + rows_per_part]
        lines = ["delete from public.collected_reviews;"] if i == 0 else []
        if chunk:
            values = ",\n".join(
                f"({sql_text(p)}, {sql_text(pl)}, {'null' if ra is None else f'{ra:.1f}'}, {sql_text(b)}, "
                f"{'null' if d is None else sql_text(d.isoformat())})"
                for p, pl, ra, b, d in chunk
            )
            lines.append(
                "insert into public.collected_reviews (kakao_place_id, platform, rating, body, reviewed_on) values\n"
                + values + ";"
            )
        parts.append("\n".join(lines) + "\n")
    return parts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--year", type=int, default=date.today().year, help="year the Naver reviews were collected")
    args = ap.parse_args()
    csv.field_size_limit(10**8)
    with open(args.csv, encoding="utf-8-sig", newline="") as f:
        items = reviews(csv.DictReader(f), args.year)
    os.makedirs(args.out_dir, exist_ok=True)
    parts = sql_parts(items)
    for n, text in enumerate(parts, 1):
        with open(os.path.join(args.out_dir, f"collected_reviews_{n:02d}.sql"), "w", encoding="utf-8") as f:
            f.write(text)
    places = len({x[0] for x in items})
    undated = sum(1 for x in items if x[4] is None)
    print(f"{len(items)} reviews of {places} places in {len(parts)} parts ({undated} without a date)", file=sys.stderr)


if __name__ == "__main__":
    main()
