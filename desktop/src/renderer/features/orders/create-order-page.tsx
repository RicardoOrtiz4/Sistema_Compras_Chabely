import { ChangeEvent, useEffect, useMemo, useRef, useState } from "react";
import { CalendarDays, Plus, Search, Upload, Undo2, X } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { push, ref, serverTimestamp, set } from "firebase/database";
import { canAssignClientsToOrderItems } from "@/lib/access-control";
import {
  firstAllowedNormalRequestedDeliveryDate,
  isAllowedNormalRequestedDeliveryDate,
  isAllowedUrgentRequestedDeliveryDate,
  normalRequestedDeliveryLeadDays,
  normalizeCalendarDate,
  urgentRequestedDeliveryWindowDays,
} from "@/lib/business-calendar";
import { database } from "@/lib/firebase/client";
import { useRtdbValue } from "@/lib/firebase/hooks";
import {
  emptyOrderItem,
  mapPartners,
  orderUnitOptions,
  parseOrderCsv,
  type OrderDraftItem,
  type OrderUrgency,
  type PartnerEntry,
} from "@/features/orders/create-order-data";
import {
  readCreateOrderFormDraft,
  saveCreateOrderPreviewDraft,
  saveCreateOrderFormDraft,
  type CreateOrderPreviewDraft,
} from "@/features/orders/create-order-preview-state";
import { type AppUser, useSessionStore } from "@/store/session-store";
import { useBrandingStore } from "@/store/branding-store";

function toDateInputValue(value: Date | null) {
  if (!value) return "";
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function parseDateInputValue(value: string) {
  if (!value.trim()) return null;
  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime()) ? null : normalizeCalendarDate(date);
}

function requestedDeliveryDateError(urgency: OrderUrgency, requestedDate: Date | null) {
  if (!requestedDate) {
    return "La fecha maxima solicitada es obligatoria.";
  }

  const today = normalizeCalendarDate(new Date());
  if (requestedDate < today) {
    return "La fecha maxima solicitada no puede ser anterior a hoy.";
  }

  if (urgency === "urgente") {
    return isAllowedUrgentRequestedDeliveryDate(requestedDate, today)
      ? null
      : `Para urgencia, la fecha requerida solo puede estar entre hoy y ${urgentRequestedDeliveryWindowDays} dias mas.`;
  }

  return isAllowedNormalRequestedDeliveryDate(requestedDate, today)
    ? null
    : `Para urgencia normal, la fecha requerida debe ser a partir de ${normalRequestedDeliveryLeadDays} dias despues de hoy y en dia habil.`;
}

function itemLabelForPieces(unit: string) {
  const normalized = unit.trim().toUpperCase();
  if (normalized === "PZA" || normalized === "PZ") return "Piezas requeridas";
  if (!normalized) return "Cantidad requerida";
  return `Cantidad requerida (${normalized})`;
}

