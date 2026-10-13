import { formatInrExact } from "@/lib/money";

export type JournalRow = {
  id: string;
  memo: string;
  posted_at: string;
  journal_lines: { account_code: string; debit: number; credit: number }[] | { account_code: string; debit: number; credit: number };
};

export function JournalList({
  entries,
  names,
}: {
  entries: JournalRow[];
  names: Map<string, string>;
}) {
  if (entries.length === 0) {
    return <p className="text-sm text-ink/60">No journals yet. Capture posts rental revenue and a separate deposit liability.</p>;
  }

  return (
    <div className="space-y-4">
      {entries.map((entry) => {
        const lines = Array.isArray(entry.journal_lines) ? entry.journal_lines : [entry.journal_lines];
        const debit = lines.reduce((sum, line) => sum + Number(line.debit), 0);
        const credit = lines.reduce((sum, line) => sum + Number(line.credit), 0);
        return (
          <article key={entry.id} className="panel rounded-3xl p-5">
            <p className="text-sm font-medium">{entry.memo}</p>
            <p className="mt-1 text-xs text-ink/50">
              Debits {formatInrExact(debit)} · credits {formatInrExact(credit)}
              {debit === credit ? " · balanced" : " · out of balance"}
            </p>
            <table className="mt-3 w-full text-left text-sm">
              <tbody>
                {lines.map((line) => (
                  <tr key={line.account_code + String(line.debit) + String(line.credit)} className="border-t border-ink/10">
                    <td className="py-2">
                      {line.account_code} {names.get(line.account_code) ?? ""}
                    </td>
                    <td className="text-right">{Number(line.debit) ? formatInrExact(line.debit) : ""}</td>
                    <td className="text-right">{Number(line.credit) ? formatInrExact(line.credit) : ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </article>
        );
      })}
    </div>
  );
}
