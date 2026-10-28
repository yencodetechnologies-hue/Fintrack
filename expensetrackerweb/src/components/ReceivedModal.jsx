import { useEffect, useState } from "react";
import { getLedgerBorrowSources, receivedLedgerExpense } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { money, PAYMENT_METHODS, roleLabel } from "../utils.js";
import Modal from "./Modal.jsx";
import { useFundTopUp } from "./FundTopUp.jsx";
import { NewLenderFields, newLenderPayload } from "./NewLenderFields.jsx";

// A manager's own expense (company owes them): record that they got the money back — from the company's
// Cash/Bank, from another member who paid them personally (the company then owes that member), or from another
// company (this company borrows from it: a company I manage, or an outside one). Closes it.
const OUTSIDE = "__outside__";

export default function ReceivedModal({ expense, company, user, members, funds, otherCompanies = [], canBorrow = false, onClose, onDone }) {
  const { showToast } = useToast();
  const [from, setFrom] = useState("company");
  const [fundId, setFundId] = useState(funds[0]?.fundId || "cash");
  const others = members.filter((m) => String(m.userId) !== String(user.id));
  const [personId, setPersonId] = useState("");
  const [method, setMethod] = useState("UPI");
  const [reference, setReference] = useState("");
  const [saving, setSaving] = useState(false);
  // from "borrow": "co:<companyId>:<fundId>" (a company I manage, and which of its accounts paid), or OUTSIDE
  const [lenderPick, setLenderPick] = useState("");
  const [outsideName, setOutsideName] = useState("");
  const [outsideGstin, setOutsideGstin] = useState("");
  const [outsideKind, setOutsideKind] = useState("company");
  const [outsidePhone, setOutsidePhone] = useState("");
  // every other company (loaded the first time "Another company" is picked); mine come first with their accounts
  const [allCompanies, setAllCompanies] = useState(null);
  const thisCompanyId = String(company?._id || expense.companyId?._id || expense.companyId);
  useEffect(() => {
    if (from !== "borrow" || allCompanies !== null) return;
    getLedgerBorrowSources(thisCompanyId, user.id).then((res) => setAllCompanies(res.success ? res.companies || [] : []));
  }, [from, allCompanies, thisCompanyId, user.id]);
  const mineIds = new Set(otherCompanies.map((c) => String(c._id)));
  const restCompanies = (allCompanies || []).filter((c) => !mineIds.has(String(c._id)) && String(c._id) !== thisCompanyId);
  const lenderId = lenderPick.startsWith("co:") ? lenderPick.split(":")[1] : "";
  const lenderName = lenderPick === OUTSIDE
    ? outsideName.trim() || "the outside company"
    : [...otherCompanies, ...(allCompanies || [])].find((c) => String(c._id) === lenderId)?.name || "";
  const amount = Number(expense.amount || 0);
  const fund = funds.find((f) => String(f.fundId) === String(fundId));
  const short = from === "company" && fund && Number(fund.balance || 0) < amount;
  const person = others.find((m) => String(m.userId) === String(personId));

  const topUp = useFundTopUp({ companyId: company?._id || expense.companyId?._id || expense.companyId, user, funds });

  function submit(event) {
    event.preventDefault();
    if (from === "person" && !personId) return showToast("Choose who paid you", "error");
    if (from === "borrow" && !lenderPick) return showToast("Choose the company that paid you", "error");
    if (from === "borrow" && lenderPick === OUTSIDE) {
      const check = newLenderPayload(outsideKind, outsideName, outsideGstin, outsidePhone);
      if (check.error) return showToast(check.error, "error");
    }
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
      ...(from === "borrow"
        ? lenderPick === OUTSIDE
          ? { newCompany: newLenderPayload(outsideKind, outsideName, outsideGstin, outsidePhone).newCompany }
          : { sourceCompanyId: lenderPick.split(":")[1], sourceFundId: lenderPick.split(":")[2] }
        : {}),
      method,
      reference: reference.trim(),
    });
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not mark it received", "error");
    showToast(from === "borrow" ? `Marked received · ${company?.name || "the company"} now owes ${lenderName} ${money(amount)}` : from === "person" ? `Marked received · ${company?.name || "the company"} now owes ${person?.name || "them"} ${money(amount)}` : `Marked received · ${money(amount)} from ${fund?.name || "company"}`);
    onDone?.();
  }

  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Mark received</h2>
      <p style={{ margin: "0 0 14px", color: "var(--muted)", fontSize: 14 }}>
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
          {canBorrow && (
            <button type="button" className={from === "borrow" ? "on" : ""} onClick={() => setFrom("borrow")}>
              <strong>Another company</strong>
              <span>It paid you; {company?.name || "this company"} borrows from it</span>
            </button>
          )}
        </div>

        {from === "company" ? (
          <>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Paid from</label>
            <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)}>
              {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
            </select>
            {short && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>Only {money(fund.balance)} available in {fund.name}. You can add money when you pay.</div>}
          </>
        ) : from === "borrow" ? (
          <>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Which company paid you?</label>
            <select className="field-select" value={lenderPick} onChange={(e) => setLenderPick(e.target.value)}>
              <option value="">{allCompanies === null ? "Loading companies…" : "Choose a company"}</option>
              {/* my companies: pick which of their accounts paid */}
              {otherCompanies.map((c) => (
                <optgroup key={c._id} label={c.name}>
                  <option value={`co:${c._id}:cash`}>{c.name} · {c.cashAccountName || "Cash"}</option>
                  {(c.bankAccounts || []).map((b) => <option key={b._id} value={`co:${c._id}:${b._id}`}>{c.name} · {b.bankName}</option>)}
                </optgroup>
              ))}
              {restCompanies.length > 0 && (
                <optgroup label="Other companies">
                  {restCompanies.map((c) => <option key={c._id} value={`co:${c._id}:cash`}>{c.name}{c.lenderKind === "person" ? " (person)" : c.external ? " (outside)" : ""}</option>)}
                </optgroup>
              )}
              <option value={OUTSIDE}>+ Add company or person…</option>
            </select>
            {lenderPick === OUTSIDE && (
              <NewLenderFields kind={outsideKind} onKind={setOutsideKind} name={outsideName} onName={setOutsideName} gstin={outsideGstin} onGstin={setOutsideGstin} phone={outsidePhone} onPhone={setOutsidePhone} />
            )}
            {lenderPick && (
              <div style={{ marginTop: 6, fontSize: 12, color: "var(--muted)", lineHeight: 1.45 }}>
                {company?.name || "The company"} borrows {money(amount)} from {lenderName}: it shows under Borrowed here and Lent there until repaid.
                {lenderId && !mineIds.has(lenderId) && !restCompanies.find((c) => String(c._id) === lenderId)?.external && ` ${lenderName}'s admins are notified.`}
              </div>
            )}
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
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving || (from === "person" && !personId) || (from === "borrow" && !lenderPick)}>
            {saving ? "Saving…" : "Mark received"}
          </button>
        </div>
      </form>
      {topUp.ui}
    </Modal>
  );
}
