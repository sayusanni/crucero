import { AreaLogin } from "@/components/area-login";

export default async function OperationsLogin({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  const params = await searchParams;
  return (
    <AreaLogin
      area="operations"
      title="Operations login"
      blurb="Admin and branch staff. Customer, finance, GST, reports, and backend accounts stay out."
      denied={params.denied === "1"}
      signupHref="/Operations/signup"
    />
  );
}
