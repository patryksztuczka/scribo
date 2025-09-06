import { NavLink, Outlet } from 'react-router-dom';
import { Mic, Settings } from 'lucide-react';

export function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-screen">
      <aside className="flex w-14 flex-col items-center gap-3 border-r p-2">
        <NavLink
          to="/recordings"
          className={({ isActive }) =>
            `flex h-10 w-10 items-center justify-center rounded ${isActive ? 'bg-gray-200' : 'hover:bg-gray-100'}`
          }
          aria-label="Recordings"
          title="Recordings"
        >
          <Mic size={18} />
        </NavLink>
        <NavLink
          to="/settings"
          className={({ isActive }) =>
            `flex h-10 w-10 items-center justify-center rounded ${isActive ? 'bg-gray-200' : 'hover:bg-gray-100'}`
          }
          aria-label="Settings"
          title="Settings"
        >
          <Settings size={18} />
        </NavLink>
      </aside>

      <main className="flex-1 overflow-auto">{children ?? <Outlet />}</main>
    </div>
  );
}

export default AppLayout;
