"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { AdminUser, api, logout, session, setSessionExpiredHandler } from "@/lib/api";

const NAV: { group: string; items: { href: string; label: string; badge?: "sos" | "tickets" }[] }[] = [
  { group: "Overview", items: [
    { href: "/", label: "Dashboard" },
    { href: "/live", label: "Live map" },
    { href: "/reports", label: "Reports" },
  ] },
  { group: "Operations", items: [
    { href: "/rides", label: "Rides" },
    { href: "/captains", label: "Captains & KYC" },
    { href: "/customers", label: "Customers" },
  ] },
  { group: "Safety & support", items: [
    { href: "/sos", label: "SOS alerts", badge: "sos" },
    { href: "/tickets", label: "Support tickets", badge: "tickets" },
    { href: "/broadcast", label: "Announcements" },
  ] },
  { group: "Money", items: [
    { href: "/payments", label: "Payments" },
    { href: "/subscriptions", label: "Captain plans" },
    { href: "/dues", label: "Platform dues" },
    { href: "/promos", label: "Promo codes" },
  ] },
  { group: "Settings", items: [
    { href: "/settings", label: "Pricing & config" },
    { href: "/quick-places", label: "Quick places" },
    { href: "/audit", label: "Audit log" },
  ] },
];

export default function ConsoleLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [user, setUser] = useState<AdminUser | null>(null);
  const [counts, setCounts] = useState<{ sos: number; tickets: number }>({ sos: 0, tickets: 0 });

  useEffect(() => {
    if (!session.access) {
      router.replace("/login");
      return;
    }
    setUser(session.user);
    setSessionExpiredHandler(() => router.replace("/login"));
  }, [router]);

  useEffect(() => {
    if (!user) return;
    const load = () =>
      api<{ metrics: Record<string, number | string> }>("admin/dashboard/")
        .then((d) => setCounts({ sos: Number(d.metrics.open_sos) || 0, tickets: Number(d.metrics.open_tickets) || 0 }))
        .catch(() => {});
    load();
    const id = setInterval(load, 30000);
    return () => clearInterval(id);
  }, [user]);

  if (!user) return null;

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">🛵</span> MithrGo</div>
        <nav className="nav">
          {NAV.map((group) => (
            <div key={group.group}>
              <div className="nav-group">{group.group}</div>
              {group.items.map((item) => {
                const n = item.badge ? counts[item.badge] : 0;
                return (
                  <Link key={item.href} href={item.href} className={isActive(item.href) ? "active" : ""}>
                    {item.label}
                    {n > 0 && <span className="pill">{n}</span>}
                  </Link>
                );
              })}
            </div>
          ))}
        </nav>
      </aside>
      <div className="main">
        <header className="topbar">
          <strong>Operations console</strong>
          <div className="who">
            <span>{user.first_name || user.phone}</span>
            <button className="btn secondary small" onClick={async () => { await logout(); router.replace("/login"); }}>
              Sign out
            </button>
          </div>
        </header>
        <main className="content">{children}</main>
      </div>
    </div>
  );
}
