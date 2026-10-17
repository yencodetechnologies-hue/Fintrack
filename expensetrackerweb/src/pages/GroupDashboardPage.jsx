import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useAuth } from "../context/AuthContext.jsx";
import { useToast } from "../context/ToastContext.jsx";
import {
  addGroupMember,
  createGroupExpense,
  getCompanyDetails,
  getGroupExpenseReceipt,
  getGroupExpenses,
  getUserCompanies,
  removeGroupMember,
  settleExpenseGroup,
} from "../api.js";
import { fileToBase64, formatDate, money, personId, personName } from "../utils.js";
import Navbar from "../components/Navbar.jsx";
import Modal from "../components/Modal.jsx";

export default function GroupDashboardPage() {
  const { groupId } = useParams();
  const { user } = useAuth();
  const { showToast } = useToast();
  const [group, setGroup] = useState(null);
  const [expenses, setExpenses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [modal, setModal] = useState("");
  const [saving, setSaving] = useState(false);
  const [settlePrompt, setSettlePrompt] = useState(false);
  const [settlementType, setSettlementType] = useState("own_company");
  const [lenderCompanyId, setLenderCompanyId] = useState("");
  const [companies, setCompanies] = useState([]);
  const [receipt, setReceipt] = useState("");
  const [draft, setDraft] = useState({
    amount: "",
    description: "",
    category: "General",
    date: new Date().toISOString().slice(0, 10),
    attachment: "",
  });

  const [companyMembers, setCompanyMembers] = useState([]);
  const [membersModal, setMembersModal] = useState(false);
  const [selectedAddMemberId, setSelectedAddMemberId] = useState("");
  const [updatingMember, setUpdatingMember] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    const [res, companyList] = await Promise.all([
      getGroupExpenses(groupId, user.id),
      getUserCompanies(user.id),
    ]);
    if (res.success) {
      setGroup(res.group);
      setExpenses(res.expenses || []);
      setCompanies(Array.isArray(companyList) ? companyList : companyList.companies || []);
      if (res.group?.companyId) {
        const cId = personId(res.group.companyId);
        getCompanyDetails(cId, user.id).then((cRes) => {
          if (cRes.success && cRes.members) setCompanyMembers(cRes.members);
        });
      }
    } else {
      setError(res.message || "Could not load this group");
    }
    setLoading(false);
  }, [groupId, user.id]);

  useEffect(() => {
    load();
  }, [load]);

  const total = useMemo(
    () => expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0),
    [expenses]
  );
  const creatorId = personId(group?.createdBy);
  const isCreator = creatorId === user.id;
  const isSettled = group?.settlementStatus === "settled";
  const companyId = personId(group?.companyId);
  const companyName = personName(group?.companyId, "Company");
  const lenderOptions = companies.filter((company) => company._id !== companyId);

  const groupMemberIds = new Set((group?.members || []).map((m) => personId(m)));
  const availableCompanyMembers = companyMembers.filter(
    (cm) => !groupMemberIds.has(String(cm.userId))
  );

  async function handleCreateExpense(e) {
    e.preventDefault();
    const amount = Number(draft.amount);
    if (!(amount > 0) || !draft.description.trim()) {
      showToast("Enter a positive amount and description", "error");
      return;
    }
    setSaving(true);
    const res = await createGroupExpense(groupId, {
      userId: user.id,
      amount,
      description: draft.description.trim(),
      category: draft.category.trim() || "General",
      date: new Date(draft.date).toISOString(),
      attachment: draft.attachment,
    });
    setSaving(false);
    if (res.success) {
      setModal("");
      setDraft({
        amount: "",
        description: "",
        category: "General",
        date: new Date().toISOString().slice(0, 10),
        attachment: "",
      });
      showToast("Group expense added");
      load();
    } else {
      showToast(res.message || "Could not add expense", "error");
    }
  }

  async function handleReceipt(expense) {
    const res = await getGroupExpenseReceipt(groupId, expense._id, user.id);
    if (!res.success || !res.attachment) {
      showToast(res.message || "Receipt is unavailable", "error");
      return;
    }
    const value = res.attachment.startsWith("data:")
      ? res.attachment
      : `data:image/jpeg;base64,${res.attachment}`;
    setReceipt(value);
  }

  async function handleAttachmentChange(event) {
    const file = event.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) {
      showToast("Receipt must be 5 MB or smaller", "error");
      event.target.value = "";
      return;
    }
    const attachment = await fileToBase64(file);
    setDraft((current) => ({ ...current, attachment }));
  }

  async function handleAddGroupMember(e) {
    e.preventDefault();
    if (!selectedAddMemberId) return;
    setUpdatingMember(true);
    const res = await addGroupMember(groupId, user.id, selectedAddMemberId);
    setUpdatingMember(false);
    if (res.success) {
      showToast("Staff added to group");
      setSelectedAddMemberId("");
      load();
    } else {
      showToast(res.message || "Failed to add staff", "error");
    }
  }

  async function handleRemoveGroupMember(memberId) {
    setUpdatingMember(true);
    const res = await removeGroupMember(groupId, memberId, user.id);
    setUpdatingMember(false);
    if (res.success) {
      showToast("Staff removed from group");
      load();
    } else {
      showToast(res.message || "Failed to remove staff", "error");
    }
  }

  async function handleSettle() {
    if (settlementType === "other_company" && !lenderCompanyId) {
      showToast("Choose the paying company", "error");
      return;
    }
    setSaving(true);
    const payload = {
      userId: user.id,
      settlementType,
      ...(settlementType === "other_company" ? { lenderCompanyId } : {}),
    };
    const res = await settleExpenseGroup(groupId, payload);
    setSaving(false);
    if (res.success) {
      setSettlePrompt(false);
      showToast(
        settlementType === "other_company"
          ? "Group settled and company loan recorded"
          : "Group settled"
      );
      load();
    } else {
      showToast(res.message || "Could not settle this group", "error");
    }
  }

  return (
    <div style={{ minHeight: "100vh" }}>
      <Navbar crumb={group?.name || "Group"} backTo="/companies">
        <Link className="nav-text-btn" to="/companies">
          All expenses
        </Link>
      </Navbar>
      <main className="container" style={{ paddingTop: 34, paddingBottom: 64 }}>
        {loading ? (
          <div style={{ display: "flex", justifyContent: "center", padding: 70 }}>
            <div className="spinner" />
          </div>
        ) : error ? (
          <div className="card">
            <p>{error}</p>
            <button className="btn btn-outline" onClick={load}>
              Retry
            </button>
          </div>
        ) : (
          group && (
            <>
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "flex-start",
                  gap: 16,
                  flexWrap: "wrap",
                  marginBottom: 24,
                }}
              >
                <div>
                  <div className="eyebrow">{companyName}</div>
                  <h1 style={{ color: "#fff", margin: "8px 0 4px", fontSize: 32 }}>{group.name}</h1>
                  <p style={{ color: "rgba(255,255,255,0.68)", margin: 0 }}>
                    Shared group expenses
                  </p>
                </div>
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                  <button className="btn btn-outline" onClick={() => setMembersModal(true)}>
                    Staff ({group.members?.length || 0})
                  </button>
                  {!isSettled && (
                    <button className="btn btn-primary" onClick={() => setModal("expense")}>
                      + Add Expense
                    </button>
                  )}
                </div>
              </div>

              <div
                className="stat-card"
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  gap: 18,
                  flexWrap: "wrap",
                  marginBottom: 24,
                }}
              >
                <div>
                  <div className="field-label">TOTAL RECORDED</div>
                  <div
                    style={{
                      fontFamily: "Fraunces, serif",
                      fontWeight: 700,
                      color: "var(--forest)",
                      fontSize: 28,
                    }}
                  >
                    {money(total)}
                  </div>
                </div>
                {isSettled ? (
                  <span className="pill pill-paid">SETTLED</span>
                ) : (
                  isCreator && (
                    <button
                      className="btn btn-dark"
                      onClick={() => setSettlePrompt(true)}
                      disabled={!total}
                    >
                      Settle Group
                    </button>
                  )
                )}
              </div>
              {isSettled && group.settlementType === "other_company" && (
                <p className="card" style={{ color: "var(--muted)" }}>
                  Settled through another company; a company loan was recorded.
                </p>
              )}

              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  marginBottom: 12,
                }}
              >
                <h2 style={{ color: "#fff", fontSize: 20, margin: 0 }}>Expenses</h2>
                <span style={{ color: "rgba(255,255,255,0.7)", fontSize: 13 }}>
                  {expenses.length} entries
                </span>
              </div>
              {expenses.length === 0 ? (
                <div className="card" style={{ textAlign: "center", color: "var(--muted)" }}>
                  No expenses in this group yet.
                </div>
              ) : (
                expenses.map((expense) => (
                  <article className="card" key={expense._id} style={{ marginBottom: 10, padding: 16 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", gap: 16 }}>
                      <div>
                        <span className="pill pill-category">{expense.category || "General"}</span>
                        <h3 style={{ margin: "10px 0 4px", fontSize: 16 }}>{expense.description}</h3>
                        <span style={{ color: "var(--muted)", fontSize: 12 }}>
                          {personName(expense.createdBy)} ·{" "}
                          {formatDate(expense.date || expense.createdAt)}
                        </span>
                      </div>
                      <strong style={{ whiteSpace: "nowrap" }}>{money(expense.amount)}</strong>
                    </div>
                    {expense.hasAttachment && (
                      <button
                        className="btn btn-outline"
                        style={{ marginTop: 12 }}
                        onClick={() => handleReceipt(expense)}
                      >
                        View receipt
                      </button>
                    )}
                  </article>
                ))
              )}
            </>
          )
        )}
      </main>

      {modal === "expense" && (
        <Modal onClose={() => setModal("")} maxWidth={500}>
          <h2 style={{ marginTop: 0 }}>Add group expense</h2>
          <form onSubmit={handleCreateExpense}>
            <label className="field-label">Amount (₹)</label>
            <input
              className="field-input"
              type="number"
              min="0.01"
              step="0.01"
              value={draft.amount}
              onChange={(e) => setDraft({ ...draft, amount: e.target.value })}
              required
            />
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>
              Description
            </label>
            <input
              className="field-input"
              value={draft.description}
              onChange={(e) => setDraft({ ...draft, description: e.target.value })}
              required
            />
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>
              Category
            </label>
            <input
              className="field-input"
              value={draft.category}
              onChange={(e) => setDraft({ ...draft, category: e.target.value })}
            />
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>
              Date
            </label>
            <input
              className="field-input"
              type="date"
              value={draft.date}
              onChange={(e) => setDraft({ ...draft, date: e.target.value })}
            />
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>
              Receipt (optional)
            </label>
            <input type="file" accept="image/*" onChange={handleAttachmentChange} />
            <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
              <button
                type="button"
                className="btn btn-outline"
                style={{ flex: 1 }}
                onClick={() => setModal("")}
              >
                Cancel
              </button>
              <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>
                {saving ? "Saving…" : "Save Expense"}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {membersModal && (
        <Modal onClose={() => setMembersModal(false)} maxWidth={500}>
          <h2 style={{ marginTop: 0, marginBottom: 6 }}>Group Staff</h2>
          <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 16px" }}>
            Staff who can share and split expenses in this group.
          </p>

          <div style={{ maxHeight: 240, overflowY: "auto", marginBottom: 18 }}>
            {(group.members || []).map((m) => {
              const mId = personId(m);
              const mName = personName(m);
              const isGroupCreator = mId === creatorId;
              return (
                <div
                  key={mId}
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    padding: "8px 0",
                    borderBottom: "1px solid var(--slate-border-2)",
                  }}
                >
                  <div>
                    <div style={{ fontWeight: 600, fontSize: 13.5 }}>{mName}</div>
                    <small style={{ color: "var(--muted)" }}>
                      {isGroupCreator ? "Group Creator" : "Staff"}
                    </small>
                  </div>
                  {isCreator && !isGroupCreator && (
                    <button
                      className="btn btn-outline-danger"
                      style={{ padding: "4px 8px", fontSize: 11.5 }}
                      onClick={() => handleRemoveGroupMember(mId)}
                      disabled={updatingMember}
                    >
                      Remove
                    </button>
                  )}
                </div>
              );
            })}
          </div>

          {isCreator && availableCompanyMembers.length > 0 && (
            <form
              onSubmit={handleAddGroupMember}
              style={{
                marginTop: 14,
                paddingTop: 14,
                borderTop: "1px solid var(--slate-border-2)",
              }}
            >
              <label className="field-label">Add Company Staff to Group</label>
              <div style={{ display: "flex", gap: 8, marginTop: 6 }}>
                <select
                  className="field-select"
                  value={selectedAddMemberId}
                  onChange={(e) => setSelectedAddMemberId(e.target.value)}
                  style={{ flex: 1 }}
                  required
                >
                  <option value="">Select colleague</option>
                  {availableCompanyMembers.map((cm) => (
                    <option key={cm.userId} value={cm.userId}>
                      {cm.name} ({cm.email || cm.role || "Staff"})
                    </option>
                  ))}
                </select>
                <button className="btn btn-primary" disabled={updatingMember || !selectedAddMemberId}>
                  + Add
                </button>
              </div>
            </form>
          )}

          <div style={{ marginTop: 20, textAlign: "right" }}>
            <button className="btn btn-outline" onClick={() => setMembersModal(false)}>
              Close
            </button>
          </div>
        </Modal>
      )}

      {receipt && (
        <Modal onClose={() => setReceipt("")} maxWidth={760}>
          <img
            src={receipt}
            alt="Expense receipt"
            style={{ maxWidth: "100%", maxHeight: "75vh", display: "block", margin: "auto" }}
          />
        </Modal>
      )}
      {settlePrompt && (
        <Modal onClose={() => setSettlePrompt(false)} maxWidth={440}>
          <h2 style={{ marginTop: 0 }}>Settle {group?.name}</h2>
          <p>
            Total group expenses: <strong>{money(total)}</strong>
          </p>
          <label className="group-member-option">
            <input
              type="radio"
              name="settlement"
              checked={settlementType === "own_company"}
              onChange={() => setSettlementType("own_company")}
            />
            Settled by {companyName}
          </label>
          <label className="group-member-option" style={{ marginTop: 8 }}>
            <input
              type="radio"
              name="settlement"
              checked={settlementType === "other_company"}
              onChange={() => setSettlementType("other_company")}
            />
            Settled by another company
          </label>
          {settlementType === "other_company" && (
            <select
              className="field-select"
              style={{ marginTop: 12 }}
              value={lenderCompanyId}
              onChange={(e) => setLenderCompanyId(e.target.value)}
            >
              <option value="">Choose paying company</option>
              {lenderOptions.map((company) => (
                <option key={company._id} value={company._id}>
                  {company.name}
                </option>
              ))}
            </select>
          )}
          <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
            <button
              className="btn btn-outline"
              style={{ flex: 1 }}
              onClick={() => setSettlePrompt(false)}
            >
              Cancel
            </button>
            <button
              className="btn btn-primary"
              style={{ flex: 1 }}
              disabled={saving}
              onClick={handleSettle}
            >
              {saving ? "Settling…" : "Settle group"}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
