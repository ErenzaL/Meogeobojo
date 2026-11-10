import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Route, Routes } from 'react-router-dom'
import { RequireAdmin, RequireRole } from '@/layouts'
import AnalyticsPage from '@/features/AnalyticsPage'
import AuditPage from '@/features/AuditPage'
import CafeteriaPage from '@/features/CafeteriaPage'
import ContentPage from '@/features/ContentPage'
import MenusPage from '@/features/MenusPage'
import MissionsPage from '@/features/MissionsPage'
import ModerationPage from '@/features/ModerationPage'
import PhotosPage from '@/features/PhotosPage'
import OverviewPage from '@/features/OverviewPage'
import RecommendationsPage from '@/features/RecommendationsPage'
import RestaurantFormPage from '@/features/restaurants/RestaurantFormPage'
import RestaurantsPage from '@/features/restaurants/RestaurantsPage'
import SettingsPage from '@/features/SettingsPage'
import UniversitiesPage from '@/features/UniversitiesPage'
import UsersPage from '@/features/UsersPage'
import LoginPage from '@/pages/LoginPage'
import { AuthProvider } from '@/lib/auth'

export const makeQueryClient = () => new QueryClient({ defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false, staleTime: 15_000 } } })

export function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<RequireAdmin />}>
        <Route index element={<OverviewPage />} />
        <Route element={<RequireRole min="moderator" />}>
          <Route path="moderation" element={<ModerationPage />} />
          <Route path="missions" element={<MissionsPage />} />
          <Route path="analytics" element={<AnalyticsPage />} />
          <Route path="settings" element={<SettingsPage />} />
        </Route>
        <Route element={<RequireRole min="admin" />}>
          <Route path="restaurants" element={<RestaurantsPage />} />
          <Route path="restaurants/new" element={<RestaurantFormPage />} />
          <Route path="restaurants/:id" element={<RestaurantFormPage />} />
          <Route path="menus" element={<MenusPage />} />
          <Route path="photos" element={<PhotosPage />} />
          <Route path="universities" element={<UniversitiesPage />} />
          <Route path="cafeteria" element={<CafeteriaPage />} />
          <Route path="users" element={<UsersPage />} />
          <Route path="content" element={<ContentPage />} />
          <Route path="audit" element={<AuditPage />} />
          <Route path="recommendations" element={<RecommendationsPage />} />
        </Route>
        <Route path="*" element={<div className="p-8 text-sm text-muted">페이지를 찾을 수 없어요.</div>} />
      </Route>
    </Routes>
  )
}

export default function App({ client = makeQueryClient() }: { client?: QueryClient }) {
  return (
    <QueryClientProvider client={client}>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </QueryClientProvider>
  )
}
