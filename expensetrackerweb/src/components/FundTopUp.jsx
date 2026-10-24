import { useState } from "react";
import { addIncome } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { money } from "../utils.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import DescriptionInput from "./DescriptionInput.jsx";
import Modal from "./Modal.jsx";

const round = (n) => Math.round(n * 100) / 100;

// When a payment needs more than a fund holds: ask, add money to that fund in a popup on the same screen,
// then carry on with the payment.
//   const topUp = useFundTopUp({ companyId, user, funds, onFunded });
//   if (short) return topUp.ask(fund, amountNeeded, pay);   // pay() runs after the money is added
//   …render {topUp.ui}
// funds: [{ fundId: "cash" | bankAccountId, name, balance }] of the company being topped up.
export function useFundTopUp({ companyId, user, funds = [], onFunded }) {
  const [state, setState] = useState(null); // { fund, need, then, step: "confirm" | "add" }

  const ask = (fund, need, then) => {
    if (!fund) return;
    setState({ fund, need: round(need), then, step: "confirm" });
  };

  let ui = null;
  if (state?.step === "confirm") {
    const shortBy = round(state.need - Number(state.fund.balance || 0));
    ui = (
      <ConfirmDialog
        title="Not enough balance"
        message={`${state.fund.name} has ${money(state.fund.balance || 0)}, but this payment needs ${money(state.need)} (${money(shortBy)} short). Do you want to add money to ${state.fund.name} and pay now?`}
        confirmLabel="Add money"
        onCancel={() => setState(null)}
        onConfirm={() => setState({ ...state, step: "add" })}
      />
    );
  } else if (state?.step === "add") {
    ui = (
      <AddFundModal
        companyId={companyId}
        user={user}
        funds={funds}
        fund={state.fund}
        need={state.need}
        onClose={() => setState(null)}
        onAdded={(res) => {
          const then = state.then;
          setState(null);
          onFunded?.(res);
          then?.();
        }}
      />
    );
  }
  return { ask, ui };
}

function AddFundModal({ companyId, user, funds, fund, need, onClose, onAdded }) {
  const { showToast } = useToast();
  const shortBy = round(need - Number(fund.balance || 0));
  const [amountText, setAmountText] = useState(String(shortBy));
  const [source, setSource] = useState("direct");
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);
  const isCash = String(fund.fundId) === "cash";
  // money can come in new, or move from another bank account (cash can't be moved into a bank here)
  const sources = funds.filter((f) => String(f.fundId) !== "cash" && String(f.fundId) !== String(fund.fundId));
  const amount = round(Number(amountText) || 0);
  const from = sources.find((f) => String(f.fundId) === source);
  const sourceShort = from && Number(from.balance || 0) < amount;

  async function submit(e) {
    e.preventDefault();
    if (amount < shortBy) return showToast(`Add at least ${money(shortBy)} to cover this payment`, "error");
    if (sourceShort) return showToast(`Only ${money(from.balance)} available in ${from.name}`, "error");
    setSaving(true);
    const res = await addIncome(companyId, user.id, amount, isCash ? "cash" : String(fund.fundId), source, description.trim());
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not add money", "error");
    showToast(`${money(amount)} added to ${fund.name}`);
    onAdded(res);
  }

  return (
    <Modal onClose={onClose} maxWidth={440}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Add money to {fund.name}</h2>
      <p style={{ margin: "0 0 14px", color: "var(--muted)", fontSize: 13 }}>
        Balance {money(fund.balance || 0)} · payment needs {money(need)}. The payment goes through right after the money is added.
      </p>
      <form onSubmit={submit}>
        <label className="field-label">Amount (₹) *</label>
        <input className="field-input" type="number" step="0.01" min={shortBy} value={amountText} onChange={(e) => setAmountText(e.target.value)} />
        <small style={{ display: "block", marginTop: 4, color: "var(--muted)", fontSize: 11.5 }}>At least {money(shortBy)}</small>
        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Money coming from *</label>
        <select className="field-select" value={source} onChange={(e) => setSource(e.target.value)}>
          <option value="direct">{isCash ? "Direct cash (new money)" : "Direct income (new money)"}</option>
          {sources.map((f) => (
            <option key={f.fundId} value={String(f.fundId)}>{f.name} · {money(f.balance || 0)}</option>
          ))}
        </select>
        {sourceShort && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>Only {money(from.balance)} available in {from.name}.</div>}
        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Description (optional)</label>
        <DescriptionInput companyId={companyId} userId={user.id} kind="fund" value={description} onChange={setDescription} placeholder="e.g. Cash withdrawn for office" />
        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving || sourceShort || !(amount > 0)}>
            {saving ? "Adding…" : `Add ${money(amount)} & pay`}
          </button>
        </div>
      </form>
    </Modal>
  );
}
