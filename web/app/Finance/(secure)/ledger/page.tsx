import { SiteNav } from "@/components/nav";
import { JournalList, type JournalRow } from "@/components/journal-list";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export default async function LedgerPage() {
  const profile = await requireArea("finance");
  const supabase = await createClient();
  const [{ data: entries }, { data: accounts }] = await Promise.all([
    supabase.from("journal_entries").select("id, memo, posted_at, journal_lines(account_code, debit, credit)").order("posted_at", { ascending: false }),
    supabase.from("accounts").select("code, name"),
  ]);
  const names = new Map((accounts ?? []).map((account) => [account.code, account.name]));

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="finance" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Finance</p>
        <h1 className="display mt-3 text-5xl">Ledger</h1>
        <p className="mt-3 text-ink/70">Every entry is posted from a financial event, and the lines have to balance.</p>
        <div className="mt-8">
          <JournalList entries={(entries ?? []) as JournalRow[]} names={names} />
        </div>
      </main>
    </div>
  );
}
