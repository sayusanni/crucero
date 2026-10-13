import Link from "next/link";
import { SiteNav } from "@/components/nav";
import { ActionForm } from "@/components/form-error";
import { requireArea } from "@/lib/auth";
import { releaseDeposit } from "@/lib/actions";
import { createClient } from "@/lib/supabase/server";
import { formatInr, formatInrExact } from "@/lib/money";

async function release(_prev: string | null, formData: FormData) {
  "use server";
  const result = await releaseDeposit(formData);
  return result?.error ?? null;
}

export default async function FinancePage() {
  const profile = await requireArea("finance");
  const supabase = await createClient();
  const [{ data: lines }, { data: returned }, { data: released }] = await Promise.all([
    supabase.from("journal_lines").select("account_code, debit, credit"),
    supabase.from("bookings").select("id, deposit_amount, vehicles(name)").eq("status", "returned"),
    supabase.from("financial_events").select("booking_id").eq("event_type", "deposit_released"),
  ]);
  const sum = (code: string, side: "debit" | "credit") =>
    (lines ?? []).filter((line) => line.account_code === code).reduce((total, line) => total + Number(line[side]), 0);
  const releasedIds = new Set((released ?? []).map((row) => row.booking_id));
  const holding = ((returned ?? []) as { id: string; deposit_amount: number; vehicles: { name: string } | { name: string }[] }[]).filter(
    (row) => !releasedIds.has(row.id),
  );

  const cards = [
    ["Cash", formatInrExact(sum("1000", "debit") - sum("1000", "credit"))],
    ["Rental revenue", formatInr(sum("4000", "credit"))],
    ["Deposits still held", formatInrExact(sum("2100", "credit") - sum("2100", "debit"))],
    ["Late fees", formatInr(sum("4100", "credit"))],
  ];

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="finance" />
      <main className="mx-auto max-w-5xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Finance</p>
        <h1 className="display mt-3 text-5xl">Money in and money out</h1>
        <p className="mt-3 max-w-xl text-ink/70">
          A captured rental is revenue. The deposit is cash we owe back. Releasing it reduces the liability. It never touches rental revenue.
        </p>
        <div className="mt-8 grid gap-4 md:grid-cols-2">
          {cards.map(([label, value]) => (
            <article key={label} className="panel rounded-3xl p-5">
              <p className="text-xs uppercase tracking-wider text-ink/50">{label}</p>
              <p className="display mt-2 text-3xl">{value}</p>
            </article>
          ))}
        </div>
        <section className="mt-10">
          <h2 className="display text-3xl">Deposits ready to return</h2>
          {holding.length === 0 ? (
            <p className="mt-3 text-sm text-ink/60">No returned booking is still holding a deposit.</p>
          ) : null}
          <div className="mt-4 space-y-3">
            {holding.map((row) => {
              const vehicle = Array.isArray(row.vehicles) ? row.vehicles[0] : row.vehicles;
              return (
                <article key={row.id} className="panel flex flex-wrap items-center justify-between gap-4 rounded-3xl p-5">
                  <div>
                    <p className="font-medium">{vehicle?.name ?? "Vehicle"}</p>
                    <p className="text-sm text-ink/65">Liability {formatInrExact(row.deposit_amount)}</p>
                  </div>
                  <div className="w-full max-w-xs">
                    <ActionForm action={release} submit="Release deposit">
                      <input type="hidden" name="booking_id" value={row.id} />
                    </ActionForm>
                  </div>
                </article>
              );
            })}
          </div>
        </section>
        <p className="mt-8 text-sm">
          <Link href="/Finance/payments" className="underline">
            Payments
          </Link>{" "}
          show the method.{" "}
          <Link href="/Finance/ledger" className="underline">
            The ledger
          </Link>{" "}
          shows the business event.
        </p>
      </main>
    </div>
  );
}
