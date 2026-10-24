import { useCallback, useEffect, useRef, useState } from "react";
import { getPayableBills, payOwnOutstanding } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, money, PAYMENT_METHODS } from "../utils.js";
import Modal from "./Modal.jsx";

const round = (n) => Math.round(n * 100) / 100;
const keyOf = (b) => (b.transactionId ? `tx:${b.transactionId}` : `exp:${b.expenseId}`);

// Payments page, managers: what the company owes ME, bill by bill. Pay everything or just the ticked bills —
// always from company Cash/Bank (never "by self"); exactly those bills close.
export default function OwnOutstanding({ companyId, company, user, funds, focus, refreshKey, onPaid }) {
  const { showToast } = useToast();
  const [bills, setBills] = useState(null);
  const [selected, setSelected] = useState(() => new Set());
  const [paying, setPaying] = useState(null); // bills being paid
  const [payingAmount, setPayingAmount] = useState(false); // "Pay an amount": spread oldest first
  const ref = useRef(null);

  const load = useCallback(async () => {
    const res = await getPayableBills(companyId, user.id, user.id);
    if (res.success) setBills(res.bills || []);
    else setBills([]);
  }, [companyId, user.id]);

  useEffect(() => {
    load();
  }, [load, refreshKey]);

  // opened from the Home "My outstanding" tile: bring this section into view
  useEffect(() => {
    if (focus && bills && ref.current) ref.current.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [focus, bills]);

  if (!bills) return null;
  const total = round(bills.reduce((s, b) => s + Number(b.remaining || 0), 0));
  if (!(total > 0) && !focus) return null;
  const chosen = bills.filter((b) => selected.has(keyOf(b)));
  const chosenTotal = round(chosen.reduce((s, b) => s + Number(b.remaining || 0), 0));
  const allOn = bills.length > 0 && chosen.length === bills.length;

  const toggle = (b) =>
    setSelected((cur) => {
      const next = new Set(cur);
      if (next.has(keyOf(b))) next.delete(keyOf(b));
      else next.add(keyOf(b));
      return next;
    });

  return (
    <section ref={ref} className={`card own-outstanding${focus ? " focus" : ""}`}>
      {/* sticks to the top while the bill list scrolls; the amount follows the ticked bills */}
      <div className="own-outstanding-head">
        <div>
          <div className="own-outstanding-title">Your outstanding</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: total > 0 ? "var(--terracotta)" : "var(--forest)" }}>
            {/* ticked bills come off the total: what would still be owed after paying them */}
            {money(round(total - chosenTotal))}
          </div>
          <div style={{ color: "var(--muted)", fontSize: 12.5 }}>
            {!(total > 0)
              ? "The company doesn't owe you anything."
              : chosen.length
                ? `${money(chosenTotal)} selected · left after paying the selected bills`
                : `${company?.name || "The company"} owes you this · paid from company Cash/Bank`}
          </div>
        </div>
        {total > 0 && (
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button type="button" className="btn btn-outline" onClick={() => setPayingAmount(true)}>Pay an amount</button>
            <button type="button" className="btn btn-outline" disabled={!chosen.length} onClick={() => setPaying(chosen)}>
              Pay selected{chosen.length ? ` · ${money(chosenTotal)}` : ""}
            </button>
            <button type="button" className="btn btn-primary" onClick={() => setPaying(bills)}>Pay all · {money(total)}</button>
          </div>
        )}
      </div>

      {bills.length > 0 && (
        <div className="expense-list" style={{ marginTop: 12 }}>
          <label className="own-outstanding-row head">
            <input type="checkbox" checked={allOn} onChange={() => setSelected(allOn ? new Set() : new Set(bills.map(keyOf)))} />
            <span>Select all ({bills.length})</span>
          </label>
          {bills.map((b) => (
            <label key={keyOf(b)} className={`own-outstanding-row${selected.has(keyOf(b)) ? " on" : ""}`}>
              <input type="checkbox" checked={selected.has(keyOf(b))} onChange={() => toggle(b)} />
              <span className="own-outstanding-main">
                <span style={{ fontWeight: 600 }}>{b.description}</span>
                <span style={{ color: "var(--muted)", fontSize: 12 }}>
                  {[b.category, formatDate(b.date || b.postedAt), b.claim ? "approved, not yet paid" : b.remaining < b.amount ? `part paid · ${money(b.amount)} in all` : "paid by you"].filter(Boolean).join(" · ")}
                </span>
              </span>
              <strong>{money(b.remaining)}</strong>
            </label>
          ))}
        </div>
      )}

      {payingAmount && (
        <PayOwnModal
          companyId={companyId}
          user={user}
          bills={bills}
          byAmount
          funds={funds}
          onClose={() => setPayingAmount(false)}
          onDone={(res) => {
            setPayingAmount(false);
            setSelected(new Set());
            showToast(`${money(res.paid)} paid to you from company · ${res.closed} bill${res.closed === 1 ? "" : "s"} closed${res.bills > res.closed ? " · 1 part-paid" : ""}`);
            load();
            onPaid?.();
          }}
        />
      )}
      {paying && (
        <PayOwnModal
          companyId={companyId}
          user={user}
          bills={paying}
          funds={funds}
          onClose={() => setPaying(null)}
          onDone={(res) => {
            setPaying(null);
            setSelected(new Set());
            showToast(`${money(res.paid)} paid to you from company · ${res.bills} bill${res.bills === 1 ? "" : "s"} closed`);
            load();
            onPaid?.();
          }}
        />
      )}
    </section>
  );
}

