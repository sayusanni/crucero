import { AreaLogin } from "@/components/area-login";

export default async function FinanceLogin({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  const params = await searchParams;
  return (
    <AreaLogin
      area="finance"
      title="Finance login"
      blurb="Money in, money out, and deposits. This login does not open the customer site."
      denied={params.denied === "1"}
    />
  );
}
