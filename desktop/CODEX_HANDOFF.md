# Codex Handoff

## Objetivo

Migrar el sistema de compras hecho en Flutter a una base nueva compartida para:

- `web` con `React + Vite`
- `desktop` con `React + Vite + Electron`

La nueva app **no depende de Flutter para ejecutarse**. Flutter sigue existiendo como proyecto original, pero la nueva app reutiliza:

- `Firebase Auth`
- `Firebase Realtime Database`
- `Firebase Storage`
- `Cloud Functions`
- estructura de datos y flujo operativo ya existente

## Ubicación

Proyecto nuevo:

- `desktop/`

Proyecto original Flutter:

- raíz del repo actual, principalmente `lib/` y `functions/`

## Stack actual

- `React`
- `TypeScript`
- `Vite`
- `Electron`
- `Tailwind CSS`
- componentes UI internos estilo `shadcn-like`
- `Zustand`
- `Firebase`

## Estado actual

### Módulos ya migrados con lógica real

- `auth`
- `inicio`
- `crear orden`
- `historial`
- `detalle`
- `usuarios`
- `autorizaciones`
- `paquetes`
- `eta / facturas / cierre`
- `monitoreo`
- `reportes`
- `pdf por estatus`

### Lógica real conectada

- login real con `Firebase Auth`
- lectura de perfil real desde `users/{uid}`
- writes reales sobre `purchaseOrders`
- flujo real de autorizaciones / compras / paquetes / seguimiento
- generación y actualización de `pdfUrl` en distintos estatus

## Decisiones de arquitectura

- La app React es una implementación nueva del frontend.
- Web y desktop comparten la misma base de UI y lógica.
- `Electron` solo agrega shell desktop y APIs de escritorio.
- La lógica de negocio se ha ido portando desde Flutter a servicios y pantallas React.
- No mantener dos proyectos frontend separados para web/desktop.

## Alias y TypeScript

Archivo:

- [tsconfig.json](D:/chabely/Sistema_Compras_Chabely/desktop/tsconfig.json)

Estado correcto actual:

- `baseUrl` eliminado
- alias `@/*` configurado con ruta relativa:

```json
"paths": {
  "@/*": ["./src/renderer/*"]
}
```

Esto se dejó así porque `baseUrl` ya marca advertencia deprecada en TypeScript 6+.

## Branding

Sistema de marcas:

- `Chabely`
- `Acerpro`

Archivos clave:

- [branding.ts](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/lib/branding.ts)
- [branding-store.ts](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/store/branding-store.ts)

### Reglas visuales actuales

- `Chabely`: negros, grises y rojo moderado
- `Acerpro`: azules, blancos y grises
- `Órdenes rechazadas`: rojo en ambas marcas
- `Órdenes en proceso`: azul rey en ambas marcas
- el contenedor del logo en `appbar` es blanco para ambas marcas

### Logos

Los logos se copiaron desde Flutter y se usan en UI y PDFs.

## Reglas visuales pedidas por usuario

Estas reglas son importantes y deben respetarse en futuras sesiones:

1. El sistema debe parecerse lo más posible al Flutter original.
2. Evitar look genérico de web.
3. Mantener contraste correcto siempre:
   - fondo claro -> texto oscuro
   - fondo oscuro -> texto claro
4. El `background` global no debe verse blanco puro.
5. Hay un `animated technical background` en login y shell.
6. Se han ido quitando bloques introductorios arriba del contenido.
7. El usuario prefiere iterar pantalla por pantalla.
8. Explicar cambios también en lenguaje de programador para ir educándolo.

## Navegación actual

### App bar

- flecha `back` global hacia `Inicio`
- botón icon-only de `Monitoreo`
- botón icon-only de `Cambiar empresa`
- bloque de usuario con nombre y área
- contenedor blanco para logo

Archivo clave:

- [app-shell.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/shared/layout/app-shell.tsx)

### Menú lateral

El menú lateral debe contener principalmente:

