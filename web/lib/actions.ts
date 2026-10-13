"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getProfile } from "@/lib/auth";
import { AREA_HOME, isArea } from "@/lib/areas";
import { toIso } from "@/lib/time";

function field(formData: FormData, key: string) {
  return String(formData.get(key) ?? "").trim();
}

export async function signUp(formData: FormData) {
  const supabase = await createClient();
  const asAdmin = field(formData, "as_admin") === "true";
  const { error } = await supabase.auth.signUp({
    email: field(formData, "email"),
    password: field(formData, "password"),
    options: { data: { full_name: field(formData, "full_name") } },
  });
  if (error) return { error: error.message };
  if (asAdmin) {
    const { error: claimError } = await supabase.rpc("claim_first_admin");
    if (claimError) return { error: claimError.message };
  }
  redirect(asAdmin ? "/Operations" : "/Platform");
}

export async function signIn(formData: FormData) {
  const supabase = await createClient();
  const area = field(formData, "area");
  if (!isArea(area)) return { error: "Unknown desk." };
  const next = field(formData, "next") || AREA_HOME[area];
  const { error } = await supabase.auth.signInWithPassword({
    email: field(formData, "email"),
    password: field(formData, "password"),
  });
  if (error) return { error: error.message };

  const profile = await getProfile();
  const { data: access } = await supabase
    .from("profile_areas")
    .select("area")
    .eq("profile_id", profile?.id ?? "")
    .eq("area", area)
    .maybeSingle();
  if (!access) {
    await supabase.auth.signOut();
    return { error: "This account cannot open this desk. Sign in on your own area." };
  }
  redirect(next);
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}

export async function createBooking(formData: FormData) {
  const profile = await getProfile();
  if (!profile) redirect(`/Platform/login?next=/Platform/vehicles/${field(formData, "vehicle_id")}`);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_rental_booking", {
    p_vehicle: field(formData, "vehicle_id"),
    p_start: toIso(field(formData, "start")),
    p_end: toIso(field(formData, "end")),
    p_coupon: field(formData, "coupon") || null,
    p_km: field(formData, "km") ? Number(field(formData, "km")) : null,
  });
  if (error || !data) return { error: error?.message ?? "Could not create the booking" };
  redirect(`/Platform/book/${data}/documents`);
}

export async function saveDocuments(formData: FormData) {
  const profile = await getProfile();
  if (!profile) redirect("/Platform/login");
  const bookingId = field(formData, "booking_id");
  const last4 = field(formData, "last4").replace(/\s/g, "");
  if (last4.length > 4 || /^\d{12}$/.test(last4)) {
    return { error: "Enter only the last 4 characters. A full Aadhaar number is never stored." };
  }
  if (!/^[0-9A-Za-z]{4}$/.test(last4)) {
    return { error: "The ID reference must be exactly 4 letters or digits." };
  }

  const file = formData.get("dl_front");
  if (!(file instanceof File) || file.size === 0) {
    return { error: "Upload the front of the driving licence." };
  }

  const supabase = await createClient();
  const path = `${profile.id}/${bookingId}/dl-front-${file.name}`;
  const { error: uploadError } = await supabase.storage
    .from("customer-documents")
    .upload(path, file, { upsert: true });
  if (uploadError) return { error: uploadError.message };

  const { error } = await supabase.from("documents").insert([
    { customer_id: profile.id, booking_id: bookingId, kind: "dl_front", storage_path: path },
    { customer_id: profile.id, booking_id: bookingId, kind: "id_last4", last4 },
  ]);
  if (error) return { error: error.message };
  redirect(`/Platform/book/${bookingId}/pay`);
}

export async function authorizeBooking(formData: FormData) {
  const supabase = await createClient();
  const bookingId = field(formData, "booking_id");
  const { error } = await supabase.rpc("authorize_booking", {
    p_booking: bookingId,
    p_method: field(formData, "method") || "upi",
  });
  if (error) return { error: error.message };
  redirect(`/Platform/book/${bookingId}/agreement`);
}

export async function signAgreement(formData: FormData) {
  const supabase = await createClient();
  const bookingId = field(formData, "booking_id");
  const { error } = await supabase.rpc("sign_agreement", { p_booking: bookingId });
  if (error) return { error: error.message };
  redirect(`/Platform/book/${bookingId}/agreement`);
}

export async function captureBooking(formData: FormData) {
  const supabase = await createClient();
  const bookingId = field(formData, "booking_id");
  const { error } = await supabase.rpc("capture_booking", { p_booking: bookingId });
  if (error) return { error: error.message };
  redirect("/Platform/bookings?captured=1");
}

export async function confirmPickup(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("confirm_pickup", {
    p_booking: field(formData, "booking_id"),
    p_odometer: Number(field(formData, "odometer")),
  });
  if (error) return { error: error.message };
  revalidatePath("/Operations/staff");
}

export async function confirmReturn(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("confirm_return", {
    p_booking: field(formData, "booking_id"),
    p_odometer: Number(field(formData, "odometer")),
    p_returned_at: new Date().toISOString(),
  });
  if (error) return { error: error.message };
  revalidatePath("/Operations/staff");
  revalidatePath("/Finance");
  revalidatePath("/Finance/ledger");
}

export async function setVehicleStatus(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_vehicle_status", {
    p_vehicle: field(formData, "vehicle_id"),
    p_status: field(formData, "status"),
  });
  if (error) return { error: error.message };
  revalidatePath("/Operations/fleet");
  revalidatePath("/Operations/staff");
  revalidatePath("/Gst/assets");
}

export async function releaseDeposit(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("release_deposit", {
    p_booking: field(formData, "booking_id"),
  });
  if (error) return { error: error.message };
  revalidatePath("/Finance");
  revalidatePath("/Finance/ledger");
}

export async function saveRateCard(formData: FormData) {
  const supabase = await createClient();
  const id = field(formData, "card_id");
  const { error } = await supabase.rpc("save_package", {
    p_id: id || null,
    p_name: field(formData, "name"),
    p_package: Number(field(formData, "package")),
    p_included_km: Number(field(formData, "included_km")),
    p_excess: Number(field(formData, "excess")),
    p_deposit: Number(field(formData, "deposit") || 0),
  });
  if (error) return { error: error.message };
  revalidatePath("/Operations/rates");
}

export async function allotVehiclePrice(formData: FormData) {
  const supabase = await createClient();
  const card = field(formData, "rate_card_id");
  const { error } = await supabase.rpc("allot_package", {
    p_vehicle: field(formData, "vehicle_id"),
    p_rate_card: card && card !== "custom" ? card : null,
    p_package: field(formData, "package") ? Number(field(formData, "package")) : null,
    p_included_km: field(formData, "included_km") ? Number(field(formData, "included_km")) : null,
    p_excess: field(formData, "excess") ? Number(field(formData, "excess")) : null,
    p_deposit: field(formData, "deposit") ? Number(field(formData, "deposit")) : 0,
  });
  if (error) return { error: error.message };
  revalidatePath("/Operations/fleet");
  revalidatePath("/Platform/rent");
}

export async function addTaxRule(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("add_tax_rule", {
    p_name: field(formData, "name"),
    p_sac: field(formData, "sac"),
    p_rate: Number(field(formData, "rate")),
    p_from: field(formData, "effective_from"),
  });
  if (error) return { error: error.message };
  revalidatePath("/Gst");
  revalidatePath("/Gst/rules");
}
