import path from "node:path";
import { app, BrowserWindow, shell } from "electron";
const isDev = !app.isPackaged;
function createMainWindow() {
    const mainWindow = new BrowserWindow({
        width: 1440,
        height: 920,
        minWidth: 1200,
        minHeight: 760,
        backgroundColor: "#e5e7eb",
        show: false,
        title: "Sistema de Compras",
        webPreferences: {
            preload: path.join(app.getAppPath(), "dist-electron", "preload", "index.js"),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: false,
        },
    });
    mainWindow.once("ready-to-show", () => {
        mainWindow.show();
    });
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        void shell.openExternal(url);
        return { action: "deny" };
    });
    if (isDev) {
        void mainWindow.loadURL("http://localhost:5173");
        return;
    }
    void mainWindow.loadFile(path.join(app.getAppPath(), "dist", "index.html"));
}
app.whenReady().then(() => {
    createMainWindow();
    app.on("activate", () => {
        if (BrowserWindow.getAllWindows().length === 0) {
            createMainWindow();
        }
    });
});
app.on("window-all-closed", () => {
    if (process.platform !== "darwin") {
        app.quit();
    }
});
