-- =============================================================================
-- 폐업했거나 배달 전문인 식당을 앱에서 숨긴다 (visibility -> hidden).
--
-- 근거 (2026-11-19 확인):
--   1776574319 대학자장 (학생회관)    폐업: 카카오맵 장소 API가 "카카오맵에 존재하지 않는 장소입니다"(404)를 돌려주고,
--                                      네이버 플레이스 검색에서도 같은 곳을 찾지 못했다. 관리 좌표가 있어 앱에는 계속 보였다.
--   18105730   토마토도시락 순천향대점 배달 전문: 카카오 카테고리가 "음식점 > 도시락 > 배달도시락".
--
-- 새 플래그는 없다: 앱 목록·지도·검색, AI 추천, 미션이 모두 visibility = 'published'만 쓰므로 hidden 하나로 어디서나 빠진다.
-- 관리자 게시와 같은 _cms_commit으로 바꾸므로 사유가 붙은 버전이 남고, 관리자 화면에서 다시 공개하면 되돌릴 수 있다.
-- 지금 공개 중인 행만 바꾼다: DB에 없는 장소는 건너뛰고, 다시 실행해도 아무것도 바꾸지 않는다.
-- NOT applied by the repository: apply deliberately, after review.
-- =============================================================================
do $$
declare
  r record;
begin
  for r in
    select o.id, x.reason
      from (values
        ('1776574319', '폐업: 카카오맵에 없는 장소(404), 네이버 플레이스에서도 찾지 못함 (2026-11-19 확인)'),
        ('18105730',   '배달 전문: 카카오 카테고리 배달도시락 (2026-11-19 확인)')
      ) as x (kakao_place_id, reason)
      join public.restaurant_overrides o on o.kakao_place_id = x.kakao_place_id
     where o.visibility = 'published'
  loop
    perform public._cms_lock('restaurant', r.id);
    perform public._cms_commit('restaurant', r.id,
      public._cms_snapshot('restaurant', r.id) || '{"visibility":"hidden"}'::jsonb, 'visibility', r.reason, null);
  end loop;
end $$;
