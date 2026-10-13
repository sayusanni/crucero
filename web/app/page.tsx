import Link from "next/link";

const areas = [
  ["/Platform", "01 Customer", "Search a branch and a time, price a bike or car, upload documents, authorize, sign, then capture."],
  ["/Operations", "02 Operations", "Admin desk for the whole company, and the staff phone for pickups, returns, and live overdue."],
  ["/Finance", "03 Finance", "Money in and money out. A rental payment and a deposit are different facts."],
  ["/Gst", "04–06 Tax, assets, books", "GST rule versions, the vehicle register, and the journal those events post."],
  ["/Reports", "07 Reports", "Revenue, fleet, and branch numbers read from the same events."],
  ["/Backend", "08–11 Backend", "Agreements, notifications, Supabase, and the payment and eSign adapters."],
];

export default function Home() {
  return (
    <div className="yard min-h-svh">
      <main className="mx-auto max-w-5xl px-5 py-16">
        <p className="text-xs uppercase tracking-[0.28em] text-ember">Crucero</p>
        <h1 className="display mt-4 max-w-2xl text-5xl leading-[0.95] sm:text-6xl">
          Six doors. One rental company.
        </h1>
        <p className="mt-4 max-w-xl text-ink/70">
          Each area has its own URL. Customer booking does not live on the finance desk, and the books do not live inside the booking form.
        </p>
        <div className="mt-12 grid gap-4 md:grid-cols-2">
          {areas.map(([href, title, copy]) => (
            <Link key={href} href={href} className="panel block rounded-3xl p-6">
              <p className="text-xs uppercase tracking-[0.18em] text-ember">{href}</p>
              <h2 className="display mt-2 text-3xl">{title}</h2>
              <p className="mt-2 text-sm text-ink/70">{copy}</p>
            </Link>
          ))}
        </div>
      </main>
    </div>
  );
}