export function CreateOrderPage() {
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const company = useBrandingStore((state) => state.company);
  const csvInputRef = useRef<HTMLInputElement | null>(null);
  const hydratedDraftRef = useRef(false);

  const [urgency, setUrgency] = useState<OrderUrgency>("normal");
  const [requestedDate, setRequestedDate] = useState<Date | null>(
    firstAllowedNormalRequestedDeliveryDate(),
  );
  const [notes, setNotes] = useState("");
  const [urgentJustification, setUrgentJustification] = useState("");
  const [items, setItems] = useState<OrderDraftItem[]>([emptyOrderItem(1)]);
  const [pageError, setPageError] = useState<string | null>(null);
  const [pageMessage, setPageMessage] = useState<string | null>(null);
  const [clientDialogOpen, setClientDialogOpen] = useState(false);
  const [unitPickerIndex, setUnitPickerIndex] = useState<number | null>(null);

  const clientsState = useRtdbValue("partners/clients", mapPartners, Boolean(profile));
  const clientOptions = clientsState.data ?? [];
  const canAssignClients = canAssignClientsToOrderItems(profile);

  const deliveryError = useMemo(
    () => requestedDeliveryDateError(urgency, requestedDate),
    [requestedDate, urgency],
  );

  useEffect(() => {
    if (hydratedDraftRef.current) return;
    hydratedDraftRef.current = true;

    const cachedDraft = readCreateOrderFormDraft();
    if (!cachedDraft) return;

    setUrgency(cachedDraft.urgency);
    setRequestedDate(
      typeof cachedDraft.requestedDeliveryDate === "number"
        ? normalizeCalendarDate(new Date(cachedDraft.requestedDeliveryDate))
        : null,
    );
    setNotes(cachedDraft.notes);
    setUrgentJustification(cachedDraft.urgentJustification);
    setItems(
      cachedDraft.items?.length
        ? cachedDraft.items.map((item, index) => ({
            ...item,
            line: index + 1,
            quantity: item.pieces,
          }))
        : [emptyOrderItem(1)],
    );
  }, []);

  useEffect(() => {
    if (!hydratedDraftRef.current) return;

    saveCreateOrderFormDraft({
      urgency,
      requestedDeliveryDate: requestedDate ? requestedDate.getTime() : null,
      notes,
      urgentJustification,
      items,
    });
  }, [items, notes, requestedDate, urgency, urgentJustification]);

  function updateItem(index: number, patch: Partial<OrderDraftItem>) {
    setItems((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index
          ? {
              ...item,
              ...patch,
              quantity: typeof patch.pieces === "number" ? patch.pieces : item.quantity,
            }
          : item,
      ),
    );
  }

  function addItem() {
    setItems((current) => [emptyOrderItem(current.length + 1), ...current]);
  }

  function removeItem(index: number) {
    setItems((current) =>
      current
        .filter((_, itemIndex) => itemIndex !== index)
        .map((item, itemIndex) => ({ ...item, line: itemIndex + 1 })),
    );
  }

  async function handleImportCsv(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;

    setPageError(null);
    setPageMessage(null);

    try {
      const content = await file.text();
      const importedItems = parseOrderCsv(content);
      setItems(importedItems);
      setPageMessage(`Se importaron ${importedItems.length} articulos.`);
    } catch (error) {
      setPageError(error instanceof Error ? error.message : "No se pudo importar el CSV.");
    } finally {
      event.target.value = "";
    }
  }

  function validateBeforePreview() {
    if (!profile) {
      return "Perfil no disponible, reintenta.";
    }

    if (urgency === "urgente" && !urgentJustification.trim()) {
      return "Debes justificar por que la requisicion esta marcada como urgente.";
    }

    if (deliveryError) {
      return deliveryError;
    }

    const invalidItem = items.find(
      (item) =>
        !item.description.trim() ||
        !item.unit.trim() ||
        !Number.isFinite(item.pieces) ||
        item.pieces <= 0,
    );

    if (invalidItem) {
      return "Revisa los campos requeridos.";
    }

    return null;
  }

  function handleReviewPdf() {
    setPageError(null);
    setPageMessage(null);

    const validationError = validateBeforePreview();
    if (validationError) {
      setPageError(validationError);
      return;
    }

    const previewDraft: CreateOrderPreviewDraft = {
      company,
      requester: profile!,
      urgency,
      requestedDeliveryDate: requestedDate!.getTime(),
      notes,
      urgentJustification,
      items,
      createdAt: Date.now(),
    };

    saveCreateOrderPreviewDraft(previewDraft);
    navigate("/orders/create/preview");
  }

  return (
    <div className="space-y-6 pb-4">
      <section className="space-y-6">
        <div>
          <div className="mt-3 flex flex-col gap-3 md:flex-row md:items-start">
            <div className="inline-flex overflow-hidden rounded-full border border-slate-500 bg-white">
              {(["normal", "urgente"] as OrderUrgency[]).map((option) => {
                const active = urgency === option;
                const activeStyle =
                  option === "urgente"
                    ? "bg-white text-slate-900"
                    : "border-slate-900 bg-slate-900 text-white";

                return (
                  <button
                    key={option}
                    type="button"
                    onClick={() => {
                      setUrgency(option);
                      if (
                        option === "normal" &&
                        requestedDate &&
                        !isAllowedNormalRequestedDeliveryDate(requestedDate)
                      ) {
                        setRequestedDate(firstAllowedNormalRequestedDeliveryDate());
                      }
                      if (
                        option === "urgente" &&
                        (!requestedDate || !isAllowedUrgentRequestedDeliveryDate(requestedDate))
                      ) {
                        setRequestedDate(normalizeCalendarDate(new Date()));
                      }
                    }}
                    className={[
                      "px-5 py-2 text-sm font-medium transition",
                      active
                        ? "border-slate-900 bg-slate-900 text-white"
                        : "bg-white text-slate-700 hover:bg-slate-50",
                    ].join(" ")}
                  >
                    {option === "urgente" ? "Urgente" : "Normal"}
                  </button>
                );
              })}
            </div>

            {urgency === "urgente" ? (
              <div className="flex-1">
                <label className="mb-2 block text-sm font-medium text-slate-700">
                  Justificacion de urgencia
                </label>
                <textarea
                  value={urgentJustification}
                  onChange={(event) => setUrgentJustification(event.target.value)}
                  rows={4}
                  className="w-full resize-none border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                />
                <p className="mt-2 text-xs text-slate-500">
                  Describe por que este item impide seguir trabajando o puede parar produccion.
                </p>
              </div>
            ) : null}
          </div>

          {urgency === "urgente" ? (
            <div className="mt-3 rounded-xl bg-red-100 px-4 py-3 text-sm text-red-800">
              El estado urgente solo es para items importantes que, sin ellos, no se pueda seguir trabajando o paren la produccion.
            </div>
          ) : null}
        </div>

        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_340px] lg:items-start">
          <RequestedDeliveryDateSection
            urgency={urgency}
            requestedDate={requestedDate}
            error={deliveryError}
            onChangeDate={(nextValue) => setRequestedDate(nextValue)}
            onClearDate={requestedDate ? () => setRequestedDate(null) : null}
          />
          <CreateOrderActions
            canAssignClients={canAssignClients}
            onImportCsv={() => csvInputRef.current?.click()}
            onAddItem={addItem}
            onAssignClient={canAssignClients ? () => setClientDialogOpen(true) : null}
          />
        </div>

        <div className="hidden">
          <input
            ref={csvInputRef}
            type="file"
            accept=".csv,text/csv"
            onChange={handleImportCsv}
            className="hidden"
          />
        </div>

        <div>
          <p className="mb-4 text-[18px] font-semibold text-slate-900">Articulos</p>
          {items.map((item, index) => (
            <article
              key={`item-${item.line}`}
              className="mb-4 rounded-[18px] border border-slate-200 bg-[#edf4f7] px-5 py-5"
            >
              <div className="flex items-center gap-3">
                <h3 className="text-base font-semibold text-slate-900">Articulo {item.line}</h3>
                <div className="ml-auto">
                  {items.length > 1 ? (
                    <button
                      type="button"
                      onClick={() => removeItem(index)}
                      className="rounded-full p-2 text-red-700 hover:bg-red-50"
                      title="Eliminar articulo"
                    >
                      <X size={18} />
                    </button>
                  ) : null}
                </div>
              </div>

              <div className="mt-4 space-y-4">
                <div>
                  <label className="mb-2 block text-sm font-medium text-slate-700">
                    Descripcion del producto
                  </label>
                  <textarea
                    value={item.description}
                    onChange={(event) => updateItem(index, { description: event.target.value })}
                    rows={3}
                    className="w-full resize-none border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                  />
                </div>

                {item.customer?.trim() ? (
                  <div className="flex items-center gap-2 text-sm text-slate-700">
                    <Search size={16} />
                    <span>Cliente: {item.customer.trim()}</span>
                  </div>
                ) : null}

                <div className="grid gap-4 md:grid-cols-2">
                  <div>
                    <label className="mb-2 block text-sm font-medium text-slate-700">
                      Unidad de medida
                    </label>
                    <div className="relative">
                      <input
                        value={item.unit}
                        onChange={(event) =>
                          updateItem(index, { unit: event.target.value.trim().toUpperCase() })
                        }
                        className="w-full border-0 border-b border-slate-500 bg-transparent px-0 py-2 pr-10 text-[15px] text-slate-900 outline-none"
                      />
                      <button
                        type="button"
                        onClick={() => setUnitPickerIndex(index)}
                        className="absolute right-1 top-1/2 -translate-y-1/2 rounded-full p-2 text-slate-500 transition hover:bg-slate-200"
                        title="Buscar unidad"
                      >
                        <Search size={16} />
                      </button>
                    </div>
                  </div>

                  <div>
                    <label className="mb-2 block text-sm font-medium text-slate-700">
                      {itemLabelForPieces(item.unit)}
                    </label>
                    <input
                      type="number"
                      min={1}
                      value={item.pieces}
                      onChange={(event) => {
                        const parsed = Number.parseInt(event.target.value, 10);
                        updateItem(index, {
                          pieces: Number.isFinite(parsed) && parsed > 0 ? parsed : 1,
                        });
                      }}
                      className="w-full border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                    />
                  </div>
                </div>

                <div>
                  <label className="mb-2 block text-sm font-medium text-slate-700">
                    No. de parte (opcional)
                  </label>
                  <input
                    value={item.partNumber}
                    onChange={(event) => updateItem(index, { partNumber: event.target.value })}
                    className="w-full border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                  />
                </div>
              </div>
            </article>
          ))}
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-slate-700">Observaciones</label>
          <textarea
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
            rows={4}
            className="w-full resize-none border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
          />
        </div>

        {pageError ? (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {pageError}
          </div>
        ) : null}

        {pageMessage ? (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
            {pageMessage}
          </div>
        ) : null}

        <button
          type="button"
          onClick={handleReviewPdf}
          className="w-full rounded-t-xl rounded-b-none bg-slate-900 px-4 py-3 text-base font-semibold text-white"
        >
          Revisar PDF
        </button>
      </section>

      {clientDialogOpen ? (
        <ClientAssignmentDialog
          items={items}
          clientOptions={clientOptions}
          profile={profile}
          onClose={() => setClientDialogOpen(false)}
          onApply={(nextItems) => {
            setItems(nextItems);
            setClientDialogOpen(false);
            setPageMessage("Asignacion de clientes actualizada.");
          }}
        />
      ) : null}

      {unitPickerIndex !== null ? (
        <SearchableOptionsDialog
          title="Selecciona unidad"
          options={orderUnitOptions}
          emptyLabel="Sin unidades registradas."
          onClose={() => setUnitPickerIndex(null)}
          onSelect={(value) => {
            updateItem(unitPickerIndex, { unit: value });
            setUnitPickerIndex(null);
          }}
        />
      ) : null}
    </div>
  );
}

