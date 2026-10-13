import Link from "next/link";
import { SiteNav } from "@/components/nav";
import { getProfile } from "@/lib/auth";

export default async function PlatformHome() {
  const profile = await getProfile();
  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="mx-auto max-w-5xl px-5 py-16">
        <p className="text-xs uppercase tracking-[0.28em] text-ember">/Platform</p>
        <h1 className="display mt-4 text-5xl leading-[0.95] sm:text-6xl">
          Rent a bike or a car.
        </h1>
        <p className="mt-4 max-w-xl text-ink/70">
          Choose a branch and a clock time. The price, GST, and deposit are calculated on the server and stored on the booking.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/Platform/rent" className="rounded-full bg-ember px-6 py-3 text-paper">
            Find a vehicle
          </Link>
          <Link href="/Platform/bookings" className="rounded-full border border-ink/15 px-6 py-3">
            My bookings
          </Link>
        </div>
      </main>
    </div>
  );
}
