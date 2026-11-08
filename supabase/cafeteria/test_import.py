import csv, os, subprocess, sys, tempfile, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "import_cafeteria_csv.py")
U = "5c0a8f3e-0001-4a6e-9b1d-000000000001"
C = "11111111-1111-4111-8111-111111111111"
HEAD = "action,university_id,cafeteria_id,meal_date,meal_type,option_name,option_order,menu_items,price_krw,start_time,end_time,status,source_url,verified_at\n"
OK = f"upsert,{U},{C},2026-11-03,lunch,,0,main:김치찌개|rice:쌀밥,5500,11:30,13:30,published,https://example.org/m,2026-11-03T09:00:00+09:00\n"

def run(kind, body, head=HEAD):
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8") as f:
        f.write(head + body)
    try:
        p = subprocess.run([sys.executable, SCRIPT, kind, f.name], capture_output=True, text=True)
    finally:
        os.unlink(f.name)
    return p.returncode, p.stdout, p.stderr

class T(unittest.TestCase):
    def bad(self, body, needle):
        rc, _, err = run("meals", body)
        self.assertEqual(rc, 1, err)
        self.assertIn(needle, err)
    def test_valid(self):
        rc, out, err = run("meals", OK)
        self.assertEqual(rc, 0, err)
        self.assertIn("begin;", out); self.assertIn("commit;", out)
        self.assertIn("김치찌개", out); self.assertIn("on conflict", out)
    def test_bad_date(self): self.bad(OK.replace("2026-11-03,lunch", "2026-13-40,lunch"), "meal_date")
    def test_bad_meal_type(self): self.bad(OK.replace(",lunch,", ",brunch,"), "meal_type")
    def test_bad_price(self): self.bad(OK.replace(",5500,", ",-5,"), "price_krw")
    def test_price_not_number(self): self.bad(OK.replace(",5500,", ",abc,"), "price_krw")
    def test_bad_cafeteria_uuid(self): self.bad(OK.replace(C, "nope"), "cafeteria_id")
    def test_bad_time(self): self.bad(OK.replace("11:30", "25:99"), "start_time")
    def test_time_order(self): self.bad(OK.replace("11:30,13:30", "14:00,13:30"), "before")
    def test_http_source_rejected(self): self.bad(OK.replace("https://example.org", "http://example.org"), "https")
    def test_verified_at_required(self): self.bad(OK.replace("2026-11-03T09:00:00+09:00", ""), "verified_at")
    def test_verified_at_needs_tz(self): self.bad(OK.replace("T09:00:00+09:00", "T09:00:00"), "time zone")
    def test_published_needs_items(self): self.bad(OK.replace("main:김치찌개|rice:쌀밥", ""), "published")
    def test_duplicate_rows(self): self.bad(OK + OK, "duplicate")
    def test_closed_without_items_ok(self):
        rc, out, err = run("meals", OK.replace("main:김치찌개|rice:쌀밥", "").replace("published", "closed"))
        self.assertEqual(rc, 0, err); self.assertIn("'closed'", out)
    def test_delete_row(self):
        rc, out, err = run("meals", f"delete,{U},{C},2026-11-03,lunch,,,,,,,,,\n")
        self.assertEqual(rc, 0, err); self.assertIn("delete from public.cafeteria_meals", out)
    def test_two_options_do_not_collide(self):
        rc, _, err = run("meals", OK + OK.replace(",lunch,,0,", ",lunch,B코너,1,"))
        self.assertEqual(rc, 0, err)
    def test_quote_escaping(self):
        rc, out, _ = run("meals", OK.replace("김치찌개", "it's"))
        self.assertEqual(rc, 0); self.assertIn("it''s", out)
    def test_cafeterias(self):
        head = "university_id,cafeteria_id,kind,name_ko,name_en,name_zh,location_description,sort_order\n"
        rc, out, err = run("cafeterias", f"{U},,dormitory,,,,,1\n", head)
        self.assertEqual(rc, 0, err); self.assertIn("campus_cafeterias", out)
        rc, _, err = run("cafeterias", f"{U},,restaurant,,,,,1\n", head)
        self.assertEqual(rc, 1); self.assertIn("kind", err)
    def test_ids_are_stable(self):
        head = "university_id,cafeteria_id,kind,name_ko,name_en,name_zh,location_description,sort_order\n"
        a = run("cafeterias", f"{U},,student,,,,,0\n", head)[1]
        b = run("cafeterias", f"{U},,student,,,,,0\n", head)[1]
        self.assertEqual(a, b)

if __name__ == "__main__":
    unittest.main()