function RequestedDeliveryDateSection({
  urgency,
  requestedDate,
  error,
  onChangeDate,
  onClearDate,
}: {
  urgency: OrderUrgency;
  requestedDate: Date | null;
  error: string | null;
  onChangeDate: (nextValue: Date | null) => void;
  onClearDate: (() => void) | null;
}) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const helperText = requestedDate
    ? `Fecha requerida: ${new Intl.DateTimeFormat("es-MX", { dateStyle: "short" }).format(requestedDate)}`
    : "Sin fecha capturada. Define para cuando se requiere lo solicitado.";
  const urgencyHelpText =
    urgency === "urgente"
      ? `Para urgencia solo se permite elegir entre hoy y ${urgentRequestedDeliveryWindowDays} dias mas.`
      : `Con urgencia normal solo puedes elegir desde ${normalRequestedDeliveryLeadDays} dias despues de hoy, en dia habil.`;
  const today = normalizeCalendarDate(new Date());
  const minDate =
    urgency === "urgente" ? today : firstAllowedNormalRequestedDeliveryDate(today);
  const maxDate =
    urgency === "urgente"
      ? normalizeCalendarDate(
          new Date(today.getFullYear(), today.getMonth(), today.getDate() + urgentRequestedDeliveryWindowDays),
        )
      : null;

  function openDatePicker() {
    if (!inputRef.current) return;
    if (typeof inputRef.current.showPicker === "function") {
      inputRef.current.showPicker();
      return;
    }
    inputRef.current.click();
  }

  return (
    <div className="rounded-[18px] bg-slate-100 px-4 py-4">
      <p className="text-sm font-semibold text-slate-900">Fecha requerida por el solicitante</p>
      <p className="mt-1 text-sm text-slate-700">{helperText}</p>
      <p className="mt-1 text-sm text-slate-500">{urgencyHelpText}</p>
      <div className="mt-3 flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={openDatePicker}
          className="inline-flex items-center rounded-2xl border border-slate-700 bg-[#f7f7f7] px-4 py-2 text-sm font-medium text-slate-700"
        >
          <CalendarDays size={16} className="mr-2" />
          <span>{requestedDate ? "Cambiar fecha" : "Definir fecha"}</span>
        </button>
        <input
          ref={inputRef}
          type="date"
          value={toDateInputValue(requestedDate)}
          min={toDateInputValue(minDate)}
          max={maxDate ? toDateInputValue(maxDate) : undefined}
          onChange={(event) => onChangeDate(parseDateInputValue(event.target.value))}
          className="pointer-events-none absolute h-0 w-0 opacity-0"
          tabIndex={-1}
          aria-hidden="true"
        />
        {onClearDate ? (
          <button type="button" onClick={onClearDate} className="text-sm font-medium text-slate-600">
            Limpiar
          </button>
        ) : null}
      </div>
      {error ? <p className="mt-3 text-sm font-medium text-red-600">{error}</p> : null}
    </div>
  );
}

