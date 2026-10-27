import { Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./context/AuthContext.jsx";
import LoginPage from "./pages/LoginPage.jsx";
import SignupPage from "./pages/SignupPage.jsx";
import ForgotPasswordPage from "./pages/ForgotPasswordPage.jsx";
import CompaniesPage from "./pages/CompaniesPage.jsx";
import DashboardPage from "./pages/DashboardPage.jsx";
import GroupDashboardPage from "./pages/GroupDashboardPage.jsx";
import ProfilePage from "./pages/ProfilePage.jsx";

function RequireAuth({ children }) {
  const { user } = useAuth();
  if (!user) return <Navigate to="/login" replace />;
  return children;
}

export default function App() {
  const { user } = useAuth();

  return (
    <Routes>
      <Route path="/login" element={user ? <Navigate to="/companies" replace /> : <LoginPage />} />
      <Route path="/signup" element={user ? <Navigate to="/companies" replace /> : <SignupPage />} />
      <Route path="/forgot-password" element={user ? <Navigate to="/companies" replace /> : <ForgotPasswordPage />} />
      <Route
        path="/companies"
        element={
          <RequireAuth>
            <CompaniesPage />
          </RequireAuth>
        }
      />
      <Route
        path="/company/:companyId"
        element={
          <RequireAuth>
            <DashboardPage />
          </RequireAuth>
        }
      />
      <Route
        path="/group/:groupId"
        element={
          <RequireAuth>
            <GroupDashboardPage />
          </RequireAuth>
        }
      />
      <Route
        path="/profile"
        element={
          <RequireAuth>
            <ProfilePage />
          </RequireAuth>
        }
      />
      <Route path="*" element={<Navigate to={user ? "/companies" : "/login"} replace />} />
    </Routes>
  );
}
