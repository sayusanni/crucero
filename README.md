# Crucero

Bike and car rental for a school showcase. The name is the brand. The product is renting vehicles and running the company: branches, a price snapshot, versioned GST, deposits that are not revenue, and a staff desk.

## Run

```bash
cd web
npm install
npm run dev
```

Open http://localhost:3000. Environment lives in `web/.env.local` (see `web/.env.example`).

## Areas and logins

Each door has its own URL and its own login. An account for one desk cannot open another.

| Area | URL | Login |
| --- | --- | --- |
| Customer | `/Platform` | `guest.zia@example.com` / `Guest123!` |
| Operations | `/Operations` | `admin@crucero.app` / `Admin123!` |
| Finance | `/Finance` | `finance@crucero.app` / `Finance123!` |
| Tax, assets, books | `/Gst` | `gst@crucero.app` / `Gst12345!` |
| Reports | `/Reports` | `reports@crucero.app` / `Reports123!` |
| Agreements and adapters | `/Backend` | `backend@crucero.app` / `Backend123!` |

The admin account can also open Finance, GST, Reports, and Backend. The customer account cannot.

## What a booking does

1. Search by branch, start, end, and bike or car. Availability ignores cancelled bookings and blocks overlaps.
2. The database prices the rental. Up to 24 hours is hourly. After that, whole days plus the leftover hours. `WEEKEND10` takes 10% off the rental, not the deposit.
3. GST comes from the tax rule in force on the start date (SAC 997329, 18% in the seed). The rate is copied onto the booking.
4. Documents: licence file, and only the last 4 characters of an ID. A full Aadhaar number is rejected.
5. Payment is authorized, then the agreement is signed, then the rental is captured.
6. Capture posts two journals: rental revenue plus GST, and a customer-deposit liability.
