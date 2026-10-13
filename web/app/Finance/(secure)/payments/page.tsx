import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatInrExact } from "@/lib/money";

export default async function PaymentsPage() {
  const profile = await requireArea("finance");
  const supabase = await createClient();
  const [{ data: payments }, { data: events }] = await Promise.all([
    supabase.from("payments").select("id, purpose, method, amount, status, created_at").order("created_at", { ascending: false }),
    supabase.from("financial_events").select("id, event_type, amount, created_at").order("created_at", { ascending: false }),
  ]);

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="finance" />
      <main className="mx-auto max-w-5xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Finance</p>
        <h1 className="display mt-3 text-5xl">Method is not the transaction</h1>
        <p className="mt-3 max-w-xl text-ink/70">
          UPI, card, and cash are how money moved. Authorization, capture, and a released deposit are what the company did.
        </p>
        <div className="mt-8 grid gap-8 md:grid-cols-2">
          <section>
            <h2 className="display text-2xl">Payments</h2>
            <div className="mt-3 space-y-2">
              {(payments ?? []).length === 0 ? <p className="text-sm text-ink/60">No payment rows yet.</p> : null}
              {(payments ?? []).map((payment) => (
                <article key={payment.id} className="panel rounded-2xl p-4 text-sm">
                  <p className="text-xs uppercase tracking-wider text-ember">{payment.status}</p>
                  <p>
                    {payment.purpose} · {payment.method}
                  </p>
                  <p>{formatInrExact(payment.amount)}</p>
                </article>
              ))}
            </div>
          </section>
          <section>
            <h2 className="display text-2xl">Financial events</h2>
            <div className="mt-3 space-y-2">
              {(events ?? []).length === 0 ? <p className="text-sm text-ink/60">No events posted yet.</p> : null}
              {(events ?? []).map((event) => (
                <article key={event.id} className="panel rounded-2xl p-4 text-sm">
                  <p className="font-medium">{event.event_type}</p>
                  <p>{formatInrExact(event.amount)}</p>
                </article>
              ))}
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}
