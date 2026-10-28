import { formatDate, money } from "../utils.js";

// Shows a person's open bills oldest first and which ones `amount` will close (same FIFO rule as the server).
export default function PayableBillsPreview({ bills, loading, amount }) {
  if (loading) return <div style={{ color: "var(--muted)", fontSize: 13, fontStyle: "italic", marginTop: 10 }}>Loading open bills…</div>;
  if (!bills.length) return <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 10 }}>No open bills.</div>;

  const { rows } = bills.reduce(
    (acc, bill) => {
      const applied = Math.min(bill.remaining, Math.max(0, acc.left));
      const state = applied >= bill.remaining ? "closed" : applied > 0 ? "partial" : "open";
      return { left: Math.round((acc.left - applied) * 100) / 100, rows: [...acc.rows, { ...bill, applied, state }] };
    },
    { left: Number(amount) || 0, rows: [] }
  );
  const closing = rows.filter((r) => r.state === "closed").length;

  return (
    <div style={{ marginTop: 12 }}>
      <div className="field-label" style={{ display: "flex", justifyContent: "space-between" }}>
        <span>Open bills (oldest first)</span>
        {Number(amount) > 0 && <span style={{ color: "var(--forest)" }}>{closing} of {rows.length} will be closed</span>}
      </div>
      {rows.some((r) => r.claim) && (
        <p style={{ margin: "0 0 6px", fontSize: 12, color: "var(--muted)", lineHeight: 1.4 }}>
          Approved claims this payment reaches are recorded as paid by this person, then closed.
        </p>
      )}
      <div style={{ maxHeight: 220, overflowY: "auto", border: "1px solid var(--slate-border)", borderRadius: 10 }}>
        {rows.map((r, idx) => (
          <div
            key={String(r.transactionId || r.expenseId)}
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              gap: 10,
              padding: "8px 12px",
              fontSize: 13,
              borderBottom: idx < rows.length - 1 ? "1px solid var(--slate-border-2)" : "none",
              background: r.state === "closed" ? "#ECFDF5" : r.state === "partial" ? "#FFF7ED" : "transparent",
            }}
          >
            <span style={{ minWidth: 0 }}>
              <strong style={{ display: "block", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{r.description}</strong>
              <span style={{ color: "var(--muted)" }}>
                {formatDate(r.date)}
                {r.remaining < r.amount ? ` · ${money(r.amount - r.remaining)} already paid` : ""}
                {r.claim ? " · Approved claim (not yet marked paid)" : ""}
              </span>
            </span>
            <span style={{ textAlign: "right", flexShrink: 0 }}>
              <strong>{money(r.remaining)}</strong>
              <div style={{ fontSize: 11, fontWeight: 700, color: r.state === "closed" ? "#047857" : r.state === "partial" ? "#C2410C" : "var(--muted)" }}>
                {r.state === "closed" ? "✓ Will be closed" : r.state === "partial" ? `Partly paid ${money(r.applied)}` : "Stays open"}
              </div>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
