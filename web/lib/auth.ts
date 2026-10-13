import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AREA_HOME, type Area } from "@/lib/areas";
import type { Profile } from "@/lib/database.types";

export async function getProfile(): Promise<Profile | null> {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub as string | undefined;
  if (!userId) return null;

  const { data: profile } = await supabase.from("profiles").select("*").eq("id", userId).maybeSingle();
  return profile as Profile | null;
}

export async function hasArea(area: Area) {
  const profile = await getProfile();
  if (!profile) return false;
  const supabase = await createClient();
  const { data } = await supabase
    .from("profile_areas")
    .select("area")
    .eq("profile_id", profile.id)
    .eq("area", area)
    .maybeSingle();
  return Boolean(data);
}

export async function requireArea(area: Area) {
  const profile = await getProfile();
  const login = `${AREA_HOME[area]}/login`;
  if (!profile) redirect(login);
  if (!(await hasArea(area))) redirect(`${login}?denied=1`);
  return profile;
}
