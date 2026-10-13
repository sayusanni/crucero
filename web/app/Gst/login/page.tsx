import { AreaLogin } from "@/components/area-login";

export default async function GstLogin({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  const params = await searchParams;
  return (
    <AreaLogin
      area="gst"
      title="GST and books login"
      blurb="Tax rules, the asset register, and the journal. A separate login from finance and from customers."
      denied={params.denied === "1"}
    />
  );
}
