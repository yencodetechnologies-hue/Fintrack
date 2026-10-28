import { useCallback, useEffect, useState } from "react";
import { getOutstandingReport } from "../api.js";
import { money, roleNames } from "../utils.js";

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

          <div className="card report-list">
            <h3>People</h3>
            {people.length === 0 ? (
              <p className="report-empty">Nobody is owed anything right now.</p>
            ) : (
              people.map((r) => {
                const details = [
                  r.recorded > 0 ? `paid ${money(r.recorded)}` : "",
                  r.claims > 0 ? `claims ${money(r.claims)}` : "",
                  r.awaitingApproval > 0 ? `${money(r.awaitingApproval)} awaiting approval` : "",
                  (r.advanceHeld || 0) > 0 ? `holds ${money(r.advanceHeld)} voucher money` : "",
                ].filter(Boolean);
                return (
                  <div key={r.userId} className="report-row">
                    <span>
                      <strong>{r.name}</strong>
                      <small>{r.role}{details.length ? ` · ${details.join(" · ")}` : ""}</small>
                    </span>
                    <b className={r.owed > 0 ? "out" : ""}>{r.owed > 0 ? money(r.owed) : "—"}</b>
                  </div>
                );
              })
            )}
          </div>

          {companies.length > 0 && (
            <div className="card report-list">
              <h3>Companies</h3>
              {companies.map((c) => (
                <div key={c.companyId} className="report-row">
                  <span>
                    <strong>{c.name}</strong>
                    <small>{c.loans} open loan{c.loans === 1 ? "" : "s"}{c.external ? " · outside company" : ""}</small>
                  </span>
                  <b className={c.net < 0 ? "out" : "in"}>{c.net < 0 ? `We owe ${money(-c.net)}` : c.net > 0 ? `They owe ${money(c.net)}` : "Settled"}</b>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </section>
  );
}
