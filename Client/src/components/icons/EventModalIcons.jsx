/** Inline SVGs for event details modal (stroke icons, no emojis). */

function Svg({ children, className = "", size = 18 }) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      focusable="false"
    >
      {children}
    </svg>
  );
}

export function IconCalendar({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
      <path d="M16 2v4M8 2v4M3 10h18" />
    </Svg>
  );
}

export function IconMapPin({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M12 21s7-4.35 7-10a7 7 0 10-14 0c0 5.65 7 10 7 10z" />
      <circle cx="12" cy="11" r="2.5" />
    </Svg>
  );
}

export function IconUser({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </Svg>
  );
}

export function IconWallet({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M21 12V7H5a2 2 0 010-4h14v4" />
      <path d="M3 5v14a2 2 0 002 2h16v-5" />
      <path d="M18 12a2 2 0 100 4 2 2 0 000-4z" />
    </Svg>
  );
}

export function IconFlag({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M4 22V4a1 1 0 011-1h12l-3 5 3 5H6" />
    </Svg>
  );
}

export function IconUsersAudience({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M17 21v-2a4 4 0 00-3-3.87M9 21v-2a4 4 0 013-3.87" />
      <circle cx="9" cy="7" r="3.5" />
      <path d="M15 3.13a4 4 0 010 7.75" />
    </Svg>
  );
}

export function IconDocument({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6z" />
      <path d="M14 2v6h6M8 13h8M8 17h6" />
    </Svg>
  );
}

export function IconClipboard({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M9 2h6l1 3h4a1 1 0 011 1v14a2 2 0 01-2 2H5a2 2 0 01-2-2V6a1 1 0 011-1h4l1-3z" />
      <path d="M9 14h6M9 18h4" />
    </Svg>
  );
}

export function DeptIconMarketing({ className, size = 20 }) {
  return (
    <Svg className={className} size={size}>
      <path d="M3 11v6l4 2v-8l-4-2z" />
      <path d="M7 9v8l11 3V6L7 9z" />
      <path d="M18 6l3-2v14l-3-2" />
    </Svg>
  );
}

export function DeptIconFacility({ className, size = 20 }) {
  return (
    <Svg className={className} size={size}>
      <path d="M3 21h18M5 21V7l8-4v18M13 21V11l6-3v13" />
      <path d="M9 9v.01M9 12v.01M9 15v.01M9 18v.01" />
    </Svg>
  );
}

export function DeptIconIt({ className, size = 20 }) {
  return (
    <Svg className={className} size={size}>
      <rect x="2" y="3" width="20" height="14" rx="2" />
      <path d="M8 21h8M12 17v4" />
    </Svg>
  );
}

export function DeptIconTransport({ className, size = 20 }) {
  return (
    <Svg className={className} size={size}>
      <path d="M14 18V6a2 2 0 00-2-2H4a2 2 0 00-2 2v11a1 1 0 001 1h2" />
      <path d="M15 18h2M15 18h4a1 1 0 001-1v-3.5l-2.5-2.5" />
      <circle cx="7.5" cy="18.5" r="2.5" />
      <circle cx="17.5" cy="18.5" r="2.5" />
    </Svg>
  );
}

export function DeptIconIqac({ className, size = 20 }) {
  return (
    <Svg className={className} size={size}>
      <path d="M9 11l3 3L22 4" />
      <path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" />
    </Svg>
  );
}

export function IconFlow({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <circle cx="5" cy="12" r="2.5" />
      <circle cx="12" cy="12" r="2.5" />
      <circle cx="19" cy="12" r="2.5" />
      <path d="M7.5 12h3M14.5 12h3" />
    </Svg>
  );
}

export function IconLayers({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M12 2L2 7l10 5 10-5-10-5z" />
      <path d="M2 17l10 5 10-5M2 12l10 5 10-5" />
    </Svg>
  );
}

export function IconUploadCloud({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M12 13v8M8 17l4-4 4 4" />
      <path d="M4 14.5A4 4 0 016.34 7 5 5 0 0117 9a3 3 0 012.17 4.5" />
    </Svg>
  );
}

export function IconStatusRing({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="3" fill="currentColor" stroke="none" />
    </Svg>
  );
}

export function IconEnvelope({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M3 7l9 6 9-6" />
    </Svg>
  );
}

export function IconShieldCheck({ className, size }) {
  return (
    <Svg className={className} size={size}>
      <path d="M12 3l8 4v5c0 5-3.5 9-8 10-4.5-1-8-5-8-10V7l8-4z" />
      <path d="M9 12l2 2 4-4" />
    </Svg>
  );
}
