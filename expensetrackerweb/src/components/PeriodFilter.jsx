import { useEffect, useState } from "react";

const inputStyle = { height: 38, padding: "0 10px", fontSize: 13, width: 150, marginBottom: 0 };
const labelStyle = { fontSize: 12, fontWeight: 600, color: "var(--muted)" };

const pad = (n) => String(n).padStart(2, "0");
const todayKey = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

// Every date-range filter in the app: All time / Day / Month / Year / Custom.
// Works in YYYY-MM-DD strings and reports the chosen range as onChange(from, to); "" means open-ended.
export default function PeriodFilter({ from, to, onChange, years, label = "Period" }) {
  const [mode, setMode] = useState(() => (from || to ? "custom" : "all"));

  // a parent "Reset" clears the range: show All time again
  useEffect(() => {
    if (!from && !to && mode !== "custom") setMode("all");
  }, [from, to, mode]);

  function setPeriod(kind, value) {
    if (!value) return;
    if (kind === "day") onChange(value, value);
    else if (kind === "month") {
      const [y, m] = value.split("-").map(Number);
      onChange(`${value}-01`, `${value}-${pad(new Date(y, m, 0).getDate())}`);
    } else if (kind === "year") onChange(`${value}-01-01`, `${value}-12-31`);
  }

  function choose(next) {
    setMode(next);
    const today = todayKey();
    if (next === "all") onChange("", "");
    else if (next === "day") setPeriod("day", today);
    else if (next === "month") setPeriod("month", today.slice(0, 7));
    else if (next === "year") setPeriod("year", today.slice(0, 4));
  }

  const yearList = (years && years.length ? years : [String(new Date().getFullYear())]).slice().sort().reverse();
  if (mode === "year" && from && !yearList.includes(from.slice(0, 4))) yearList.unshift(from.slice(0, 4));

  return (
    <div className="period-filter">
      <div className="period-filter-field">
        {label && <span style={labelStyle}>{label}</span>}
        <select
          className="field-select"
          style={{ ...inputStyle, width: "auto", minWidth: 110 }}
          value={mode}
          onChange={(e) => choose(e.target.value)}
          title="Filter by day, month, year or a custom range"
        >
          <option value="all">All time</option>
          <option value="day">Day</option>
          <option value="month">Month</option>
          <option value="year">Year</option>
          <option value="custom">Custom</option>
        </select>
      </div>

      {mode === "day" && (
        <input type="date" className="field-input" style={inputStyle} value={from} onChange={(e) => setPeriod("day", e.target.value)} title="Day" />
      )}
      {mode === "month" && (
        <input type="month" className="field-input" style={inputStyle} value={(from || "").slice(0, 7)} onChange={(e) => setPeriod("month", e.target.value)} title="Month" />
      )}
      {mode === "year" && (
        <select className="field-select" style={{ ...inputStyle, width: "auto" }} value={(from || "").slice(0, 4)} onChange={(e) => setPeriod("year", e.target.value)} title="Year">
          {yearList.map((y) => <option key={y} value={y}>{y}</option>)}
        </select>
      )}
      {mode === "custom" && (
        <>
          <div className="period-filter-field">
            <span style={labelStyle}>From</span>
            <input type="date" className="field-input" style={inputStyle} value={from} onChange={(e) => onChange(e.target.value, to)} title="From date" />
          </div>
          <div className="period-filter-field">
            <span style={labelStyle}>To</span>
            <input type="date" className="field-input" style={inputStyle} value={to} onChange={(e) => onChange(from, e.target.value)} title="To date" />
          </div>
        </>
      )}
    </div>
  );
}
