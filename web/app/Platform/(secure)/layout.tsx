import type { ReactNode } from "react";
import { requireArea } from "@/lib/auth";

export default async function PlatformLayout({ children }: { children: ReactNode }) {
  await requireArea("platform");
  return children;
}
