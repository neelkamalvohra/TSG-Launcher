class TileModel {
  final String pk;
  final String name;
  final String slug;
  final String launchUrl;
  final String? iconUrl;
  final String? description;
  final String? quickPanel;  // 'roster' | 'time' | 'date' | null

  const TileModel({
    required this.pk,
    required this.name,
    required this.slug,
    required this.launchUrl,
    this.iconUrl,
    this.description,
    this.quickPanel,
  });

  factory TileModel.fromJson(Map<String, dynamic> json) {
    return TileModel(
      pk: json['pk']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      launchUrl: json['meta_launch_url']?.toString() ?? '',
      iconUrl: json['meta_icon']?.toString(),
      description: json['meta_description']?.toString(),
      quickPanel: json['quick_panel']?.toString(),
    );
  }

  TileModel copyWith({
    String? name,
    String? launchUrl,
    String? iconUrl,
    String? description,
    String? quickPanel,
  }) {
    return TileModel(
      pk: pk,
      name: name ?? this.name,
      slug: slug,
      launchUrl: launchUrl ?? this.launchUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      description: description ?? this.description,
      quickPanel: quickPanel ?? this.quickPanel,
    );
  }
}
