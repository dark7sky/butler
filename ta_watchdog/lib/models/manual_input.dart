class ManualInput {
  final int? id;
  final String keyName;
  final double value;
  final DateTime? updatedAt;

  ManualInput({
    this.id,
    required this.keyName,
    required this.value,
    this.updatedAt,
  });

  factory ManualInput.fromJson(Map<String, dynamic> json) {
    return ManualInput(
      id: json['id'],
      keyName: json['key_name'],
      value: _asDouble(json['value']),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'key_name': keyName,
      'value': value,
    };
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
