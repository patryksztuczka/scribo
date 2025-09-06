import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AudioSourceSelector } from './components/audio-source-selector';
import { RecordingsList } from './components/recordings-list.tsx';

const queryClient = new QueryClient();

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <main className="space-y-8 p-4">
        <AudioSourceSelector />
        <RecordingsList />
      </main>
    </QueryClientProvider>
  );
}

export default App;
