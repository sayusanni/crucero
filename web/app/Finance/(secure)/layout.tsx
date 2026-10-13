import type { ReactNode } from "react";
import { requireArea } from "@/lib/auth";

export default async function FinanceLayout({ children }: { children: ReactNode }) {
  await requireArea("finance");
  return children;
}