- `Inicio`
- `Historial de mis órdenes`
- `Reportes`
- `Administrar usuarios`
- `Perfil`

### Home / Inicio

`Inicio` no es un dashboard analítico. Representa el `home` principal del proyecto Flutter.

Orden actual de módulos:

1. `Crear orden`
2. `Autorizar órdenes`
3. `Compras`
4. `Dirección General`
5. `Agregar fecha estimada`
6. `Facturas y evidencias`
7. `Órdenes en proceso`
8. `Órdenes rechazadas`

Layout actual:

- `2 columnas`

## PDFs

Tema crítico para el proyecto.

Ya existe soporte para:

- generar PDF de orden por estatus
- regenerar PDF en transiciones importantes
- subirlo a Storage
- guardar `pdfUrl`

Archivos clave:

- [order-pdf-service.ts](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/orders/order-pdf-service.ts)
- [create-order-service.ts](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/orders/create-order-service.ts)
- [authorize-orders-service.ts](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/workflow/authorize-orders-service.ts)
- [packet-follow-up-service.ts](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/workflow/packet-follow-up-service.ts)

## Background y shell

Hay un lenguaje visual de fondo compartido:

- base gris
- líneas técnicas animadas
- glow suave

Archivo principal:

- [styles.css](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/app/styles.css)

## Pantallas tocadas recientemente

- [login-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/auth/login-page.tsx)
- [dashboard-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/dashboard/dashboard-page.tsx)
- [create-order-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/orders/create-order-page.tsx)
- [order-history-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/orders/order-history-page.tsx)
- [order-detail-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/orders/order-detail-page.tsx)
- [authorize-orders-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/workflow/authorize-orders-page.tsx)
- [purchase-packets-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/purchase-packets/purchase-packets-page.tsx)
- [packet-follow-up-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/workflow/packet-follow-up-page.tsx)
- [reports-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/reports/reports-page.tsx)
- [order-monitoring-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/orders/order-monitoring-page.tsx)
- [admin-users-page.tsx](D:/chabely/Sistema_Compras_Chabely/desktop/src/renderer/features/admin/admin-users-page.tsx)

## Ajustes técnicos ya resueltos

- saneo de `undefined` antes de escribir a Firebase
- chunk splitting en Vite
- alias `@/` funcionando sin `baseUrl`
- ventana Electron ya no debe abrir `chrome-error://chromewebdata/`
- `window.desktopApi` protegido con fallback

## Cosas a cuidar

1. No romper compatibilidad con la base real de Firebase.
2. No reintroducir fondos blancos puros donde el usuario ya pidió gris.
3. No meter textos explicativos arriba del contenido si no aportan.
4. No asumir que “dashboard” es correcto; el usuario lo entiende como `Inicio/Home`.
5. Mantener web y desktop sobre la misma base.
6. Seguir trabajando en iteraciones pequeñas de diseño.

## Pendientes probables

Pendientes de mayor probabilidad para próximas sesiones:

- seguir afinando fidelidad visual contra Flutter
- pulir `Autorizaciones`, `Paquetes` y `ETA/Facturas`
- seguir limpiando textos con encoding heredado en algunos archivos viejos
- revisar estados `hover/active/focus` de botones y cards
- más similitud de layout respecto a Flutter en pantallas operativas

## Forma recomendada de continuar

1. abrir la app
2. revisar una pantalla concreta
3. hacer cambios solo de `presentation`
4. validar `tsc`
5. validar `npm run build:desktop`

## Comandos de validación

Desde `desktop/`:

```powershell
.\node_modules\.bin\tsc -p tsconfig.json --noEmit
npm run build:desktop
```

## Nota para nueva sesión de Codex

El usuario quiere:

- máxima cercanía visual al Flutter original
- misma lógica de negocio
- mismo backend real
- mejoras iterativas
- explicaciones simples, pero también con términos de programador para aprender

Evitar respuestas genéricas. Revisar primero este archivo y luego tocar la pantalla específica que el usuario esté pidiendo.
