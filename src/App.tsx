import { useState } from "react";
import reactLogo from "./assets/react.svg";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";

function App() {
  const [greetMsg, setGreetMsg] = useState("");
  const [sources, setSources] = useState<any | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<{ kind: string; id: string } | null>(
    null
  );

  async function greet() {
    setGreetMsg(await invoke("hello_cpp"));
  }

  async function loadSources() {
    setError(null);
    try {
      const result = await invoke("list_sources");
      setSources(result);
    } catch (e: any) {
      setError(e?.toString?.() ?? "Unknown error");
    }
  }

  return (
    <main className="container">
      <h1>Welcome to Tauri + React</h1>

      <div className="row">
        <a href="https://vite.dev" target="_blank">
          <img src="/vite.svg" className="logo vite" alt="Vite logo" />
        </a>
        <a href="https://tauri.app" target="_blank">
          <img src="/tauri.svg" className="logo tauri" alt="Tauri logo" />
        </a>
        <a href="https://react.dev" target="_blank">
          <img src={reactLogo} className="logo react" alt="React logo" />
        </a>
      </div>
      <p>Click on the Tauri, Vite, and React logos to learn more.</p>

      <form
        className="row"
        onSubmit={(e) => {
          e.preventDefault();
          greet();
        }}
      >
        <input id="greet-input" placeholder="Enter a name..." />
        <button type="submit">Greet</button>
      </form>
      <p>{greetMsg}</p>
      <div className="row" style={{ gap: 8 }}>
        <button onClick={loadSources}>Load Sources</button>
        {error && <span style={{ color: "red" }}>{error}</span>}
      </div>
      {sources && (
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr 1fr",
            gap: 16,
            marginTop: 16,
          }}
        >
          <div>
            <h3>Displays</h3>
            <ul>
              {(sources.displays || []).map((d: any) => (
                <li key={`d-${d.id}`}>
                  <label style={{ cursor: "pointer" }}>
                    <input
                      type="radio"
                      name="source"
                      onChange={() =>
                        setSelected({ kind: "display", id: String(d.id) })
                      }
                    />
                    {d.name ?? `Display ${d.id}`}
                  </label>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <h3>Windows</h3>
            <ul>
              {(sources.windows || []).map((w: any) => (
                <li key={`w-${w.id}`}>
                  <label style={{ cursor: "pointer" }}>
                    <input
                      type="radio"
                      name="source"
                      onChange={() =>
                        setSelected({ kind: "window", id: String(w.id) })
                      }
                    />
                    {w.title || "(no title)"}{" "}
                    {w.appName ? `- ${w.appName}` : ""}
                  </label>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <h3>Applications</h3>
            <ul>
              {(sources.applications || []).map((a: any) => (
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
        </div>
      )}
      {selected && (
        <p>
          Selected: {selected.kind} #{selected.id}
        </p>
      )}
    </main>
  );
}

export default App;
