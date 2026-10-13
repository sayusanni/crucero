import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

const labels: Record<string, string> = {
  booking_confirmed: "Booking confirmed",
  vehicle_picked_up: "Vehicle picked up",
  vehicle_returned: "Vehicle returned",
};

export default async function MessagesPage() {
  const profile = await requireArea("backend");
  const supabase = await createClient();
  const { data } = await supabase
    .from("notifications")
    .select("id, channel, recipient, template, status, created_at")
    .order("created_at", { ascending: false });

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="backend" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Backend</p>
        <h1 className="display mt-3 text-5xl">Messages</h1>
        <p className="mt-3 text-ink/70">
          A status change queues SMS and WhatsApp. They stay queued because Twilio is named here and not connected.
        </p>
        <div className="mt-8 space-y-2">
          {(data ?? []).length === 0 ? <p className="text-sm text-ink/60">Nothing queued yet. Capture, pickup, or return creates a message.</p> : null}
          {(data ?? []).map((note) => (
            <article key={note.id} className="panel rounded-2xl p-4 text-sm">
              <p className="text-xs uppercase tracking-wider text-ember">{note.status}</p>
              <p className="font-medium">{labels[note.template] ?? note.template}</p>
              <p className="text-ink/70">
                {note.channel} · {note.recipient}
              </p>
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
