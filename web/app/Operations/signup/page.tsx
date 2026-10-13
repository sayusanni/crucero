import { AuthForm } from "@/components/auth-form";
import { SiteNav } from "@/components/nav";
import { getProfile } from "@/lib/auth";

export default async function AdminSignupPage() {
  const profile = await getProfile();
  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="operations" />
      <main className="px-5 py-16">
        <h1 className="display mb-8 text-center text-5xl">First admin</h1>
        <AuthForm mode="signup" area="operations" asAdmin next="/Operations" />
      </main>
    </div>
  );
}
