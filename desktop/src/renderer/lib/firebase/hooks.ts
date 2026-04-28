import { useEffect, useMemo, useState } from "react";
import { onValue, ref } from "firebase/database";
import { database } from "@/lib/firebase/client";

export function useRtdbValue<T>(
  path: string,
  mapValue: (value: unknown) => T,
  enabled = true,
) {
  const stableMapper = useMemo(() => mapValue, [mapValue]);
  const [data, setData] = useState<T | null>(null);
  const [isLoading, setIsLoading] = useState(enabled);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!enabled) {
      setData(null);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    const unsubscribe = onValue(
      ref(database, path),
      (snapshot) => {
        setData(stableMapper(snapshot.val()));
        setIsLoading(false);
      },
      (nextError) => {
        setError(nextError.message);
        setIsLoading(false);
      },
    );

    return () => unsubscribe();
  }, [enabled, path, stableMapper]);

  return { data, isLoading, error };
}
