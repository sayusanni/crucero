import { notFound, redirect } from "next/navigation";
import { SiteNav } from "@/components/nav";
import { ActionForm } from "@/components/form-error";
import { requireArea } from "@/lib/auth";
import { captureBooking, signAgreement } from "@/lib/actions";
import { createClient } from "@/lib/supabase/server";
import { formatInr } from "@/lib/money";
import { formatWhen } from "@/lib/time";
import type { Booking } from "@/lib/database.types";

async function sign(_prev: string | null, formData: FormData) {
  "use server";
  const result = await signAgreement(formData);
  return result?.error ?? null;
}

async function capture(_prev: string | null, formData: FormData) {
  "use server";
  const result = await captureBooking(formData);
  return result?.error ?? null;
}

export default async function AgreementPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const profile = await requireArea("platform");
  const supabase = await createClient();
  const { data } = await supabase.from("bookings").select("*, vehicles(name, registration)").eq("id", id).maybeSingle();
  if (!data || data.customer_id !== profile.id) notFound();
  const booking = data as Booking & { vehicles: { name: string; registration: string } | { name: string; registration: string }[] };
  if (booking.status === "draft") redirect(`/Platform/book/${id}/pay`);
  const vehicle = Array.isArray(booking.vehicles) ? booking.vehicles[0] : booking.vehicles;

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="mx-auto max-w-lg px-5 py-12">
        <h1 className="display text-4xl">Agreement</h1>
        <article className="panel mt-6 space-y-2 rounded-3xl p-6 text-sm">
          <p>
            {vehicle?.name} · {vehicle?.registration}
          </p>
          <p>
            {formatWhen(booking.start_at)} → {formatWhen(booking.end_at)}
          </p>
          <p>
            Price snapshot: {booking.duration_hours} h at {formatInr(Number(booking.hourly_price))}/h and{" "}
            {formatInr(Number(booking.daily_price))}/day.
          </p>
          <p>
            GST {booking.tax_rate}% on {formatInr(Number(booking.taxable_amount))} = {formatInr(Number(booking.tax_amount))}.
          </p>
          <p>Deposit {formatInr(Number(booking.deposit_amount))} is held, not earned.</p>
          <p>Damage, late return, and cancellation are settled at the branch from this snapshot.</p>
        </article>
        {booking.status === "authorized" ? (
          <div className="mt-4">
            <ActionForm action={sign} submit="eSign agreement">
              <input type="hidden" name="booking_id" value={booking.id} />
            </ActionForm>
          </div>
        ) : null}
        {booking.status === "signed" ? (
          <div className="mt-4">
            <ActionForm action={capture} submit="Capture rental payment">
              <input type="hidden" name="booking_id" value={booking.id} />
            </ActionForm>
          </div>
        ) : null}
      </main>
    </div>
  );
}
