import { SiteNav } from "@/components/nav";
import { JournalList, type JournalRow } from "@/components/journal-list";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatInrExact } from "@/lib/money";

export default async function GstJournalPage() {
  const profile = await requireArea("gst");
  const supabase = await createClient();
  const [{ data: entries }, { data: accounts }, { data: gstLines }] = await Promise.all([
    supabase.from("journal_entries").select("id, memo, posted_at, journal_lines(account_code, debit, credit)").order("posted_at", { ascending: false }),
    supabase.from("accounts").select("code, name, kind"),
    supabase.from("journal_lines").select("credit, debit").eq("account_code", "2200"),
  ]);
  const payable = (gstLines ?? []).reduce((total, line) => total + Number(line.credit) - Number(line.debit), 0);
  const names = new Map((accounts ?? []).map((account) => [account.code, account.name]));

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="gst" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Gst</p>
        <h1 className="display mt-3 text-5xl">Journal</h1>
        <p className="mt-3 text-ink/70">GST payable on 2200 is {formatInrExact(payable)}. It is not mixed into rental revenue.</p>
        <div className="mt-6 grid gap-2 md:grid-cols-2">
          {(accounts ?? []).map((account) => (
            <p key={account.code} className="panel rounded-2xl px-4 py-3 text-sm">
              {account.code} · {account.name} · {account.kind}
            </p>
          ))}
        </div>
        <div className="mt-8">
          <JournalList entries={(entries ?? []) as JournalRow[]} names={names} />
        </div>
      </main>
    </div>
  );
}
