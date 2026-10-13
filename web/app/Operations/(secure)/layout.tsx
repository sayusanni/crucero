import type { ReactNode } from "react";
import { requireArea } from "@/lib/auth";

export default async function OperationsLayout({ children }: { children: ReactNode }) {
  await requireArea("operations");
  return children;
}
