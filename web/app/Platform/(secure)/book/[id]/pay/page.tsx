import { notFound, redirect } from "next/navigation";
import { SiteNav } from "@/components/nav";
import { ActionForm } from "@/components/form-error";
import { requireArea } from "@/lib/auth";
import { authorizeBooking } from "@/lib/actions";
import { createClient } from "@/lib/supabase/server";
import { formatInr } from "@/lib/money";
import type { Booking } from "@/lib/database.types";

async function pay(_prev: string | null, formData: FormData) {
  "use server";
  const result = await authorizeBooking(formData);
  return result?.error ?? null;
}

export default async function PayPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const profile = await requireArea("platform");
  const supabase = await createClient();
  const { data } = await supabase.from("bookings").select("*").eq("id", id).maybeSingle();
  const booking = data as Booking | null;
  if (!booking || booking.customer_id !== profile.id) notFound();
  if (booking.status === "authorized" || booking.status === "signed") redirect(`/Platform/book/${id}/agreement`);
  if (booking.status !== "draft") redirect("/Platform/bookings");

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="mx-auto max-w-lg px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">Authorize, do not capture yet</p>
        <h1 className="display mt-2 text-4xl">Hold {formatInr(Number(booking.authorize_amount))}</h1>
        <p className="mt-2 text-sm text-ink/70">
          Rental plus GST is {formatInr(Number(booking.rental_total))}. Deposit{" "}
          {formatInr(Number(booking.deposit_amount))} stays a liability. Capture waits for the signature.
        </p>
        <div className="panel mt-6 rounded-3xl p-6">
          <ActionForm action={pay} submit="Authorize payment">
            <input type="hidden" name="booking_id" value={booking.id} />
            <label className="block text-sm">
              Method
              <select name="method" className="mt-1 w-full rounded-xl px-3 py-2">
                <option value="upi">UPI</option>
                <option value="card">Card</option>
                <option value="cash">Cash at branch</option>
              </select>
            </label>
          </ActionForm>
        </div>
      </main>
    </div>
  );
}
