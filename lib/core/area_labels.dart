const direccionGeneralLabel = 'Direcci\u00f3n General';
const contabilidadLabel = 'Contabilidad';
const comprasLabel = 'Compras';

String normalizeAreaLabel(String? value) {
  if (value == null) return '';
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final lower = trimmed.toLowerCase();
  if (lower == 'gerencia general' ||
      lower == 'gerencia' ||
      lower == 'direccion general' ||
      lower == 'direcci\u00f3n general') {
    return direccionGeneralLabel;
  }
  return trimmed;
}

bool isDireccionGeneralLabel(String? value) =>
    normalizeAreaLabel(value) == direccionGeneralLabel;

bool isContabilidadLabel(String? value) =>
    normalizeAreaLabel(value) == contabilidadLabel;

bool isComprasLabel(String? value) => normalizeAreaLabel(value) == comprasLabel;
