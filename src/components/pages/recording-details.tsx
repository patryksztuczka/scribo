import { useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';

function downloadTextFile(filename: string, content: string, mimeType: string) {
  const blob = new Blob([content], { type: `${mimeType};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export function RecordingDetailsPage() {
  const params = useParams();
  const encodedPath = params.id ?? '';
  const path = useMemo(() => {
    try {
      return decodeURIComponent(encodedPath);
    } catch {
      return encodedPath;
    }
  }, [encodedPath]);

  const title = useMemo(() => {
    if (!path) return 'Recording';
    const parts = path.split('/');
    return parts[parts.length - 1] || 'Recording';
  }, [path]);

  // Mocked data
  const summary = useMemo(
    () =>
      `# Summary\n\n- Topic: Mock conversation about product design\n- Key decisions: Adopt a thin left sidebar, lazy routes\n- Action items: Implement export to md/txt, wire details screen\n\nThis is a placeholder summary for ${title}.`,
    [title],
  );
  const transcription = useMemo(
    () =>
      [
        'Speaker 1: Welcome to the meeting. Today we discuss the new recording flow.',
        'Speaker 2: Agreed. Let’s implement a details screen with summary and transcription tabs.',
        'Speaker 1: We will also add export buttons for summary (md) and transcription (txt).',
      ].join('\n'),
    [],
  );

  const [activeTab, setActiveTab] = useState<'summary' | 'transcript'>('summary');

  return (
    <div className="p-4">
      <div className="mb-2 text-sm">
        <Link to="/recordings" className="text-blue-600 hover:underline">
          Recordings
        </Link>
        <span className="mx-2 text-gray-400">/</span>
        <span className="text-gray-700">{title}</span>
      </div>
      <div className="mb-4 flex items-center justify-between">
        <h3 className="truncate text-lg font-semibold" title={title}>
          {title}
        </h3>
        <div className="flex items-center gap-2">
          <button
            className="rounded border px-3 py-2 text-sm"
            onClick={() => downloadTextFile(`${title}.md`, summary, 'text/markdown')}
          >
            Export summary (.md)
          </button>
          <button
            className="rounded border px-3 py-2 text-sm"
            onClick={() => downloadTextFile(`${title}.txt`, transcription, 'text/plain')}
          >
            Export transcription (.txt)
          </button>
        </div>
      </div>

      <div className="mb-3 flex items-center gap-2">
        <button
          className={`rounded px-3 py-1 text-sm ${activeTab === 'summary' ? 'border' : 'text-gray-600 hover:underline'}`}
          onClick={() => setActiveTab('summary')}
        >
          Summary
        </button>
        <button
          className={`rounded px-3 py-1 text-sm ${activeTab === 'transcript' ? 'border' : 'text-gray-600 hover:underline'}`}
          onClick={() => setActiveTab('transcript')}
        >
          Transcription
        </button>
      </div>

      {activeTab === 'summary' ? (
        <pre className="rounded border bg-gray-50 p-3 text-sm whitespace-pre-wrap">{summary}</pre>
      ) : (
        <pre className="rounded border bg-gray-50 p-3 text-sm whitespace-pre-wrap">{transcription}</pre>
      )}
    </div>
  );
}

export default RecordingDetailsPage;
