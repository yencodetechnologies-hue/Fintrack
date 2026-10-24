import { useState } from "react";
import { receivedLedgerExpense } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { money, PAYMENT_METHODS, roleLabel } from "../utils.js";
import Modal from "./Modal.jsx";
import { useFundTopUp } from "./FundTopUp.jsx";

// A manager's own expense (company owes them): record that they got the money back — from the company's
// Cash/Bank, or from another member who paid them personally (the company then owes that member). Closes it.
export default function ReceivedModal({ expense, company, user, members, funds, onClose, onDone }) {
  const { showToast } = useToast();
  const [from, setFrom] = useState("company");
  const [fundId, setFundId] = useState(funds[0]?.fundId || "cash");
  const others = members.filter((m) => String(m.userId) !== String(user.id));
  const [personId, setPersonId] = useState("");
  const [method, setMethod] = useState("UPI");
  const [reference, setReference] = useState("");
  const [saving, setSaving] = useState(false);
  const amount = Number(expense.amount || 0);
  const fund = funds.find((f) => String(f.fundId) === String(fundId));
  const short = from === "company" && fund && Number(fund.balance || 0) < amount;
  const person = others.find((m) => String(m.userId) === String(personId));

  const topUp = useFundTopUp({ companyId: company?._id || expense.companyId?._id || expense.companyId, user, funds });

  function submit(event) {
    event.preventDefault();
    if (from === "person" && !personId) return showToast("Choose who paid you", "error");
    if (short) return topUp.ask(fund, amount, save);
    save();
  }

  async function save() {
    setSaving(true);
    const res = await receivedLedgerExpense(expense._id, {
      userId: user.id,
      from,
      fundId: from === "company" ? fundId : undefined,
      personId: from === "person" ? personId : undefined,
      method,
      reference: reference.trim(),
    });
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not mark it received", "error");
    showToast(from === "person" ? `Marked received · ${company?.name || "the company"} now owes ${person?.name || "them"} ${money(amount)}` : `Marked received · ${money(amount)} from ${fund?.name || "company"}`);
    onDone?.();
  }

  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Mark received</h2>
      <p style={{ margin: "0 0 14px", color: "var(--muted)", fontSize: 13.5 }}>
        {expense.description} · <strong style={{ color: "var(--dark-text)" }}>{money(amount)}</strong> — you got this money back, so the expense closes.
      </p>
      <form onSubmit={submit}>
        <label className="field-label">Received from</label>
        <div className="payments-choice">
          <button type="button" className={from === "company" ? "on" : ""} onClick={() => setFrom("company")}>
            <strong>{company?.name || "Company"}</strong>
            <span>From Cash or Bank</span>
          </button>
          <button type="button" className={from === "person" ? "on" : ""} onClick={() => setFrom("person")} disabled={!others.length}>
            <strong>A person</strong>
            <span>They paid you; the company owes them</span>
          </button>
        </div>

        {from === "company" ? (
          <>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Paid from</label>
            <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)}>
              {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
            </select>
            {short && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>Only {money(fund.balance)} available in {fund.name}. You can add money when you pay.</div>}
          </>
        ) : (
          <>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Who paid you?</label>
            <select className="field-select" value={personId} onChange={(e) => setPersonId(e.target.value)} required>
              <option value="">Choose a person</option>
              {others.map((m) => <option key={m.userId} value={m.userId}>{m.name} · {roleLabel(company, m.role)}</option>)}
            </select>
            {person && <div style={{ marginTop: 6, fontSize: 12, color: "var(--muted)" }}>{company?.name || "The company"} will owe {person.name} {money(amount)}.</div>}
          </>
        )}

        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
        <select className="field-select" value={method} onChange={(e) => setMethod(e.target.value)}>
          {PAYMENT_METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Reference (optional)</label>
        <input className="field-input" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="UTR / cheque no." />

        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving || (from === "person" && !personId)}>
            {saving ? "Saving…" : "Mark received"}
          </button>
        </div>
      </form>
      {topUp.ui}
    </Modal>
  );
}
