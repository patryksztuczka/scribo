import AppRouterProvider from './providers/router-provider.tsx';
import AppQueryClientProvider from './providers/query-client-provider.tsx';

function App() {
  return (
    <AppQueryClientProvider>
      <AppRouterProvider />
    </AppQueryClientProvider>
  );
}

export default App;
