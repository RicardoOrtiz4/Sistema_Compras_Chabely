const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);

const DEFAULT_DB_URL = 'https://sistemacompraschabely-default-rtdb.firebaseio.com';
const TARGETS = [
  {
    label: 'Direcci\u00f3n General',
    aliases: new Set(['gerencia general', 'gerencia', 'direccion general']),
  },
  {
    label: 'Almac\u00e9n',
    aliases: new Set(['almacen']),
  },
];

function getArg(flag) {
  const index = args.indexOf(flag);
  if (index === -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

function fixMojibake(value) {
  if (typeof value !== 'string') return value;
  if (!/[ÃÂâ]/.test(value)) return value;
  const fixed = Buffer.from(value, 'latin1').toString('utf8');
  if (fixed.includes('\uFFFD')) return value;
  if (!/[ÃÂâ]/.test(fixed)) return fixed;
  return fixed === value ? value : fixed;
}

function normalizeLabel(value) {
  const fixed = fixMojibake(value);
  return String(fixed || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ');
}

for (const target of TARGETS) {
  target.normalized = normalizeLabel(target.label);
}

function resolveTarget(value) {
  const normalized = normalizeLabel(value);
  if (!normalized) return null;
  for (const target of TARGETS) {
    if (normalized === target.normalized || target.aliases.has(normalized)) {
      return target.label;
    }
  }
  return null;
}

function resolveValue(value) {
  if (value == null) return value;
  const fixed = fixMojibake(String(value));
  return resolveTarget(fixed) || fixed;
}

function toAreaPayload(raw) {
  if (raw && typeof raw === 'object') {
    return { ...raw };
  }
  return { name: raw == null ? '' : String(raw) };
}

function formatCounts(counts) {
  return [
    `areas.name=${counts.areasName}`,
    `areas.id=${counts.areasId}`,
    `users.areaName=${counts.usersAreaName}`,
    `users.areaId=${counts.usersAreaId}`,
    `orders.areaName=${counts.ordersAreaName}`,
    `orders.areaId=${counts.ordersAreaId}`,
    `events.byRole=${counts.eventsByRole}`,
  ].join(' | ');
}

async function main() {
  const apply = args.includes('--apply');
  const renameAreaId = args.includes('--rename-area-id');
  const serviceAccountPath =
    getArg('--service-account') || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!serviceAccountPath) {
    console.error('Missing service account JSON. Pass --service-account or set GOOGLE_APPLICATION_CREDENTIALS.');
    process.exit(1);
  }

  const resolvedPath = path.resolve(serviceAccountPath);
  const serviceAccount = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
  const databaseURL =
    getArg('--database-url') ||
    process.env.FIREBASE_DATABASE_URL ||
    serviceAccount.databaseURL ||
    DEFAULT_DB_URL;

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL,
  });

  const db = admin.database();
  const updates = {};
  const counts = {
    areasName: 0,
    areasId: 0,
    usersAreaName: 0,
    usersAreaId: 0,
    ordersAreaName: 0,
    ordersAreaId: 0,
    eventsByRole: 0,
  };

  const areasSnap = await db.ref('areas').get();
  if (areasSnap.exists()) {
    const areas = areasSnap.val();
    const targetPayloads = new Map();
    for (const target of TARGETS) {
      const existingTarget = areas[target.label];
      if (existingTarget != null) {
        const payload = toAreaPayload(existingTarget);
        payload.name = target.label;
        targetPayloads.set(target.label, payload);
      }
    }

    const setTargetPayload = (label, payload) => {
      const existing = targetPayloads.get(label);
      if (existing == null) {
        targetPayloads.set(label, payload);
        return;
      }
      targetPayloads.set(label, { ...payload, ...existing, name: label });
    };

    for (const [areaId, raw] of Object.entries(areas)) {
      const name =
        raw && typeof raw === 'object' && typeof raw.name === 'string'
          ? raw.name
          : typeof raw === 'string'
            ? raw
            : null;
      if (typeof name === 'string') {
        const resolvedName = resolveValue(name);
        if (resolvedName && resolvedName !== name) {
          if (raw && typeof raw === 'object') {
            updates[`areas/${areaId}/name`] = resolvedName;
          } else {
            updates[`areas/${areaId}`] = resolvedName;
          }
          counts.areasName += 1;
        }
      }

      const targetId = renameAreaId ? resolveTarget(areaId) : null;
      if (renameAreaId && targetId && areaId !== targetId) {
        const payload = toAreaPayload(raw);
        payload.name = resolveValue(payload.name);
        setTargetPayload(targetId, payload);
        updates[`areas/${areaId}`] = null;
        counts.areasId += 1;
      }
    }

    if (renameAreaId) {
      for (const [label, payload] of targetPayloads.entries()) {
        updates[`areas/${label}`] = payload;
      }
    }
  }

  const usersSnap = await db.ref('users').get();
  if (usersSnap.exists()) {
    const users = usersSnap.val();
    for (const [uid, raw] of Object.entries(users)) {
      if (!raw || typeof raw !== 'object') continue;
      if (typeof raw.areaName === 'string') {
        const resolvedName = resolveValue(raw.areaName);
        if (resolvedName && resolvedName !== raw.areaName) {
          updates[`users/${uid}/areaName`] = resolvedName;
          counts.usersAreaName += 1;
        }
      }
      if (renameAreaId && typeof raw.areaId === 'string') {
        const targetId = resolveTarget(raw.areaId);
        if (targetId && targetId !== raw.areaId) {
          updates[`users/${uid}/areaId`] = targetId;
          counts.usersAreaId += 1;
        }
      }
    }
  }

  const ordersSnap = await db.ref('purchaseOrders').get();
  if (ordersSnap.exists()) {
    const orders = ordersSnap.val();
    for (const [orderId, raw] of Object.entries(orders)) {
      if (!raw || typeof raw !== 'object') continue;
      if (typeof raw.areaName === 'string') {
        const resolvedName = resolveValue(raw.areaName);
        if (resolvedName && resolvedName !== raw.areaName) {
          updates[`purchaseOrders/${orderId}/areaName`] = resolvedName;
          counts.ordersAreaName += 1;
        }
      }
      if (renameAreaId && typeof raw.areaId === 'string') {
        const targetId = resolveTarget(raw.areaId);
        if (targetId && targetId !== raw.areaId) {
          updates[`purchaseOrders/${orderId}/areaId`] = targetId;
          counts.ordersAreaId += 1;
        }
      }
      if (raw.events && typeof raw.events === 'object') {
        for (const [eventId, eventRaw] of Object.entries(raw.events)) {
          if (!eventRaw || typeof eventRaw !== 'object') continue;
          if (typeof eventRaw.byRole === 'string') {
            const resolvedRole = resolveValue(eventRaw.byRole);
            if (resolvedRole && resolvedRole !== eventRaw.byRole) {
              updates[`purchaseOrders/${orderId}/events/${eventId}/byRole`] = resolvedRole;
              counts.eventsByRole += 1;
            }
          }
        }
      }
    }
  }

  const updateCount = Object.keys(updates).length;
  console.log(`Changes queued: ${updateCount}`);
  console.log(formatCounts(counts));

  if (!apply) {
    console.log('Dry run. Re-run with --apply to write changes.');
    return;
  }
  if (updateCount === 0) {
    console.log('No changes to apply.');
    return;
  }

  await db.ref().update(updates);
  console.log('Migration applied.');
}

main().catch((error) => {
  console.error('Migration failed:', error);
  process.exit(1);
});
