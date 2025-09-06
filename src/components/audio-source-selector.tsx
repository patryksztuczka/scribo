import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getApplications, getInputDevices, startCapture, stopCapture } from '../data-access-layer/audio';

export const AudioSourceSelector = () => {
  const queryClient = useQueryClient();
  const { data: apps } = useQuery({
    queryKey: ['apps'],
    queryFn: getApplications,
  });
  const { data: mics } = useQuery({
    queryKey: ['mics'],
    queryFn: getInputDevices,
  });
  const { mutate: startCaptureMutation } = useMutation({
    mutationFn: (id: string) => startCapture(id),
    onSuccess: () => {
      setIsCapturing(true);
    },
    onError: (error) => {
      setError(error.message);
    },
  });
  const { mutate: stopCaptureMutation } = useMutation({
    mutationFn: stopCapture,
    onSuccess: () => {
      setIsCapturing(false);
      void queryClient.invalidateQueries({ queryKey: ['recordings'] });
    },
    onError: (error) => {
      setError(error.message);
    },
  });

  const [selectedApp, setSelectedApp] = useState<string>('');
  const [selectedMic, setSelectedMic] = useState<string>('');
  const [isCapturing, setIsCapturing] = useState(false);
  const [error, setError] = useState<string>('');

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold">Audio sources</h3>
      {error && <div className="text-sm text-red-600">{error}</div>}

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        {/* System Audio */}
        <div className="space-y-3">
          <label className="text-sm font-medium">System audio</label>
          <select
            className="w-full rounded border px-3 py-2 text-sm"
            value={selectedApp}
            onChange={(e) => setSelectedApp(e.target.value)}
          >
            <option value="" disabled>
              Pick an application
            </option>
            {(apps || []).map((app) => (
              <option key={app.pid} value={String(app.pid)}>
                {app.name || app.bundleId || app.pid}
              </option>
            ))}
          </select>
        </div>

        {/* Microphone */}
        <div className="space-y-3">
          <label className="text-sm font-medium">Microphone</label>
          <select
            className="w-full rounded border px-3 py-2 text-sm"
            value={selectedMic}
            onChange={(e) => setSelectedMic(e.target.value)}
          >
            <option value="" disabled>
              Pick a microphone
            </option>
            {(mics || []).map((mic) => (
              <option key={mic.id} value={mic.id}>
                {mic.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Controls */}
      <div className="flex items-center gap-2">
        <button
          className="rounded border px-3 py-2 text-sm disabled:opacity-50"
          onClick={() => startCaptureMutation(selectedApp)}
          disabled={!selectedApp || isCapturing}
        >
          Start capture
        </button>
        <button
          className="rounded border px-3 py-2 text-sm disabled:opacity-50"
          onClick={() => stopCaptureMutation()}
          disabled={!isCapturing}
        >
          Stop capture
        </button>
        {isCapturing && <span className="text-xs text-gray-600">Recording…</span>}
      </div>
    </div>
  );
};

export default AudioSourceSelector;
