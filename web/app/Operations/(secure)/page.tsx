import Link from "next/link";
import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import type { Booking } from "@/lib/database.types";

const roles = [
  ["manager", "Branch desk", "Sees that branch's fleet, bookings, pickups, and returns."],
  ["sales", "Counter", "Hands over a captured booking and records the odometer out."],
  ["mechanic", "Workshop", "Marks a bike or car as maintenance so it drops out of search."],
  ["collection", "Returns", "Takes the vehicle back and sees the live late fee from the snapshot."],
];

export default async function OperationsHome() {
  const profile = await requireArea("operations");
  const supabase = await createClient();
  let bookings = supabase.from("bookings").select("status, end_at").in("status", ["captured", "out"]);
  if (profile.role !== "admin" && profile.branch_id) {
    bookings = bookings.eq("branch_id", profile.branch_id);
  }
  const [{ count: fleet }, { data: open }] = await Promise.all([
    supabase.from("vehicles").select("id", { count: "exact", head: true }).eq("status", "available"),
    bookings,
  ]);
  const rows = (open ?? []) as Pick<Booking, "status" | "end_at">[];
  const now = Date.now();

  const cards = [
    ["Ready to rent", String(fleet ?? 0)],
    ["Waiting for pickup", String(rows.filter((row) => row.status === "captured").length)],
    ["Out", String(rows.filter((row) => row.status === "out").length)],
    ["Overdue", String(rows.filter((row) => row.status === "out" && new Date(row.end_at).getTime() < now).length)],
  ];

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="operations" />
      <main className="mx-auto max-w-6xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.24em] text-ember">/Operations · {profile.role}</p>
        <h1 className="display mt-3 text-5xl">The yard, not the books</h1>
        <p className="mt-2 max-w-xl text-ink/70">
          This desk moves vehicles. Revenue, GST, and deposits live on their own doors.
        </p>
        <div className="mt-8 grid gap-4 md:grid-cols-4">
          {cards.map(([label, value]) => (
            <article key={label} className="panel rounded-3xl p-5">
              <p className="text-xs uppercase tracking-wider text-ink/50">{label}</p>
              <p className="display mt-2 text-3xl">{value}</p>
            </article>
          ))}
        </div>
        <div className="mt-8 grid gap-3 md:grid-cols-2">
          {roles.map(([role, title, copy]) => (
            <article key={role} className="panel rounded-3xl p-5">
              <p className="text-xs uppercase tracking-wider text-moss">{role}</p>
              <h2 className="display text-2xl">{title}</h2>
              <p className="mt-1 text-sm text-ink/70">{copy}</p>
            </article>
          ))}
        </div>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/Operations/staff" className="rounded-full bg-ember px-5 py-3 text-paper">
            Staff phone
          </Link>
          <Link href="/Operations/fleet" className="rounded-full border border-ink/15 px-5 py-3">
            Fleet
          </Link>
          <Link href="/Operations/bookings" className="rounded-full border border-ink/15 px-5 py-3">
            Bookings
          </Link>
        </div>
      </main>
    </div>
  );
}
