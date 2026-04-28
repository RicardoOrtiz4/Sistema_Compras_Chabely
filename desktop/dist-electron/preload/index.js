import { contextBridge } from "electron";
const desktopApi = {
    platform: process.platform,
    versions: {
        node: process.versions.node,
        chrome: process.versions.chrome,
        electron: process.versions.electron,
    },
};
contextBridge.exposeInMainWorld("desktopApi", desktopApi);
