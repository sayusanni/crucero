import Link from "next/link";
import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatInrExact } from "@/lib/money";

export default async function GstPage() {
  const profile = await requireArea("gst");
  const supabase = await createClient();
  const [{ count: rules }, { count: assets }, { data: lines }] = await Promise.all([
    supabase.from("tax_rules").select("id", { count: "exact", head: true }).eq("is_active", true),
    supabase.from("vehicles").select("id", { count: "exact", head: true }),
    supabase.from("journal_lines").select("account_code, debit, credit").eq("account_code", "2200"),
  ]);
  const gst = (lines ?? []).reduce((total, line) => total + Number(line.credit) - Number(line.debit), 0);

  const doors = [
    ["/Gst/rules", "Tax rules", "A rate has a start date. Old bookings keep the rate copied onto them."],
    ["/Gst/assets", "Asset register", "Every bike and car, with registration and whether it is in the workshop."],
    ["/Gst/journal", "Journal", "The books those events posted. GST payable is account 2200."],
  ];

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="gst" />
      <main className="mx-auto max-w-5xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Gst</p>
        <h1 className="display mt-3 text-5xl">Tax, assets, and the journal</h1>
        <p className="mt-3 max-w-xl text-ink/70">
          {rules ?? 0} active tax rules · {assets ?? 0} vehicles · GST payable {formatInrExact(gst)}.
        </p>
        <div className="mt-8 grid gap-4 md:grid-cols-3">
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
