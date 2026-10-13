import { AreaLogin } from "@/components/area-login";

export default async function ReportsLogin({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  const params = await searchParams;
  return (
    <AreaLogin
      area="reports"
      title="Reports login"
      blurb="Read-only numbers for the company. This account cannot book a vehicle or post a journal."
      denied={params.denied === "1"}
    />
  );
}
