import Link from "next/link";
import { AuthForm } from "@/components/auth-form";
import { SiteNav } from "@/components/nav";
import { getProfile } from "@/lib/auth";

export default async function SignupPage() {
  const profile = await getProfile();
  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="px-5 py-16">
        <h1 className="display mb-8 text-center text-5xl">Create an account</h1>
        <AuthForm mode="signup" area="platform" next="/Platform" />
        <p className="mt-6 text-center text-sm">
          Already renting? <Link href="/Platform/login">Sign in</Link>
        </p>
      </main>
    </div>
  );
}
