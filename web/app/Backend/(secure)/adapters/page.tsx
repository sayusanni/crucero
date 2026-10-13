import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";

const adapters = [
  ["Payments", "Stripe, Razorpay, PhonePe", "Authorize holds rental plus deposit. Capture runs only after eSign and posts the journal. The booking form never talks to a provider."],
  ["eSign", "Digio", "The agreement is stored with the price snapshot. Signing moves the booking from authorized to signed."],
  ["Messages", "Twilio", "Templates are booking confirmed, picked up, and returned. The queue records channel, recipient, and template."],
  ["Platform", "Supabase", "Auth, Postgres, row-level security, and the private customer-documents bucket."],
];

export default async function AdaptersPage() {
  const profile = await requireArea("backend");

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="backend" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Backend</p>
        <h1 className="display mt-3 text-5xl">Adapters</h1>
        <div className="mt-8 space-y-3">
          {adapters.map(([title, vendor, copy]) => (
            <article key={title} className="panel rounded-3xl p-5">
              <p className="text-xs uppercase tracking-wider text-moss">{vendor}</p>
              <h2 className="display text-2xl">{title}</h2>
              <p className="mt-2 text-sm text-ink/70">{copy}</p>
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
