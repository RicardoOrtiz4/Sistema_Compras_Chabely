import { ref, serverTimestamp, update } from "firebase/database";
import { database } from "@/lib/firebase/client";

export type UpdateAdminUserInput = {
  id: string;
  name: string;
  role: string;
  areaId: string;
  areaName: string;
};

export async function updateAdminUserProfile(input: UpdateAdminUserInput) {
  await update(ref(database, `users/${input.id}`), {
    name: input.name.trim(),
    role: input.role,
    areaId: input.areaId,
    areaName: input.areaName,
    updatedAt: serverTimestamp(),
  });
}
