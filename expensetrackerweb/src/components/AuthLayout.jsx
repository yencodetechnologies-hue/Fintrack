export default function AuthLayout({ children }) {
  return (
    <div className="auth-shell">
      <div className="auth-brand-panel">
        <img
          src="/logo.png"
          alt="Q Fin"
          style={{ width: 64, height: 64, borderRadius: 16, border: "1px solid rgba(255,255,255,0.28)", display: "block", marginBottom: 28 }}
        />
        <h1 style={{ color: "#fff", fontSize: 44, maxWidth: 520, lineHeight: 1.15, margin: "0 0 18px" }}>
          Track shared company expenses, without the spreadsheet.
        </h1>
        <p style={{ color: "rgba(255,255,255,0.75)", fontSize: 16, maxWidth: 480, lineHeight: 1.65, margin: 0 }}>
          Log expenses, settle payments, and manage company bank accounts and InCash balances —
          the same account you use on the Q Fin mobile app.
        </p>
      </div>

      <div className="auth-form-panel">
        <div style={{ width: "100%", maxWidth: 380 }}>{children}</div>
      </div>
    </div>
  );
}
