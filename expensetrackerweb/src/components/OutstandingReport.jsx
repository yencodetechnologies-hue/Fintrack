import { useCallback, useEffect, useState } from "react";
import { getOutstandingReport } from "../api.js";
import { money } from "../utils.js";

const th = { textAlign: "left", fontSize: 11, fontWeight: 700, letterSpacing: 0.5, color: "var(--muted)", padding: "8px 10px", borderBottom: "1px solid var(--slate-border)" };
const td = { padding: "9px 10px", fontSize: 13, borderBottom: "1px solid var(--slate-border-2)" };
const num = { ...td, textAlign: "right", whiteSpace: "nowrap" };

function Tile({ label, value, color }) {
  return (
    <div className="stat-card">
      <div style={{ fontSize: 10.5, color: "var(--muted)", fontWeight: 700, letterSpacing: 0.6, marginBottom: 6 }}>{label}</div>
      <div style={{ fontSize: 20, fontWeight: 800, color: color || "var(--dark-text)" }}>{money(value)}</div>
    </div>
  );
}

function PeopleTable({ title, rows }) {
  return (
    <div className="card" style={{ marginBottom: 16, padding: 0, overflowX: "auto" }}>
      <h3 style={{ fontSize: 16, margin: 0, padding: "14px 14px 6px" }}>{title}</h3>
      {rows.length === 0 ? (
        <div style={{ color: "var(--muted)", padding: "6px 14px 16px", fontSize: 13 }}>Nothing outstanding.</div>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 640 }}>
          <thead>
            <tr>
              <th style={th}>NAME</th>
              <th style={{ ...th, textAlign: "right" }}>PAID, NOT REIMBURSED</th>
              <th style={{ ...th, textAlign: "right" }}>APPROVED CLAIMS</th>
              <th style={{ ...th, textAlign: "right" }}>COMPANY OWES</th>
              <th style={{ ...th, textAlign: "right" }}>AWAITING APPROVAL</th>
              <th style={{ ...th, textAlign: "right" }}>VOUCHER MONEY HELD</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.userId}>
                <td style={td}><strong>{r.name}</strong></td>
                <td style={num}>{money(r.recorded)}</td>
                <td style={num}>{money(r.claims)}{r.claimCount ? <small style={{ color: "var(--muted)" }}> ({r.claimCount})</small> : null}</td>
                <td style={{ ...num, fontWeight: 800, color: r.owed > 0 ? "var(--terracotta)" : "var(--dark-text)" }}>{money(r.owed)}</td>
                <td style={{ ...num, color: "var(--muted)" }}>{money(r.awaitingApproval)}{r.awaitingCount ? <small> ({r.awaitingCount})</small> : null}</td>
                <td style={{ ...num, color: r.advanceHeld > 0 ? "var(--forest)" : "var(--muted)" }}>{money(r.advanceHeld || 0)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

// Who the company owes right now (managers, staff) and where it stands with other companies.
export default function OutstandingReport({ companyId, userId, refreshKey }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    const res = await getOutstandingReport(companyId, userId);
    if (res.success) {
      setData(res);
      setError("");
    } else setError(res.message || "Could not load outstanding report");
  }, [companyId, userId]);

  useEffect(() => {
    load();
  }, [load, refreshKey]);

  return (
    <section style={{ marginTop: 28 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap", marginBottom: 12 }}>
        <h2 style={{ fontSize: 20, margin: 0 }}>Outstanding</h2>
        <button className="btn btn-outline" onClick={load}>Refresh</button>
      </div>
      {error ? (
        <div className="card" style={{ color: "var(--terracotta)" }}>{error}</div>
      ) : !data ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 32 }}><div className="spinner" /></div>
      ) : (
        <>
          <div className="m-tiles-2" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(170px, 1fr))", gap: 12, marginBottom: 18 }}>
            <Tile label="OWED TO MANAGERS" value={data.totals.owedToManagers} color="var(--terracotta)" />
            <Tile label="OWED TO STAFF" value={data.totals.owedToStaff} color="var(--terracotta)" />
            <Tile label="WE OWE COMPANIES" value={data.totals.weOweCompanies} color="var(--terracotta)" />
            <Tile label="COMPANIES OWE US" value={data.totals.companiesOweUs} color="var(--forest)" />
            <Tile label="AWAITING APPROVAL" value={data.totals.awaitingApproval} />
            <Tile label="VOUCHER MONEY WITH STAFF" value={data.totals.advanceHeld || 0} />
          </div>

          <PeopleTable title="Managers" rows={data.managers} />
          <PeopleTable title="Staff" rows={data.staff} />

          <div className="card" style={{ padding: 0, overflowX: "auto" }}>
            <h3 style={{ fontSize: 16, margin: 0, padding: "14px 14px 6px" }}>Companies</h3>
            {data.companies.length === 0 ? (
              <div style={{ color: "var(--muted)", padding: "6px 14px 16px", fontSize: 13 }}>No open company loans.</div>
            ) : (
              <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 480 }}>
                <thead>
                  <tr>
                    <th style={th}>COMPANY</th>
                    <th style={{ ...th, textAlign: "right" }}>WE OWE THEM</th>
                    <th style={{ ...th, textAlign: "right" }}>THEY OWE US</th>
                    <th style={{ ...th, textAlign: "right" }}>NET</th>
                  </tr>
                </thead>
                <tbody>
                  {data.companies.map((c) => (
                    <tr key={c.companyId}>
                      <td style={td}>
                        <strong>{c.name}</strong>
                        <small style={{ color: "var(--muted)" }}> · {c.loans} open loan{c.loans === 1 ? "" : "s"}{c.external ? " · outside company" : ""}</small>
                      </td>
                      <td style={num}>{money(c.weOwe)}</td>
                      <td style={num}>{money(c.theyOwe)}</td>
                      <td style={{ ...num, fontWeight: 800, color: c.net < 0 ? "var(--terracotta)" : "var(--forest)" }}>
                        {c.net < 0 ? `We owe ${money(-c.net)}` : c.net > 0 ? `They owe ${money(c.net)}` : "Settled"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
          <p style={{ color: "var(--muted)", fontSize: 12, marginTop: 10 }}>
            "Company owes" = paid out of pocket and not yet reimbursed + approved claims not yet paid. Awaiting approval is shown separately and not counted. "Voucher money held" is company money staff still have from vouchers.
          </p>
        </>
      )}
    </section>
  );
}
