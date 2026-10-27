/// Backend numbers arrive as strings (DRF decimals) or numbers. Missing or bad values become 0.
double parseDouble(Object? value) => double.tryParse(value?.toString() ?? '') ?? 0;

/// Like [parseDouble], but keeps null when the value is absent.
double? parseDoubleOrNull(Object? value) => value == null ? null : double.tryParse(value.toString());
