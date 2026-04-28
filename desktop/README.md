# Desktop / Web

Este proyecto usa una sola base `React + Vite` para compartir:

- componentes de UI
- lógica de negocio
- integración con Firebase
- rutas y pantallas

El mismo frontend corre en dos modos:

- `Web`: navegador normal
- `Desktop`: Electron envolviendo la misma app React

## Desarrollo

Modo web:

```powershell
cd D:\chabely\Sistema_Compras_Chabely\desktop
npm run dev:web
```

Modo desktop:

```powershell
cd D:\chabely\Sistema_Compras_Chabely\desktop
npm run dev:desktop
```

`npm run dev` apunta por defecto a `dev:desktop`.

## Build

Build web:

```powershell
npm run build:web
```

Build desktop:

```powershell
npm run build:desktop
```

## Nota de arquitectura

- `src/renderer`: app compartida entre web y desktop
- `src/main` y `src/preload`: solo Electron

Si una funcionalidad necesita algo exclusivo de desktop, debe entrar por `preload` y tener fallback para web.
