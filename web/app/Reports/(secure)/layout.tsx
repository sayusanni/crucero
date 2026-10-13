import type { ReactNode } from "react";
import { requireArea } from "@/lib/auth";

export default async function ReportsLayout({ children }: { children: ReactNode }) {
  await requireArea("reports");
  return children;
}