// byAmount: you type an amount; it goes to the oldest bills first (by bill date) and the last may be part-paid.
function PayOwnModal({ companyId, user, bills, funds, byAmount = false, onClose, onDone }) {
  const { showToast } = useToast();
  const [fundId, setFundId] = useState(funds[0]?.fundId || "cash");
  const [method, setMethod] = useState("Bank");
  const [reference, setReference] = useState("");
  const [amountText, setAmountText] = useState("");
  const [saving, setSaving] = useState(false);
  const owed = round(bills.reduce((s, b) => s + Number(b.remaining || 0), 0));
  const typed = round(Math.max(0, Number(amountText) || 0));
  const total = byAmount ? typed : owed;
  const fund = funds.find((f) => String(f.fundId) === String(fundId));
  const short = fund && Number(fund.balance || 0) < total;
  const tooMuch = byAmount && typed > owed + 0.001;

  // oldest first: what this amount does to each bill
  const plan = (() => {
    let left = typed;
    return [...bills]
      .sort((a, b) => new Date(a.date || a.postedAt) - new Date(b.date || b.postedAt))
      .map((b) => {
        const take = round(Math.min(Math.max(0, left), Number(b.remaining || 0)));
        left = round(left - take);
        return { bill: b, take, state: take <= 0 ? "open" : take < Number(b.remaining || 0) ? "part" : "closed" };
      });
  })();

  async function submit(e) {
    e.preventDefault();
    setSaving(true);
    const payload = byAmount
      ? { userId: user.id, amount: typed, fundId, method, reference: reference.trim() }
      : { userId: user.id, items: bills.map((b) => (b.transactionId ? { transactionId: b.transactionId } : { expenseId: b.expenseId })), fundId, method, reference: reference.trim() };
    const res = await payOwnOutstanding(companyId, payload);
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not pay", "error");
    onDone(res);
  }

  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>{byAmount ? "Pay an amount" : "Pay your outstanding"}</h2>
      <p style={{ margin: "0 0 12px", color: "var(--muted)", fontSize: 13 }}>
        {byAmount
          ? <>Goes to your oldest bills first. You're owed <strong style={{ color: "var(--dark-text)" }}>{money(owed)}</strong>.</>
          : <>{bills.length} bill{bills.length === 1 ? "" : "s"} · <strong style={{ color: "var(--dark-text)" }}>{money(total)}</strong> from company funds to you.</>}
      </p>
      <form onSubmit={submit}>
        {byAmount && (
          <>
            <label className="field-label">Amount (₹)</label>
            <div style={{ display: "flex", gap: 8 }}>
              <input className="field-input" type="number" min="0.01" step="0.01" max={owed} autoFocus value={amountText} onChange={(e) => setAmountText(e.target.value)} required style={{ flex: 1 }} />
              <button type="button" className="btn btn-outline" onClick={() => setAmountText(String(owed))}>Full</button>
            </div>
            {tooMuch && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>You're owed only {money(owed)}.</div>}
            {typed > 0 && !tooMuch && (
              <div className="own-plan">
                {plan.map(({ bill, take, state }) => (
                  <div key={keyOf(bill)} className={`own-plan-row ${state}`}>
                    <span>{bill.description}<small>{formatDate(bill.date || bill.postedAt)}</small></span>
                    <span>{state === "closed" ? `Closes · ${money(take)}` : state === "part" ? `${money(take)} of ${money(bill.remaining)}` : "Stays owed"}</span>
                  </div>
                ))}
              </div>
            )}
            <div style={{ height: 12 }} />
          </>
        )}
        <label className="field-label">Paid from</label>
        <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)}>
          {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
        </select>
        {short && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>Only {money(fund.balance)} available in {fund.name}.</div>}
        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
        <select className="field-select" value={method} onChange={(e) => setMethod(e.target.value)}>
          {PAYMENT_METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Reference (optional)</label>
        <input className="field-input" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="UTR / cheque no." />
        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving || short || tooMuch || !(total > 0)}>{saving ? "Paying…" : `Pay ${money(total)}`}</button>
        </div>
      </form>
    </Modal>
  );
}
