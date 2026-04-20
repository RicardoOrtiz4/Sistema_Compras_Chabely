const adminAreaLabel = 'Sistemas Informaticos (SIN)';
const direccionGeneralLabel = 'Direccion General (DIG)';
const contraloriaLabel = 'Contraloria';
const comprasLabel = 'Compras';
const planeacionProduccionLabel = 'Planeacion y Control de la Produccion (PPR)';
const contabilidadLabel = 'Contabilidad';
const tesoreriaLabel = 'Tesoreria';
const nominasLabel = 'Nominas';

String normalizeAreaLabel(String? value) {
  if (value == null) return '';
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final lower = trimmed.toLowerCase();
  if (lower == 'administrador' ||
      lower == 'admin' ||
      lower == 'sistemas' ||
      lower == 'sistemas informaticos' ||
      lower == 'sistemas informaticos (sin)' ||
      lower == 'sistemas informáticos' ||
      lower == 'sistemas informáticos (sin)' ||
      lower == 'sin') {
    return adminAreaLabel;
  }
  if (lower == 'gerencia general' ||
      lower == 'gerencia' ||
      lower == 'direccion' ||
      lower == 'dirección' ||
      lower == 'direccion general' ||
      lower == 'direccion general (dig)' ||
      lower == 'direcci\u00f3n general' ||
      lower == 'direcci\u00f3n general (dig)' ||
      lower == 'dig') {
    return direccionGeneralLabel;
  }
  if (lower == 'contraloria' || lower == 'contralor' || lower == 'ctl') {
    return contraloriaLabel;
  }
  if (lower == 'compras' || lower == 'com') {
    return comprasLabel;
  }
  if (lower == 'planeacion y control de la produccion' ||
      lower == 'planeacion y control de la produccion (ppr)' ||
      lower == 'planeaciÃ³n y control de la producciÃ³n' ||
      lower == 'planeaci\u00f3n y control de la producci\u00f3n' ||
      lower == 'planeaci\u00f3n y control de la producci\u00f3n (ppr)' ||
      lower == 'ppr') {
    return planeacionProduccionLabel;
  }
  if (lower == 'contabilidad') {
    return contabilidadLabel;
  }
  if (lower == 'tesoreria') {
    return tesoreriaLabel;
  }
  if (lower == 'nominas' || lower == 'nóminas') {
    return nominasLabel;
  }
  return trimmed;
}

bool isAdminAreaLabel(String? value) => normalizeAreaLabel(value) == adminAreaLabel;

bool isDireccionGeneralLabel(String? value) =>
    normalizeAreaLabel(value) == direccionGeneralLabel;

bool isContraloriaLabel(String? value) =>
    normalizeAreaLabel(value) == contraloriaLabel;

bool isContabilidadLabel(String? value) =>
    normalizeAreaLabel(value) == contabilidadLabel;

bool isComprasLabel(String? value) => normalizeAreaLabel(value) == comprasLabel;

bool isPlaneacionProduccionLabel(String? value) =>
    normalizeAreaLabel(value) == planeacionProduccionLabel;
