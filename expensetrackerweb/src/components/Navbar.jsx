import { Link } from "react-router-dom";

export default function Navbar({ crumb, backTo, children }) {
  return (
    <div className="navbar">
      <div className="navbar-inner">
        <Link to="/companies" className="navbar-brand">
          <span
            style={{
              width: 30,
              height: 30,
              borderRadius: "50%",
              border: "1.5px solid rgba(255,255,255,0.5)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontFamily: "Fraunces, serif",
              color: "#FDE68A",
              fontSize: 15,
            }}
          >
            Q
          </span>
          <span>Expense Tracker</span>
        </Link>
        {crumb && (
          <>
            <span className="navbar-crumb">/</span>
            {backTo ? (
              <Link to={backTo} className="navbar-crumb" style={{ fontWeight: 600 }}>
                {crumb}
              </Link>
            ) : (
              <span className="navbar-crumb" style={{ color: "#fff", fontWeight: 700 }}>
                {crumb}
              </span>
            )}
          </>
        )}
        <div className="navbar-actions">{children}</div>
      </div>
    </div>
  );
}
