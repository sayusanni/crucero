/** Interpret a datetime-local value as India time for a Hyderabad rental desk. */
export function toIso(localValue: string) {
  const trimmed = localValue.trim();
  if (!trimmed) throw new Error("Choose a start and end time");
  const withSeconds = trimmed.length === 16 ? `${trimmed}:00` : trimmed;
  return new Date(`${withSeconds}+05:30`).toISOString();
}

export function defaultWindow() {
  const start = new Date();
  start.setDate(start.getDate() + 1);
  start.setHours(10, 0, 0, 0);
  const end = new Date(start);
  end.setHours(18, 0, 0, 0);
  const stamp = (date: Date) => {
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  };
  return { start: stamp(start), end: stamp(end) };
}

export function formatWhen(iso: string) {
  return new Intl.DateTimeFormat("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Kolkata",
  }).format(new Date(iso));
}

export function liveLateFee(endAt: string, hourlyPrice: number, now = Date.now()) {
  const hours = Math.max(0, (now - new Date(endAt).getTime()) / 3_600_000);
  const roundedHours = Math.round(hours * 100) / 100;
  const fee = Math.round(roundedHours * Number(hourlyPrice) * 100) / 100;
  return { hours: roundedHours, fee };
}
