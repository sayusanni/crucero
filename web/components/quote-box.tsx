"use client";

import { useEffect, useState } from "react";
import { useActionState } from "react";
import { createBooking } from "@/lib/actions";
import { createClient } from "@/lib/supabase/client";
import { formatInrExact } from "@/lib/money";
import type { Quote } from "@/lib/database.types";
import { toIso } from "@/lib/time";

async function book(_prev: string | null, formData: FormData) {
  const result = await createBooking(formData);
  return result?.error ?? null;
}

export function QuoteBox({
  vehicleId,
  start,
  end,
  signedIn,
  priceUnit,
}: {
  vehicleId: string;
  start: string;
  end: string;
  signedIn: boolean;
  priceUnit: "hour" | "minute" | "km" | "package";
}) {
  const [quote, setQuote] = useState<Quote | null>(null);
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [error, action, pending] = useActionState(book, null);

  useEffect(() => {
    const startValue = start;
    const endValue = end;
    const coupon = "";
    let cancelled = false;
    async function run(nextStart = startValue, nextEnd = endValue, nextCoupon = coupon, nextKm = "") {
      try {
        const supabase = createClient();
        const { data, error: rpcError } = await supabase.rpc("quote_rental", {
          p_vehicle: vehicleId,
          p_start: toIso(nextStart),
          p_end: toIso(nextEnd),
          p_coupon: nextCoupon || null,
          p_km: null,
        });
        if (cancelled) return;
        if (rpcError) {
          setQuote(null);
          setQuoteError(rpcError.message);
          return;
        }
        setQuote(data as Quote);
        setQuoteError(null);
      } catch (err) {
        if (!cancelled) setQuoteError(err instanceof Error ? err.message : "Could not price this rental");
      }
    }
    const form = document.getElementById("rent-form");
    const onInput = () => {
      const data = new FormData(form as HTMLFormElement);
      void run(
        String(data.get("start") ?? ""),
        String(data.get("end") ?? ""),
        String(data.get("coupon") ?? ""),
        String(data.get("km") ?? ""),
      );
    };
    void run();
    form?.addEventListener("input", onInput);
    return () => {
      cancelled = true;
      form?.removeEventListener("input", onInput);
    };
  }, [vehicleId, start, end, priceUnit]);

  return (
    <form id="rent-form" action={action} className="panel space-y-3 rounded-3xl p-5">
      <input type="hidden" name="vehicle_id" value={vehicleId} />
      <label className="block text-sm">
        Start
        <input name="start" type="datetime-local" defaultValue={start} required className="mt-1 w-full rounded-xl px-3 py-2" />
      </label>
      <label className="block text-sm">
        End
        <input name="end" type="datetime-local" defaultValue={end} required className="mt-1 w-full rounded-xl px-3 py-2" />
      </label>
      <label className="block text-sm">
        Coupon
        <input name="coupon" placeholder="WEEKEND10" className="mt-1 w-full rounded-xl px-3 py-2" />
      </label>
      {quote ? (
        <dl className="space-y-1 text-sm">
          <div className="flex justify-between">
            <dt>Duration</dt>
            <dd>
              {quote.billed_days > 0
                ? `${quote.billed_days} day + ${quote.remainder_hours} h`
                : `${quote.duration_hours} hours`}
            </dd>
          </div>
          <div className="flex justify-between">
            <dt>12-hour package</dt>
            <dd>{formatInrExact(Number(quote.base_amount))}</dd>
          </div>
          <div className="flex justify-between">
            <dt>Included kilometres</dt>
            <dd>{quote.km_allowance} km</dd>
          </div>
          <div className="flex justify-between">
            <dt>Extra kilometre</dt>
            <dd>{formatInrExact(Number(quote.excess_per_km))} + GST</dd>
          </div>
          <div className="flex justify-between">
            <dt>CGST</dt>
            <dd>{formatInrExact(Number(quote.cgst))}</dd>
          </div>
          <div className="flex justify-between">
            <dt>SGST</dt>
            <dd>{formatInrExact(Number(quote.sgst))}</dd>
          </div>
          <div className="flex justify-between">
            <dt>Deposit</dt>
            <dd>{formatInrExact(Number(quote.deposit_amount))}</dd>
          </div>
          <div className="flex justify-between font-medium">
            <dt>Payable</dt>
            <dd>{formatInrExact(Number(quote.authorize_amount))}</dd>
          </div>
          <p className="pt-1 text-ink/60">Fuel is not included. One helmet is included. Extra kilometres are settled when the bike comes back.</p>
        </dl>
      ) : null}
      {quoteError ? <p className="text-sm text-ember">{quoteError}</p> : null}
      {error ? <p className="text-sm text-ember">{error}</p> : null}
      {signedIn ? (
        <button disabled={pending || !quote} className="w-full rounded-full bg-ember py-3 text-paper">
          {pending ? "Holding the vehicle..." : "Hold and continue"}
        </button>
      ) : (
        <a href="/Platform/login" className="block rounded-full bg-ember py-3 text-center text-paper">
          Sign in to book
        </a>
      )}
    </form>
  );
}
