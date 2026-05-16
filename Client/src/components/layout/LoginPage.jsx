import { stats } from "../../constants";
import { GoogleIcon, PlaceholderCard } from "../icons";

export default function LoginPage({ googleButtonRef, status }) {
  return (
    <div className="page">
      <div className="orb orb-left" />
      <div className="orb orb-right" />
      <div className="container">
        <section className="hero">
          <PlaceholderCard />
          <div className="hero-text">
            <p className="eyebrow">VU Sync</p>
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

            {status?.message ? (
              <p className={`status ${status.type}`}>{status.message}</p>
            ) : null}

            <p className="panel-footnote">
              Use your institutional Google account to continue.
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}
