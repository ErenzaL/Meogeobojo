import ContentPage from './ContentPage'

/** 알림: what the bell (🔔) in the app and on the website lists. It is the existing 앱 콘텐츠 pipeline for two kinds, so
 *  everything works the same way: a new item is created switched OFF, editing saves a draft, and the publishing toolbar
 *  publishes, schedules (Seoul time), unpublishes and restores, with history and an audit record. */
export default function NotificationsPage() {
  return (
    <ContentPage kinds={['notification', 'announcement']} defaultKind="notification" title="알림"
      description="앱과 웹의 종 아이콘(🔔) 목록에 보이는 알림을 관리해요. '알림'은 종 아이콘 목록에만, '공지'는 홈 카드와 목록에 함께 보여요. 새 항목은 꺼진 상태로 만들어지고, 게시하거나 예약해야 보여요. 앱을 쓰는 기기마다 '안 읽음' 표시가 따로 있어요." />
  )
}
