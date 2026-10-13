import Link from "next/link";
import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export default async function BackendPage() {
  const profile = await requireArea("backend");
  const supabase = await createClient();
  const [{ count: agreements }, { count: documents }, { count: queued }] = await Promise.all([
    supabase.from("agreements").select("id", { count: "exact", head: true }).eq("status", "signed"),
    supabase.from("documents").select("id", { count: "exact", head: true }),
    supabase.from("notifications").select("id", { count: "exact", head: true }).eq("status", "queued"),
  ]);

  const doors = [
    ["/Backend/agreements", "Agreements", `${agreements ?? 0} signed. eSign is the Digio adapter, called only after authorize.`],
    ["/Backend/documents", "Documents", `${documents ?? 0} records. A full ID number is rejected. Last 4 only.`],
    ["/Backend/messages", "Messages", `${queued ?? 0} queued. SMS and WhatsApp stay named until an adapter sends them.`],
    ["/Backend/adapters", "Adapters", "Stripe, Razorpay, PhonePe, Digio, and Twilio sit behind one service each."],
  ];

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="backend" />
      <main className="mx-auto max-w-5xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Backend</p>
        <h1 className="display mt-3 text-5xl">Agreements, messages, adapters</h1>
        <p className="mt-3 max-w-xl text-ink/70">
          Supabase holds Auth, Postgres, row security, and the private document bucket. Bookings never call a provider directly.
        </p>
        <div className="mt-8 grid gap-4 md:grid-cols-2">
          {doors.map(([href, title, copy]) => (
            <Link key={href} href={href} className="panel rounded-3xl p-5">
              <h2 className="display text-2xl">{title}</h2>
              <p className="mt-2 text-sm text-ink/70">{copy}</p>
            </Link>
          ))}
        </div>
      </main>
    </div>
  );
}
