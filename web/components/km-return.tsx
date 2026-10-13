"use client";

import { useState } from "react";
import { ActionForm } from "@/components/form-error";
import { formatInrExact } from "@/lib/money";

export function KmReturn({
  bookingId,
  odometerOut,
  unitRate,
  taxRate,
  discount,
  plannedKm,
  action,
}: {
  bookingId: string;
  odometerOut: number;
  unitRate: number;
  taxRate: number;
  discount: number;
  plannedKm: number | null;
  action: (prev: string | null, formData: FormData) => Promise<string | null>;
}) {
  const [reading, setReading] = useState("");
  const entered = reading === "" ? null : Number(reading);
  const driven = entered == null || Number.isNaN(entered) ? null : entered - odometerOut;
  const base = driven == null || driven < 0 ? null : Math.round(driven * unitRate * 100) / 100;
  const keptDiscount = base == null ? 0 : Math.min(discount, base);
  const taxable = base == null ? null : Math.round((base - keptDiscount) * 100) / 100;
  const tax = taxable == null ? null : Math.round((taxable * taxRate) / 100 * 100) / 100;
  const rental = taxable == null || tax == null ? null : Math.round((taxable + tax) * 100) / 100;

  return (
    <ActionForm action={action} submit="Settle kilometres and return">
      <input type="hidden" name="booking_id" value={bookingId} />
      <p className="text-sm text-white/70">
        Out {odometerOut}
        {plannedKm != null ? ` · quoted ${plannedKm} km` : ""}. Fare is the distance times {formatInrExact(unitRate)} per km.
      </p>
      <input
        name="odometer"
        type="number"
        required
        min={odometerOut}
        value={reading}
        onChange={(event) => setReading(event.target.value)}
        placeholder="Odometer in"
        className="w-full rounded-xl px-3 py-2 text-black"
      />
      {driven != null && driven >= 0 && rental != null ? (
        <p className="text-sm">
          {driven} km · rental {formatInrExact(rental)} including GST. The deposit is not part of this fare.
        </p>
      ) : null}
    </ActionForm>
  );
}
