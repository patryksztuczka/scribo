import { useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';

import { getRecordings, getRecordingDataUrl, deleteRecording } from '../data-access-layer/audio.ts';

export const RecordingsList = () => {
  const {
    data: recordings,
    refetch,
    isLoading,
    error,
  } = useQuery({
    queryKey: ['recordings'],
    queryFn: getRecordings,
    refetchOnWindowFocus: false,
  });
  const { mutate: deleteRecordingMutation } = useMutation({
    mutationFn: (path: string) => deleteRecording(path),
    onSuccess: () => {
      refetch();
    },
    onError: (error) => {
      setPlayError(error.message);
    },
  });

  const [currentSrc, setCurrentSrc] = useState<string>('');
  const [playError, setPlayError] = useState<string>('');
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const onPlay = async (path: string) => {
    setPlayError('');
    let url = '';
    try {
      url = await getRecordingDataUrl(path);
    } catch (e) {
      setPlayError((e as Error).message);
      return;
    }
    setCurrentSrc(url);
    const el = audioRef.current;
    if (el) {
      el.src = url;
      void el.play();
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-semibold">Recordings</h3>
        <button
          className="rounded border px-3 py-1 text-sm disabled:opacity-50"
          onClick={() => refetch()}
          disabled={isLoading}
        >
          Refresh
        </button>
      </div>
      {error && <div className="text-sm text-red-600">{(error as Error).message}</div>}
      {isLoading && <div className="text-sm text-gray-500">Loading…</div>}
      <ul className="divide-y rounded border">
        {recordings?.map((r) => (
          <li key={r.path} className="flex items-center justify-between px-3 py-2">
            <div className="min-w-0">
              <div className="truncate text-sm font-medium">
                <Link
                  to={`/recordings/${encodeURIComponent(r.path)}`}
                  className="text-blue-600 hover:underline"
                  title={r.fileName}
                >
                  {r.fileName}
                </Link>
              </div>
              <div className="text-xs text-gray-600">{new Date(r.createdAtMs).toLocaleString()}</div>
            </div>
            <div className="flex items-center gap-2">
              <button className="rounded border px-2 py-1 text-xs" onClick={() => onPlay(r.path)}>
                Play
              </button>
              <button
                className="rounded border px-2 py-1 text-xs text-red-600"
                onClick={() => deleteRecordingMutation(r.path)}
              >
                Delete
              </button>
            </div>
          </li>
        ))}
        {recordings?.length === 0 && !isLoading && (
          <li className="px-3 py-2 text-sm text-gray-600">No recordings yet.</li>
        )}
      </ul>
      <audio
        ref={audioRef}
        controls
        className="w-full"
        onError={() => {
          const err = audioRef.current?.error;
          const code = err?.code ?? 0;
          const msg =
            code === 1
              ? 'Aborted'
              : code === 2
                ? 'Network error'
                : code === 3
                  ? 'Decoding error'
                  : code === 4
                    ? 'Source not supported'
                    : 'Unknown error';
          setPlayError(`${msg} (code ${code})`);
        }}
      >
        {currentSrc && <source src={currentSrc} type="audio/wav" />}
      </audio>
      {playError && <div className="text-sm text-red-600">Failed to play: {playError}</div>}
    </div>
  );
};

export default RecordingsList;
