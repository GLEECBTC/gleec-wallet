"""HTML report generator for test run results."""

from __future__ import annotations

import json
from pathlib import Path

from jinja2 import Template

from .models import TestRun

REPORT_TEMPLATE = Template("""\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gleec QA Report — {{ run.timestamp }}</title>
<style>
  :root {
    --bg: #1a1a2e; --surface: #16213e; --card: #0f3460;
    --text: #e6e6e6; --muted: #8a8a9a;
    --pass: #00c853; --fail: #ff1744; --flaky: #ffab00;
    --error: #d50000; --skip: #607d8b;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg); color: var(--text);
    line-height: 1.6; padding: 2rem;
  }
  h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
  .meta { color: var(--muted); font-size: 0.85rem; margin-bottom: 1.5rem; }
  .summary {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 1rem; margin-bottom: 2rem;
  }
  .stat {
    background: var(--surface); border-radius: 8px; padding: 1rem;
    text-align: center;
  }
  .stat .value { font-size: 2rem; font-weight: 700; }
  .stat .label { color: var(--muted); font-size: 0.8rem; text-transform: uppercase; }
  .stat.pass .value { color: var(--pass); }
  .stat.fail .value { color: var(--fail); }
  .stat.flaky .value { color: var(--flaky); }
  .stat.error .value { color: var(--error); }
  .stat.skip .value { color: var(--skip); }
  table {
    width: 100%; border-collapse: collapse; background: var(--surface);
    border-radius: 8px; overflow: hidden;
  }
  th {
    background: var(--card); padding: 0.75rem 1rem; text-align: left;
    font-size: 0.8rem; text-transform: uppercase; color: var(--muted);
  }
  td { padding: 0.6rem 1rem; border-top: 1px solid #1a1a3e; font-size: 0.9rem; }
  tr:hover td { background: rgba(255,255,255,0.03); }
  .badge {
    display: inline-block; padding: 2px 10px; border-radius: 12px;
    font-size: 0.75rem; font-weight: 600; text-transform: uppercase;
  }
  .badge-pass { background: var(--pass); color: #000; }
  .badge-fail { background: var(--fail); color: #fff; }
  .badge-flaky { background: var(--flaky); color: #000; }
  .badge-error { background: var(--error); color: #fff; }
  .badge-skip { background: var(--skip); color: #fff; }
  .tags { color: var(--muted); font-size: 0.75rem; }
  .attempts { font-size: 0.75rem; color: var(--muted); }
  .error-msg { color: var(--fail); font-size: 0.8rem; max-width: 300px; }
  .section-title { margin: 2rem 0 1rem; font-size: 1.2rem; }
  .manual-badge { background: #795548; color: #fff; }
  details { margin-top: 0.3rem; }
  details summary { cursor: pointer; color: var(--muted); font-size: 0.8rem; }
  details pre {
    background: var(--bg); padding: 0.5rem; border-radius: 4px;
    font-size: 0.75rem; overflow-x: auto; margin-top: 0.3rem;
  }
</style>
</head>
<body>
<h1>Gleec Wallet QA Report</h1>
<div class="meta">
  {{ run.timestamp }} &middot; {{ run.base_url }} &middot;
  Engine: {{ run.engine }} &middot; Model: {{ run.model }} &middot;
  Duration: {{ "%.0f"|format(run.duration_seconds) }}s
</div>

<div class="summary">
  <div class="stat"><div class="value">{{ run.total }}</div><div class="label">Total</div></div>
  <div class="stat pass"><div class="value">{{ run.passed }}</div><div class="label">Passed</div></div>
  <div class="stat fail"><div class="value">{{ run.failed }}</div><div class="label">Failed</div></div>
  <div class="stat flaky"><div class="value">{{ run.flaky }}</div><div class="label">Flaky</div></div>
  <div class="stat error"><div class="value">{{ run.errors }}</div><div class="label">Errors</div></div>
  <div class="stat skip"><div class="value">{{ run.skipped }}</div><div class="label">Skipped</div></div>
  <div class="stat"><div class="value">{{ run.pass_rate }}%</div><div class="label">Pass Rate</div></div>
</div>

<h2 class="section-title">Automated Tests</h2>
<table>
<thead>
<tr>
  <th>ID</th><th>Name</th><th>Tags</th><th>Status</th>
  <th>Confidence</th><th>Votes</th><th>Duration</th><th>Details</th>
</tr>
</thead>
<tbody>
{% for r in run.voted_results %}
<tr>
  <td>{{ r.test_id }}</td>
  <td>{{ r.test_name }}</td>
  <td class="tags">{{ r.tags | join(', ') }}</td>
  <td><span class="badge badge-{{ r.final_status | lower }}">{{ r.final_status }}</span></td>
  <td>{{ "%.0f"|format(r.confidence * 100) }}%</td>
  <td class="attempts">{{ r.vote_counts }}</td>
  <td>{{ "%.1f"|format(r.duration_seconds) }}s</td>
  <td>
    {% if r.attempts %}
    <details>
      <summary>{{ r.attempts | length }} attempt(s)</summary>
      <pre>{{ r.attempts | tojson }}</pre>
    </details>
    {% endif %}
    {% if r.manual_verification_note %}
    <div class="error-msg">Manual check: {{ r.manual_verification_note }}</div>
    {% endif %}
  </td>
</tr>
{% endfor %}
</tbody>
</table>

{% if run.manual_results %}
<h2 class="section-title">Manual / Interactive Tests</h2>
<table>
<thead>
<tr><th>ID</th><th>Title</th><th>Status</th><th>Notes</th></tr>
</thead>
<tbody>
{% for m in run.manual_results %}
<tr>
  <td>{{ m.test_id }}</td>
  <td>{{ m.title }}</td>
  <td><span class="badge {% if m.status == 'PASS' %}badge-pass{% elif m.status == 'FAIL' %}badge-fail{% else %}badge-skip{% endif %}">{{ m.status }}</span></td>
  <td>{{ m.notes }}</td>
</tr>
{% endfor %}
</tbody>
</table>
{% endif %}

</body>
</html>
""")


def generate_html_report(run: TestRun, output_path: Path) -> None:
    """Render the test run as a styled HTML report."""
    html = REPORT_TEMPLATE.render(run=run.model_dump())
    output_path.write_text(html, encoding="utf-8")


def write_json_results(run: TestRun, output_path: Path) -> None:
    """Write the test run as a structured JSON file."""
    output_path.write_text(
        json.dumps(run.model_dump(), indent=2, default=str),
        encoding="utf-8",
    )
