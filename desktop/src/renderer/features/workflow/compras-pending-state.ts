import type { PurchaseOrderItem } from "@/features/orders/orders-data";

type ComprasPendingDraft = {
  items: PurchaseOrderItem[];
  confirmed: boolean;
  processName?: string;
  processArea?: string;
};

const storageKey = "desktop.comprasPendingDrafts";

function readAllDrafts() {
  if (typeof window === "undefined") return {} as Record<string, ComprasPendingDraft>;
  try {
    const raw = window.localStorage.getItem(storageKey);
    if (!raw) return {} as Record<string, ComprasPendingDraft>;
    const parsed = JSON.parse(raw) as Record<string, ComprasPendingDraft>;
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {} as Record<string, ComprasPendingDraft>;
  }
}

function writeAllDrafts(value: Record<string, ComprasPendingDraft>) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(storageKey, JSON.stringify(value));
}

export function readComprasPendingDraft(orderId: string) {
  const draft = readAllDrafts()[orderId];
  return draft ?? null;
}

export function saveComprasPendingDraft(orderId: string, draft: ComprasPendingDraft) {
  const all = readAllDrafts();
  all[orderId] = draft;
  writeAllDrafts(all);
}

export function clearComprasPendingDraft(orderId: string) {
  const all = readAllDrafts();
  delete all[orderId];
  writeAllDrafts(all);
}
