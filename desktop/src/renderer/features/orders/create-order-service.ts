import {
  get,
  push,
  ref,
  runTransaction,
  serverTimestamp,
  update,
} from "firebase/database";
import { database } from "@/lib/firebase/client";
import { sanitizeForFirebase } from "@/lib/firebase/sanitize";
import type { AppUser } from "@/store/session-store";
import type { OrderDraftItem, OrderUrgency } from "@/features/orders/create-order-data";

const sharedCompanyDataId = "shared";

type SubmitOrderInput = {
  reservedOrderId?: string;
  onOrderIdReserved?: (orderId: string) => void;
  requester: AppUser;
  urgency: OrderUrgency;
  requestedDeliveryDate: Date;
  notes: string;
  urgentJustification: string;
  items: OrderDraftItem[];
};

const submitTimeoutMs = 45000;

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

export async function submitPurchaseOrder(input: SubmitOrderInput) {
  const databaseItems = sanitizeForFirebase(mapDatabaseItems(input.items));
  const orderId = await withTimeout(
    resolveOrderId(input.reservedOrderId),
    "No se pudo reservar el folio de la orden.",
  );
  input.onOrderIdReserved?.(orderId);

  const eventRef = push(ref(database, `purchaseOrders/${orderId}/events`));
  const eventId = eventRef.key;
  if (!eventId) {
    throw new Error("No se pudo crear el evento inicial de la orden.");
  }

  await withTimeout(
    update(ref(database), {
      [`purchaseOrders/${orderId}/companyId`]: sharedCompanyDataId,
      [`purchaseOrders/${orderId}/requesterId`]: input.requester.id,
      [`purchaseOrders/${orderId}/requesterName`]: input.requester.name,
      [`purchaseOrders/${orderId}/areaId`]: input.requester.areaId,
      [`purchaseOrders/${orderId}/areaName`]: input.requester.areaDisplay,
      [`purchaseOrders/${orderId}/urgency`]: input.urgency,
      [`purchaseOrders/${orderId}/clientNote`]: input.notes.trim() || null,
      [`purchaseOrders/${orderId}/urgentJustification`]: input.urgentJustification.trim() || null,
      [`purchaseOrders/${orderId}/requestedDeliveryDate`]: input.requestedDeliveryDate.getTime(),
      [`purchaseOrders/${orderId}/items`]: databaseItems,
      [`purchaseOrders/${orderId}/status`]: "intakeReview",
      [`purchaseOrders/${orderId}/isDraft`]: false,
      [`purchaseOrders/${orderId}/pdfUrl`]: null,
      [`purchaseOrders/${orderId}/authorizedByName`]: null,
      [`purchaseOrders/${orderId}/authorizedByArea`]: null,
      [`purchaseOrders/${orderId}/authorizedAt`]: null,
      [`purchaseOrders/${orderId}/processByName`]: null,
      [`purchaseOrders/${orderId}/processByArea`]: null,
      [`purchaseOrders/${orderId}/processAt`]: null,
      [`purchaseOrders/${orderId}/visibility/contabilidad`]: false,
      [`purchaseOrders/${orderId}/statusEnteredAt`]: serverTimestamp(),
      [`purchaseOrders/${orderId}/statusDurations`]: {},
      [`purchaseOrders/${orderId}/updatedAt`]: serverTimestamp(),
      [`purchaseOrders/${orderId}/createdAt`]: serverTimestamp(),
      [`purchaseOrders/${orderId}/events/${eventId}`]: {
        fromStatus: "draft",
        toStatus: "intakeReview",
        byUserId: input.requester.id,
        byRole: input.requester.areaDisplay,
        timestamp: serverTimestamp(),
        type: "advance",
        itemsSnapshot: databaseItems,
      },
    }),
    "No se pudo guardar la orden en la base de datos.",
  );

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

async function resolveOrderId(preferredOrderId?: string) {
  const normalizedPreferred = preferredOrderId?.trim();
  if (normalizedPreferred) {
    const snapshot = await get(ref(database, `purchaseOrders/${normalizedPreferred}`));
    if (!snapshot.exists()) {
      return normalizedPreferred;
    }
  }

  return reserveNextFolio();
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

async function withTimeout<T>(promise: Promise<T>, errorMessage: string) {
  let timer: ReturnType<typeof setTimeout> | null = null;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error(errorMessage)), submitTimeoutMs);
      }),
    ]);
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}
