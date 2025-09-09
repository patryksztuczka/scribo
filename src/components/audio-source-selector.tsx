import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getApplications, getInputDevices, startCapture, stopCapture } from '../data-access-layer/audio';
import {
  loadLastSelectedAppPid,
  loadLastSelectedMicId,
  saveLastSelectedAppPid,
  saveLastSelectedMicId,
} from '../data-access-layer/audio-preferences.ts';

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

  const selectedAppQuery = useQuery({
    queryKey: ['selectedAppPid'],
    enabled: !!apps?.length,
    queryFn: loadLastSelectedAppPid,
    select: (pid) => {
      if (!pid || !apps) return '';
      return apps.some((app) => String(app.pid) === pid) ? pid : '';
    },
    staleTime: Infinity,
    gcTime: Infinity,
    refetchOnWindowFocus: false,
  });

  const selectedMicQuery = useQuery({
    queryKey: ['selectedMicId'],
    enabled: !!mics?.length,
    queryFn: loadLastSelectedMicId,
    select: (id) => {
      if (!id || !mics) return '';
      return mics.some((mic) => mic.id === id) ? id : '';
    },
    staleTime: Infinity,
    gcTime: Infinity,
    refetchOnWindowFocus: false,
  });
  const [isCapturing, setIsCapturing] = useState(false);
  const [error, setError] = useState<string>('');

  const setSelectedAppMutation = useMutation({
    mutationFn: async (pid: string) => {
      if (!apps?.some((app) => String(app.pid) === pid)) return '';
      saveLastSelectedAppPid(pid);
      return pid;
    },
    onSuccess: (pid) => {
      queryClient.setQueryData(['selectedAppPid'], pid);
    },
  });

  const setSelectedMicMutation = useMutation({
    mutationFn: async (id: string) => {
      if (!mics?.some((mic) => mic.id === id)) return '';
      saveLastSelectedMicId(id);
      return id;
    },
    onSuccess: (id) => {
      queryClient.setQueryData(['selectedMicId'], id);
    },
  });

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
            value={selectedAppQuery.data ?? ''}
            onChange={(e) => setSelectedAppMutation.mutate(e.target.value)}
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
            value={selectedMicQuery.data ?? ''}
            onChange={(e) => setSelectedMicMutation.mutate(e.target.value)}
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
          onClick={() => startCaptureMutation(selectedAppQuery.data ?? '')}
          disabled={!selectedAppQuery.data || isCapturing}
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
