import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { downloadDir, join } from "@tauri-apps/api/path";
import { z } from "zod";

const AppItemSchema = z.object({
  pid: z.number(),
  name: z.string(),
  bundleId: z.string().optional().default(""),
});
const AppListSchema = z.array(AppItemSchema);

type AppItem = z.infer<typeof AppItemSchema>;

function App() {
  const [greetMsg, setGreetMsg] = useState("");
  const [apps, setApps] = useState<AppItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<{ kind: string; id: string } | null>(
    null
  );
  const [isCapturing, setIsCapturing] = useState(false);
  const [mics, setMics] = useState<any[] | null>(null);
  const [selectedMic, setSelectedMic] = useState<string | null>(null);

  async function greet() {
    setGreetMsg(await invoke("hello_cpp"));
  }

  async function loadApps() {
    setError(null);
    try {
      const raw = await invoke("list_apps");
      const parsed = AppListSchema.parse(raw);
      setApps(parsed);
      const micList: any = await invoke("list_input_devices");
      setMics(micList);
    } catch (e: any) {
      setError(e?.toString?.() ?? "Unknown error");
    }
  }

  async function start() {
    if (!selected) {
      setError("Select a source first");
      return;
    }
    setError(null);
    try {
      const dir = await downloadDir();
      const base = await join(dir, "scribo");
      const file = await join(base, `capture-${Date.now()}.wav`);
      await invoke("start_capture", {
        kind: selected.kind,
        id: selected.id,
        outPath: file,
      });
      setIsCapturing(true);
    } catch (e: any) {
      setError(e?.toString?.() ?? "Unknown error");
    }
  }

  async function stop() {
    try {
      await invoke("stop_capture");
    } finally {
      setIsCapturing(false);
    }
  }

  return (
    <main className="container">
      <div className="row" style={{ gap: 8 }}>
        <button onClick={loadApps}>Load Apps</button>
        {error && <span style={{ color: "red" }}>{error}</span>}
      </div>

      {apps && (
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: 16,
            marginTop: 16,
          }}
        >
          <div>
            <h3>Applications</h3>
            <ul>
              {apps.map((a) => (
                <li key={`a-${a.pid}`}>
                  <label style={{ cursor: "pointer" }}>
                    <input
                      type="radio"
                      name="source"
                      onChange={() =>
                        setSelected({ kind: "application", id: String(a.pid) })
                      }
                    />
                    {a.name || a.bundleId || a.pid}
                  </label>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <h3>Microphones</h3>
            <ul>
              {(mics || []).map((d: any) => (
                <li key={`mic-${d.id}`}>
                  <label style={{ cursor: "pointer" }}>
                    <input
                      type="radio"
                      name="mic"
                      onChange={() => setSelectedMic(String(d.id))}
                    />
                    {d.name || d.uniqueId}
                  </label>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}

      {selected && <p>Selected app PID: {selected.id}</p>}
      {selectedMic && <p>Mic: {selectedMic}</p>}

      <div className="row" style={{ gap: 8, marginTop: 16 }}>
        <button onClick={start} disabled={!selected || isCapturing}>
          Start capture
        </button>
        <button onClick={stop} disabled={!isCapturing}>
          Stop capture
        </button>
        {isCapturing && (
          <span>Recording to Downloads/scribo (timestamped)…</span>
        )}
      </div>
    </main>
  );
}

export default App;
