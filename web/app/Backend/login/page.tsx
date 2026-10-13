import { AreaLogin } from "@/components/area-login";

export default async function BackendLogin({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  const params = await searchParams;
  return (
    <AreaLogin
      area="backend"
      title="Backend login"
      blurb="Agreements, documents, notifications, and the outside adapters."
      denied={params.denied === "1"}
    />
  );
}