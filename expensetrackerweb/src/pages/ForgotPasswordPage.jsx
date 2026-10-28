import { useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { requestPasswordReset, resetPassword, verifyResetCode } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import AuthLayout from "../components/AuthLayout.jsx";

// Forgot password, in three steps on one page: email → 6-digit code from the email (valid 5 minutes) → new password.
// Same backend flow as the mobile app (/api/auth/forgot-password, /verify-otp, /reset-password).
export default function ForgotPasswordPage() {
  const [params] = useSearchParams();
  const [step, setStep] = useState("email"); // email | code | password
  const [email, setEmail] = useState(params.get("email") || "");
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const { showToast } = useToast();
  const navigate = useNavigate();

  async function sendCode(e) {
    e?.preventDefault();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) return showToast("Enter a valid email address", "error");
    setLoading(true);
    const res = await requestPasswordReset(email.trim());
    setLoading(false);
    if (!res.success) return showToast(res.message || "Could not send the code", "error");
    showToast(`Code sent to ${email.trim()}`);
    setCode("");
    setStep("code");
  }

  async function checkCode(e) {
    e.preventDefault();
    if (!/^\d{6}$/.test(code.trim())) return showToast("Enter the 6-digit code from the email", "error");
    setLoading(true);
    const res = await verifyResetCode(email.trim(), code.trim());
    setLoading(false);
    if (!res.success) return showToast(res.message || "That code didn't work", "error");
    setStep("password");
  }

  async function savePassword(e) {
    e.preventDefault();
    if (password.length < 6) return showToast("Use at least 6 characters", "error");
    if (password !== confirm) return showToast("The passwords don't match", "error");
    setLoading(true);
    const res = await resetPassword(email.trim(), password);
    setLoading(false);
    if (!res.success) return showToast(res.message || "Could not change the password", "error");
    showToast("Password changed. Sign in with your new password.");
    navigate("/login", { replace: true });
  }

  const titles = {
    email: ["Forgot password", "Enter your account's email and we'll send you a 6-digit code."],
    code: ["Check your email", `We sent a 6-digit code to ${email.trim()}. It's valid for 5 minutes.`],
    password: ["Set a new password", "Choose a new password for your account."],
  };

  return (
    <AuthLayout>
      <h1 style={{ fontSize: 22, margin: "0 0 4px" }}>{titles[step][0]}</h1>
      <p style={{ color: "var(--muted)", fontSize: 14, margin: "0 0 24px" }}>{titles[step][1]}</p>

      {step === "email" && (
        <form onSubmit={sendCode}>
          <label className="field-label">Email address</label>
          <input className="field-input" type="email" autoComplete="email" autoFocus value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" />
          <button type="submit" className="btn btn-primary btn-block" style={{ marginTop: 20 }} disabled={loading}>
            {loading ? "Sending…" : "Send code"}
          </button>
        </form>
      )}

      {step === "code" && (
        <form onSubmit={checkCode}>
          <label className="field-label">6-digit code</label>
          <input
            className="field-input"
            inputMode="numeric"
            autoComplete="one-time-code"
            autoFocus
            maxLength={6}
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            placeholder="••••••"
            style={{ letterSpacing: 8, fontSize: 20, fontWeight: 700, textAlign: "center" }}
          />
          <button type="submit" className="btn btn-primary btn-block" style={{ marginTop: 20 }} disabled={loading || code.length !== 6}>
            {loading ? "Checking…" : "Verify code"}
          </button>
          <p style={{ textAlign: "center", fontSize: 13, color: "var(--muted)", margin: "16px 0 0" }}>
            Didn't get it?{" "}
            <button type="button" onClick={sendCode} disabled={loading} style={linkButton}>Send again</button>
            {" · "}
            <button type="button" onClick={() => setStep("email")} disabled={loading} style={linkButton}>Change email</button>
          </p>
        </form>
      )}

      {step === "password" && (
        <form onSubmit={savePassword}>
          <label className="field-label">New password</label>
          <div style={{ position: "relative" }}>
            <input
              className="field-input"
              type={showPassword ? "text" : "password"}
              autoComplete="new-password"
              autoFocus
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="At least 6 characters"
              style={{ paddingRight: 56 }}
            />
            <button type="button" onClick={() => setShowPassword((v) => !v)} style={showButton}>
              {showPassword ? "HIDE" : "SHOW"}
            </button>
          </div>
          <div style={{ height: 14 }} />
          <label className="field-label">Confirm new password</label>
          <input
            className="field-input"
            type={showPassword ? "text" : "password"}
            autoComplete="new-password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            placeholder="Type it again"
          />
          <button type="submit" className="btn btn-primary btn-block" style={{ marginTop: 20 }} disabled={loading}>
            {loading ? "Saving…" : "Change password"}
          </button>
        </form>
      )}

      <p style={{ textAlign: "center", fontSize: 14, color: "var(--muted)", marginTop: 18, marginBottom: 0 }}>
        Remembered it? <Link to="/login" style={{ color: "var(--forest)", fontWeight: 700 }}>Back to sign in</Link>
      </p>
    </AuthLayout>
  );
}

const linkButton = { background: "none", border: "none", padding: 0, color: "var(--forest)", fontWeight: 700, fontSize: 13, cursor: "pointer" };
const showButton = {
  position: "absolute",
  right: 10,
  top: "50%",
  transform: "translateY(-50%)",
  background: "none",
  border: "none",
  color: "var(--forest)",
  fontSize: 12,
  fontWeight: 700,
};
