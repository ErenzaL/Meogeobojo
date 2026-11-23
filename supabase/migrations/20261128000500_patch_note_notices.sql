-- =============================================================================
-- 공지사항: the changes so far as version patch notes (v1.0 - v1.4), one announcement per version.
--
-- The rows are created SWITCHED OFF, exactly like a notice made in Admin → 앱 콘텐츠 ("꺼진 상태로 만들었어요"), so
-- applying this changes nothing for students and the CMS rule "live content changes only by publishing" holds. To show
-- them: Admin → 앱 콘텐츠 → each 패치노트 → 바로 게시 (versioned and audited), and 내리기 the old temporary notices.
-- starts_at is each version's date: the 공지사항 list sorts and dates by it. sort_order puts the newest first on Home
-- (Home shows the first two announcements).
--
-- Data only and idempotent: fixed ids, ON CONFLICT DO NOTHING, so a re-run neither duplicates nor overwrites a notice
-- an admin has since edited, published or taken down. Requires 20261109000100. NOT applied by the repository.
-- =============================================================================
do $$ begin
  if to_regclass('public.app_content') is null then raise exception 'Apply 20261109000100 first.'; end if;
end $$;

insert into public.app_content (id, kind, title, body, active, sort_order, starts_at) values
('a7c40000-0000-4000-8000-000000000104', 'announcement', 'v1.4 업데이트: AI 맛집 채팅과 모바일 미리보기',
$t$• 마스코트 버튼을 눌러 AI와 대화하며 맛집을 찾을 수 있어요
• Top 3에 카테고리를 표시해 식당 이름의 학식과 교내 학식을 구분해요
• 1순위 추천 사진이 잘리지 않고 전체가 보여요
• 영업시간·편의시설에 실제 정보를 반영했어요
• PC에서 휴대폰 화면 미리보기로 앱을 써 볼 수 있어요$t$,
 false, 1, '2026-11-18 18:00:00+09'),
('a7c40000-0000-4000-8000-000000000103', 'announcement', 'v1.3 업데이트: Top 3 추천과 순위',
$t$• 홈에 Top 3 추천, 전체 순위 페이지, 지도 바로가기를 넣었어요
• 추천이 취향·거리·리뷰를 함께 반영해요
• 1순위 아래에서 조건에 맞는 메뉴를 옆으로 넘겨 볼 수 있어요
• 정보를 확인할 수 없는 식당은 목록에 띄우지 않아요
• 메뉴·가격 정보를 업데이트했어요$t$,
 false, 2, '2026-11-17 09:00:00+09'),
('a7c40000-0000-4000-8000-000000000102', 'announcement', 'v1.2 업데이트: 새 디자인과 추천 흐름',
$t$• 맛집 정보·리뷰·검색·저장한 맛집·로그인 화면을 새로 단장했어요
• 추천 → 먹었어요 → MY 기록으로 이어지게 바꿨어요
• 지도 핀을 가격이 보이는 작은 태그로 바꿨어요
• 학식 식당을 골라서 볼 수 있어요
• 공지사항, 문의 및 제안, 이용약관·개인정보처리방침을 앱 안에서 볼 수 있어요$t$,
 false, 3, '2026-11-13 09:00:00+09'),
('a7c40000-0000-4000-8000-000000000101', 'announcement', 'v1.1 업데이트: 학식과 PC 화면',
$t$• 조식·중식·석식을 한 번에 보고, 천원의 아침밥은 조식 아래에 표시해요
• 지도가 캠퍼스에서 시작하고 웹에서도 핀이 잘 보여요
• PC 화면: 넓은 레이아웃, 상세 필터, 주소 링크로 바로 이동
• 알림(종)에서 새 소식을 확인할 수 있어요$t$,
 false, 4, '2026-11-11 09:00:00+09'),
('a7c40000-0000-4000-8000-000000000100', 'announcement', 'v1.0 먹어보조 첫 공개',
$t$• 캠퍼스 주변 맛집을 예산·거리·종류 조건에 맞춰 추천해요
• 출발 위치를 정하면 걸어서 몇 분인지 알려 줘요
• 지도, 학식, 미션, MY 화면을 열었어요
• PC 웹에서도 쓸 수 있어요$t$,
 false, 5, '2026-11-09 09:00:00+09')
on conflict (id) do nothing;
