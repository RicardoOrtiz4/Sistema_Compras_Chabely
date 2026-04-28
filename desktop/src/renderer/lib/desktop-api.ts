type DesktopApiShape = {
  platform: string;
  versions: {
    node: string;
    chrome: string;
    electron: string;
  };
};

const browserFallback: DesktopApiShape = {
  platform: "browser",
  versions: {
    node: "n/d",
    chrome: "n/d",
    electron: "n/d",
  },
};

export function getDesktopApi(): DesktopApiShape {
  if (typeof window === "undefined") {
    return browserFallback;
  }

  const candidate = (window as Window & { desktopApi?: Partial<DesktopApiShape> }).desktopApi;
  if (!candidate) {
    return browserFallback;
  }

  return {
    platform: candidate.platform?.trim() || browserFallback.platform,
    versions: {
      node: candidate.versions?.node?.trim() || browserFallback.versions.node,
      chrome: candidate.versions?.chrome?.trim() || browserFallback.versions.chrome,
      electron: candidate.versions?.electron?.trim() || browserFallback.versions.electron,
    },
  };
}

export function isDesktopRuntime() {
  const api = getDesktopApi();
  return api.platform !== "browser" && api.versions.electron !== "n/d";
}
