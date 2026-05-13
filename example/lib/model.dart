class ARItem {
  ARItem({
    required this.image,
    required this.video,
  });

  factory ARItem.fromJson(
    Map<String, dynamic> json,
  ) {
    return ARItem(
      image: json['image'] as String,
      video: json['video'] as String,
    );
  }

  final String image;
  final String video;
}
