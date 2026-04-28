export {};

declare global {
  interface Window {
    desktopApi: {
      platform: string;
      versions: {
        node: string;
        chrome: string;
        electron: string;
      };
    };
  }
}
