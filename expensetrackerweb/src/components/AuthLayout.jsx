export default function AuthLayout({ children }) {
  return (
    <div className="auth-shell">
      <div className="auth-brand-panel">
        <div
          style={{
            width: 56,
            height: 56,
            borderRadius: "50%",
            border: "2px solid rgba(255,255,255,0.5)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            marginBottom: 28,
          }}
        >
          <span style={{ fontFamily: "Fraunces, serif", fontSize: 26, color: "#FDE68A" }}>Q</span>
        </div>
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
