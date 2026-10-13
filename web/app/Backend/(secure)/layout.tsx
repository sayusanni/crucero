import type { ReactNode } from "react";
import { requireArea } from "@/lib/auth";

export default async function BackendLayout({ children }: { children: ReactNode }) {
  await requireArea("backend");
  return children;
}