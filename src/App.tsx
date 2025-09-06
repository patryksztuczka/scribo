import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AudioSourceSelector } from './components/audio-source-selector';

const queryClient = new QueryClient();

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <main>
        <AudioSourceSelector />
      </main>
    </QueryClientProvider>
  );
}

export default App;
