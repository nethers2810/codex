import { useEffect, useState } from 'react';

const apiBase = import.meta.env.VITE_API_BASE || 'http://localhost:8080';

export default function App() {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch(`${apiBase}/api/assessments/latest`)
      .then(async (res) => {
        if (!res.ok) {
          const body = await res.json();
          throw new Error(body.error || 'Failed to load data');
        }
        return res.json();
      })
      .then((json) => setData(json))
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <main className="container">
      <h1>Security Assessment Dashboard</h1>
      <p>Stack: Ubuntu 22.04 + Docker Compose + Laravel</p>

      {loading && <div className="card">Loading latest assessment...</div>}
      {error && <div className="card error">{error}</div>}

      {data && (
        <>
          <section className="card">
            <h2>Latest Assessment</h2>
            <p><strong>ID:</strong> {data.id}</p>
            <p><strong>Target URL:</strong> {data.target_url || '-'}</p>
            <p><strong>Report Dir:</strong> {data.report_dir}</p>
            <p><strong>Created At:</strong> {new Date(data.created_at).toLocaleString()}</p>
          </section>

          <section className="grid">
            <div className="card">
              <h3>Checks Run</h3>
              <p className="metric">{data.summary_json.checksRun}</p>
            </div>
            <div className="card">
              <h3>Skipped Tools</h3>
              <p className="metric">{data.summary_json.skippedTools}</p>
            </div>
            <div className="card">
              <h3>Status</h3>
              <p className="metric">{data.summary_json.status}</p>
            </div>
          </section>

          <section className="card">
            <h2>Stage Completion</h2>
            <ul>
              {Object.entries(data.summary_json.stages).map(([k, v]) => (
                <li key={k}>{k}: {v ? '✅' : '❌'}</li>
              ))}
            </ul>
          </section>

          <section className="card">
            <h2>Executive Summary</h2>
            <pre>{data.summary_json.executiveSummary || 'No summary'}</pre>
          </section>
        </>
      )}
    </main>
  );
}
