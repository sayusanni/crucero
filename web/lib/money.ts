export function formatInr(amount: number | string) {
  const value = typeof amount === "string" ? Number(amount) : amount;
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0,
  }).format(value);
}

export function formatInrExact(amount: number | string) {
  const value = typeof amount === "string" ? Number(amount) : amount;
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function describeRate(unit: string, unitRate: number, dailyRate?: number | null) {
  const rate = formatInr(unitRate);
  if (unit === "package") return `${rate} for 12 hours`;
  if (unit === "minute") return `${rate} per minute`;
  if (unit === "km") return `${rate} per km`;
  return `${rate} per hour${dailyRate != null ? ` · ${formatInr(dailyRate)} per day` : ""}`;
}

export function describePackage(price: number, includedKm: number, excess: number) {
  return `${formatInr(price)} for 12 hours · ${includedKm} km included · extra ${formatInr(excess)}/km`;
}

export function formatDate(iso: string) {
  return new Intl.DateTimeFormat("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(`${iso}T00:00:00`));
}
