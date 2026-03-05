import express from 'express';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import { Pool } from 'pg';

const app = express();
const port = Number(process.env.PORT || 8080);

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

const safeRead = (filePath) => {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return '';
  }
};

const countMatches = (text, regex) => (text.match(regex) || []).length;

function buildSummary(reportDir) {
  const logFile = path.join(reportDir, 'assessment.log');
  const summaryFile = path.join(reportDir, 'EXEC_SUMMARY.md');
  const log = safeRead(logFile);
  const execSummary = safeRead(summaryFile);

  const checksRun = countMatches(log, /Running:/g);
  const skippedTools = countMatches(log, /skipping/g);

  return {
    reportDir,
    checksRun,
    skippedTools,
    status: 'completed',
    generatedAt: new Date().toISOString(),
    stages: {
      os: /Stage 1/.test(log),
      docker: /Stage 2/.test(log),
      laravel: /Stage 3/.test(log),
      web: /Stage 4/.test(log),
      remediation: /Stage 5/.test(log)
    },
    executiveSummary: execSummary.slice(0, 5000)
  };
}

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

app.post('/api/assessments/import', async (req, res) => {
  const { reportDir, targetUrl } = req.body;
  if (!reportDir) {
    return res.status(400).json({ error: 'reportDir is required' });
  }

  const absoluteDir = path.resolve(reportDir);
  if (!fs.existsSync(absoluteDir)) {
    return res.status(404).json({ error: 'reportDir not found' });
  }

  const summary = buildSummary(absoluteDir);
  const logExcerpt = safeRead(path.join(absoluteDir, 'assessment.log')).slice(0, 8000);

  const query = `
    INSERT INTO assessments(target_url, report_dir, summary_json, log_excerpt)
    VALUES($1,$2,$3,$4)
    ON CONFLICT(report_dir)
    DO UPDATE SET target_url=EXCLUDED.target_url, summary_json=EXCLUDED.summary_json, log_excerpt=EXCLUDED.log_excerpt
    RETURNING id, created_at
  `;

  const result = await pool.query(query, [targetUrl || null, absoluteDir, summary, logExcerpt]);
  return res.json({ message: 'imported', assessment: result.rows[0], summary });
});

app.get('/api/assessments', async (_req, res) => {
  const result = await pool.query(
    'SELECT id, target_url, report_dir, created_at, summary_json FROM assessments ORDER BY created_at DESC LIMIT 50'
  );
  res.json(result.rows);
});

app.get('/api/assessments/latest', async (_req, res) => {
  const result = await pool.query(
    'SELECT id, target_url, report_dir, created_at, summary_json, log_excerpt FROM assessments ORDER BY created_at DESC LIMIT 1'
  );
  if (!result.rows[0]) {
    return res.status(404).json({ error: 'no assessment imported yet' });
  }
  return res.json(result.rows[0]);
});

app.listen(port, () => {
  console.log(`API listening on ${port}`);
});