function CreateOrderActions({
  canAssignClients,
  onImportCsv,
  onAddItem,
  onAssignClient,
}: {
  canAssignClients: boolean;
  onImportCsv: () => void;
  onAddItem: () => void;
  onAssignClient: (() => void) | null;
}) {
  const buttons = [
    {
      key: "csv",
      label: "Importar CSV",
      icon: <Upload size={16} className="mr-2" />,
      action: onImportCsv,
    },
    {
      key: "add",
      label: "Agregar item",
      icon: <Plus size={16} className="mr-2" />,
      action: onAddItem,
    },
    ...(canAssignClients && onAssignClient
      ? [
          {
            key: "client",
            label: "Asignar cliente",
            icon: <Search size={16} className="mr-2" />,
            action: onAssignClient,
          },
        ]
      : []),
  ];

  return (
    <div className="grid gap-3">
      {buttons.map((button) => (
        <button
          key={button.key}
          type="button"
          onClick={button.action}
          className="inline-flex w-full items-center justify-center rounded-2xl border border-slate-700 bg-[#f7f7f7] px-4 py-2.5 text-base font-medium text-slate-800"
        >
          {button.icon}
          {button.label}
        </button>
      ))}
    </div>
  );
}

function ClientAssignmentDialog({
  items,
  clientOptions,
  profile,
  onClose,
  onApply,
}: {
  items: OrderDraftItem[];
  clientOptions: PartnerEntry[];
  profile: AppUser | null;
  onClose: () => void;
  onApply: (items: OrderDraftItem[]) => void;
}) {
  const [selectedClient, setSelectedClient] = useState("");
  const [selectedIndexes, setSelectedIndexes] = useState<number[]>([]);
  const [draftItems, setDraftItems] = useState(items);
  const [clientPickerOpen, setClientPickerOpen] = useState(false);
  const [createClientOpen, setCreateClientOpen] = useState(false);
  const [dialogError, setDialogError] = useState<string | null>(null);

  const canApply = selectedClient.trim().length > 0 && selectedIndexes.length > 0;
  const clientNames = useMemo(
    () => Array.from(new Set(clientOptions.map((item) => item.name.trim()).filter(Boolean))).sort((a, b) => a.localeCompare(b, "es")),
    [clientOptions],
  );
  const selectableIndexes = draftItems
    .map((item, index) => ({ item, index }))
    .filter(({ item }) => {
      const customer = item.customer?.trim() ?? "";
      return !customer || customer === selectedClient.trim();
    })
    .map(({ index }) => index);

  function toggleIndex(index: number, checked: boolean) {
    setSelectedIndexes((current) =>
      checked ? [...new Set([...current, index])] : current.filter((value) => value !== index),
    );
  }

  function toggleAll(checked: boolean) {
    setSelectedIndexes(checked ? selectableIndexes : []);
  }

  function applySelectedClient() {
    const normalizedClient = selectedClient.trim();
    if (!normalizedClient) return;

    setDraftItems((current) =>
      current.map((item, index) =>
        selectedIndexes.includes(index) ? { ...item, customer: normalizedClient } : item,
      ),
    );
    setSelectedIndexes([]);
  }

  async function handleCreateClient(name: string) {
    if (!profile) {
      setDialogError("Perfil no disponible para crear clientes.");
      return;
    }

    try {
      const createdName = await createClientPartner(name, profile);
      setSelectedClient(createdName);
      setDialogError(null);
      setCreateClientOpen(false);
      setClientPickerOpen(false);
    } catch (error) {
      setDialogError(error instanceof Error ? error.message : "No se pudo crear el cliente.");
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-slate-950/35 px-4 py-8" onClick={onClose}>
      <div
        className="mx-auto max-h-full w-full max-w-4xl overflow-hidden rounded-[24px] bg-white shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="border-b px-6 py-4">
          <h3 className="text-lg font-semibold text-slate-900">Asignar cliente</h3>
        </div>
        <div className="space-y-4 px-6 py-5">
          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              className="app-button-secondary min-w-[280px] justify-start"
              onClick={() => setClientPickerOpen(true)}
            >
              <Search size={16} className="mr-2" />
              <span className="truncate">{selectedClient.trim() || "Seleccionar cliente"}</span>
            </button>
            <button
              type="button"
              onClick={() => setCreateClientOpen(true)}
              className="app-button-secondary"
            >
              <Plus size={16} className="mr-2" />
              Agregar cliente
            </button>
            <button type="button" onClick={() => setSelectedIndexes([])} className="rounded-full p-3 text-slate-500 hover:bg-slate-100" title="Limpiar seleccion">
              <X size={18} />
            </button>
          </div>

          {dialogError ? (
            <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {dialogError}
            </div>
          ) : null}

          <div className="flex items-center gap-3 text-sm">
            <label className="inline-flex items-center gap-2">
              <input
                type="checkbox"
                checked={selectableIndexes.length > 0 && selectedIndexes.length === selectableIndexes.length}
                onChange={(event) => toggleAll(event.target.checked)}
              />
              <span>Seleccionar todos</span>
            </label>
            <button type="button" onClick={() => setSelectedIndexes([])} className="font-medium text-slate-600">
              Limpiar
            </button>
          </div>

          <div className="max-h-[50vh] space-y-2 overflow-auto">
            {draftItems.map((item, index) => {
              const customer = item.customer?.trim() ?? "";
              const selectable = !customer || customer === selectedClient.trim();

              return (
                <label key={`assign-${item.line}`} className="flex items-start gap-3 rounded-xl px-1 py-2">
                  <input
                    type="checkbox"
                    checked={selectedIndexes.includes(index)}
                    onChange={(event) => toggleIndex(index, event.target.checked)}
                    disabled={!selectable}
                    className="mt-1"
                  />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-slate-900">
                      Item {item.line}: {item.description || "Sin descripcion"}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      {item.partNumber?.trim() ? `No. parte: ${item.partNumber} | ` : ""}
                      Cantidad: {item.pieces} {item.unit}
                      {customer ? ` | Cliente actual: ${customer}` : ""}
                    </p>
                  </div>
                  {customer ? (
                    <button
                      type="button"
                      onClick={() =>
                        setDraftItems((current) =>
                          current.map((entry, itemIndex) =>
                            itemIndex === index ? { ...entry, customer: undefined } : entry,
                          ),
                        )
                      }
                      className="rounded-full p-2 text-slate-500 hover:bg-slate-100"
                      title="Deshacer cliente"
                    >
                      <Undo2 size={16} />
                    </button>
                  ) : null}
                </label>
              );
            })}
          </div>
        </div>

        <div className="flex flex-wrap justify-end gap-3 border-t px-6 py-4">
          <button type="button" onClick={onClose} className="app-button-secondary">
            Cancelar
          </button>
          <button type="button" onClick={() => onApply(draftItems)} className="app-button-secondary">
            Listo
          </button>
          <button
            type="button"
            onClick={applySelectedClient}
            disabled={!canApply}
            className="app-button-primary"
          >
            Aplicar
          </button>
        </div>
      </div>

      {clientPickerOpen ? (
        <SearchableOptionsDialog
          title="Seleccionar cliente"
          options={clientNames}
          emptyLabel="Sin clientes registrados."
          onClose={() => setClientPickerOpen(false)}
          onSelect={(value) => {
            setSelectedClient(value);
            setDialogError(null);
            setClientPickerOpen(false);
          }}
        />
      ) : null}

      {createClientOpen ? (
        <CreateClientDialog
          onClose={() => setCreateClientOpen(false)}
          onCreate={handleCreateClient}
        />
      ) : null}
    </div>
  );
}

function SearchableOptionsDialog({
  title,
  options,
  emptyLabel,
  onClose,
  onSelect,
}: {
  title: string;
  options: readonly string[];
  emptyLabel: string;
  onClose: () => void;
  onSelect: (value: string) => void;
}) {
  const [query, setQuery] = useState("");

  const filteredOptions = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    if (!normalizedQuery) return [...options];
    return options.filter((option) => option.toLowerCase().includes(normalizedQuery));
  }, [options, query]);

  return (
    <div className="fixed inset-0 z-[60] bg-slate-950/35 px-4 py-8" onClick={onClose}>
      <div
        className="mx-auto flex max-h-full w-full max-w-2xl flex-col overflow-hidden rounded-[24px] bg-white shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center gap-3 border-b px-6 py-4">
          <h3 className="text-lg font-semibold text-slate-900">{title}</h3>
          <button
            type="button"
            onClick={onClose}
            className="ml-auto rounded-full p-2 text-slate-500 hover:bg-slate-100"
            title="Cerrar"
          >
            <X size={18} />
          </button>
        </div>
        <div className="space-y-4 px-6 py-5">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" size={16} />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              className="app-input w-full pl-10"
              placeholder="Buscar"
            />
          </div>
          <div className="max-h-[50vh] overflow-auto">
            {!options.length ? (
              <p className="text-sm text-slate-500">{emptyLabel}</p>
            ) : !filteredOptions.length ? (
              <p className="text-sm text-slate-500">Sin coincidencias.</p>
            ) : (
              <div className="divide-y divide-slate-100 rounded-2xl border border-slate-200">
                {filteredOptions.map((option) => (
                  <button
                    key={option}
                    type="button"
                    onClick={() => onSelect(option)}
                    className="flex w-full items-center px-4 py-3 text-left text-sm text-slate-800 transition hover:bg-slate-50"
                  >
                    {option}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function CreateClientDialog({
  onClose,
  onCreate,
}: {
  onClose: () => void;
  onCreate: (name: string) => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    const trimmedName = name.trim();
    if (!trimmedName) {
      setError("El nombre del cliente es obligatorio.");
      return;
    }

    setIsSubmitting(true);
    setError(null);
    try {
      await onCreate(trimmedName);
    } catch (submissionError) {
      setError(
        submissionError instanceof Error
          ? submissionError.message
          : "No se pudo crear el cliente.",
      );
      setIsSubmitting(false);
      return;
    }
    setIsSubmitting(false);
  }

  return (
    <div className="fixed inset-0 z-[70] bg-slate-950/35 px-4 py-8" onClick={onClose}>
      <div
        className="mx-auto w-full max-w-lg rounded-[24px] bg-white shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="border-b px-6 py-4">
          <h3 className="text-lg font-semibold text-slate-900">Agregar cliente</h3>
        </div>
        <div className="space-y-4 px-6 py-5">
          <div>
            <label className="mb-2 block text-sm font-medium text-slate-700">Nombre del cliente</label>
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
              className="app-input w-full"
              placeholder="Captura el nombre del cliente"
            />
          </div>
          {error ? <p className="text-sm text-red-600">{error}</p> : null}
        </div>
        <div className="flex justify-end gap-3 border-t px-6 py-4">
          <button type="button" onClick={onClose} className="app-button-secondary">
            Cancelar
          </button>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={isSubmitting}
            className="app-button-primary"
          >
            {isSubmitting ? "Creando..." : "Crear"}
          </button>
        </div>
      </div>
    </div>
  );
}

async function createClientPartner(name: string, profile: AppUser) {
  const trimmedName = name.trim();
  if (!trimmedName) {
    throw new Error("Nombre requerido.");
  }

  const partnerRef = push(ref(database, "partners/clients"));
  await set(partnerRef, {
    name: trimmedName,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdById: profile.id,
    createdByName: profile.name.trim(),
    createdByArea: profile.areaDisplay.trim(),
    updatedById: profile.id,
    updatedByName: profile.name.trim(),
    updatedByArea: profile.areaDisplay.trim(),
  });

  return trimmedName;
}
