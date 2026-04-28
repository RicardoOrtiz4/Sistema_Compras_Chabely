export function getOrderStatusLabel(status: string) {
  switch (status) {
    case "draft":
      return "Requiere correccion";
    case "intakeReview":
      return "Revision operativa";
    case "sourcing":
      return "Preparacion";
    case "readyForApproval":
      return "Lista para ejecucion";
    case "approvalQueue":
      return "Validacion";
    case "paymentDone":
      return "Seguimiento logistica";
    case "contabilidad":
      return "Cierre documental";
    case "orderPlaced":
      return "Orden realizada";
    case "eta":
      return "Orden finalizada";
    default:
      return status || "Sin estado";
  }
}

export function getEventTypeLabel(type?: string) {
  switch ((type ?? "").trim().toLowerCase()) {
    case "advance":
      return "Avance";
    case "return":
      return "Regreso";
    case "save":
      return "Actualizacion";
    case "received":
      return "Recibido";
    case "items_eta":
      return "ETA registrada";
    case "items_to_facturas":
      return "Enviado a facturas";
    case "accounting_evidence":
      return "Links contables";
    case "items_arrived":
      return "Llegada registrada";
    case "material_arrived":
      return "Material recibido";
    case "received_timeout":
      return "Autocierre";
    case "service_rating":
      return "Calificacion";
    case "close_unpurchasable":
      return "Cierre sin compra";
    default:
      return type || "Evento";
  }
}
