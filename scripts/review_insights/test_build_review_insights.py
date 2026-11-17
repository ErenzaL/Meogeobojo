import csv
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_review_insights as b  # noqa: E402

NOW = datetime(2026, 11, 17, tzinfo=timezone.utc)
PLACES = [{"kakao_place_id": "1", "name": "A", "shops": [{"shop_name": "A점", "address": "충남 아산시 신창면 1"}]}]
COLS = ["platform_shop_name", "shop_address", "rating", "created_at", "content"]


def write_csv(d, rows):
    with open(os.path.join(d, "r.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, COLS)
        w.writeheader()
        w.writerows(rows)


class ReviewInsightsTest(unittest.TestCase):
    def test_signal_matches_the_app_formula(self):
        self.assertEqual(b.review_signal([], NOW, 4.5), 0.0)
        self.assertEqual(b.review_signal([(None, NOW)], NOW, 4.5), 0.0)
        # one fresh 5-star review against overall 4: (20*4 + 5) / 21 = 4.0476..., R = 0.0476 / 4
        self.assertAlmostEqual(b.review_signal([(5.0, NOW)], NOW, 4.0), (85 / 21 - 4) / 4)
        # a review 90 days old counts half
        old = datetime(2026, 8, 19, tzinfo=timezone.utc)
        self.assertAlmostEqual(b.review_signal([(5.0, old)], NOW, 4.0), ((80 + 2.5) / 20.5 - 4) / 4)

    def test_matches_only_listed_shops_and_builds_sql(self):
        with tempfile.TemporaryDirectory() as d:
            write_csv(d, [
                {"platform_shop_name": "A점", "shop_address": "충남 아산시 신창면 1", "rating": "5", "created_at": "2026-11-01 10:00:00", "content": "맛있어요"},
                {"platform_shop_name": "A점", "shop_address": "충남 아산시 신창면 1", "rating": "-", "created_at": "2026-11-02 10:00:00", "content": "it's ok"},
                {"platform_shop_name": "B점", "shop_address": "충남 아산시 신창면 2", "rating": "3", "created_at": "2026-11-01 10:00:00", "content": ""},
                {"platform_shop_name": "A점", "shop_address": "부산 해운대구", "rating": "1", "created_at": "2026-11-01 10:00:00", "content": ""},
            ])
            reviews, area = b.load_provided(d, PLACES, "아산시 신창면")
        self.assertEqual(len(reviews["1"]), 2)  # B점 and the Busan shop are not this place
        self.assertEqual(sorted(area), [3.0, 5.0])  # the Busan rating is outside the baseline area
        rows = b.build(reviews, area, {"1": {"summary": "사장님's 국밥", "highlights": ["a", "b", "c", "d"], "model": "m"}}, NOW)
        self.assertEqual(len(rows), 1)
        r = rows[0]
        self.assertEqual((r["review_count"], r["avg_rating"], r["source"]), (2, 5.0, "provided_reviews"))
        self.assertGreater(r["review_signal"], 0)
        self.assertEqual(r["highlights"], ["a", "b", "c"])
        sql = b.to_sql(rows)
        self.assertIn("'사장님''s 국밥'", sql)  # quotes are escaped
        self.assertIn("on conflict (kakao_place_id) do update", sql)

    def test_student_reviews_extend_a_place(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "s.csv")
            with open(p, "w", encoding="utf-8", newline="") as f:
                f.write("kakao_place_id,rating,content,created_at\n9,4,괜찮아요,2026-11-10T03:00:00+00:00\n")
            student = b.load_student(p)
        rows = b.build(student, [], {}, NOW)
        self.assertEqual((rows[0]["kakao_place_id"], rows[0]["source"], rows[0]["summary"]), ("9", "student_reviews", None))


if __name__ == "__main__":
    unittest.main()
