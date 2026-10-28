import { useState } from "react";

// Text size for the whole web: every size in the app is in px, so the page is scaled as a whole (CSS zoom).
// The choice is per viewer, kept in this browser and applied before the app first draws (main.jsx).
// 11 steps from 80% to 130%; 100% is the default.
export const TEXT_STEPS = [0.8, 0.85, 0.9, 0.95, 1, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3];
const KEY = "et_text_size";

export function savedTextSize() {
  try {
    const v = Number(localStorage.getItem(KEY));
    return TEXT_STEPS.includes(v) ? v : 1;
  } catch {
    return 1;
  }
}

export function applyTextSize(value) {
  document.documentElement.style.zoom = value === 1 ? "" : String(value);
}

// Settings / Profile card: A- ——o—— A+ slider with a tick per step; applies at once and is remembered
export default function TextSizeCard({ style }) {
  const [size, setSize] = useState(savedTextSize);
  const index = Math.max(0, TEXT_STEPS.indexOf(size));

  function choose(i) {
    const value = TEXT_STEPS[Math.min(TEXT_STEPS.length - 1, Math.max(0, i))];
    setSize(value);
    applyTextSize(value);
    try {
      localStorage.setItem(KEY, String(value));
    } catch {
      // storage blocked: the size still applies for this visit
    }
  }

  return (
    <div className="card text-size-card" style={style}>
      <div className="text-size-head">
        <h3>Font size</h3>
        <span>{Math.round(size * 100)}%{size === 1 ? " · default" : ""}</span>
      </div>
      <div className="text-size-box">
        <button type="button" className="text-size-a small" onClick={() => choose(index - 1)} aria-label="Smaller text">A -</button>
        <div className="text-size-track">
          <input
            type="range"
            min={0}
            max={TEXT_STEPS.length - 1}
            step={1}
            value={index}
            onChange={(e) => choose(Number(e.target.value))}
            aria-label="Font size"
            aria-valuetext={`${Math.round(size * 100)}%`}
          />
          <div className="text-size-ticks" aria-hidden="true">
            {TEXT_STEPS.map((s) => <span key={s} className={s === 1 ? "mid" : ""} />)}
          </div>
        </div>
        <button type="button" className="text-size-a big" onClick={() => choose(index + 1)} aria-label="Bigger text">A +</button>
      </div>
      {size !== 1 && (
        <button type="button" className="report-link" style={{ marginTop: 8 }} onClick={() => choose(TEXT_STEPS.indexOf(1))}>Reset to default</button>
      )}
    </div>
  );
}
