import Link from "next/link";
import { signOut } from "@/lib/actions";
import type { Profile } from "@/lib/database.types";

export type Area = "platform" | "operations" | "finance" | "gst" | "reports" | "backend";

const links: Record<Area, { href: string; label: string }[]> = {
  platform: [
    { href: "/Platform/rent", label: "Find a vehicle" },
    { href: "/Platform/bookings", label: "My bookings" },
  ],
  operations: [
    { href: "/Operations", label: "Desk" },
    { href: "/Operations/fleet", label: "Fleet" },
    { href: "/Operations/rates", label: "Default rates" },
    { href: "/Operations/branches", label: "Branches" },
    { href: "/Operations/bookings", label: "Bookings" },
    { href: "/Operations/staff", label: "Staff phone" },
  ],
  finance: [
    { href: "/Finance", label: "Money" },
    { href: "/Finance/payments", label: "Payments" },
    { href: "/Finance/ledger", label: "Ledger" },
  ],
  gst: [
    { href: "/Gst", label: "Desk" },
    { href: "/Gst/rules", label: "Tax rules" },
    { href: "/Gst/assets", label: "Assets" },
    { href: "/Gst/journal", label: "Journal" },
  ],
  reports: [{ href: "/Reports", label: "Reports" }],
  backend: [
    { href: "/Backend", label: "Desk" },
    { href: "/Backend/agreements", label: "Agreements" },
    { href: "/Backend/documents", label: "Documents" },
    { href: "/Backend/messages", label: "Messages" },
    { href: "/Backend/adapters", label: "Adapters" },
  ],
};

const home: Record<Area, string> = {
  platform: "/Platform",
  operations: "/Operations",
  finance: "/Finance",
  gst: "/Gst",
  reports: "/Reports",
  backend: "/Backend",
};

export function SiteNav({ profile, area }: { profile: Profile | null; area: Area }) {
  const signInHref = `${home[area]}/login`;
  return (
    <header className="sticky top-0 z-20 border-b border-ink/10 bg-paper/85 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-5 py-4">
        <Link href={home[area]} className="display text-2xl">
          Crucero
        </Link>
        <nav className="flex flex-wrap items-center justify-end gap-4 text-sm">
          <Link href="/">Areas</Link>
          {links[area].map((item) => (
            <Link key={item.href} href={item.href}>
              {item.label}
            </Link>
          ))}
          {profile ? (
            <form action={signOut}>
              <button className="rounded-full border border-ink/15 px-3 py-1.5">Sign out</button>
            </form>
          ) : (
            <Link href={signInHref} className="rounded-full bg-ember px-4 py-1.5 text-paper">
              Sign in
            </Link>
          )}
        </nav>
      </div>
    </header>
  );
}
