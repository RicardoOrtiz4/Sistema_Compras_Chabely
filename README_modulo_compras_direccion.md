# Rebuild Clean: Modulo Compras + Direccion General

Este documento define como rehacer el modulo completo desde cero, sin reutilizar logica previa, sin copiar estructuras antiguas y sin depender de implementaciones eliminadas.

Objetivo principal:
- reconstruir el flujo de agrupacion para autorizacion ejecutiva sin arrastrar deuda tecnica;
- evitar el crash historico al enviar agrupaciones;
- dejar una arquitectura verificable, trazable y facil de evolucionar.

## 1) Principios de reconstruccion

Reglas obligatorias para la siguiente sesion:
- no recuperar ni adaptar codigo legacy del flujo eliminado;
- no renombrar wrappers viejos para "simular" limpieza;
- crear componentes nuevos con contratos nuevos;
- aislar persistencia de datos por contexto de negocio (orden vs paquete de aprobacion);
- privilegiar operaciones atomicas por entidad, nunca escrituras masivas de arbol completo.

Definicion de "hecho bien":
- el flujo funciona end-to-end con datos nuevos;
- datos viejos no rompen parseo;
- no hay dependencia circular entre ordenes y paquetes;
- el envio a autorizacion no crashea aunque falten datos parciales en memoria UI.

## 2) Modelo de dominio nuevo (sin herencia legacy)

Crear tres agregados nuevos:

1. `RequestOrder`
- representa la solicitud original.
- contiene items, solicitante, urgencia y estado operacional base.
- no contiene estado interno por proveedor ni decisiones de autorizacion ejecutiva por item.

2. `PurchasePacket`
- representa un paquete agrupado por proveedor para revision ejecutiva.
- incluye: proveedor, lista de referencias a items de orden, monto total, evidencia, version.
- es entidad independiente; no se embebe como snapshot dentro de la orden.

3. `PacketDecision`
- representa decisiones sobre un paquete (aprobar, regresar, cerrar items no comprables).
- cada decision es inmutable (append-only), con actor, timestamp y motivo.

Relaciones:
- una `RequestOrder` puede participar en multiples `PurchasePacket`;
- un `PurchasePacket` referencia items via `orderId + itemId` (no por indice mutable);
- la vista de estado consolidado se calcula por proyeccion, no por duplicacion manual.

## 3) Maquina de estados nueva

Definir estados nuevos con nombres neutrales:
- `draft`
- `intake_review`
- `sourcing`
- `ready_for_approval`
- `approval_queue`
- `execution_ready`
- `documents_check`
- `completed`

Reglas:
- los estados de orden y de paquete son distintos;
- no mezclar estados de paquete dentro del enum de orden;
- transiciones invalidas deben fallar con error de dominio (no silencioso).

## 4) Contrato de persistencia

Estructura sugerida:
- `orders/{orderId}`
- `order_items/{orderId}/{itemId}`
- `packets/{packetId}`
- `packet_items/{packetId}/{itemRefId}`
- `packet_decisions/{packetId}/{decisionId}`

Reglas de escritura:
- actualizar solo el nodo de la entidad afectada;
- prohibido: leer arbol completo y reescribirlo para cambios puntuales;
- para cambios multi-entidad, usar operacion transaccional o batch con verificacion de version.

Control de concurrencia:
- cada `PurchasePacket` debe tener `version` entero incremental;
- cada mutacion exige `expectedVersion`;
- si version no coincide, responder conflicto y pedir recarga.

## 5) API de aplicacion (casos de uso nuevos)

Definir casos de uso explicitos:
- `CreatePacketFromReadyOrders`
- `SubmitPacketForExecutiveApproval`
- `ApprovePacket`
- `ReturnPacketForRework`
- `ClosePacketItemsAsUnpurchasable`
- `RebuildOrderProjectionFromPackets`

Condiciones criticas:
- `SubmitPacketForExecutiveApproval` nunca depende solo de cache UI;
- antes de enviar, rehidrata entidades necesarias desde repositorio;
- valida referencias huercanas (item no existe, item ya cerrado, orden cerrada).

## 6) Estrategia anti-crash (causa historica)

Checklist duro para evitar el crash de envio:
- no usar update masivo de raiz;
- no construir payload con snapshots parciales de pantalla;
- no asumir que la lista local de ordenes contiene todo lo requerido;
- resolver referencias con lectura fuerte por ID antes de mutar;
- envolver cada paso con errores de dominio tipados y logging estructurado.

Errores esperados:
- `MissingOrderReference`
- `MissingItemReference`
- `PacketVersionConflict`
- `PacketAlreadySubmitted`
- `InvalidPacketTransition`

## 7) Telemetria minima obligatoria

Registrar por mutacion:
- `operationId`
- `actorId`
- `entityId`
- `expectedVersion`
- `actualVersion`
- duracion total
- resultado (`ok` o `error_type`)

Si hay fallo, guardar contexto minimo para reproducir:
- IDs afectados;
- estado previo;
- paso exacto donde fallo.

## 8) Plan de implementacion por fases

Fase 1: Dominio
- crear entidades nuevas y value objects;
- definir reglas de transicion y validaciones;
- tests unitarios de maquina de estados y reglas de integridad.

Fase 2: Persistencia
- implementar repositorios nuevos con operaciones atomicas;
- agregar control de version por paquete;
- tests de repositorio para conflicto de concurrencia.

Fase 3: Casos de uso
- implementar casos de uso listados en seccion 5;
- usar DTOs puros de entrada/salida (sin dependencia UI);
- tests de integracion con escenarios felices y de conflicto.

Fase 4: UI
- construir vistas nuevas conectadas solo a casos de uso nuevos;
- no reutilizar widgets de flujo anterior;
- manejar estados de carga, conflicto y reintento.

Fase 5: Migracion y corte
- mantener lectura compatible de estados legacy solo para historico;
- nuevas escrituras deben usar solo esquema nuevo;
- remover cualquier puente temporal cuando todo quede estable.

## 9) Criterios de aceptacion

Debe cumplirse todo:
- enviar agrupacion a autorizacion no crashea en 100 intentos consecutivos;
- conflicto de version devuelve error controlado y no rompe UI;
- orden con multiples paquetes mantiene consistencia de proyeccion;
- regreso de paquete no corrompe items no involucrados;
- cierre de items no comprables recalcula estado final correctamente;
- no existen escrituras de arbol raiz para operaciones de paquete.

## 10) Suite de pruebas minima

Unitarias:
- transiciones validas/invalidas de orden;
- transiciones validas/invalidas de paquete;
- resolucion de estado consolidado por items y decisiones.

Integracion:
- crear paquete -> enviar -> aprobar;
- crear paquete -> enviar -> regresar -> reenviar;
- cierre parcial de items como no comprables;
- conflicto de version concurrente.

Regresion:
- datos con estados legacy se leen sin crash;
- nuevas operaciones no generan campos legacy.

## 11) Definicion de terminado

El rebuild termina cuando:
- flujo nuevo funciona completo;
- crash historico deja de reproducirse;
- no hay referencias activas a logica eliminada;
- documentacion tecnica y pruebas cubren el ciclo principal y edge cases.

---

Guia para la siguiente sesion:
- implementar exactamente este blueprint;
- tomar decisiones de detalle sin mirar codigo previo eliminado;
- priorizar seguridad de datos y consistencia antes que velocidad de entrega.
