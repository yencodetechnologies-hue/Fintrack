import { useEffect, useMemo, useState } from "react";
import { getDescriptionSuggestions } from "../api.js";

// Text input that suggests descriptions used before in this company.
// kind: "expense" | "payment" | "fund" (picks which past descriptions the backend returns).
export default function DescriptionInput({ companyId, userId, kind, value, onChange, style, ...inputProps }) {
  const [all, setAll] = useState([]);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!companyId || !userId) return;
    let alive = true;
    getDescriptionSuggestions(companyId, userId, kind).then((res) => {
      if (alive && res.success) setAll(res.descriptions || []);
    });
    return () => { alive = false; };
  }, [companyId, userId, kind]);

  const matches = useMemo(() => {
    const q = String(value || "").trim().toLowerCase();
    return all.filter((d) => d.toLowerCase() !== q && (!q || d.toLowerCase().includes(q))).slice(0, 8);
  }, [all, value]);

  return (
    <div style={{ position: "relative" }}>
      <input
        className="field-input"
        autoComplete="off"
        {...inputProps}
        style={style}
        value={value}
        onChange={(e) => { onChange(e.target.value); setOpen(true); }}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onKeyDown={(e) => { if (e.key === "Escape" && open) { e.stopPropagation(); setOpen(false); } }}
      />
      {open && !inputProps.disabled && matches.length > 0 && (
        <div
          style={{
            position: "absolute",
            top: "calc(100% + 4px)",
            left: 0,
            right: 0,
            zIndex: 20,
            background: "#fff",
            border: "1px solid var(--slate-border)",
            borderRadius: 10,
            boxShadow: "0 8px 24px rgba(15, 23, 42, 0.12)",
            maxHeight: 240,
            overflowY: "auto",
            padding: 4,
          }}
        >
          <div style={{ fontSize: 11, color: "var(--muted)", padding: "4px 10px" }}>Previously used</div>
          {matches.map((d) => (
            <button
              key={d}
              type="button"
              // mousedown fires before the input's blur, so the pick lands before the list closes
              onMouseDown={(e) => { e.preventDefault(); onChange(d); setOpen(false); }}
              style={{
                display: "block",
                width: "100%",
                textAlign: "left",
                background: "none",
                border: "none",
                borderRadius: 6,
                padding: "8px 10px",
                fontSize: 13,
                color: "var(--dark-text)",
                cursor: "pointer",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
              onMouseEnter={(e) => { e.currentTarget.style.background = "var(--slate-bg)"; }}
              onMouseLeave={(e) => { e.currentTarget.style.background = "none"; }}
            >
              {d}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
