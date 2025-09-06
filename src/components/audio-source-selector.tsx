import { useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { downloadDir, join } from '@tauri-apps/api/path';
import { z } from 'zod';

const AppItemSchema = z.object({
  pid: z.number(),
  name: z.string(),
  bundleId: z.string().optional().default(''),
});
const AppListSchema = z.array(AppItemSchema);

type AppItem = z.infer<typeof AppItemSchema>;

type MicItem = { id: string; name: string; uniqueId?: string };

export const AudioSourceSelector = () => {
  const [apps, setApps] = useState<AppItem[] | null>(null);
  const [mics, setMics] = useState<MicItem[] | null>(null);
  const [selectedApp, setSelectedApp] = useState<string>('');
  const [selectedMic, setSelectedMic] = useState<string>('');
  const [isTesting, setIsTesting] = useState(false);
  const [micLevel, setMicLevel] = useState(45);
  const [systemLevel, setSystemLevel] = useState(60);
  const [testProgress, setTestProgress] = useState(0);
  const [isCapturing, setIsCapturing] = useState(false);
  const [error, setError] = useState<string>('');

  const timerRef = useRef<number | null>(null);
  const animRef = useRef<number | null>(null);

  async function loadLists() {
    setError('');
    try {
      const raw = await invoke('list_apps');
      const parsed = AppListSchema.parse(raw);
      setApps(parsed);
      const micRaw: any = await invoke('list_input_devices');
      const micList: MicItem[] = Array.isArray(micRaw)
        ? micRaw.map((d: any) => ({
            id: String(d.id),
            name: String(d.name ?? d.uniqueId ?? d.id),
            uniqueId: d.uniqueId,
          }))
        : [];
      setMics(micList);
    } catch (e: any) {
      setError(e?.toString?.() ?? 'Failed to load devices');
    }
  }

  useEffect(() => {
    loadLists();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleTestAudio = () => {
    if (isTesting) return;
    setIsTesting(true);
    setTestProgress(0);

    const start = Date.now();
    const durationMs = 3000;

    const tick = () => {
      const elapsed = Date.now() - start;
      const p = Math.min(100, Math.round((elapsed / durationMs) * 100));
      setTestProgress(p);
      if (elapsed >= durationMs) {
        setIsTesting(false);
        if (timerRef.current) window.clearInterval(timerRef.current);
        timerRef.current = null;
        return;
      }
    };

    timerRef.current = window.setInterval(tick, 100);

    const animate = () => {
      setMicLevel((prev) => Math.max(0, Math.min(100, prev + (Math.random() * 16 - 8))));
      setSystemLevel((prev) => Math.max(0, Math.min(100, prev + (Math.random() * 16 - 8))));
      if (isTesting) {
        animRef.current = window.setTimeout(animate, 150) as unknown as number;
      }
    };
    animRef.current = window.setTimeout(animate, 150) as unknown as number;
  };

  useEffect(() => {
    if (!isTesting) {
      if (animRef.current) window.clearTimeout(animRef.current);
      animRef.current = null;
    }
    return () => {
      if (timerRef.current) window.clearInterval(timerRef.current);
      if (animRef.current) window.clearTimeout(animRef.current);
    };
  }, [isTesting]);

  async function startCapture() {
    setError('');
    if (!selectedApp) {
      setError('Wybierz aplikację');
      return;
    }
    try {
      const dir = await downloadDir();
      const base = await join(dir, 'scribo');
      const file = await join(base, `capture-${Date.now()}.wav`);
      await invoke('start_capture', {
        kind: 'application',
        id: selectedApp,
        outPath: file,
      });
      setIsCapturing(true);
    } catch (e: any) {
      setError(e?.toString?.() ?? 'Start capture failed');
    }
  }

  async function stopCapture() {
    try {
      await invoke('stop_capture');
    } catch (e) {
      // ignore
    }
    setIsCapturing(false);
  }

  const levelBars = (level: number) => (
    <div className="flex gap-1">
      {Array.from({ length: 5 }).map((_, i) => (
        <div
          key={i}
          className={['h-4 w-1 rounded-full', i < Math.floor(level / 20) ? 'bg-gray-600' : 'bg-gray-200'].join(' ')}
        />
      ))}
    </div>
  );

  const progressBars = (progress: number) => (
    <div className="grid grid-cols-20 gap-0.5">
      {Array.from({ length: 20 }).map((_, i) => (
        <div
          key={i}
          className={['h-1 rounded-sm', i < Math.floor(progress / 5) ? 'bg-gray-600' : 'bg-gray-200'].join(' ')}
        />
      ))}
    </div>
  );

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold">Źródła Audio</h3>
      {error && <div className="text-sm text-red-600">{error}</div>}

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        {/* System Audio */}
        <div className="space-y-3">
          <label className="text-sm font-medium">Dźwięk systemowy</label>
          <select
            className="w-full rounded border px-3 py-2 text-sm"
            value={selectedApp}
            onChange={(e) => setSelectedApp(e.target.value)}
          >
            <option value="" disabled>
              Wybierz aplikację
            </option>
            {(apps || []).map((app) => (
              <option key={app.pid} value={String(app.pid)}>
                {app.name || app.bundleId || app.pid}
              </option>
            ))}
          </select>

          <div className="space-y-1">
            <div className="flex items-center justify-between text-xs text-gray-500">
              <span>Poziom systemu</span>
              <span>{systemLevel}%</span>
            </div>
            <div className="flex items-center gap-2">{levelBars(systemLevel)}</div>
          </div>
        </div>

        {/* Microphone */}
        <div className="space-y-3">
          <label className="text-sm font-medium">Mikrofon</label>
          <select
            className="w-full rounded border px-3 py-2 text-sm"
            value={selectedMic}
            onChange={(e) => setSelectedMic(e.target.value)}
          >
            <option value="" disabled>
              Wybierz mikrofon
            </option>
            {(mics || []).map((mic) => (
              <option key={mic.id} value={mic.id}>
                {mic.name}
              </option>
            ))}
          </select>

          <div className="space-y-1">
            <div className="flex items-center justify-between text-xs text-gray-500">
              <span>Poziom mikrofonu</span>
              <span>{micLevel}%</span>
            </div>
            <div className="flex items-center gap-2">{levelBars(micLevel)}</div>
          </div>
        </div>
      </div>

      {/* Controls */}
      <div className="flex items-center gap-2">
        <button
          className="rounded border px-3 py-2 text-sm"
          onClick={startCapture}
          disabled={!selectedApp || isCapturing}
        >
          Start capture
        </button>
        <button className="rounded border px-3 py-2 text-sm" onClick={stopCapture} disabled={isCapturing === false}>
          Stop capture
        </button>
        {isCapturing && <span className="text-xs text-gray-600">Recording…</span>}
      </div>

      {/* Test Audio */}
      <div className="space-y-2">
        <button
          className="rounded border px-3 py-2 text-sm"
          onClick={handleTestAudio}
          disabled={isTesting || !selectedApp || !selectedMic}
        >
          {isTesting ? 'Testowanie...' : 'Testuj Audio'}
        </button>
        {isTesting && (
          <div className="space-y-2 rounded border p-2">
            <div className="flex items-center justify-between text-sm">
              <span>Test audio w toku</span>
              <span className="text-xs text-gray-500">3s</span>
            </div>
            {progressBars(testProgress)}
          </div>
        )}
      </div>
    </div>
  );
};

export default AudioSourceSelector;
