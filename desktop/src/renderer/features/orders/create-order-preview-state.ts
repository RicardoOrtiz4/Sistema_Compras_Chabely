import type { AppUser } from "@/store/session-store";
import type { OrderDraftItem, OrderUrgency } from "@/features/orders/create-order-data";
import type { CompanyId } from "@/lib/branding";

const previewStorageKey = "create-order-preview-draft";
const formStorageKey = "create-order-form-draft";

export type CreateOrderPreviewDraft = {
  company: CompanyId;
  requester: AppUser;
  urgency: OrderUrgency;
  requestedDeliveryDate: number;
  notes: string;
  urgentJustification: string;
  items: OrderDraftItem[];
  createdAt: number;
  reservedOrderId?: string;
};

export type CreateOrderFormDraft = {
  urgency: OrderUrgency;
  requestedDeliveryDate: number | null;
  notes: string;
  urgentJustification: string;
  items: OrderDraftItem[];
};

export function saveCreateOrderPreviewDraft(draft: CreateOrderPreviewDraft) {
  sessionStorage.setItem(previewStorageKey, JSON.stringify(draft));
}

export function readCreateOrderPreviewDraft() {
  const raw = sessionStorage.getItem(previewStorageKey);
  if (!raw) return null;

  try {
    return JSON.parse(raw) as CreateOrderPreviewDraft;
  } catch {
    return null;
  }
}

export function clearCreateOrderPreviewDraft() {
  sessionStorage.removeItem(previewStorageKey);
}

export function updateCreateOrderPreviewDraft(
  updater: (draft: CreateOrderPreviewDraft) => CreateOrderPreviewDraft,
) {
  const current = readCreateOrderPreviewDraft();
  if (!current) return null;
  const next = updater(current);
  saveCreateOrderPreviewDraft(next);
  return next;
}

export function saveCreateOrderFormDraft(draft: CreateOrderFormDraft) {
  sessionStorage.setItem(formStorageKey, JSON.stringify(draft));
}

export function readCreateOrderFormDraft() {
  const raw = sessionStorage.getItem(formStorageKey);
  if (!raw) return null;

  try {
    return JSON.parse(raw) as CreateOrderFormDraft;
  } catch {
    return null;
  }
}

export function clearCreateOrderFormDraft() {
  sessionStorage.removeItem(formStorageKey);
}
