import { AudioSourceSelector } from '../../components/audio-source-selector';
import { RecordingsList } from '../../components/recordings-list.tsx';

export function RecordingsPage() {
  return (
    <div className="space-y-8 p-4">
      <AudioSourceSelector />
      <RecordingsList />
    </div>
  );
}

export default RecordingsPage;
