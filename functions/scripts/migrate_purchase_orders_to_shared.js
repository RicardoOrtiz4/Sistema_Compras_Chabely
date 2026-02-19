const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);

const DEFAULT_DB_URL = 'https://sistemacompraschabely-default-rtdb.firebaseio.com';

function getArg(flag) {
  const index = args.indexOf(flag);
  if (index === -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

function normalizeCompany(value) {
  if (!value) return '';
  return String(value).trim().toLowerCase();
}

async function resolveCompanies(db) {
  const fromArgs = getArg('--companies');
  if (fromArgs) {
    return fromArgs
      .split(',')
      .map((entry) => normalizeCompany(entry))
      .filter((entry) => entry.length > 0);
  }

  const companiesSnap = await db.ref('companies').get();
  if (companiesSnap.exists()) {
    const raw = companiesSnap.val();
    if (raw && typeof raw === 'object') {
      const keys = Object.keys(raw)
        .map((entry) => normalizeCompany(entry))
        .filter((entry) => entry.length > 0);
      if (keys.length > 0) return keys;
    }
  }

  return ['chabely', 'acerpro'];
}

function hasCompanyId(order) {
  if (!order || typeof order !== 'object') return false;
  const value = order.companyId;
  if (value == null) return false;
  return String(value).trim().length > 0;
}

async function main() {
  const apply = args.includes('--apply');
  const deleteSource = args.includes('--delete-source');
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
  const companies = await resolveCompanies(db);
  const targetSnap = await db.ref('purchaseOrders').get();
  const targetRaw = targetSnap.exists() && targetSnap.val() && typeof targetSnap.val() === 'object'
    ? targetSnap.val()
    : {};
  const targetIds = new Set(Object.keys(targetRaw));

  const counts = {
    companies: companies.length,
    sourceOrders: 0,
    copied: 0,
    skippedExisting: 0,
    patchedCompanyId: 0,
    deletedSource: 0,
  };

  console.log(`Companies: ${companies.join(', ') || '(none)'}`);

  for (const company of companies) {
    const sourceRef = db.ref(`companies/${company}/purchaseOrders`);
    const sourceSnap = await sourceRef.get();
    if (!sourceSnap.exists()) {
      continue;
    }
    const sourceRaw = sourceSnap.val();
    if (!sourceRaw || typeof sourceRaw !== 'object') {
      continue;
    }

    for (const [orderId, orderRaw] of Object.entries(sourceRaw)) {
      if (!orderRaw || typeof orderRaw !== 'object') continue;
      counts.sourceOrders += 1;

      if (targetIds.has(orderId)) {
        counts.skippedExisting += 1;
        const existing = targetRaw[orderId];
        if (!hasCompanyId(existing)) {
          counts.patchedCompanyId += 1;
          if (apply) {
            await db.ref(`purchaseOrders/${orderId}`).update({
              companyId: company,
            });
          }
        }
        if (apply && deleteSource) {
          await sourceRef.child(orderId).remove();
          counts.deletedSource += 1;
        }
        continue;
      }

      const payload = { ...orderRaw };
      if (!hasCompanyId(payload)) {
        payload.companyId = company;
      }

      if (apply) {
        await db.ref(`purchaseOrders/${orderId}`).set(payload);
        if (deleteSource) {
          await sourceRef.child(orderId).remove();
          counts.deletedSource += 1;
        }
      }

      targetIds.add(orderId);
      targetRaw[orderId] = payload;
      counts.copied += 1;
    }
  }

  console.log('Summary:');
  console.log(`- companies: ${counts.companies}`);
  console.log(`- sourceOrders: ${counts.sourceOrders}`);
  console.log(`- copied: ${counts.copied}`);
  console.log(`- skippedExisting: ${counts.skippedExisting}`);
  console.log(`- patchedCompanyId: ${counts.patchedCompanyId}`);
  console.log(`- deletedSource: ${counts.deletedSource}`);

  if (!apply) {
    console.log('Dry run only. Re-run with --apply to write changes.');
  }
}

main().catch((error) => {
  console.error('Migration failed:', error);
  process.exit(1);
});
