export const AREAS = ["platform", "operations", "finance", "gst", "reports", "backend"] as const;
export type Area = (typeof AREAS)[number];

export const AREA_HOME: Record<Area, string> = {
  platform: "/Platform",
  operations: "/Operations",
  finance: "/Finance",
  gst: "/Gst",
  reports: "/Reports",
  backend: "/Backend",
};

export function isArea(value: string): value is Area {
  return (AREAS as readonly string[]).includes(value);
}
