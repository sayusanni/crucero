import { notFound, redirect } from "next/navigation";
import { SiteNav } from "@/components/nav";
import { ActionForm } from "@/components/form-error";
import { requireArea } from "@/lib/auth";
import { saveDocuments } from "@/lib/actions";
import { createClient } from "@/lib/supabase/server";
import type { Booking } from "@/lib/database.types";

async function save(_prev: string | null, formData: FormData) {
  "use server";
  const result = await saveDocuments(formData);
  return result?.error ?? null;
}

export default async function DocumentsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const profile = await requireArea("platform");
  const supabase = await createClient();
  const { data } = await supabase.from("bookings").select("*").eq("id", id).maybeSingle();
  const booking = data as Booking | null;
  if (!booking || booking.customer_id !== profile.id) notFound();
  if (booking.status !== "draft") redirect(`/Platform/book/${id}/pay`);

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="mx-auto max-w-lg px-5 py-12">
        <h1 className="display text-4xl">Documents</h1>
        <p className="mt-2 text-sm text-ink/70">
          Licence front is stored as a file. For Aadhaar, PAN, or passport, enter only the last 4 characters.
        </p>
        <div className="panel mt-6 rounded-3xl p-6">
          <ActionForm action={save} submit="Save and continue to payment">
            <input type="hidden" name="booking_id" value={booking.id} />
            <label className="block text-sm">
              Driving licence, front
              <input name="dl_front" type="file" accept="image/*,.pdf" required className="mt-1 w-full" />
            </label>
            <label className="block text-sm">
              ID last 4
              <input name="last4" maxLength={4} required placeholder="3821" className="mt-1 w-full rounded-xl px-3 py-2" />
            </label>
          </ActionForm>
        </div>
      </main>
    </div>
  );
}
