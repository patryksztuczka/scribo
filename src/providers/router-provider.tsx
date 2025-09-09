import { Suspense, lazy } from 'react';
import { HashRouter, Navigate, Route, Routes } from 'react-router-dom';

import AppLayout from '../components/app-layout.tsx';

const RecordingsPage = lazy(() => import('../components/pages/recordings.tsx'));
const SettingsPage = lazy(() => import('../components/pages/settings.tsx'));
const RecordingDetailsPage = lazy(() => import('../components/pages/recording-details.tsx'));

export function AppRouterProvider() {
  return (
    <HashRouter>
      <AppLayout>
        <Suspense fallback={<div className="p-4 text-sm text-gray-600">Loading…</div>}>
          <Routes>
            <Route path="/" element={<Navigate to="/recordings" replace />} />
            <Route path="/recordings" element={<RecordingsPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="/recordings/:id" element={<RecordingDetailsPage />} />
            <Route path="*" element={<Navigate to="/recordings" replace />} />
          </Routes>
        </Suspense>
      </AppLayout>
    </HashRouter>
  );
}

export default AppRouterProvider;
