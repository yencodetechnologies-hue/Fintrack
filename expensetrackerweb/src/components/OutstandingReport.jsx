import { useCallback, useEffect, useState } from "react";
import { getOutstandingReport } from "../api.js";
import { money, roleNames } from "../utils.js";
import { TableCard } from "./DataTable.jsx";

// Who the company owes right now (managers and staff) and where it stands with other companies. Kept short:
// people and companies with nothing outstanding are left out.
export default function OutstandingReport({ companyId, company, userId, role = "all", refreshKey }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    const res = await getOutstandingReport(companyId, userId, role);
    if (res.success) {
      setData(res);
      setError("");
    } else setError(res.message || "Could not load outstanding report");
  }, [companyId, userId, role]);

  useEffect(() => {
    load();
  }, [load, refreshKey]);

  const names = roleNames(company);
  const people = data
    ? [
        ...data.managers.map((r) => ({ ...r, role: names.manager })),
        ...data.staff.map((r) => ({ ...r, role: names.staff })),
      ]
        .filter((r) => r.owed > 0 || r.awaitingApproval > 0 || (r.advanceHeld || 0) > 0)
        .sort((a, b) => b.owed - a.owed)
    : [];
  const companies = data ? data.companies.filter((c) => c.weOwe > 0 || c.theyOwe > 0) : [];

  return (
    <section className="report-section">
      <h2>Outstanding</h2>
      {error ? (
        <div className="card" style={{ color: "var(--terracotta)" }}>{error}</div>
      ) : !data ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 32 }}><div className="spinner dark" /></div>
      ) : (
        <>
          <div className="card report-strip">
            <div><small>Owed to {names.managers.toLowerCase()}</small><strong className={data.totals.owedToManagers > 0 ? "out" : ""}>{money(data.totals.owedToManagers)}</strong></div>
            <div><small>Owed to {names.staffs.toLowerCase()}</small><strong className={data.totals.owedToStaff > 0 ? "out" : ""}>{money(data.totals.owedToStaff)}</strong></div>
            <div><small>Awaiting approval</small><strong>{money(data.totals.awaitingApproval)}</strong></div>
            <div><small>We owe companies</small><strong className={data.totals.weOweCompanies > 0 ? "out" : ""}>{money(data.totals.weOweCompanies)}</strong></div>
            <div><small>Companies owe us</small><strong className={data.totals.companiesOweUs > 0 ? "in" : ""}>{money(data.totals.companiesOweUs)}</strong></div>
          </div>

          <TableCard title="People" meta={`${people.length} ${people.length === 1 ? "person" : "people"}`}>
            {people.length === 0 ? (
              <div className="dt-empty">Nobody is owed anything right now.</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr><th>Name</th><th>Role</th><th className="num">Paid by them</th><th className="num">Claims</th><th className="num">Awaiting approval</th><th className="num">Voucher money</th><th className="num">Owed</th></tr>
                </thead>
                <tbody>
                  {people.map((r) => (
                    <tr key={r.userId}>
                      <td className="dt-strong">{r.name}</td>
                      <td>{r.role}</td>
                      <td className="num">{r.recorded > 0 ? money(r.recorded) : "—"}</td>
                      <td className="num">{r.claims > 0 ? money(r.claims) : "—"}</td>
                      <td className="num">{r.awaitingApproval > 0 ? money(r.awaitingApproval) : "—"}</td>
                      <td className="num">{(r.advanceHeld || 0) > 0 ? money(r.advanceHeld) : "—"}</td>
                      <td className={`num ${r.owed > 0 ? "out" : ""}`}>{r.owed > 0 ? money(r.owed) : "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </TableCard>

          {companies.length > 0 && (
            <TableCard title="Companies" meta={`${companies.length} with open loans`}>
              <table className="dt">
                <thead>
                  <tr><th>Company / person</th><th>Type</th><th className="center">Open loans</th><th className="num">We owe</th><th className="num">They owe</th><th className="num">Net</th></tr>
                </thead>
                <tbody>
                  {companies.map((c) => (
                    <tr key={c.companyId}>
                      <td className="dt-strong">{c.name}</td>
                      <td>{c.external ? "Outside company" : "Company"}</td>
                      <td className="center">{c.loans}</td>
                      <td className="num out">{c.weOwe > 0 ? money(c.weOwe) : "—"}</td>
                      <td className="num in">{c.theyOwe > 0 ? money(c.theyOwe) : "—"}</td>
                      <td className={`num ${c.net < 0 ? "out" : "in"}`}>{c.net < 0 ? `We owe ${money(-c.net)}` : c.net > 0 ? `They owe ${money(c.net)}` : "Settled"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TableCard>
          )}
        </>
      )}
    </section>
  );
}
