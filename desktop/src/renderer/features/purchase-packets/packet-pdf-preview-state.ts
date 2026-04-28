type PacketPreviewItemDraft = {
  orderId: string;
  lineNumber: number;
  description: string;
  quantity: number;
  unit: string;
  amount: number;
  internalOrder?: string;
};

export type PacketPreviewDraft = {
  supplier: string;
  orderIds: string[];
  items: PacketPreviewItemDraft[];
  totalAmount: number;
  evidenceUrls: string[];
  folio?: string;
  issuedAt: number;
};

const storageKey = "desktop.packetPreviewDraft";

export function savePacketPreviewDraft(draft: PacketPreviewDraft) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(storageKey, JSON.stringify(draft));
}

export function readPacketPreviewDraft() {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(storageKey);
    if (!raw) return null;
    return JSON.parse(raw) as PacketPreviewDraft;
  } catch {
    return null;
  }
}

export function clearPacketPreviewDraft() {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(storageKey);
}
