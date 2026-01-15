import { useCallback, useEffect, useRef, useState } from "react";

const stats = [
  { label: "Active Events", value: "128+" },
  { label: "Attendees Managed", value: "24k" },
  { label: "Automated Reminders", value: "98%" }
];

const GoogleIcon = () => (
  <svg viewBox="0 0 48 48" aria-hidden="true" focusable="false">
    <path
      fill="#EA4335"
      d="M24 9.5c3.3 0 6.1 1.1 8.3 3.1l6-6C34.7 3.4 29.8 1.5 24 1.5 14.6 1.5 6.6 6.9 3.2 14.7l7.2 5.6C12.2 14 17.7 9.5 24 9.5z"
    />
    <path
      fill="#FBBC05"
      d="M46.5 24.5c0-1.6-.1-2.7-.4-4H24v7.6h12.7c-.5 2.6-2 6.4-5.2 9l8 6.2c4.7-4.3 7-10.7 7-18.8z"
    />
    <path
      fill="#34A853"
      d="M10.4 28.3a13.9 13.9 0 0 1-.7-4.3c0-1.5.3-3 .7-4.3l-7.2-5.6A23.6 23.6 0 0 0 1.5 24c0 3.9.9 7.5 2.7 10.9l6.2-6.6z"
    />
    <path
      fill="#4285F4"
      d="M24 46.5c6.4 0 11.7-2.1 15.6-5.8l-8-6.2c-2.2 1.5-5.1 2.6-7.6 2.6-6.3 0-11.7-4.2-13.6-10l-6.2 6.6C7.6 41.8 15.2 46.5 24 46.5z"
    />
  </svg>
);

const PlaceholderCard = () => (
  <div className="image-card">
    <div className="image-glow" />
    <div className="image-placeholder">
      <div className="image-icon" aria-hidden="true" />
    </div>
  </div>
);

export default function App() {
  const googleButtonRef = useRef(null);
  const [status, setStatus] = useState({ type: "idle", message: "" });
  const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";
  const googleClientId =
    import.meta.env.VITE_GOOGLE_CLIENT_ID ||
    "947113013769-dsal8c7k52irs6eokfnvl6o1a6v2rvea.apps.googleusercontent.com";

  const handleGoogleCredential = useCallback(
    async (response) => {
      if (!response?.credential) {
        setStatus({ type: "error", message: "Missing Google credential." });
        return;
      }

      setStatus({ type: "loading", message: "Signing you in..." });

      try {
        const res = await fetch(`${apiBaseUrl}/auth/google`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ token: response.credential })
        });

        if (!res.ok) {
          throw new Error("Login failed. Please try again.");
        }

        const data = await res.json();
        localStorage.setItem("auth_token", data.access_token);
        localStorage.setItem("auth_user", JSON.stringify(data.user));
        setStatus({ type: "success", message: "Signed in successfully." });
      } catch (err) {
        setStatus({
          type: "error",
          message: err?.message || "Unable to sign in right now."
        });
      }
    },
    [apiBaseUrl]
  );

  useEffect(() => {
    if (!googleClientId) {
      setStatus({
        type: "error",
        message: "Missing Google Client ID."
      });
      return;
    }

    let timerId;

    const tryInit = () => {
      if (!window.google?.accounts?.id || !googleButtonRef.current) {
        return false;
      }

      window.google.accounts.id.initialize({
        client_id: googleClientId,
        callback: handleGoogleCredential
      });

      window.google.accounts.id.renderButton(googleButtonRef.current, {
        theme: "outline",
        size: "large",
        text: "continue_with",
        shape: "pill",
        width: 320
      });
      googleButtonRef.current.classList.add("google-ready");

      window.google.accounts.id.prompt();
      return true;
    };

    if (!tryInit()) {
      timerId = window.setInterval(() => {
        if (tryInit()) {
          window.clearInterval(timerId);
        }
      }, 300);
    }

    return () => {
      if (timerId) {
        window.clearInterval(timerId);
      }
    };
  }, [googleClientId, handleGoogleCredential]);

  return (
    <div className="page">
      <div className="orb orb-left" />
      <div className="orb orb-right" />
      <div className="container">
        <section className="hero">
          <PlaceholderCard />
          <div className="hero-text">
            <p className="eyebrow">Event Booking Management</p>
            <h1>Run smarter events, from invites to attendance.</h1>
            <p className="lead">
              Organize every stage with a centralized workspace, automated
              reminders, and real-time visibility that keeps teams aligned.
            </p>
            <div className="stats">
              {stats.map((item) => (
                <div key={item.label} className="stat">
                  <span className="stat-value">{item.value}</span>
                  <span className="stat-label">{item.label}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="login-panel">
          <div className="panel-card">
            <p className="panel-eyebrow">Welcome back</p>
            <h2>Login to your account</h2>
            <p className="panel-copy">
              Sign in to continue scheduling, tracking, and refining every
              event experience.
            </p>

            <div className="google-button google-render" ref={googleButtonRef}>
              <span className="google-fallback" aria-hidden="true">
                <span className="google-icon">
                  <GoogleIcon />
                </span>
                Continue with Google
              </span>
            </div>

            {status.message ? (
              <p className={`status ${status.type}`}>{status.message}</p>
            ) : null}

            <p className="panel-footnote">
              New here? <span>Create an account</span>
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}
