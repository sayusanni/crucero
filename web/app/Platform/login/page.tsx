import { AreaLogin } from "@/components/area-login";

export default async function PlatformLogin({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  const params = await searchParams;
  return (
    <AreaLogin
      area="platform"
      title="Customer login"
      blurb="Renters sign in here. A finance or staff account will not open this door."
      denied={params.denied === "1"}
      signupHref="/Platform/signup"
    />
  );
}
