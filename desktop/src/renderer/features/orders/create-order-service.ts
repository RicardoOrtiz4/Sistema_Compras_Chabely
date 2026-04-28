import {
  get,
  push,
  ref,
  runTransaction,
  serverTimestamp,
  set,
  update,
} from "firebase/database";
import { database } from "@/lib/firebase/client";
import { resolveLoginEmail } from "@/lib/branding";
import { sanitizeForFirebase } from "@/lib/firebase/sanitize";
import { uploadOrderPdf } from "@/features/orders/order-pdf-service";
import type { AppUser } from "@/store/session-store";
import { useBrandingStore } from "@/store/branding-store";
import type { OrderDraftItem, OrderUrgency } from "@/features/orders/create-order-data";

const sharedCompanyDataId = "shared";

type SubmitOrderInput = {
  requester: AppUser;
  urgency: OrderUrgency;
  requestedDeliveryDate: Date;
  notes: string;
  urgentJustification: string;
  items: OrderDraftItem[];
};

function mapDatabaseItems(items: OrderDraftItem[]) {
  return items.map((item) => ({
    line: item.line,
    pieces: item.pieces,
    partNumber: item.partNumber.trim(),
    description: item.description.trim(),
    quantity: item.pieces,
    unit: item.unit.trim().toUpperCase(),
    customer: item.customer?.trim() || null,
  }));
}

function mapPdfItems(items: OrderDraftItem[]) {
  return items.map((item) => ({
    line: item.line,
    pieces: item.pieces,
    partNumber: item.partNumber.trim(),
    description: item.description.trim(),
    quantity: item.pieces,
    unit: item.unit.trim().toUpperCase(),
    customer: item.customer?.trim() || undefined,
    reviewFlagged: false,
    isArrivalRegistered: false,
    isNotPurchased: false,
    requiresFulfillment: true,
    isResolved: false,
  }));
}

export async function submitPurchaseOrder(input: SubmitOrderInput) {
  const orderId = await reserveNextFolio();
  const orderRef = ref(database, `purchaseOrders/${orderId}`);
  const company =
    useBrandingStore.getState().company ||
    resolveLoginEmail(input.requester.email).company ||
    "chabely";
  const databaseItems = mapDatabaseItems(input.items);
  const pdfItems = mapPdfItems(input.items);

  await set(orderRef, {
    companyId: sharedCompanyDataId,
    requesterId: input.requester.id,
    requesterName: input.requester.name,
    areaId: input.requester.areaId,
    areaName: input.requester.areaDisplay,
    urgency: input.urgency,
    clientNote: input.notes.trim() || null,
    urgentJustification: input.urgentJustification.trim() || null,
    requestedDeliveryDate: input.requestedDeliveryDate.getTime(),
    items: sanitizeForFirebase(databaseItems),
    status: "intakeReview",
    isDraft: false,
    pdfUrl: null,
    authorizedByName: null,
    authorizedByArea: null,
    authorizedAt: null,
    processByName: null,
    processByArea: null,
    processAt: null,
    visibility: {
      contabilidad: false,
    },
    statusEnteredAt: serverTimestamp(),
    statusDurations: {},
    updatedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  });

  const eventRef = push(ref(database, `purchaseOrders/${orderId}/events`));
  await set(eventRef, {
    fromStatus: "draft",
    toStatus: "intakeReview",
    byUserId: input.requester.id,
    byRole: input.requester.areaDisplay,
    timestamp: serverTimestamp(),
    type: "advance",
    itemsSnapshot: sanitizeForFirebase(databaseItems),
  });

  const now = Date.now();
  const pdfUrl = await uploadOrderPdf({
    company,
    fileLabel: "requisicion",
    order: {
      id: orderId,
      requesterName: input.requester.name,
      areaName: input.requester.areaDisplay,
      urgency: input.urgency,
      status: "intakeReview",
      items: pdfItems,
      clientNote: input.notes.trim() || undefined,
      urgentJustification: input.urgentJustification.trim() || undefined,
      supplier: undefined,
      authorizedByName: undefined,
      authorizedByArea: undefined,
      authorizedAt: undefined,
      processByName: undefined,
      processByArea: undefined,
      processAt: undefined,
      createdAt: now,
      updatedAt: now,
      requestedDeliveryDate: input.requestedDeliveryDate.getTime(),
      etaDate: undefined,
      materialArrivedAt: undefined,
      requesterReceivedAt: undefined,
      paymentReceiptUrls: [],
      facturaPdfUrls: [],
    },
  });

  await update(orderRef, {
    pdfUrl,
    updatedAt: serverTimestamp(),
  });

  return orderId;
}

async function reserveNextFolio() {
  const counterRef = ref(database, "counters/folios/purchaseOrderNext");
  const currentSnapshot = await get(counterRef);
  const currentValue = parseCounterValue(currentSnapshot.val());
  const legacySeed = currentValue > 0 ? 0 : await resolveLegacyCounterMax();

  const result = await runTransaction(counterRef, (current) => {
    const base = parseCounterValue(current);
    const effective = base > 0 ? base : legacySeed;
    return effective + 1;
  });

  if (!result.committed) {
    throw new Error("No se pudo reservar el folio.");
  }

  const nextValue = parseCounterValue(result.snapshot.val());
  if (nextValue <= 0) {
    throw new Error("Folio inválido.");
  }

  return String(nextValue).padStart(6, "0");
}

async function resolveLegacyCounterMax() {
  const legacyKeys = ["chabely", "acerpro"];
  const snapshots = await Promise.all(
    legacyKeys.map((company) => get(ref(database, `counters/folios/${company}/purchaseOrderNext`))),
  );

  return snapshots.reduce((max, snapshot) => {
    const value = parseCounterValue(snapshot.val());
    return value > max ? value : max;
  }, 0);
}

function parseCounterValue(raw: unknown) {
  if (typeof raw === "number") return Math.trunc(raw);
  if (typeof raw === "string") return Number.parseInt(raw.trim(), 10) || 0;
  return 0;
}
