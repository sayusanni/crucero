import type { ReactNode } from "react";
import { requireArea } from "@/lib/auth";

export default async function GstLayout({ children }: { children: ReactNode }) {
  await requireArea("gst");
  return children;
}
